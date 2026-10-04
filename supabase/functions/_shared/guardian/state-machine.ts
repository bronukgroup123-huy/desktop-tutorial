import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { SessionStatus, GuardianSession } from "./types.ts";

export const USER_TRANSITIONS: Record<SessionStatus, SessionStatus[]> = {
  pending:         ["active", "closed", "sos", "closing"],
  active:          ["exiting", "closing", "sos", "stale", "offline", "overdue_soft"],
  stale:           ["active", "exiting", "closing", "sos", "offline", "overdue_soft"],
  offline:         ["active", "exiting", "closing", "sos", "overdue_soft"],
  exiting:         ["active", "closing", "sos", "closed"],
  overdue_soft:    ["active", "exiting", "closing", "sos", "overdue_medium"],
  overdue_medium:  ["active", "exiting", "closing", "sos", "overdue_hard"],
  overdue_hard:    ["active", "exiting", "closing", "sos"],
  sos:             ["closing", "active"],
  closing:         ["active", "closed"],
  closed:          ["active"],
};

export const TIME_TRANSITIONS: Record<SessionStatus, SessionStatus[]> = {
  pending:         ["closed"],
  active:          ["stale", "overdue_soft"],
  stale:           ["offline", "overdue_soft"],
  offline:         ["overdue_soft", "overdue_medium"],
  exiting:         ["closed"],
  overdue_soft:    ["overdue_medium", "overdue_hard"],
  overdue_medium:  ["overdue_hard"],
  overdue_hard:    [],
  sos:             [],
  closing:         ["closed"],
  closed:          [],
};

export interface TransitionCheck {
  allowed: boolean;
  reason?: string;
}

export function canUserTransition(
  from: SessionStatus,
  to: SessionStatus
): TransitionCheck {
  if (from === to) {
    return { allowed: false, reason: `Already in status '${from}'` };
  }
  const allowed = USER_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    return {
      allowed: false,
      reason: `Transition ${from} → ${to} not allowed by user`,
    };
  }
  return { allowed: true };
}

export interface TransitionOptions {
  savePreviousStatus?: boolean;
  extraUpdates?: Record<string, unknown>;
}

export async function transitionSession(
  db: SupabaseClient,
  session: GuardianSession,
  to: SessionStatus,
  options: TransitionOptions = {}
): Promise<GuardianSession> {
  const check = canUserTransition(session.status, to);
  if (!check.allowed) {
    throw new Error(`Invalid transition: ${check.reason}`);
  }

  const updates: Record<string, unknown> = {
    status: to,
    ...(options.extraUpdates ?? {}),
  };

  if (options.savePreviousStatus) {
    updates.previous_status = session.status;
  }

  const { data, error } = await db
    .from("guardian_sessions")
    .update(updates)
    .eq("id", session.id)
    .select("*")
    .single();

  if (error) throw error;
  return data as GuardianSession;
}
