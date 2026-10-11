// ============================================================================
// Forecast Engine — Weather fetch (Open-Meteo, §11.1)
// ============================================================================

import type { WeatherData, PressureTrend, SoilMoistureState } from "./types.ts";

// ────────────────────────────────────────────────────────────────────
// Open-Meteo API
// ────────────────────────────────────────────────────────────────────

const OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast";

interface OpenMeteoResponse {
  hourly: {
    time: string[];
    temperature_2m: number[];
    relative_humidity_2m: number[];
    precipitation: number[];
    pressure_msl: number[];
    soil_moisture_0_to_7cm: number[];
  };
  daily: {
    time: string[];
    temperature_2m_max: number[];
    temperature_2m_min: number[];
    precipitation_sum: number[];
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
    ].join(","),
    daily: [
      "temperature_2m_max",
      "temperature_2m_min",
      "precipitation_sum",
    ].join(","),
    past_days: String(pastDays),
    forecast_days: String(forecastDays),
    timezone: "UTC",
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
 * Тренд тиску за останні 24 години.
 */
export function computePressureTrend(hourlyPressure: number[]): PressureTrend {
  if (hourlyPressure.length < 24) return "stable";

  const recent = hourlyPressure.slice(-24);
  const first = recent[0];
  const last = recent[recent.length - 1];
  const diff = last - first;

  if (diff > 2) return "rising";
  if (diff < -4) return "falling";

  // Плавне зниження перед дощем
  if (diff < -1 && diff > -4) {
    const hasRainRecently = true; // приблизно: тиск знизився, дощ буде
    if (hasRainRecently) return "smooth_decline_before_rain";
  }

  return "stable";
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
// Головна функція
// ────────────────────────────────────────────────────────────────────

/**
 * Отримати погоду для точки.
 * Повертає WeatherData з source = 'unavailable' при невдачі
 * (замість помилки — graceful degradation).
 */
export async function fetchWeather(
  lat: number,
  lng: number
): Promise<WeatherData> {
  const data = await fetchOpenMeteo(lat, lng);

  if (!data) {
    // Graceful degradation — повертаємо "пусту" погоду
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

  const { hourly, daily } = data;

  // Температура (останні N годин)
  const temp7d = hourly.temperature_2m.slice(-7 * 24);
  const temp14d = hourly.temperature_2m.slice(-14 * 24);
  const temp20d = hourly.temperature_2m.slice(-20 * 24);

  // Денні дані
  const dailyPrecip = daily.precipitation_sum ?? [];
  const dailyMax = daily.temperature_2m_max ?? [];
  const dailyMin = daily.temperature_2m_min ?? [];

  // Опади
  const rain1d = sumLast(dailyPrecip, 1);
  const rain2d = sumLast(dailyPrecip, 2);
  const rain3d = sumLast(dailyPrecip, 3);
  const rain7d = sumLast(dailyPrecip, 7);
  const rain14d = sumLast(dailyPrecip, 14);
  const rain30d = sumLast(dailyPrecip, 30);

  const droughtDays = computeDroughtDays(dailyPrecip);
  const daysAfterRain = computeDaysAfterRain(dailyPrecip);

  // Тиск і soil_moisture (середнє останніх 7 днів для ґрунту)
  const pressure = hourly.pressure_msl.slice(-1)[0] ?? 1013;
  const pressureTrend = computePressureTrend(hourly.pressure_msl);

  const soilMoisture7d = avg(
    hourly.soil_moisture_0_to_7cm.slice(-7 * 24).filter((x) => x != null)
  );

  const soilState = computeSoilState(
    rain7d, rain14d, droughtDays,
    soilMoisture7d || null
  );

  const gdd = computeGDD(dailyMax, dailyMin);

  return {
    tempAvg7d: avg(temp7d),
    tempAvg14d: avg(temp14d),
    tempAvg20d: avg(temp20d),
    tempMin: Math.min(...dailyMin.slice(-7)) || 0,
    tempMax: Math.max(...dailyMax.slice(-7)) || 0,
    humidity: avg(hourly.relative_humidity_2m.slice(-7 * 24)),
    rain1d, rain2d, rain3d,
    rain7d, rain14d, rain30d,
    droughtDays, daysAfterRain,
    pressure, pressureTrend,
    soilState,
    gdd,
    fetchedAt: new Date().toISOString(),
    source: "open-meteo",
  };
}
