// ============================================================================
// GET v1-air-alerts — повітряна тривога по областях (ADR-022 §22.5 п.5, BACKEND_PLAN B4.12)
//
// Дані — офіційний сервіс тривог alerts.in.ua (`GET /v1/alerts/active.json`, ключ —
// секрет `ALERTS_IN_UA_TOKEN`). Ключа немає або сервіс недоступний — `available: false`,
// застосунок банер не показує (без помилок). ОДИН запит на всю Україну розкладається по
// областях; кеш 45 с — спільний для всіх копій функції (таблиця air_alerts_cache, оновлює
// одна копія за раз), If-Modified-Since, пауза після 429. Клієнт питає раз на хвилину.
// GET ?region=<slug> — лише своя область.
// 200 { data: { available, updated_at, regions: [{ slug, scope: "oblast" | "part", title }] } }
// Публічний: стан тривог — відкриті дані, без даних користувача (гостю теж).
// ============================================================================

import { assertMethod, enforceRateLimit, ok } from "../http.ts";

export const ALERTS_URL = "https://api.alerts.in.ua/v1/alerts/active.json";
export const ALERTS_TTL_MS = 45_000;

/** Назва області в alerts.in.ua («Житомирська область», «м. Київ») → slug області застосунку. */
const OBLAST_SLUGS: Record<string, string> = {
  "Вінницька": "vinnytska",
  "Волинська": "volynska",
  "Дніпропетровська": "dnipropetrovska",
  "Донецька": "donetska",
  "Житомирська": "zhytomyrska",
  "Закарпатська": "zakarpatska",
  "Запорізька": "zaporizka",
  "Івано-Франківська": "ivano-frankivska",
  "Київська": "kyivska",
  "Кіровоградська": "kirovohradska",
  "Луганська": "luhanska",
  "Львівська": "lvivska",
  "Миколаївська": "mykolaivska",
  "Одеська": "odeska",
  "Полтавська": "poltavska",
  "Рівненська": "rivnenska",
  "Сумська": "sumska",
  "Тернопільська": "ternopilska",
  "Харківська": "kharkivska",
  "Херсонська": "khersonska",
  "Хмельницька": "khmelnytska",
  "Черкаська": "cherkaska",
  "Чернівецька": "chernivetska",
  "Чернігівська": "chernihivska",
  "Автономна Республіка Крим": "krym",
};

/** slug області за назвою з сервісу тривог; Київ — частина Київської області застосунку. */
export function oblastSlug(name: string | null | undefined): { slug: string; city: boolean } | null {
  if (!name) return null;
  const n = name.trim();
  if (/^м\.\s*Київ$/.test(n)) return { slug: "kyivska", city: true };
  if (/^м\.\s*Севастополь$/.test(n)) return { slug: "krym", city: true };
  const base = n.replace(/\s+область$/, "");
  const slug = OBLAST_SLUGS[base] ?? (/Крим/.test(n) ? "krym" : undefined);
  return slug ? { slug, city: false } : null;
}

export interface AirAlertRegion {
  slug: string;
  /** `oblast` — тривога на всю область; `part` — у частині (район, громада, місто). */
  scope: "oblast" | "part";
  title: string;
}

/** Активні повітряні тривоги → області застосунку (одна область — один запис, «уся» важливіша). */
export function parseAlerts(raw: unknown): AirAlertRegion[] {
  const alerts = (raw as { alerts?: unknown } | null)?.alerts;
  if (!Array.isArray(alerts)) return [];
  // slug → місця тривоги в частині області; `null` — тривога на всю область.
  const parts = new Map<string, string[] | null>();
  for (const a of alerts) {
    if (!a || typeof a !== "object") continue;
    const o = a as Record<string, unknown>;
    if (o.alert_type !== "air_raid" || o.finished_at) continue;
    const region = oblastSlug((o.location_oblast ?? o.location_title) as string | undefined);
    if (!region) continue;
    const whole = o.location_type === "oblast" && !region.city;
    const prev = parts.get(region.slug);
    if (whole) {
      parts.set(region.slug, null);
    } else if (prev !== null) {
      const place = String(o.location_title ?? "частина області");
      parts.set(region.slug, prev ? [...new Set([...prev, place])] : [place]);
    }
  }
  return [...parts.entries()]
    .map(([slug, places]): AirAlertRegion =>
      places === null
        ? { slug, scope: "oblast", title: "Повітряна тривога в області" }
        : {
          slug,
          scope: "part",
          title: `Повітряна тривога: ${places.slice(0, 3).join(", ")}${places.length > 3 ? " та ін." : ""}`,
        }
    )
    .sort((a, b) => a.slug.localeCompare(b.slug));
}

/** Відповідь alerts.in.ua: 200 — список; 304 — без змін (If-Modified-Since); 429 — забагато запитів. */
export interface AlertsResponse {
  status: number;
  body?: unknown;
  lastModified?: string | null;
  retryAfterS?: number | null;
}
export type AlertsFetcher = (url: string, token: string, ifModifiedSince?: string | null) => Promise<AlertsResponse>;

const defaultFetcher: AlertsFetcher = async (url, token, ifModifiedSince) => {
  const headers: Record<string, string> = { Authorization: `Bearer ${token}` };
  if (ifModifiedSince) headers["If-Modified-Since"] = ifModifiedSince;
  const res = await fetch(url, { headers, signal: AbortSignal.timeout(8000) });
  const retry = Number(res.headers.get("Retry-After"));
  return {
    status: res.status,
    body: res.status === 200 ? await res.json() : (await res.body?.cancel(), undefined),
    lastModified: res.headers.get("Last-Modified"),
    retryAfterS: Number.isFinite(retry) && retry > 0 ? retry : null,
  };
};

