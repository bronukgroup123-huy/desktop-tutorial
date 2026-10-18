import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

// ============================================================================
// Rate limiting для нотифікацій (захист від SMS-фроду / спаму)
// Атомарний UPSERT — race-safe навіть при паралельних dispatch.
// ============================================================================

/** Ліміт повідомлень на user за годинне вікно */
export const RATE_LIMITS: Record<string, number> = {
  sms: 5,
  telegram: 10, // Telegram дешевший/SMS — але резервуємо на Phase C
};

export interface RateLimitResult {
  allowed: boolean;
  /** Залишок ліміту ПІСЛЯ цього запиту */
  remaining: number;
  /** Поточний count у вікні (для діагностики) */
  count: number;
}

/**
 * Перевіряє та інкрементує лічильник. Викликати ПЕРЕД кожною відправкою.
 *
 * Реалізація: атомарний UPSERT через ON CONFLICT DO UPDATE.
 * Оскільки `count = count + 1` виконується всередині одного statement,
 * паралельні виклики не втрачають інкременти (race-free).
 */
export async function checkAndIncrementRateLimit(
  db: SupabaseClient,
  userId: string,
  channel: keyof typeof RATE_LIMITS | string,
  limit?: number,
  windowHours = 1
): Promise<RateLimitResult> {
  const maxCount = limit ?? RATE_LIMITS[channel] ?? 5;
  const windowStart = currentWindowStart(windowHours);

  const { data, error } = await db.rpc(
    "check_and_increment_rate_limit",
    {
      p_user_id: userId,
      p_channel: channel,
      p_window_start: windowStart,
    }
  );

  // Fallback (якщо RPC ще не задеплоєне): м'який дозвіл + ручний UPSERT.
  if (error) {
    const { data: row, error: upsertError } = await db
      .from("notification_rate_limit")
      .upsert(
        {
          user_id: userId,
          channel,
          window_start: windowStart,
          count: 1,
        },
        { onConflict: "user_id,channel,window_start", ignoreDuplicates: false }
      )
      .select("count")
      .single();

    if (upsertError) {
      console.error("[rate-limit] RPC and upsert failed:", upsertError.message);
      // Fail-open для нотифікацій безпеки: краще надіслати, ніж втратити тривогу
      return { allowed: true, remaining: maxCount, count: 1 };
    }

    const count = Number(row?.count ?? 1);
    return {
      allowed: count <= maxCount,
      remaining: Math.max(0, maxCount - count),
      count,
    };
  }

  const count = Number(data?.count ?? 1);
  return {
    allowed: count <= maxCount,
    remaining: Math.max(0, maxCount - count),
    count,
  };
}

/**
 * Початок поточного вікна (truncate до години у UTC).
 * RPC рахує window сам — але для fallback-шляху потрібно узгодити.
 */
function currentWindowStart(windowHours: number): string {
  const now = Date.now();
  const windowMs = windowHours * 60 * 60 * 1000;
  const truncated = Math.floor(now / windowMs) * windowMs;
  return new Date(truncated).toISOString();
}

/** Чи дозволено надіслати, не інкрементуючи (для UI-підказок) */
export function rateLimitExceeded(result: RateLimitResult): boolean {
  return !result.allowed;
}
