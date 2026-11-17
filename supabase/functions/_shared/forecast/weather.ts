// ============================================================================
// Forecast Engine — Weather fetch (Open-Meteo, §11.1)
// ============================================================================

import type { WeatherData, PressureTrend, SoilMoistureState } from "./types.ts";

// ────────────────────────────────────────────────────────────────────
// Open-Meteo API
// ────────────────────────────────────────────────────────────────────

const OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast";

export interface OpenMeteoResponse {
  hourly: {
    time: string[];
    temperature_2m: number[];
    relative_humidity_2m: number[];
    precipitation: number[];
    pressure_msl: number[];
    soil_moisture_0_to_7cm: number[];
    /** Температура ґрунту: прогноз — 6 см, архів (ERA5) — шар 0–7 см. */
    soil_temperature_6cm?: number[];
    soil_temperature_0_to_7cm?: number[];
    /** Код погоди WMO за годину — «зараз» і коли саме дощ сьогодні. */
    weather_code?: Array<number | null>;
  };
  daily: {
    time: string[];
    temperature_2m_max: number[];
    temperature_2m_min: number[];
    precipitation_sum: number[];
    /** Код погоди WMO за добу (ясно / хмарно / туман / дощ / сніг / гроза) — для сцени погоди. */
    weather_code?: Array<number | null>;
    /** Схід / захід сонця (місцевий час ISO) і тривалість світлого дня, с — «коли їхати». */
    sunrise?: string[];
    sunset?: string[];
    daylight_duration?: Array<number | null>;
  };
}

async function fetchOpenMeteo(
  lat: number,
  lng: number,
  pastDays = 30,
  forecastDays = 7
): Promise<OpenMeteoResponse | null> {
  const params = new URLSearchParams({
    latitude: lat.toFixed(4),
    longitude: lng.toFixed(4),
    hourly: [
      "temperature_2m",
      "relative_humidity_2m",
      "precipitation",
      "pressure_msl",
      "soil_moisture_0_to_7cm",
      "soil_temperature_6cm",
      "weather_code",
    ].join(","),
    daily: [
      "temperature_2m_max",
      "temperature_2m_min",
      "precipitation_sum",
      "weather_code",
      "sunrise",
      "sunset",
      "daylight_duration",
    ].join(","),
    past_days: String(pastDays),
    forecast_days: String(forecastDays),
    // Доба — за київським часом: «сьогодні», опади за день і дні прогнозу збігаються з
    // тим, що бачить користувач.
    timezone: "Europe/Kyiv",
  });

  const url = `${OPEN_METEO_URL}?${params}`;

  // Retry 3 рази з exponential backoff (§15.3)
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const resp = await fetch(url);
      if (!resp.ok) {
        console.warn(`Open-Meteo HTTP ${resp.status}, attempt ${attempt + 1}`);
        await new Promise((r) => setTimeout(r, 2 ** attempt * 500));
        continue;
      }
      return (await resp.json()) as OpenMeteoResponse;
    } catch (e) {
      console.warn(`Open-Meteo fetch error attempt ${attempt + 1}:`, e);
      await new Promise((r) => setTimeout(r, 2 ** attempt * 500));
    }
  }

  return null;
}

// ────────────────────────────────────────────────────────────────────
// Обчислення похідних полів
// ────────────────────────────────────────────────────────────────────

/**
 * Середнє значення масиву.
 */
export function avg(arr: number[]): number {
  if (arr.length === 0) return 0;
  return arr.reduce((s, x) => s + x, 0) / arr.length;
}

/**
 * Сума останніх N значень денних опадів.
 */
export function sumLast(daily: number[], n: number): number {
  return daily.slice(-n).reduce((s, x) => s + (x ?? 0), 0);
}

/**
 * Кількість днів з опадами <1 мм поспіль (з кінця).
 * §11.1: droughtDays = дні з опадами <1 мм/24 год.
 */
export function computeDroughtDays(dailyPrecip: number[]): number {
  let days = 0;
  for (let i = dailyPrecip.length - 1; i >= 0; i--) {
    if ((dailyPrecip[i] ?? 0) < 1) days++;
    else break;
  }
  return days;
}

