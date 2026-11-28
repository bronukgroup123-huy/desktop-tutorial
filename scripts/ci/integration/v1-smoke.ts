/// <reference lib="deno.window" />
// ============================================================================
// B0.8: справжні v1-обробники проти справжньої БД з усіма міграціями (локальний Supabase у CI).
//
// Навіщо: unit-тести підміняють БД (mock-db), тож розбіжності «код ↔ схема» їх не ловлять. Так сталося
// OPS-002 (2026-11-26): CHECK на ip_rate_limit.endpoint відхиляв нові назви, і кожен v1-запит у
// продакшені отримував 503. Тут кожен виклик іде через справжній обмежувач (RPC), RLS і SQL-функції.
//
// Запуск (див. .github/workflows/integration.yml):
//   API_URL=… ANON_KEY=… SERVICE_ROLE_KEY=… deno run --allow-net --allow-env scripts/ci/integration/v1-smoke.ts
// Без зовнішніх мереж: Open-Meteo, тривоги, Telegram не викликаємо.
// ============================================================================

const API = Deno.env.get("API_URL") ?? "http://127.0.0.1:54321";
const ANON = Deno.env.get("ANON_KEY") ?? Deno.env.get("PUBLISHABLE_KEY") ?? "";
const SERVICE = Deno.env.get("SERVICE_ROLE_KEY") ?? Deno.env.get("SECRET_KEY") ?? "";
if (!ANON || !SERVICE) throw new Error("ANON_KEY і SERVICE_ROLE_KEY потрібні (supabase status -o env)");

const failures: string[] = [];
let passed = 0;

async function json(res: Response): Promise<Record<string, unknown>> {
  const text = await res.text();
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    return { raw: text.slice(0, 300) };
  }
}

/** Виклик функції; очікуваний статус — інакше записуємо збій (з тілом, щоб було видно причину). */
async function call(
  label: string,
  method: string,
  path: string,
  opts: { token?: string; body?: unknown; expect?: number[] } = {},
): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = { apikey: ANON, "x-forwarded-for": "198.51.100.7" };
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(`${API}/functions/v1/${path}`, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  const body = await json(res);
  const expect = opts.expect ?? [200];
  if (expect.includes(res.status)) {
    passed++;
    console.log(`✓ ${label} — ${res.status}`);
  } else {
    failures.push(`${label}: ${method} ${path} → ${res.status} ${JSON.stringify(body).slice(0, 400)}`);
    console.log(`✗ ${label} — ${res.status} ${JSON.stringify(body).slice(0, 400)}`);
  }
  return (body.data ?? body) as Record<string, unknown>;
}

async function auth(path: string, body: unknown, key = ANON): Promise<Record<string, unknown>> {
  const res = await fetch(`${API}/auth/v1/${path}`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await json(res);
  if (!res.ok) throw new Error(`auth ${path} → ${res.status} ${JSON.stringify(data)}`);
  return data;
}

// ─── Користувачі: гість (анонімний вхід, ADR-001) і зареєстрований ───────────
const guest = (await auth("signup", { data: {} })).access_token as string;
const email = `ci-${crypto.randomUUID().slice(0, 8)}@example.test`;
const password = `Ci-${crypto.randomUUID()}`;
await auth("admin/users", { email, password, email_confirm: true }, SERVICE);
const user = (await auth("token?grant_type=password", { email, password })).access_token as string;

// ─── Публічні ───────────────────────────────────────────────────────────────
await call("regions geometry (public)", "GET", "v1-regions/lvivska/geometry?detail=low");
await call("app-config (public)", "GET", "v1-app-config");

// ─── Онбординг: область і згода ──────────────────────────────────────────────
const me = await call("me", "GET", "v1-me", { token: user });
const terms = ((me.onboarding ?? {}) as Record<string, unknown>).terms_version;
await call("me: choose home region + accept terms", "PATCH", "v1-me", {
  token: user,
  body: { home_region_slug: "lvivska", ...(terms ? { accept_terms_version: terms } : {}) },
});

// ─── Тук-туки, друзі, аналіз, тести знань ───────────────────────────────────
await call("picks map", "GET", "v1-picks/map", { token: user });
await call("picks species", "GET", "v1-picks/species", { token: user });
await call("picks shared with me", "GET", "v1-picks/shared", { token: user });
// друзі потребують ніка (409 profile_required без нього) — задаємо нік і перевіряємо обидва випадки
await call("friends without a handle → profile_required", "GET", "v1-friends", { token: user, expect: [409] });
const handle = `гриб_${Math.floor(Math.random() * 1e6)}`;
await call("me: set handle", "PATCH", "v1-me", { token: user, body: { handle } });
await call("friends", "GET", "v1-friends", { token: user });
await call("analysis overview", "GET", "v1-analysis", { token: user });
await call("analysis feedback context", "GET", "v1-analysis/feedback?lat=49.84&lng=24.03", { token: user });
const quiz = await call("quiz overview", "GET", "v1-quiz", { token: user });
const modules = (quiz.modules ?? []) as Array<Record<string, unknown>>;
if (!modules.some((m) => m.id === "app" && m.status === "open")) {
  failures.push(`quiz: модуль app має бути відкритий, маємо ${JSON.stringify(modules.map((m) => [m.id, m.status]))}`);
}
const attempt = await call("quiz practice attempt", "POST", "v1-quiz/attempts", {
  token: user,
  body: { module_id: "app", practice: true },
});
const questions = (attempt.questions ?? []) as unknown[];
if (questions.length !== 15) failures.push(`quiz: у спробі ${questions.length} питань, очікувалось 15`);

// ─── Гість: дозволене працює, заборонене — 403, а не 5xx ─────────────────────
await call("guest me", "GET", "v1-me", { token: guest });
await call("guest quiz overview", "GET", "v1-quiz", { token: guest });
await call("guest friends → registration_required", "GET", "v1-friends", { token: guest, expect: [403] });

// ─── Без токена — 401 (і не 5xx) ─────────────────────────────────────────────
await call("me without token → 401", "GET", "v1-me", { expect: [401] });

console.log(`\n${passed} перевірок пройшло, ${failures.length} — ні`);
if (failures.length) {
  console.error("\nЗбої:\n" + failures.map((f) => `- ${f}`).join("\n"));
  Deno.exit(1);
}
