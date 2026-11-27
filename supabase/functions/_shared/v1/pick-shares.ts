// ============================================================================
// v1-picks: поділитися приватною точкою з другом (BACKEND_PLAN B9.4; ADR-021 §21.5)
//
// POST   v1-picks/{id}/shares             { friend_ids: [uuid, …] }  → { data: { shared, recipients, label } }
// DELETE v1-picks/{id}/shares             — відкликати в усіх        → { data: { revoked } }
// DELETE v1-picks/{id}/shares/{friend_id} — відкликати в одного      → { data: { revoked } }
// GET    v1-picks/shared                  — точки, якими поділились зі мною
//   → { data: { picks: [{ id, lat, lng, is_exact, species_id, name_label, shared_from_label, date_label }] } }
//
// Ділитися можна лише своєю приватною точкою і лише з друзями; переслати далі друг не може.
// Усі правила (друзі, ліміт 20, кінець дружби) — у SQL `share_pick` / `revoke_pick_share`.
// ============================================================================

import { assertRegistered, type AuthUser, HttpError, ok, readJson } from "../http.ts";
import { speciesLabel } from "../picks/presentation.ts";
import { dateLabel } from "./picks-map.ts";
import type { PicksDeps } from "./picks.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const MAX_SHARE_BATCH = 20;

const STATUS: Record<string, number> = {
  pick_not_found: 404,
  not_private: 409,
  not_friend: 403,
  share_limit: 409,
  validation_error: 400,
};

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-picks] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

function refuse(r: Record<string, unknown>): never {
  const code = typeof r.code === "string" ? r.code : "validation_error";
  throw new HttpError(STATUS[code] ?? 400, code, typeof r.message === "string" ? r.message : "Не вдалося");
}

/** «Від @Олена» — підпис поширеної точки (ADR-021 §21.5). */
export function sharedFromLabel(handle: string | null | undefined): string | null {
  if (handle === undefined || handle === null) return null;
  return handle ? `Від @${handle}` : "Від друга";
}

/** «Бачать 2 друзі» — підпис у картці своєї точки. */
export function sharedWithLabel(count: number): string | null {
  if (!count || count <= 0) return null;
  const m10 = count % 10, m100 = count % 100;
  const word = m10 === 1 && m100 !== 11 ? "друг" : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? "друзі" : "друзів";
  return `Бачать ${count} ${word}`;
}

export function parseFriendIds(body: unknown): string[] {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "validation_error", "Тіло запиту має бути JSON-об'єктом");
  }
  const raw = (body as Record<string, unknown>).friend_ids;
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_SHARE_BATCH) {
    throw new HttpError(400, "validation_error", `friend_ids — від 1 до ${MAX_SHARE_BATCH} друзів`);
  }
  if (raw.some((x) => typeof x !== "string" || !UUID_RE.test(x))) {
    throw new HttpError(400, "validation_error", "friend_ids — id друзів");
  }
  return [...new Set((raw as string[]).map((x) => x.toLowerCase()))];
}

export async function sharePick(req: Request, pickId: string, user: AuthUser, deps: PicksDeps): Promise<Response> {
  assertRegistered(user);
  const friendIds = parseFriendIds(await readJson(req));
  const { data, error } = await deps.db.rpc("share_pick", {
    p_user_id: user.id,
    p_pick_id: pickId,
    p_recipient_ids: friendIds,
  });
  if (error) dbFail("share_pick", error);
  const r = (data ?? {}) as Record<string, unknown>;
  if (r.ok !== true) refuse(r);
  const recipients = Number(r.recipients ?? 0);
  return ok({ shared: Number(r.shared ?? 0), recipients, label: sharedWithLabel(recipients) }, req);
}

export async function revokeShare(
  req: Request,
  pickId: string,
  friendId: string | null,
  user: AuthUser,
  deps: PicksDeps,
): Promise<Response> {
  const { data, error } = await deps.db.rpc("revoke_pick_share", {
    p_user_id: user.id,
    p_pick_id: pickId,
    p_recipient_id: friendId,
  });
  if (error) dbFail("revoke_pick_share", error);
  const r = (data ?? {}) as Record<string, unknown>;
  if (r.ok !== true) refuse(r);
  return ok({ revoked: Number(r.revoked ?? 0) }, req);
}

interface SharedRow {
  id: string;
  lat: number;
  lng: number;
  species_id: string | null;
  name_ua: string | null;
  from_handle: string | null;
  shared_at: string | null;
}

export async function listSharedWithMe(req: Request, user: AuthUser, deps: PicksDeps): Promise<Response> {
  const { data, error } = await deps.db.rpc("picks_shared_with_me", { p_user_id: user.id, p_limit: 200 });
  if (error) dbFail("picks_shared_with_me", error);
  const rows = Array.isArray(data) ? (data as SharedRow[]) : [];
  return ok({
    picks: rows.map((row) => ({
      id: row.id,
      lat: row.lat,
      lng: row.lng,
      is_exact: true,
      species_id: row.species_id ?? null,
      name_label: speciesLabel(row.name_ua),
      shared_from_label: sharedFromLabel(row.from_handle ?? ""),
      date_label: dateLabel(row.shared_at),
    })),
  }, req);
}