/**
 * Днів після останнього дощу ≥10 мм/24 год.
 * §11.1: daysAfterRain = після останнього дощу ≥10 мм/24 год.
 * Якщо не було — 999 (дуже давно).
 */
export function computeDaysAfterRain(dailyPrecip: number[]): number {
  for (let i = dailyPrecip.length - 1; i >= 0; i--) {
    if ((dailyPrecip[i] ?? 0) >= 10) {
      return dailyPrecip.length - 1 - i;
    }
  }
  return 999;
}

/**
 * Тренд тиску за добу: [diff] — різниця тиску в кінці й на початку доби, гПа.
 * Плавне зниження (−1…−4 гПа) — ознака наближення дощу.
 */
export function pressureTrendFromDiff(diff: number): PressureTrend {
  if (diff > 2) return "rising";
  if (diff < -4) return "falling";
  if (diff < -1) return "smooth_decline_before_rain";
  return "stable";
}

/** Тренд тиску за останні 24 години погодинного ряду. */
export function computePressureTrend(hourlyPressure: number[]): PressureTrend {
  if (hourlyPressure.length < 24) return "stable";
  const recent = hourlyPressure.slice(-24);
  return pressureTrendFromDiff(recent[recent.length - 1] - recent[0]);
}

/**
 * Евристика стану ґрунту за вологістю (за §13 плану).
 */
export function computeSoilState(
  rain7d: number,
  rain14d: number,
  droughtDays: number,
  soilMoisture: number | null
): SoilMoistureState {
  if (droughtDays >= 14 && rain7d < 5) return "dry";
  if (rain7d >= 60 || (soilMoisture !== null && soilMoisture > 0.85)) {
    return "waterlogged";
  }
  if (rain7d >= 25 || (soilMoisture !== null && soilMoisture > 0.65)) {
    return "wet";
  }
  return "normal";
}

/**
 * GDD — Growing Degree Days.
 * Сума (Tmax + Tmin)/2 - baseTemp за останні N днів (базова 5°C).
 */
export function computeGDD(
  dailyMax: number[],
  dailyMin: number[],
  baseTemp = 5
): number {
  let gdd = 0;
  for (let i = 0; i < dailyMax.length; i++) {
    const t = ((dailyMax[i] ?? 0) + (dailyMin[i] ?? 0)) / 2;
    if (t > baseTemp) gdd += t - baseTemp;
  }
  return Math.round(gdd);
}

// ────────────────────────────────────────────────────────────────────
// Ряд погоди по днях і стан «на день D»
// ────────────────────────────────────────────────────────────────────

/**
 * Погода ділянки по днях: 30 минулих днів + 7 днів прогнозу (доба — за Києвом).
 * Зберігається в кеші погоди (компактно, денні значення) і дає стан лісу на будь-який
 * день ряду — так прогноз на кілька днів рахується з ОДНОГО запиту до Open-Meteo.
 */
export interface WeatherSeries {
  version: 3;
  /** Дні ряду, "YYYY-MM-DD" за київським часом. */
  dates: string[];
  /** Сьогодні на момент запиту — перший день прогнозу. */
  today: string;
  precip: number[];
  tmax: number[];
  tmin: number[];
  tmean: number[];
  humidity: number[];
  soil: Array<number | null>;
  /** Середня температура ґрунту за добу (°C) — для дозрівання грибниці; немає → середня повітря. */
  soilT: number[];
  /** Код погоди WMO за добу; немає (старий кеш) — сцена визначається за опадами й вологістю. */
  wcode?: Array<number | null>;
  /** Схід і захід сонця «HH:MM», світлий день, хв (немає — старий кеш). */
  sunrise?: Array<string | null>;
  sunset?: Array<string | null>;
  daylightMin?: Array<number | null>;
  /** Години днів прогнозу (від сьогодні): година доби, код WMO, опади мм, температура (немає — старий кеш). */
  hours?: Record<string, DayHours>;
  /** Тиск о першій і останній годині доби — для тренду тиску. */
  pressureStart: number[];
  pressureEnd: number[];
  fetchedAt: string;
}

/** Погодинна погода дня (за київським часом): паралельні масиви. */
export interface DayHours {
  h: number[];
  code: Array<number | null>;
  rain: number[];
  temp: number[];
}

