// ============================================================================
// Кеш погоди по сітці (BACKEND_PLAN B2.6)
//
// Ключ — клітинка 0.1° (~11 × 7 км в Україні); погоду запитуємо для ЦЕНТРУ
// клітинки, тож усі точки клітинки отримують однакові дані. Свіжість — 3 год.
// Будь-яка помилка кешу (немає таблиці, БД недоступна) → звичайний запит до
// Open-Meteo: кеш не може зламати прогноз.
// ============================================================================

import type { WeatherData } from "./types.ts";
import { fetchWeather } from "./weather.ts";

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

// deno-lint-ignore no-explicit-any
type CacheDb = { from(table: string): any };

export interface WeatherCacheDeps {
  fetcher?: (lat: number, lng: number) => Promise<WeatherData>;
  now?: () => Date;
}

export async function fetchWeatherCached(
  db: CacheDb,
  lat: number,
  lng: number,
  deps: WeatherCacheDeps = {},
): Promise<WeatherData> {
  const fetcher = deps.fetcher ?? fetchWeather;
  const now = deps.now ? deps.now() : new Date();
  const cell = weatherCell(lat, lng);

  try {
    const { data, error } = await db
      .from("weather_cache")
      .select("payload, fetched_at")
      .eq("cell_key", cell.key)
      .maybeSingle();
    if (!error && data) {
      const row = data as { payload: WeatherData; fetched_at: string };
      if (now.getTime() - new Date(row.fetched_at).getTime() < WEATHER_TTL_MS) {
        return { ...row.payload, source: "cached" };
      }
    }
  } catch (e) {
    console.warn("[weather-cache] read failed, falling back to Open-Meteo:", e);
  }

  const fresh = await fetcher(cell.lat, cell.lng);
  if (fresh.source === "unavailable") return fresh; // збій не кешуємо

  try {
    const { error } = await db
      .from("weather_cache")
      .upsert({ cell_key: cell.key, payload: fresh, fetched_at: now.toISOString() }, { onConflict: "cell_key" });
    if (error) console.warn("[weather-cache] write failed:", error);
  } catch (e) {
    console.warn("[weather-cache] write failed:", e);
  }
  return fresh;
}