/** Скільки віддаємо останні дані, якщо alerts.in.ua недоступний або просить паузу. */
export const ALERTS_STALE_MS = 10 * 60_000;
/** Оренда оновлення: поки одна копія функції йде до alerts.in.ua, інші не йдуть. */
const LEASE_S = 15;
/** Пауза після 429 без Retry-After. */
const BACKOFF_S = 120;

interface Snapshot { at: number; regions: AirAlertRegion[] }

/** Кеш у пам'яті копії функції — найшвидший шлях; спільний кеш — таблиця air_alerts_cache. */
let memory: Snapshot | null = null;

/** Для тестів: скинути кеш у пам'яті. */
export function _resetAirAlertsCache(): void {
  memory = null;
}

// deno-lint-ignore no-explicit-any
type Db = any;

interface CacheRow { regions: AirAlertRegion[] | null; fetched_at: string | null; last_modified: string | null }

async function readRow(db: Db): Promise<CacheRow | null> {
  try {
    const { data, error } = await db.from("air_alerts_cache").select("regions, fetched_at, last_modified").eq("id", 1).maybeSingle();
    return error ? null : (data as CacheRow | null);
  } catch {
    return null;
  }
}

async function writeRow(db: Db, patch: Record<string, unknown>): Promise<void> {
  try {
    const { error } = await db.from("air_alerts_cache").update(patch).eq("id", 1);
    if (error) console.warn("[v1-air-alerts] cache write failed:", error);
  } catch (err) {
    console.warn("[v1-air-alerts] cache write failed:", err);
  }
}

const snapshotOf = (row: CacheRow | null): Snapshot | null =>
  row?.fetched_at ? { at: Date.parse(row.fetched_at), regions: row.regions ?? [] } : null;

export async function handleAirAlerts(
  req: Request,
  deps: { db: unknown; token?: string; fetcher?: AlertsFetcher; now?: () => number },
): Promise<Response> {
  assertMethod(req, ["GET"]);
  const db = deps.db as Db;
  await enforceRateLimit(db, req, "v1-air-alerts");
  const now = (deps.now ?? Date.now)();
  // ?region=<slug> — лише своя область (телефон показує банер для області застосунку).
  const region = new URL(req.url).searchParams.get("region");
  const only = region && /^[a-z0-9][a-z0-9-]{1,39}$/.test(region) ? region : null;
  const unavailable = () => ok({ available: false, updated_at: null, regions: [] }, req, 200, { "Cache-Control": "no-store" });
  const answer = (s: Snapshot) =>
    ok(
      {
        available: true,
        updated_at: new Date(s.at).toISOString(),
        regions: only ? s.regions.filter((r) => r.slug === only) : s.regions,
      },
      req,
      200,
      { "Cache-Control": "no-store" },
    );
  if (!deps.token) return unavailable();
  if (memory && now - memory.at <= ALERTS_TTL_MS) return answer(memory);

  // Спільний кеш: інша копія функції вже оновила — беремо її дані.
  const row = await readRow(db);
  const shared = snapshotOf(row);
  if (shared && now - shared.at <= ALERTS_TTL_MS) {
    memory = shared;
    return answer(shared);
  }

  // До alerts.in.ua йде лише одна копія (оренда); база недоступна — ідемо самі (як раніше).
  let claimed = true;
  try {
    const { data, error } = await db.rpc("air_alerts_claim_refresh", { p_ttl_seconds: ALERTS_TTL_MS / 1000, p_lease_seconds: LEASE_S });
    if (!error) claimed = data === true;
  } catch {
    // залишаємо claimed = true
  }

  if (claimed) {
    try {
      const res = await (deps.fetcher ?? defaultFetcher)(ALERTS_URL, deps.token, row?.last_modified ?? null);
      const at = new Date(now).toISOString();
      if (res.status === 200) {
        const regions = parseAlerts(res.body);
        memory = { at: now, regions };
        await writeRow(db, { regions, fetched_at: at, last_modified: res.lastModified ?? null, refreshing_until: null, backoff_until: null });
        return answer(memory);
      }
      if (res.status === 304 && shared) {
        memory = { at: now, regions: shared.regions };
        await writeRow(db, { fetched_at: at, refreshing_until: null });
        return answer(memory);
      }
      if (res.status === 429) {
        console.warn("[v1-air-alerts] alerts.in.ua: 429, pause");
        const pause = new Date(now + (res.retryAfterS ?? BACKOFF_S) * 1000).toISOString();
        await writeRow(db, { backoff_until: pause, refreshing_until: null });
      } else {
        console.warn("[v1-air-alerts] alerts.in.ua:", res.status);
        await writeRow(db, { refreshing_until: null });
      }
    } catch (err) {
      console.warn("[v1-air-alerts] source unavailable:", err);
      await writeRow(db, { refreshing_until: null });
    }
  }

  // Оновлює інша копія, пауза або збій — останні відомі дані, якщо вони не старші за 10 хв.
  const last = [memory, shared].filter((s): s is Snapshot => s !== null).sort((a, b) => b.at - a.at)[0];
  return last && now - last.at <= ALERTS_STALE_MS ? answer(last) : unavailable();
}