export function isWeatherSeries(v: unknown): v is WeatherSeries {
  const s = v as WeatherSeries | null;
  return !!s && s.version === 3 && Array.isArray(s.dates) && s.dates.length > 0 &&
    typeof s.today === "string" && Array.isArray(s.precip) && s.precip.length === s.dates.length;
}

/** "2026-11-15T07:12" → "07:12". */
const hhmm = (v: unknown): string | null => (typeof v === "string" && /T\d\d:\d\d/.test(v) ? v.slice(11, 16) : null);

const num = (v: unknown, fallback = 0): number => (typeof v === "number" && Number.isFinite(v) ? v : fallback);

/**
 * Відповідь Open-Meteo → ряд по днях. Години групуються за датою (у дні переходу на
 * літній/зимовий час їх 23 або 25). [pastDays] — скільки днів ряду минулі.
 */
export function buildSeries(data: OpenMeteoResponse, pastDays: number, fetchedAt: Date): WeatherSeries | null {
  const dates = data.daily?.time ?? [];
  if (dates.length === 0) return null;
  const byDay = new Map<string, number[]>();
  const hourly = data.hourly;
  (hourly?.time ?? []).forEach((t, i) => {
    const d = String(t).slice(0, 10);
    const list = byDay.get(d);
    if (list) list.push(i);
    else byDay.set(d, [i]);
  });
  const pick = (arr: number[] | undefined, idx: number[]) =>
    idx.map((i) => arr?.[i]).filter((x): x is number => typeof x === "number" && Number.isFinite(x));

  const tmean: number[] = [], humidity: number[] = [], soil: Array<number | null> = [], soilT: number[] = [];
  const soilTemp = hourly?.soil_temperature_6cm ?? hourly?.soil_temperature_0_to_7cm;
  const pressureStart: number[] = [], pressureEnd: number[] = [];
  dates.forEach((d, k) => {
    const idx = byDay.get(d) ?? [];
    const t = pick(hourly?.temperature_2m, idx);
    tmean.push(t.length ? avg(t) : (num(data.daily.temperature_2m_max[k]) + num(data.daily.temperature_2m_min[k])) / 2);
    humidity.push(avg(pick(hourly?.relative_humidity_2m, idx)));
    const sm = pick(hourly?.soil_moisture_0_to_7cm, idx);
    soil.push(sm.length ? avg(sm) : null);
    const st = pick(soilTemp, idx);
    soilT.push(st.length ? avg(st) : tmean[tmean.length - 1]);
    const p = pick(hourly?.pressure_msl, idx);
    pressureStart.push(p.length ? p[0] : 1013);
    pressureEnd.push(p.length ? p[p.length - 1] : 1013);
  });

  const todayIdx = Math.min(Math.max(pastDays, 0), dates.length - 1);
  const hours: Record<string, DayHours> = {};
  dates.slice(todayIdx).forEach((d) => {
    const idx = byDay.get(d) ?? [];
    if (idx.length === 0) return;
    hours[d] = {
      h: idx.map((i) => Number(String(hourly!.time[i]).slice(11, 13))),
      code: idx.map((i) => {
        const c = hourly?.weather_code?.[i];
        return typeof c === "number" && Number.isFinite(c) ? c : null;
      }),
      rain: idx.map((i) => Math.round(num(hourly?.precipitation?.[i]) * 10) / 10),
      temp: idx.map((i) => Math.round(num(hourly?.temperature_2m?.[i]) * 10) / 10),
    };
  });
  return {
    version: 3,
    dates: [...dates],
    today: dates[todayIdx],
    precip: dates.map((_, k) => num(data.daily.precipitation_sum?.[k])),
    tmax: dates.map((_, k) => num(data.daily.temperature_2m_max?.[k])),
    tmin: dates.map((_, k) => num(data.daily.temperature_2m_min?.[k])),
    wcode: dates.map((_, k) => {
      const c = data.daily.weather_code?.[k];
      return typeof c === "number" && Number.isFinite(c) ? c : null;
    }),
    sunrise: dates.map((_, k) => hhmm(data.daily.sunrise?.[k])),
    sunset: dates.map((_, k) => hhmm(data.daily.sunset?.[k])),
    daylightMin: dates.map((_, k) => {
      const v = data.daily.daylight_duration?.[k];
      return typeof v === "number" && Number.isFinite(v) ? Math.round(v / 60) : null;
    }),
    hours,
    tmean,
    humidity,
    soil,
    soilT,
    pressureStart,
    pressureEnd,
    fetchedAt: fetchedAt.toISOString(),
  };
}

