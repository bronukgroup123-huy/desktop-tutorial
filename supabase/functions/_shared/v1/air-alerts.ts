// ============================================================================
// GET v1-air-alerts — повітряна тривога по областях (ADR-022 §22.5 п.5, BACKEND_PLAN B4.12)
//
// Дані — офіційний сервіс тривог alerts.in.ua (`GET /v1/alerts/active.json`, ключ —
// секрет `ALERTS_IN_UA_TOKEN`). Ключа немає або сервіс недоступний — `available: false`,
// застосунок банер не показує (без помилок). Відповідь кешується в пам'яті функції 45 с
// (ліміти сервісу), клієнт питає раз на хвилину.
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

export type AlertsFetcher = (url: string, token: string) => Promise<unknown>;

const defaultFetcher: AlertsFetcher = async (url, token) => {
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`alerts.in.ua ${res.status}`);
  return await res.json();
};

let cache: { at: number; regions: AirAlertRegion[] } | null = null;

/** Для тестів: скинути кеш. */
export function _resetAirAlertsCache(): void {
  cache = null;
}

export async function handleAirAlerts(
  req: Request,
  deps: { db: unknown; token?: string; fetcher?: AlertsFetcher; now?: () => number },
): Promise<Response> {
  assertMethod(req, ["GET"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-air-alerts");
  const now = (deps.now ?? Date.now)();
  if (!deps.token) {
    return ok({ available: false, updated_at: null, regions: [] }, req, 200, { "Cache-Control": "no-store" });
  }
  if (!cache || now - cache.at > ALERTS_TTL_MS) {
    try {
      const raw = await (deps.fetcher ?? defaultFetcher)(ALERTS_URL, deps.token);
      cache = { at: now, regions: parseAlerts(raw) };
    } catch (err) {
      console.warn("[v1-air-alerts] source unavailable:", err);
      if (!cache || now - cache.at > 10 * 60_000) {
        return ok({ available: false, updated_at: null, regions: [] }, req, 200, { "Cache-Control": "no-store" });
      }
    }
  }
  return ok(
    { available: true, updated_at: new Date(cache.at).toISOString(), regions: cache.regions },
    req,
    200,
    { "Cache-Control": "no-store" },
  );
}
