// ============================================================================
// Edge Functions — IP-based Rate Limiting (CT-14)
//
// Захист від спаму/ботів на публічних ендпоінтах (/forecast, /picks, /regions, /catalog).
// Використовує таблицю ip_rate_limit + атомарний RPC UPSERT (race-safe).
//
// IP береться з заголовка x-forwarded-for (Supabase Edge Functions передають реальний IP клієнта там).
// ============================================================================

import { buildCorsHeaders } from "./cors.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Ліміти запитів на IP за хвилину за ендпоінтом */
export const IP_RATE_LIMITS: Record<string, number> = {
  forecast: 30,
  picks: 10,
  regions: 60,
  catalog: 60,
};

/** Результат перевірки ліміту */
export interface IpRateLimitResult {
  allowed: boolean;
  remaining: number;
  count: number;
  retryAfter?: number; // секунди до скидання вікна
}

/**
 * Лічильник не зміг прийняти надійне рішення. Викликач має повернути 503,
 * а не пропускати запит без захисту від зловживань.
 */
export class RateLimitUnavailableError extends Error {
  constructor() {
    super("Rate limit service is unavailable");
    this.name = "RateLimitUnavailableError";
  }
}

/**
 * Перевіряє та інкрементує лічильник запитів для IP + ендпоінта за поточну хвилину.
 * Викликати ПЕРЕД обробкою запиту.
 *
 * Реалізація: атомарний UPSERT через ON CONFLICT DO UPDATE — race-safe.
 */
export async function checkAndIncrementIpRateLimit(
  db: SupabaseClient,
  ip: string,
  endpoint: string,
  limit?: number,
): Promise<IpRateLimitResult> {
  const maxCount = limit ?? IP_RATE_LIMITS[endpoint] ?? 60;
  const windowStart = currentMinuteWindowStart();

  let result: { data: unknown; error: { message?: string } | null };
  try {
    result = await db.rpc(
      "check_and_increment_ip_rate_limit",
      {
        p_ip: ip,
        p_endpoint: endpoint,
        p_window_start: windowStart,
        p_limit: maxCount,
      },
    );
  } catch (error) {
    console.error("[ip-rate-limit] RPC request failed:", error);
    throw new RateLimitUnavailableError();
  }

  if (result.error) {
    console.error(
      "[ip-rate-limit] RPC failed:",
      result.error.message ?? "unknown database error",
    );
    throw new RateLimitUnavailableError();
  }

  const count = readRateLimitCount(result.data);
  if (!Number.isSafeInteger(count) || count < 1) {
    console.error("[ip-rate-limit] RPC returned an invalid count");
    throw new RateLimitUnavailableError();
  }

  return {
    allowed: count <= maxCount,
    remaining: Math.max(0, maxCount - count),
    count,
    retryAfter: count > maxCount ? 60 : undefined,
  };
}

/** PostgREST повертає RETURNS TABLE як масив; моки та старі шлюзи могли повертати об'єкт. */
function readRateLimitCount(data: unknown): number {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object" || !("count" in row)) return Number.NaN;
  return Number((row as { count: unknown }).count);
}

/** Початок поточної хвилинної вікна (truncate до хвилини у UTC). */
function currentMinuteWindowStart(): string {
  const now = new Date();
  const truncated = new Date(
    Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate(),
      now.getUTCHours(),
      now.getUTCMinutes(),
    ),
  );
  return truncated.toISOString();
}

/** Витягти IP клієнта з заголовків (x-forwarded-for або remoteAddr). */
export function getClientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    // x-forwarded-for може містити список: client, proxy1, proxy2 — беремо перший (клієнт)
    return xff.split(",")[0].trim();
  }
  return "unknown";
}

/** JSON-відповідь 429 з заголовком Retry-After */
export function rateLimitResponse(
  req: Request,
  retryAfterSeconds: number,
): Response {
  return new Response(
    JSON.stringify({
      error: "rate_limited",
      message: `Забагато запитів. Спробуйте через ${retryAfterSeconds} сек.`,
    }),
    {
      status: 429,
      headers: {
        ...buildCorsHeaders(req),
        "Content-Type": "application/json",
        "Retry-After": String(retryAfterSeconds),
      },
    },
  );
}

/** Fail-closed policy for both public reads and mutations when the counter is unavailable. */
export function rateLimitUnavailableResponse(req: Request): Response {
  return new Response(
    JSON.stringify({
      error: "rate_limit_unavailable",
      message: "Сервіс тимчасово недоступний. Спробуйте ще раз.",
    }),
    {
      status: 503,
      headers: {
        ...buildCorsHeaders(req),
        "Content-Type": "application/json",
        "Retry-After": "5",
      },
    },
  );
}
