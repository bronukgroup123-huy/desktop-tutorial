// ============================================================================
// GET v1-app-config — налаштування застосунку, що змінюються без релізу (B4.3, B4.10)
//
// Публічний (гостю теж — ADR-001: безпека без даних користувача), rate limit, ETag.
// 200 { data: { safety: SafetyContent } } · 304 · 405 · 429
// Банери й тексти безпеки — типові (`safety-content.ts`) + `feature_flags`:
// `safety_notices` (масив банерів, ADR-003) і `safety_content` (часткова заміна текстів).
// Збій БД — типові тексти: безпека не може зламатися через налаштування.
// ============================================================================

import { assertMethod, enforceRateLimit, ok } from "../http.ts";
import { buildCorsHeaders } from "../cors.ts";
import { etagFor } from "./regions.ts";
import { mergeSafetyContent } from "./safety-content.ts";

export interface AppConfigDb {
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
  from(table: string): {
    select(cols: string): {
      in(col: string, vals: string[]): PromiseLike<{ data: unknown; error: unknown }>;
    };
  };
}

export const SAFETY_FLAG_KEYS = ["safety_notices", "safety_content"];

export async function handleAppConfig(req: Request, deps: { db: AppConfigDb }): Promise<Response> {
  assertMethod(req, ["GET"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-app-config");

  const flags: Record<string, unknown> = {};
  try {
    const { data, error } = await deps.db.from("feature_flags").select("key, enabled, value").in("key", SAFETY_FLAG_KEYS);
    if (error) throw error;
    for (const row of (data as Array<{ key: string; enabled: boolean; value: unknown }> | null) ?? []) {
      if (row.enabled !== false) flags[row.key] = row.value;
    }
  } catch (err) {
    console.warn("[v1-app-config] feature_flags unavailable, defaults:", err);
  }

  const payload = { safety: mergeSafetyContent(flags.safety_notices, flags.safety_content) };
  const body = JSON.stringify({ data: payload });
  const etag = await etagFor(body);
  const cacheHeaders = { "Cache-Control": "public, max-age=3600", "ETag": etag };
  if (req.headers.get("If-None-Match") === etag) {
    return new Response(null, { status: 304, headers: { ...buildCorsHeaders(req), ...cacheHeaders } });
  }
  return ok(payload, req, 200, cacheHeaders);
}
