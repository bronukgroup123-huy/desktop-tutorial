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
 * Перевіряє та інкрементує лічильник запитів для IP + ендпоінта за поточну хвилину.
 * Викликати ПЕРЕД обробкою запиту.
 *
 * Реалізація: атомарний UPSERT через ON CONFLICT DO UPDATE — race-safe.
 */
export async function checkAndIncrementIpRateLimit(
  db: SupabaseClient,
  ip: string,
  endpoint: string,
  limit?: number
): Promise<IpRateLimitResult> {
  const maxCount = limit ?? IP_RATE_LIMITS[endpoint] ?? 60;
  const windowStart = currentMinuteWindowStart();

  const { data, error } = await db.rpc(
    "check_and_increment_ip_rate_limit",
    {
      p_ip: ip,
      p_endpoint: endpoint,
      p_window_start: windowStart,
      p_limit: maxCount,
    }
  );

  // Fallback (якщо RPC ще не задеплоєне): м'який дозвіл + ручний UPSERT.
  if (error) {
    console.warn("[ip-rate-limit] RPC failed, falling back to upsert:", error.message);
    const { data: row, error: upsertError } = await db
      .from("ip_rate_limit")
      .upsert(
        {
          ip,
          endpoint,
          window_start: windowStart,
          count: 1,
        },
        { onConflict: "ip,endpoint,window_start", ignoreDuplicates: false }
      )
      .select("count")
      .single();

    if (upsertError) {
      console.error("[ip-rate-limit] upsert failed:", upsertError.message);
      // Fail-open: краще пропустити запит, ніж блокувати всіх
      return { allowed: true, remaining: maxCount, count: 1 };
    }

    const count = Number(row?.count ?? 1);
    return {
      allowed: count <= maxCount,
      remaining: Math.max(0, maxCount - count),
      count,
      retryAfter: count > maxCount ? 60 : undefined,
    };
  }

  const count = Number(data?.count ?? 1);
  return {
    allowed: count <= maxCount,
    remaining: Math.max(0, maxCount - count),
    count,
    retryAfter: count > maxCount ? 60 : undefined,
  };
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
      now.getUTCMinutes()
    )
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
  retryAfterSeconds: number
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
    }
  );
}
