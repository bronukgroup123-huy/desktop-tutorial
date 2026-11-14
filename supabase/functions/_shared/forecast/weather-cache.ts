// ============================================================================
// Кеш погоди по сітці (BACKEND_PLAN B2.6)
//
// Ключ — клітинка 0.1° (~11 × 7 км в Україні); погоду запитуємо для ЦЕНТРУ
// клітинки, тож усі точки клітинки отримують однакові дані. Свіжість — 3 год і той
// самий київський день. У кеші — ряд погоди по днях (30 минулих + 7 днів прогнозу):
// з нього рахується стан на будь-який день горизонту без нових запитів.
// Будь-яка помилка кешу (немає таблиці, БД недоступна) → звичайний запит до
// Open-Meteo: кеш не може зламати прогноз.
// ============================================================================

import type { WeatherData } from "./types.ts";
import { fetchWeatherSeries, isWeatherSeries, unavailableWeather, type WeatherSeries, weatherAsOf } from "./weather.ts";

export const WEATHER_CELL_DEG = 0.1;
export const WEATHER_TTL_MS = 3 * 60 * 60 * 1000;

export interface WeatherCell {
  key: string;
  lat: number;
  lng: number;
}

/** Клітинка сітки для точки: ключ і координати центру. */
export function weatherCell(lat: number, lng: number): WeatherCell {
  const snap = (v: number) => Math.floor(v / WEATHER_CELL_DEG) * WEATHER_CELL_DEG + WEATHER_CELL_DEG / 2;
  const cLat = Number(snap(lat).toFixed(2));
  const cLng = Number(snap(lng).toFixed(2));
  return { key: `${cLat.toFixed(2)}:${cLng.toFixed(2)}`, lat: cLat, lng: cLng };
}

const KYIV_DATE = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Kyiv",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** Сьогоднішня дата в Києві: "YYYY-MM-DD". */
export function kyivDate(now: Date): string {
  return KYIV_DATE.format(now);
}

// deno-lint-ignore no-explicit-any
type CacheDb = { from(table: string): any };

export interface WeatherCacheDeps {
  fetcher?: (lat: number, lng: number) => Promise<WeatherSeries | null>;
  now?: () => Date;
}

export interface CachedSeries {
  /** `null` — Open-Meteo недоступний і в кеші нічого свіжого. */
  series: WeatherSeries | null;
  cached: boolean;
}

/** Ряд погоди клітинки: з кешу (свіжий і того ж дня) або з Open-Meteo. */
export async function fetchWeatherSeriesCached(
  db: CacheDb,
  lat: number,
  lng: number,
  deps: WeatherCacheDeps = {},
): Promise<CachedSeries> {
  const fetcher = deps.fetcher ?? fetchWeatherSeries;
  const now = deps.now ? deps.now() : new Date();
  const cell = weatherCell(lat, lng);
  const today = kyivDate(now);

  try {
    const { data, error } = await db
      .from("weather_cache")
      .select("payload, fetched_at")
      .eq("cell_key", cell.key)
      .maybeSingle();
    if (!error && data) {
      const row = data as { payload: unknown; fetched_at: string };
      // Старий формат (одна WeatherData) або інший день → перезапитуємо.
      if (
        isWeatherSeries(row.payload) && row.payload.today === today &&
        now.getTime() - new Date(row.fetched_at).getTime() < WEATHER_TTL_MS
      ) {
        return { series: row.payload, cached: true };
      }
    }
  } catch (e) {
    console.warn("[weather-cache] read failed, falling back to Open-Meteo:", e);
  }

  const fresh = await fetcher(cell.lat, cell.lng);
  if (!fresh) return { series: null, cached: false }; // збій не кешуємо

  try {
    const { error } = await db
      .from("weather_cache")
      .upsert({ cell_key: cell.key, payload: fresh, fetched_at: now.toISOString() }, { onConflict: "cell_key" });
    if (error) console.warn("[weather-cache] write failed:", error);
  } catch (e) {
    console.warn("[weather-cache] write failed:", e);
  }
  return { series: fresh, cached: false };
}

/** Стан погоди на день [date] (за замовчуванням — сьогодні за Києвом). */
export function weatherForDate(res: CachedSeries, date: string): WeatherData {
  if (!res.series) return unavailableWeather();
  return weatherAsOf(res.series, date, res.cached ? "cached" : "open-meteo");
}

/** Погода клітинки на день [date] (за замовчуванням — сьогодні). */
export async function fetchWeatherCached(
  db: CacheDb,
  lat: number,
  lng: number,
  deps: WeatherCacheDeps = {},
  date?: string,
): Promise<WeatherData> {
  const res = await fetchWeatherSeriesCached(db, lat, lng, deps);
  const day = date ?? kyivDate(deps.now ? deps.now() : new Date());
  return weatherForDate(res, day);
}
