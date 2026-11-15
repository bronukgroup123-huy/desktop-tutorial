// ============================================================================
// v1-wave-alerts — щоденні сповіщення «Почалась хвиля» (ADR-015 §15.8 п.19)
//
// POST v1-wave-alerts (лише service_role; запускає GitHub Actions за розкладом, ~07:15 Київ)
//   → 200 { data: { users, areas, sent, skipped } }
//
// Для кожного користувача з пристроєм (сповіщення ввімкнено) і доступом (Pro або «Слідопит»):
// аналіз кожної ділянки на сьогодні (збережений або безкоштовне щоденне оновлення), і якщо в
// найкращого виду або альтернативи хвиля почалась (1–2-й день, рівень від середнього) —
// одне сповіщення на хвилю: «Броники: зимовий опеньок — хвиля почалась. Найкращий день: пт».
// ============================================================================

import { HttpError, ok } from "../http.ts";
import { type AnalysisDeps, alertAnalysis, type AreaRow, kyivToday, loadUserAreas } from "./analysis.ts";

export interface WaveAlert {
  species: string;
  waveStart: string;
  title: string;
  body: string;
}

export interface WaveAlertDeps extends AnalysisDeps {
  /** Ключ service_role — лише з ним можна запустити розсилку. */
  serviceKey: string;
  /** Надіслати push; `unregistered` — токен більше не дійсний. */
  send: (token: string, msg: { title: string; body: string; data: Record<string, string> }) => Promise<
    { ok: boolean; unregistered?: boolean }
  >;
  /** Тестування: сповіщати всіх, не лише Pro / «Слідопит». */
  allowAll?: boolean;
}

function shiftDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Хвиля почалась (1–2-й день, рівень від середнього) у найкращого виду або альтернативи. */
export function waveStartAlert(data: Record<string, unknown>, areaTitle: string, today: string): WaveAlert | null {
  const days = (data.days as Array<Record<string, unknown>> | undefined) ?? [];
  const day = days.find((d) => d.date === today) ?? days[0];
  if (!day) return null;
  for (const key of ["top1", "alternative"]) {
    const s = day[key] as
      | { mushroom_type?: string; name_ua?: string; level?: string; wave?: { phase?: string; day?: number; days?: number } }
      | null
      | undefined;
    const w = s?.wave;
    if (!s?.mushroom_type || !w || w.phase !== "flush" || !w.day || w.day > 2) continue;
    if (!["medium", "high", "peak"].includes(String(s.level))) continue;
    const best = (data.best_day as { label?: string } | null | undefined)?.label;
    return {
      species: s.mushroom_type,
      waveStart: shiftDays(today, -(w.day - 1)),
      title: `${areaTitle}: ${String(s.name_ua).toLowerCase()} — хвиля почалась`,
      body: [`${w.day}-й день хвилі з ${w.days}.`, best ? `${best}.` : null, "Подивіться прогноз ділянки."]
        .filter(Boolean).join(" "),
    };
  }
  return null;
}

export async function handleWaveAlerts(req: Request, deps: WaveAlertDeps): Promise<Response> {
  if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Лише POST");
  const auth = req.headers.get("Authorization") ?? "";
  if (!deps.serviceKey || auth !== `Bearer ${deps.serviceKey}`) throw new HttpError(401, "unauthorized", "Лише для розкладу");
  const now = deps.now ? deps.now() : new Date();
  const today = kyivToday(now);

  const { data, error } = await deps.db.rpc("wave_alert_targets", {});
  if (error) throw new HttpError(500, "db_error", "Не вдалося отримати пристрої");
  const targets = (Array.isArray(data) ? data : []) as Array<{ user_id: string; tokens: string[] }>;

  let areasChecked = 0, sent = 0, skipped = 0;
  for (const t of targets) {
    const areas = await loadUserAreas(deps.db, t.user_id) as AreaRow[];
    for (const row of areas) {
      areasChecked++;
      let res: Awaited<ReturnType<typeof alertAnalysis>>;
      try {
        res = await alertAnalysis(deps, t.user_id, row, now);
      } catch (err) {
        console.warn("[v1-wave-alerts] analysis failed:", err);
        skipped++;
        continue;
      }
      if (!res || (!res.allowed && !deps.allowAll)) {
        skipped++;
        continue;
      }
      const title = (row.label && row.label.trim()) || `Ділянка ${row.slot}`;
      const alert = waveStartAlert(res.data, title, today);
      if (!alert) continue;
      const claim = await deps.db.rpc("claim_wave_alert", {
        p_area_id: row.id, p_species: alert.species, p_wave_start: alert.waveStart,
      });
      if (claim.error || claim.data !== true) continue; // уже надсилали цю хвилю
      for (const token of t.tokens) {
        const r = await deps.send(token, {
          title: alert.title,
          body: alert.body,
          data: { type: "wave_start", area_id: row.id, species: alert.species },
        });
        if (r.ok) sent++;
        else if (r.unregistered) await deps.db.rpc("drop_push_device", { p_token: token });
      }
    }
  }
  return ok({ users: targets.length, areas: areasChecked, sent, skipped }, req);
}
