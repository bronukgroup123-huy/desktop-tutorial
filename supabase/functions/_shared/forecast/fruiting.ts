// ============================================================================
// Рушій плодоношення (ADR-015 §15.8): поштовх → дозрівання грибниці → хвиля → спад.
//
// Для кожного виду по ряду погоди (30 минулих днів + прогноз) шукаються «події»:
//   * поштовх — дощ, що промочив ґрунт (сума за 3 дні ≥ поріг виду); для окремих видів —
//     дощ + осіннє похолодання, весняний прогрів ґрунту (сморчок) або відлига після
//     заморозків (зимовий опеньок);
//   * дозрівання — сума тепла ґрунту (градусо-дні понад базу) від дня поштовху. Якщо ґрунт
//     уже був вологий (грибниця готова), потрібно лише ~40% суми — гриби виростають за 2–4
//     дні, як пишуть книги; після посухи — повна сума (1–2 тижні). Посуха під час
//     дозрівання (10+ днів без дощу) зриває подію;
//   * хвиля — `flushDays` днів: підйом, розпал, спад.
// Стан на день D: хвиля (день N з M), дозрівання (орієнтовна дата), хвиля минула, поштовху
// немає. Рушій прогнозу множить на нього погодну оцінку — замість «пікових місяців» календаря.
// ============================================================================

import type { WeatherSeries } from "./weather.ts";

export type FruitingTrigger = "rain" | "rain_cool" | "spring_warm" | "thaw";

/** Параметри плодоношення виду (колонки expert_rules, міграція 20261114120000). */
export interface FruitingParams {
  trigger: FruitingTrigger;
  /** Сума опадів за 3 дні, що промочує ґрунт, мм. */
  triggerRainMm: number;
  /** Градусо-днів ґрунту від поштовху до появи грибів (з неготовою грибницею). */
  maturationDd: number;
  /** База градусо-днів, °C (4; для зимового опенька — 0). */
  ddBase: number;
  /** Скільки днів триває хвиля. */
  flushDays: number;
  /** Температура ґрунту, за якої гриби ростуть, °C. */
  soilTempMin: number;
  soilTempMax: number;
}

/** Частка суми тепла, коли грибниця вже готова (ґрунт вологий до поштовху). */
export const PRIMED_FRACTION = 0.4;
/** Ґрунт «вологий до поштовху»: за 10 днів перед ним випало стільки мм. */
const PRIMED_RAIN_MM = 10;
/** Нова подія — не раніше ніж через стільки днів після попереднього поштовху. */
const MIN_EVENT_GAP = 5;
/** Посуха (днів поспіль < 1 мм), що зриває дозрівання. */
const ABORT_DRY_DAYS = 10;
/** Скільки днів після хвилі вважаємо «хвиля минула». */
const AFTER_FLUSH_DAYS = 10;

export interface FruitingEvent {
  /** Індекс дня поштовху в ряду. */
  trigger: number;
  /** Опади поштовху (сума за 3 дні), мм. */
  triggerRain: number;
  primed: boolean;
  /** Індекс першого дня хвилі; null — ще дозріває (у межах ряду) або зірвано. */
  flushStart: number | null;
  aborted: boolean;
}

export type FruitingPhase = "flush" | "maturing" | "after" | "idle";

export interface FruitingState {
  phase: FruitingPhase;
  /** Хвиля: день (з 1) і тривалість. */
  flushDay?: number;
  flushDays?: number;
  /** Сила хвилі 0..1 з урахуванням температури ґрунту. */
  intensity: number;
  /** Дата й опади поштовху, від якого ця хвиля / дозрівання. */
  triggerDate?: string;
  triggerRain?: number;
  /** Дозрівання: дата початку хвилі, якщо вона в межах ряду (прогноз). */
  expectedStart?: string;
  /** Хвиля минула: коли закінчилась. */
  flushEnded?: string;
}

const sum = (xs: number[]) => xs.reduce((s, x) => s + (x ?? 0), 0);

function isTrigger(s: WeatherSeries, k: number, p: FruitingParams, springDone: Set<number>): number | null {
  const rain3 = sum(s.precip.slice(Math.max(0, k - 2), k + 1));
  const month = Number(s.dates[k].slice(5, 7));
  switch (p.trigger) {
    case "rain":
      return rain3 >= p.triggerRainMm ? rain3 : null;
    case "rain_cool": {
      const t7 = s.tmean.slice(Math.max(0, k - 6), k + 1);
      return rain3 >= p.triggerRainMm && sum(t7) / t7.length < 15 ? rain3 : null;
    }
    case "spring_warm": {
      const year = Number(s.dates[k].slice(0, 4));
      if (month < 3 || month > 6 || springDone.has(year)) return null;
      const st5 = s.soilT.slice(Math.max(0, k - 4), k + 1);
      const rain14 = sum(s.precip.slice(Math.max(0, k - 13), k + 1));
      if (st5.length === 5 && sum(st5) / 5 >= 8 && rain14 >= 10) {
        springDone.add(year);
        return rain14;
      }
      return null;
    }
    case "thaw": {
      // Зимовий опеньок: відлига після заморозків або дощ у холодну погоду (тиждень < 8°).
      const before = s.tmin.slice(Math.max(0, k - 7), k);
      if (before.some((t) => t <= -1) && s.tmean[k] >= 2) return 0;
      const t7 = s.tmean.slice(Math.max(0, k - 6), k + 1);
      return rain3 >= p.triggerRainMm && sum(t7) / t7.length < 8 ? rain3 : null;
    }
  }
}