/** Погода недоступна (збій Open-Meteo або день поза рядом). */
export function unavailableWeather(): WeatherData {
  return {
    tempAvg7d: 0, tempAvg14d: 0, tempAvg20d: 0,
    tempMin: 0, tempMax: 0,
    humidity: 0,
    rain1d: 0, rain2d: 0, rain3d: 0,
    rain7d: 0, rain14d: 0, rain30d: 0,
    droughtDays: 0, daysAfterRain: 999,
    pressure: 1013, pressureTrend: "stable",
    soilState: "normal",
    gdd: null,
    fetchedAt: new Date().toISOString(),
    source: "unavailable",
  };
}

/** На скільки днів [date] пізніше за [from] (обидві — "YYYY-MM-DD"). */
export function dayOffset(date: string, from: string): number {
  return Math.round((Date.parse(`${date}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
}

/**
 * Стан погоди НА ДЕНЬ [date]: усі вікна (опади за 1/3/7/14/30 днів, температура за
 * 7/14/20 днів, посуха, днів після дощу, ґрунт, тиск) закінчуються цим днем — фактична
 * погода до сьогодні + прогноз до [date]. Раніше вікна закінчувались останнім днем
 * прогнозу, і «сьогоднішній» аналіз бачив дощі наступного тижня.
 * День поза рядом → погода недоступна.
 */
export function weatherAsOf(series: WeatherSeries, date: string, source: WeatherData["source"] = "open-meteo"): WeatherData {
  const i = series.dates.indexOf(date);
  if (i < 0) return unavailableWeather();
  const upTo = <T>(arr: T[]) => arr.slice(0, i + 1);
  const last = <T>(arr: T[], n: number) => upTo(arr).slice(-n);

  const precip = upTo(series.precip);
  const rain7d = sumLast(precip, 7);
  const rain14d = sumLast(precip, 14);
  const droughtDays = computeDroughtDays(precip);
  const soil7 = last(series.soil, 7).filter((x): x is number => x !== null);
  const soilMoisture7d = soil7.length ? avg(soil7) : null;

  return {
    tempAvg7d: avg(last(series.tmean, 7)),
    tempAvg14d: avg(last(series.tmean, 14)),
    tempAvg20d: avg(last(series.tmean, 20)),
    tempMin: Math.min(...last(series.tmin, 7)),
    tempMax: Math.max(...last(series.tmax, 7)),
    humidity: avg(last(series.humidity, 7)),
    rain1d: sumLast(precip, 1),
    rain2d: sumLast(precip, 2),
    rain3d: sumLast(precip, 3),
    rain7d,
    rain14d,
    rain30d: sumLast(precip, 30),
    droughtDays,
    daysAfterRain: computeDaysAfterRain(precip),
    pressure: series.pressureEnd[i],
    pressureTrend: pressureTrendFromDiff(series.pressureEnd[i] - series.pressureStart[i]),
    soilState: computeSoilState(rain7d, rain14d, droughtDays, soilMoisture7d || null),
    gdd: computeGDD(upTo(series.tmax), upTo(series.tmin)),
    day: {
      date,
      tempMin: series.tmin[i],
      tempMax: series.tmax[i],
      rain: series.precip[i],
      humidity: series.humidity[i],
      daysAhead: dayOffset(date, series.today),
      code: series.wcode?.[i] ?? null,
      sunrise: series.sunrise?.[i] ?? null,
      sunset: series.sunset?.[i] ?? null,
      daylightMin: series.daylightMin?.[i] ?? null,
      hours: series.hours?.[date] ?? null,
    },
    recent: series.dates.slice(Math.max(0, i - 13), i + 1).map((d, k) => {
      const j = Math.max(0, i - 13) + k;
      return {
        date: d,
        tempMin: series.tmin[j],
        tempMax: series.tmax[j],
        rain: series.precip[j],
        humidity: series.humidity[j],
        daysAhead: dayOffset(d, series.today),
      };
    }),
    fetchedAt: series.fetchedAt,
    source,
  };
}

// ────────────────────────────────────────────────────────────────────
// Головні функції
// ────────────────────────────────────────────────────────────────────

/** Минулі дні ряду: опади за 30 днів, посуха, сума тепла. */
export const PAST_DAYS = 30;
/** Дні прогнозу (сьогодні + 6): горизонт Pro — 7 днів (ADR-010). */
export const FORECAST_DAYS = 7;

/** Ряд погоди для точки; `null` — Open-Meteo недоступний. */
export async function fetchWeatherSeries(lat: number, lng: number): Promise<WeatherSeries | null> {
  const data = await fetchOpenMeteo(lat, lng, PAST_DAYS, FORECAST_DAYS);
  return data ? buildSeries(data, PAST_DAYS, new Date()) : null;
}

/**
 * Погода для точки на сьогодні (з вікнами, що закінчуються сьогодні).
 * Повертає WeatherData з source = 'unavailable' при невдачі (graceful degradation).
 */
export async function fetchWeather(lat: number, lng: number): Promise<WeatherData> {
  const series = await fetchWeatherSeries(lat, lng);
  return series ? weatherAsOf(series, series.today) : unavailableWeather();
}

// ────────────────────────────────────────────────────────────────────
// Ансамбль для днів 4–7 (рішення PO 2026-11-15, ADR-015 §15.8 п.16)
// ────────────────────────────────────────────────────────────────────

/** Діапазон погоди дня за ансамблем моделей: 10-й і 90-й перцентилі учасників. */
export interface DayRange {
  rainMin: number;
  rainMax: number;
  tMin: number;
  tMax: number;
}

function percentile(xs: number[], q: number): number {
  const v = [...xs].sort((a, b) => a - b);
  if (v.length === 0) return NaN;
  const i = (v.length - 1) * q;
  const lo = Math.floor(i), hi = Math.ceil(i);
  return v[lo] + (v[hi] - v[lo]) * (i - lo);
}

/** Відповідь Ensemble API (daily, учасники `*_memberNN`) → діапазони по днях. */
export function parseEnsemble(json: unknown): Record<string, DayRange> {
  const daily = (json as { daily?: Record<string, unknown> })?.daily;
  const time = daily?.time;
  if (!daily || !Array.isArray(time)) return {};
  const members = (prefix: string) =>
    Object.entries(daily)
      .filter(([k, v]) => (k === prefix || k.startsWith(`${prefix}_member`)) && Array.isArray(v))
      .map(([, v]) => v as Array<number | null>);
  const rain = members("precipitation_sum"), tmax = members("temperature_2m_max"), tmin = members("temperature_2m_min");
  const out: Record<string, DayRange> = {};
  time.forEach((d, i) => {
    const col = (ms: Array<Array<number | null>>) =>
      ms.map((m) => m[i]).filter((x): x is number => typeof x === "number" && Number.isFinite(x));
    const r = col(rain), hi = col(tmax), lo = col(tmin);
    if (r.length < 3 || hi.length < 3 || lo.length < 3) return;
    out[String(d)] = {
      rainMin: Math.round(percentile(r, 0.1)),
      rainMax: Math.round(percentile(r, 0.9)),
      tMin: Math.round(percentile(lo, 0.1)),
      tMax: Math.round(percentile(hi, 0.9)),
    };
  });
  return out;
}

/** Діапазони погоди на 7 днів за ансамблем ICON (Open-Meteo); збій — порожньо. */
export async function fetchEnsembleRanges(
  lat: number,
  lng: number,
  fetchFn: (url: string) => Promise<Response> = fetch,
): Promise<Record<string, DayRange>> {
  const url = "https://ensemble-api.open-meteo.com/v1/ensemble?" + new URLSearchParams({
    latitude: lat.toFixed(4),
    longitude: lng.toFixed(4),
    daily: "precipitation_sum,temperature_2m_max,temperature_2m_min",
    models: "icon_seamless",
    forecast_days: "7",
    timezone: "Europe/Kyiv",
  });
  try {
    const res = await fetchFn(url);
    if (!res.ok) return {};
    return parseEnsemble(await res.json());
  } catch {
    return {};
  }
}

