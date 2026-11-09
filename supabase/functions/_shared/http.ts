// ============================================================================
// Спільний HTTP-шар для клієнтських ендпоінтів v1-* (BACKEND_PLAN B0.4)
//
// Контракт (BACKEND_PLAN §2):
//   успіх   → { "data": ... }
//   помилка → { "error": "snake_case_code", "message"?: "текст для людини (UA)" }
//
// Усі v1-* будуються через `serve()`: CORS-preflight, rate limit, єдиний формат
// помилок і перехоплення непередбачених винятків (500 internal_error).
// Логіка, що не залежить від мережі, тестується з мок-клієнтами.
// ============================================================================

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { buildCorsHeaders } from "./cors.ts";
import {
  checkAndIncrementIpRateLimit,
  getClientIp,
} from "./rate-limit.ts";

// ─── Помилки ───────────────────────────────────────────────────────────────

/** Помилка з HTTP-статусом і машинним кодом; перетворюється на `{ error, message }`. */
export class HttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message?: string,
    public readonly headers: Record<string, string> = {},
  ) {
    super(message ?? code);
    this.name = "HttpError";
  }

  /** Чи було передано людиночитабельне повідомлення (інакше `message` не віддаємо). */
  get hasMessage(): boolean {
    return this.message !== this.code;
  }
}

// ─── Відповіді ─────────────────────────────────────────────────────────────

export function json(
  body: unknown,
  status: number,
  req: Request,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...buildCorsHeaders(req),
      "Content-Type": "application/json",
      ...headers,
    },
  });
}

/** Успішна відповідь `{ data }`. */
export function ok(
  data: unknown,
  req: Request,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return json({ data }, status, req, headers);
}

/** Відповідь-помилка `{ error, message? }`. */
export function fail(
  code: string,
  status: number,
  req: Request,
  message?: string,
  headers: Record<string, string> = {},
): Response {
  const body: Record<string, string> = { error: code };
  if (message) body.message = message;
  return json(body, status, req, headers);
}

export function preflight(req: Request): Response {
  return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
}

function errorToResponse(err: unknown, req: Request): Response {
  if (err instanceof HttpError) {
    return fail(
      err.code,
      err.status,
      req,
      err.hasMessage ? err.message : undefined,
      err.headers,
    );
  }
  console.error("[v1] unhandled error:", err);
  return fail("internal_error", 500, req, "Внутрішня помилка сервера");
}

// ─── Методи ────────────────────────────────────────────────────────────────

export function assertMethod(req: Request, allowed: string[]): void {
  if (!allowed.includes(req.method)) {
    throw new HttpError(405, "method_not_allowed", "Метод не підтримується");
  }
}

export async function readJson(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    throw new HttpError(400, "invalid_json", "Тіло запиту має бути JSON");
  }
}

// ─── Rate limit ────────────────────────────────────────────────────────────

/** Ліміти запитів на IP за хвилину для v1-ендпоінтів. */
export const V1_RATE_LIMITS: Record<string, number> = {
  "v1-forecast": 30,
  "v1-forest-zones": 30,
  "v1-regions": 60,
  "v1-me": 60,
};

/** Мінімальний тип клієнта, потрібний для rate limit (RPC + fallback upsert). */
type RateLimitDb = Parameters<typeof checkAndIncrementIpRateLimit>[0];

export async function enforceRateLimit(
  db: RateLimitDb,
  req: Request,
  endpoint: string,
): Promise<void> {
  const rl = await checkAndIncrementIpRateLimit(
    db,
    getClientIp(req),
    endpoint,
    V1_RATE_LIMITS[endpoint],
  );
  if (!rl.allowed) {
    const retry = rl.retryAfter ?? 60;
    throw new HttpError(
      429,
      "rate_limited",
      `Забагато запитів. Спробуйте через ${retry} сек.`,
      { "Retry-After": String(retry) },
    );
  }
}

// ─── Автентифікація ────────────────────────────────────────────────────────

/** Користувач із JWT Supabase. Гість (ADR-001) — анонімний користувач з реальним UUID. */
export interface AuthUser {
  id: string;
  isAnonymous: boolean;
}

/** Перевіряє JWT і повертає користувача або null (інжектується для тестів). */
export type TokenVerifier = (jwt: string) => Promise<AuthUser | null>;

export function bearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization");
  if (!header || !header.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

/** Обов'язковий JWT. 401 `unauthorized`, якщо токена немає або він недійсний. */
export async function requireUser(
  req: Request,
  verify: TokenVerifier,
): Promise<AuthUser> {
  const token = bearerToken(req);
  if (!token) {
    throw new HttpError(401, "unauthorized", "Потрібна авторизація");
  }
  const user = await verify(token);
  if (!user) {
    throw new HttpError(401, "unauthorized", "Сесія недійсна або прострочена");
  }
  return user;
}

/** Гостям (ADR-001) заборонено: публічні/дружні точки, SOS, сесії Наглядача, друзі. */
export function assertRegistered(user: AuthUser): void {
  if (user.isAnonymous) {
    throw new HttpError(
      403,
      "registration_required",
      "Ця дія доступна після реєстрації. Увійдіть через Google, Apple або телефон.",
    );
  }
}

// ─── Профіль користувача (Home Region) ─────────────────────────────────────

/** Мінімальний тип для читання `users` (сумісний із supabase-js). */
export interface UsersReadDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
}

/** home_region_id користувача; 404 `me_not_found`, якщо немає рядка `users`. */
export async function loadHomeRegionId(
  db: UsersReadDb,
  userId: string,
): Promise<number | null> {
  const { data, error } = await db
    .from("users")
    .select("home_region_id")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    console.error("[v1] users query failed:", error);
    throw new HttpError(500, "db_error", "Помилка бази даних");
  }
  if (!data) {
    throw new HttpError(404, "me_not_found", "Профіль не знайдено");
  }
  const id = (data as { home_region_id: number | null }).home_region_id;
  return id ?? null;
}

/** Home Region обов'язковий для геоданих (Правило №1: без області карта не завантажується). */
export function requireHomeRegion(homeRegionId: number | null): number {
  if (homeRegionId === null) {
    throw new HttpError(
      409,
      "home_region_required",
      "Спочатку оберіть свою область",
    );
  }
  return homeRegionId;
}

// ─── Supabase-клієнти (продакшн) ───────────────────────────────────────────

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) {
    throw new HttpError(500, "internal_error", "Сервер неправильно налаштований");
  }
  return v;
}

export function serviceClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Перевірка JWT через Supabase Auth (getUser). */
export const supabaseTokenVerifier: TokenVerifier = async (jwt) => {
  const client = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(jwt);
  if (error || !data?.user) return null;
  return { id: data.user.id, isAnonymous: data.user.is_anonymous === true };
};

// ─── Обгортка обробника ────────────────────────────────────────────────────

/** OPTIONS → 204; винятки → єдиний формат помилки. */
export function handle(
  handler: (req: Request) => Promise<Response>,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method === "OPTIONS") return preflight(req);
    try {
      return await handler(req);
    } catch (err) {
      return errorToResponse(err, req);
    }
  };
}
