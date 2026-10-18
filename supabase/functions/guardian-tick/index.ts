import { createServiceClient } from "../_shared/guardian/db.ts";
import { withErrorHandling, successResponse } from "../_shared/guardian/errors.ts";
import { THRESHOLDS, DEFAULT_OVERDUE_THRESHOLDS } from "../_shared/guardian/thresholds.ts";
import { analyzeMovement } from "../_shared/guardian/movement.ts";
import { detectForestExit } from "../_shared/guardian/geofence.ts";
import { createAlertOnce, getHoursSinceLastAlert } from "../_shared/guardian/alerts.ts";
import type { GuardianSession, SessionStatus, AlertType } from "../_shared/guardian/types.ts";

interface TickStats {
  sessions_scanned: number;
  transitions_made: number;
  alerts_created: number;
  errors: number;
  error_details: Array<{ session_id: string; error: string }>;
}

Deno.serve(withErrorHandling(async (req) => {
  const db = createServiceClient();

  // Advisory lock — не допустити одночасних запусків (cron + manual виклик)
  const { data: lockAcquired, error: lockError } = await db.rpc(
    'pg_try_advisory_lock',
    { key: 737001 },
  );
  if (lockError || !lockAcquired) {
    console.log('[tick] another instance running, skip');
    return new Response(JSON.stringify({ skipped: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── CT-7: Перевірка guardian_fn_config (Vault) ──────────────────────
  // Якщо обидва поля NULL — алерти не працюватимуть (cron/тригери не будуть викликати EF).
  try {
    const { data: configData, error: configErr } = await db.rpc('guardian_fn_config', {});
    if (configErr || !configData) {
      console.warn('[tick] guardian_fn_config RPC failed:', configErr?.message);
      await createAlertOnce(db, "system", "config_missing", {
        check: "guardian_fn_config",
        error: configErr?.message ?? "no_data",
      });
    } else {
      const row = Array.isArray(configData) ? configData[0] : configData;
      if ((!row?.url || !row?.service_key)) {
        console.warn('[tick] guardian_fn_config returned NULL — Vault not populated');
        await createAlertOnce(db, "system", "config_missing", {
          check: "guardian_fn_config",
          url_null: !row?.url,
          service_key_null: !row?.service_key,
        });
      }
    }
  } catch (err) {
    console.error('[tick] config check error:', err);
  }

  let released = false;
  let tickId: number | undefined;

  const stats: TickStats = {
    sessions_scanned: 0,
    transitions_made: 0,
    alerts_created: 0,
    errors: 0,
    error_details: [],
  };

  const { data: tickLog } = await db
    .from("guardian_tick_log")
    .insert({})
    .select("id")
    .single();

  tickId = tickLog?.id;

  try {
    const CHUNK_SIZE = 100;
    let offset = 0;
    let hasMore = true;

    while (hasMore) {
      const { data: sessions, error } = await db
        .from("guardian_sessions")
        .select("*")
        .neq("status", "closed")
        .order("created_at", { ascending: true })
        .range(offset, offset + CHUNK_SIZE - 1);

      if (error) throw error;
      if (!sessions || sessions.length === 0) {
        hasMore = false;
        break;
      }

      for (const session of sessions as GuardianSession[]) {
        stats.sessions_scanned++;
        try {
          await processSession(db, session, stats);
        } catch (err) {
          stats.errors++;
          stats.error_details.push({
            session_id: session.id,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }

      if (sessions.length < CHUNK_SIZE) {
        hasMore = false;
      } else {
        offset += CHUNK_SIZE;
      }
    }

    if (tickId) {
      await db
        .from("guardian_tick_log")
        .update({
          finished_at: new Date().toISOString(),
          sessions_scanned: stats.sessions_scanned,
          transitions_made: stats.transitions_made,
          alerts_created: stats.alerts_created,
          errors: stats.errors,
          error_details: stats.error_details.length > 0 ? stats.error_details : null,
        })
        .eq("id", tickId);
    }

    // ── CT-8: Моніторинг tick_log.errors ──────────────────────────────
    // Якщо помилок за останню годину > 50 — алертимо адміна.
    try {
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
      const { data: recentLogs, error: logsErr } = await db
        .from("guardian_tick_log")
        .select("errors")
        .gte("created_at", oneHourAgo)
        .not("finished_at", "is", null);

      if (!logsErr && recentLogs) {
        const totalErrors = (recentLogs as Array<{ errors: number }>).reduce(
          (sum, row) => sum + (row.errors ?? 0),
          0,
        );
        if (totalErrors > 50) {
          await createAlertOnce(db, "system", "tick_errors_high", {
            errors_last_hour: totalErrors,
            threshold: 50,
            tick_id: tickId,
          });
        }
      }
    } catch (err) {
      console.error('[tick] error monitoring check failed:', err);
    }

    return successResponse(stats);
  } catch (err) {
    if (tickId) {
      await db
        .from("guardian_tick_log")
        .update({
          finished_at: new Date().toISOString(),
          errors: stats.errors + 1,
          error_details: [
            ...stats.error_details,
            { session_id: "global", error: err instanceof Error ? err.message : String(err) },
          ],
        })
        .eq("id", tickId);
    }
    throw err;
  } finally {
    if (!released) {
      released = true;
      try {
        await db.rpc('pg_advisory_unlock', { key: 737001 });
      } catch {
        // unlock error — non-fatal
      }
    }
  }
}));

export async function processSession(
  db: ReturnType<typeof createServiceClient>,
  session: GuardianSession,
  stats: TickStats
): Promise<void> {
  const now = Date.now();
  const nowIso = new Date(now).toISOString();

  if (session.status === "pending") {
    const startedMs = new Date(session.started_at).getTime();
    const hoursSinceStart = (now - startedMs) / (1000 * 60 * 60);

    if (hoursSinceStart >= THRESHOLDS.PENDING_AUTO_CLOSE_HOURS) {
      await finalClose(db, session, "auto_close_pending_timeout", stats);
      return;
    }
    return;
  }

  const lastKnownMs = session.last_known_at
    ? new Date(session.last_known_at).getTime()
    : null;

  const minutesSinceLastPing = lastKnownMs
    ? (now - lastKnownMs) / (1000 * 60)
    : null;

  if (
    minutesSinceLastPing !== null &&
    minutesSinceLastPing >= THRESHOLDS.AUTO_CLOSE_HOURS * 60 &&
    session.status !== "sos"
  ) {
    await finalClose(db, session, "auto_close_no_ping_24h", stats);
    return;
  }

  // G4: сесія жодного разу не ping'ила — auto-close за started_at.
  // `pending` вже оброблений вище (auto_close_pending_timeout), тому тут
  // лишаються non-pending статуси без жодного ping.
  if (lastKnownMs === null && session.status !== "sos") {
    const hoursSinceStart =
      (now - new Date(session.started_at).getTime()) / (1000 * 60 * 60);

    if (hoursSinceStart >= THRESHOLDS.AUTO_CLOSE_HOURS) {
      await finalClose(db, session, "auto_close_no_ping_ever", stats);
      return;
    }
  }

  if (session.status === "closing") {
    const closingStartedMs = session.closing_started_at
      ? new Date(session.closing_started_at).getTime()
      : null;

    if (closingStartedMs) {
      const minutesSinceClosing = (now - closingStartedMs) / (1000 * 60);
      const gracePeriodMin = session.settings.grace_period_min ?? 5;

      if (minutesSinceClosing >= gracePeriodMin) {
        await finalClose(db, session, "grace_period_expired", stats);
        return;
      }
    }
    return;
  }

  if (session.status === "exiting") {
    const exitDetectedMs = session.exit_detected_at
      ? new Date(session.exit_detected_at).getTime()
      : null;

    if (exitDetectedMs) {
      const minutesSinceExit = (now - exitDetectedMs) / (1000 * 60);
      if (minutesSinceExit >= THRESHOLDS.EXITING_AUTO_CLOSE_MIN) {
        await transitionTo(
          db,
          session,
          "closing",
          { closing_started_at: nowIso, previous_status: "exiting" },
          stats
        );
        return;
      }
    }
    return;
  }

  // G3: escape-hatch — overdue_hard без прогресу. Повторний алерт кожні
  // OVERDUE_HARD_ESCALATE_HOURS, поки ситуація не вирішена. Статус не змінюємо.
  if (session.status === "overdue_hard") {
    const hoursSinceHard = await getHoursSinceLastAlert(
      db,
      session.id,
      "overdue_hard"
    );

    if (
      hoursSinceHard !== null &&
      hoursSinceHard >= THRESHOLDS.OVERDUE_HARD_ESCALATE_HOURS
    ) {
      const created = await createAlertOnce(db, session.id, "overdue_hard", {
        action: "still_unresolved",
        hours_since_hard: Math.round(hoursSinceHard * 10) / 10,
      });
      if (created) stats.alerts_created++;
    }
    return;
  }

  // G5: SOS — лише нагадування (статус НЕ змінюємо, Phase 1).
  if (session.status === "sos") {
    if (session.sos_activated_at) {
      const minSinceSos =
        (now - new Date(session.sos_activated_at).getTime()) / (1000 * 60);

      if (minSinceSos >= THRESHOLDS.SOS_ESCALATE_MIN) {
        // Окремий cooldown, бо createAlertOnce для `sos` має cooldown = 0
        // і створював би alert щохвилини (tick-інтервал).
        const hoursSinceLastSos = await getHoursSinceLastAlert(
          db,
          session.id,
          "sos"
        );
        const minSinceLastSos = hoursSinceLastSos === null
          ? null
          : hoursSinceLastSos * 60;

        if (minSinceLastSos === null || minSinceLastSos >= THRESHOLDS.SOS_ESCALATE_MIN) {
          const created = await createAlertOnce(db, session.id, "sos", {
            action: "sos_unresolved",
            minutes_since_sos: Math.round(minSinceSos),
          });
          if (created) stats.alerts_created++;
        }
      }
    }
    return;
  }

  const movement = await analyzeMovement(db, session.id, session.last_known_at);

  // ─── Geofence (feature-flagged, min-time, 3-state) ─────
  const { data: flag } = await db
    .from("feature_flags")
    .select("enabled")
    .eq("key", "geofence_enabled")
    .maybeSingle();
  const geofenceEnabled = flag?.enabled ?? false;

  const minutesSinceStart =
    (Date.now() - new Date(session.started_at).getTime()) / (1000 * 60);

  if (
    geofenceEnabled &&
    minutesSinceStart >= 15 &&
    session.last_known_coords
  ) {
    const exitResult = await detectForestExit(db, session.id);
    if (
      exitResult.isConfirmedExit &&
      !session.exit_detected_at &&
      !["exiting", "closing", "closed"].includes(session.status)
    ) {
      await transitionTo(
        db,
        session,
        "exiting",
        { exit_detected_at: nowIso, overdue_level: null },
        stats
      );

      const created = await createAlertOnce(db, session.id, "exit", {
        action: "os_auto_detected",
        consecutive_outside: exitResult.consecutiveOutsideCount,
      });
      if (created) stats.alerts_created++;

      return;
    }
  }

  // Overdue рахуємо від original_return — продовження (extend) дозволяє
  // перенести expected_return, але не скидає відлік прострочення.
  const originalReturnMs = new Date(session.original_return).getTime();
  const minutesSinceOriginalReturn = (now - originalReturnMs) / (1000 * 60);

  const isOverdueCondition =
    minutesSinceOriginalReturn >= 0 &&
    (!movement.hasFreshData || !movement.isMoving);

  const overdueThresholds = {
    ...DEFAULT_OVERDUE_THRESHOLDS,
    ...(session.settings.overdue_thresholds ?? {}),
  };

  let targetOverdueLevel: "soft" | "medium" | "hard" | null = null;
  let targetStatus: SessionStatus | null = null;

  if (isOverdueCondition) {
    if (minutesSinceOriginalReturn >= overdueThresholds.hard) {
      targetOverdueLevel = "hard";
      targetStatus = "overdue_hard";
    } else if (minutesSinceOriginalReturn >= overdueThresholds.medium) {
      targetOverdueLevel = "medium";
      targetStatus = "overdue_medium";
    } else if (minutesSinceOriginalReturn >= overdueThresholds.soft) {
      targetOverdueLevel = "soft";
      targetStatus = "overdue_soft";
    }
  }

  if (targetStatus && targetOverdueLevel && session.status !== targetStatus) {
    const currentLevel = session.overdue_level;
    const levels: Array<"soft" | "medium" | "hard"> = ["soft", "medium", "hard"];
    const currentIdx = currentLevel ? levels.indexOf(currentLevel) : -1;
    const targetIdx = levels.indexOf(targetOverdueLevel);

    if (targetIdx > currentIdx) {
      await transitionTo(
        db,
        session,
        targetStatus,
        { overdue_level: targetOverdueLevel },
        stats
      );

      const alertMap: Record<string, "overdue_soft" | "overdue_medium" | "overdue_hard"> = {
        soft: "overdue_soft",
        medium: "overdue_medium",
        hard: "overdue_hard",
      };
      const created = await createAlertOnce(
        db,
        session.id,
        alertMap[targetOverdueLevel],
        {
          minutes_over: Math.round(minutesSinceOriginalReturn),
          level: targetOverdueLevel,
        }
      );
      if (created) stats.alerts_created++;
    }
    return;
  }

  if (
    session.status.startsWith("overdue_") &&
    movement.hasFreshData &&
    movement.isMoving
  ) {
    await transitionTo(
      db,
      session,
      "active",
      { overdue_level: null },
      stats
    );
    return;
  }

  if (minutesSinceLastPing !== null) {
    if (
      session.status === "active" &&
      minutesSinceLastPing >= THRESHOLDS.STALE_MIN
    ) {
      await transitionTo(db, session, "stale", {}, stats);

      const created = await createAlertOnce(db, session.id, "offline", {
        level: "stale",
        minutes_since_ping: Math.round(minutesSinceLastPing),
      });
      if (created) stats.alerts_created++;
      return;
    }

    if (
      session.status === "stale" &&
      minutesSinceLastPing >= THRESHOLDS.OFFLINE_MIN
    ) {
      await transitionTo(db, session, "offline", {}, stats);

      const created = await createAlertOnce(db, session.id, "offline", {
        level: "offline",
        minutes_since_ping: Math.round(minutesSinceLastPing),
      });
      if (created) stats.alerts_created++;
      return;
    }

    if (
      (session.status === "stale" || session.status === "offline") &&
      movement.hasFreshData
    ) {
      await transitionTo(db, session, "active", {}, stats);
      return;
    }
  }

  if (
    session.status === "active" &&
    movement.hasFreshData &&
    !movement.isMoving &&
    minutesSinceLastPing !== null &&
    minutesSinceLastPing >= THRESHOLDS.STATIONARY_MIN
  ) {
    const created = await createAlertOnce(db, session.id, "stationary", {
      minutes_stationary: Math.round(minutesSinceLastPing),
      avg_speed_kmh: movement.avgSpeedKmh,
    });
    if (created) stats.alerts_created++;
  }

  if (
    session.last_battery_pct !== null &&
    session.last_battery_pct <= 10 &&
    session.status === "active"
  ) {
    const created = await createAlertOnce(db, session.id, "battery_low", {
      battery_pct: session.last_battery_pct,
    });
    if (created) stats.alerts_created++;
  }
}

async function transitionTo(
  db: ReturnType<typeof createServiceClient>,
  session: GuardianSession,
  newStatus: SessionStatus,
  extra: Record<string, unknown>,
  stats: TickStats
): Promise<void> {
  const updates = {
    status: newStatus,
    ...extra,
  };

  const { error } = await db
    .from("guardian_sessions")
    .update(updates)
    .eq("id", session.id)
    .eq("status", session.status);

  if (error) {
    console.error(`[tick] transition error for ${session.id}:`, error);
    stats.errors++;
    return;
  }

  stats.transitions_made++;
}

async function finalClose(
  db: ReturnType<typeof createServiceClient>,
  session: GuardianSession,
  reason: string,
  stats: TickStats
): Promise<void> {
  const now = new Date();
  const nowIso = now.toISOString();
  const recoveryWindowMin = session.settings.recovery_window_min ?? 30;
  const recoverableUntil = new Date(
    now.getTime() + recoveryWindowMin * 60 * 1000
  ).toISOString();

  const { error } = await db
    .from("guardian_sessions")
    .update({
      status: "closed",
      closed_at: nowIso,
      recoverable_until: recoverableUntil,
    })
    .eq("id", session.id)
    .neq("status", "closed");

  if (error) {
    console.error(`[tick] final close error for ${session.id}:`, error);
    stats.errors++;
    return;
  }

  stats.transitions_made++;

  const created = await createAlertOnce(db, session.id, "closed", {
    reason,
    recoverable_until: recoverableUntil,
  });
  if (created) stats.alerts_created++;
}