/** Усі події плодоношення виду по ряду погоди. */
export function fruitingEvents(s: WeatherSeries, p: FruitingParams): FruitingEvent[] {
  const events: FruitingEvent[] = [];
  const springDone = new Set<number>();
  for (let k = 0; k < s.dates.length; k++) {
    const last = events.at(-1);
    if (last && k - last.trigger < MIN_EVENT_GAP) continue;
    const rain = isTrigger(s, k, p, springDone);
    if (rain === null) continue;
    const primed = p.trigger === "thaw" ||
      sum(s.precip.slice(Math.max(0, k - 10), k)) >= PRIMED_RAIN_MM;
    const need = p.maturationDd * (primed ? PRIMED_FRACTION : 1);
    let dd = 0, dry = 0, flushStart: number | null = null, aborted = false;
    for (let j = k + 1; j < s.dates.length; j++) {
      dd += Math.max(0, (s.soilT[j] ?? s.tmean[j]) - p.ddBase);
      dry = (s.precip[j] ?? 0) < 1 ? dry + 1 : 0;
      if (dd >= need) {
        flushStart = j;
        break;
      }
      if (dry >= ABORT_DRY_DAYS) {
        aborted = true;
        break;
      }
    }
    events.push({ trigger: k, triggerRain: Math.round(rain), primed, flushStart, aborted });
  }
  return events;
}

/** Форма хвилі: підйом (перші ~20% днів), розпал, спад до ~0.4 наприкінці. */
export function flushShape(day: number, days: number): number {
  const rise = Math.max(1, Math.round(days * 0.2));
  if (day < rise) return 0.55 + 0.45 * (day + 1) / rise;
  const fallFrom = days * 0.65;
  if (day < fallFrom) return 1;
  return Math.max(0.4, 1 - 0.6 * (day - fallFrom) / Math.max(1, days - fallFrom));
}

/** Наскільки температура ґрунту підходить для росту грибів: 1 / 0.6 (на межі ±3°) / 0.25. */
export function soilTempFit(t: number, p: FruitingParams): number {
  if (t >= p.soilTempMin && t <= p.soilTempMax) return 1;
  if (t >= p.soilTempMin - 3 && t <= p.soilTempMax + 3) return 0.6;
  return 0.25;
}

const cache = new WeakMap<WeatherSeries, Map<string, FruitingEvent[]>>();

/** Стан плодоношення виду на день [date]; `null` — дня немає в ряду. */
export function fruitingState(s: WeatherSeries, date: string, p: FruitingParams, key = JSON.stringify(p)): FruitingState | null {
  const i = s.dates.indexOf(date);
  if (i < 0) return null;
  let perSeries = cache.get(s);
  if (!perSeries) cache.set(s, perSeries = new Map());
  let events = perSeries.get(key);
  if (!events) perSeries.set(key, events = fruitingEvents(s, p));

  // Хвиля, що триває сьогодні (найпізніша з тих, що почалися).
  for (let e = events.length - 1; e >= 0; e--) {
    const ev = events[e];
    if (ev.flushStart === null || ev.flushStart > i) continue;
    const day = i - ev.flushStart;
    if (day < p.flushDays) {
      const intensity = flushShape(day, p.flushDays) * soilTempFit(s.soilT[i] ?? s.tmean[i], p);
      return {
        phase: "flush", flushDay: day + 1, flushDays: p.flushDays, intensity,
        triggerDate: s.dates[ev.trigger], triggerRain: ev.triggerRain,
      };
    }
  }
  // Дозрівання: поштовх уже був, хвиля ще попереду (або за межами ряду).
  for (let e = events.length - 1; e >= 0; e--) {
    const ev = events[e];
    if (ev.trigger > i || ev.aborted) continue;
    if (ev.flushStart === null || ev.flushStart > i) {
      return {
        phase: "maturing", intensity: 0,
        triggerDate: s.dates[ev.trigger], triggerRain: ev.triggerRain,
        expectedStart: ev.flushStart !== null ? s.dates[ev.flushStart] : undefined,
      };
    }
    break;
  }
  // Хвиля минула нещодавно.
  for (let e = events.length - 1; e >= 0; e--) {
    const ev = events[e];
    if (ev.flushStart === null || ev.flushStart > i) continue;
    const end = ev.flushStart + p.flushDays - 1;
    if (i > end && i - end <= AFTER_FLUSH_DAYS) {
      return { phase: "after", intensity: 0, triggerDate: s.dates[ev.trigger], triggerRain: ev.triggerRain, flushEnded: s.dates[end] };
    }
    break;
  }
  return { phase: "idle", intensity: 0 };
}
