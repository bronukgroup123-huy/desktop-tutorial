// ============================================================================
// Погода дня по годинах (рішення PO 2026-11-17)
//
// Код погоди Open-Meteo «за добу» — найсильніше явище доби: вечірній дощ робив «Дощ» на весь
// день, навіть коли зараз сонце. Тут — частини доби (ніч / ранок / день / вечір) зі своєю
// сценою і проміжки опадів «Дощ 18:00–22:00, ~4 мм». Застосунок показує частину доби, що
// триває зараз, і ще не минулі проміжки — лише вибір за годинником, тексти — з сервера.
// ============================================================================

import type { DayWeather, WeatherData } from "../forecast/types.ts";
import { SCENE_LABEL, weatherScene, type WeatherScene } from "./forecast-labels.ts";

type Hours = NonNullable<DayWeather["hours"]>;

const PARTS = [
  { key: "night", label: "Ніч", from: 0, to: 6 },
  { key: "morning", label: "Ранок", from: 6, to: 12 },
  { key: "day", label: "День", from: 12, to: 18 },
  { key: "evening", label: "Вечір", from: 18, to: 24 },
] as const;

export interface DayPart {
  key: string;
  label: string;
  from_hour: number;
  to_hour: number;
  scene: WeatherScene;
  scene_label: string;
  temp_label: string;
}

export interface RainSpan {
  from_hour: number;
  to_hour: number;
  mm: number;
  label: string;
}

const hh = (h: number) => `${String(h).padStart(2, "0")}:00`;

/** Опади за кодом WMO: мряка, дощ, крижаний дощ, зливи, сніг, гроза. */
export const isPrecipCode = (c: number | null | undefined): boolean =>
  typeof c === "number" && ((c >= 51 && c <= 67) || (c >= 71 && c <= 77) || (c >= 80 && c <= 86) || c >= 95);
const isSnowCode = (c: number | null) => c !== null && ((c >= 71 && c <= 77) || c === 85 || c === 86);

/**
 * Код частини доби: були опади — найсильніші з них; інакше — найчастіший (дві хмарні години
 * з шести не роблять сонячний день «мінливим»).
 */
const partCode = (codes: Array<number | null>): number | null => {
  const xs = codes.filter((c): c is number => c !== null);
  if (xs.length === 0) return null;
  const wet = xs.filter((c) => isPrecipCode(c));
  if (wet.length) return Math.max(...wet);
  const count = new Map<number, number>();
  for (const c of xs) count.set(c, (count.get(c) ?? 0) + 1);
  return [...count.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0][0];
};

/** Ніч / ранок / день / вечір зі сценою погоди; годин немає (старий кеш) — порожньо. */
export function dayParts(day: DayWeather, w: WeatherData | null | undefined): DayPart[] {
  const hours = day.hours;
  if (!hours || hours.h.length === 0) return [];
  const out: DayPart[] = [];
  for (const p of PARTS) {
    const idx = hours.h.map((h, i) => (h >= p.from && h < p.to ? i : -1)).filter((i) => i >= 0);
    if (idx.length === 0) continue;
    const temps = idx.map((i) => hours.temp[i]);
    const tMin = Math.min(...temps), tMax = Math.max(...temps);
    const rain = idx.reduce((s, i) => s + (hours.rain[i] ?? 0), 0);
    const scene = weatherScene(
      { tempMin: tMin, tempMax: tMax, rain, humidity: day.humidity, code: partCode(idx.map((i) => hours.code[i])) },
      w,
    );
    const t = Math.round(tMin) === Math.round(tMax) ? `${Math.round(tMax)}°` : `${Math.round(tMin)}…${Math.round(tMax)}°`;
    out.push({ key: p.key, label: p.label, from_hour: p.from, to_hour: p.to, scene, scene_label: SCENE_LABEL[scene], temp_label: t });
  }
  return out;
}

/** Година з опадами: від 0,1 мм або код опадів. */
const wetHour = (hours: Hours, i: number) => (hours.rain[i] ?? 0) >= 0.1 || isPrecipCode(hours.code[i]);

/**
 * Проміжки опадів доби (сусідні мокрі години; перерва в 1 годину не розриває), до трьох:
 * «Дощ 18:00–22:00, ~4 мм», «Мряка 06:00–09:00», «Сніг 03:00–07:00, ~2 мм».
 */
export function rainSpans(day: DayWeather): RainSpan[] {
  const hours = day.hours;
  if (!hours) return [];
  const spans: Array<{ from: number; to: number; mm: number; snow: boolean }> = [];
  hours.h.forEach((h, i) => {
    if (!wetHour(hours, i)) return;
    const last = spans[spans.length - 1];
    if (last && h - last.to <= 1) {
      last.to = h + 1;
      last.mm += hours.rain[i] ?? 0;
      last.snow ||= isSnowCode(hours.code[i]);
    } else {
      spans.push({ from: h, to: h + 1, mm: hours.rain[i] ?? 0, snow: isSnowCode(hours.code[i]) });
    }
  });
  return spans.slice(0, 3).map((s) => {
    const mm = Math.round(s.mm * 10) / 10;
    const what = s.snow ? "Сніг" : mm < 0.5 ? "Мряка" : "Дощ";
    const amount = mm >= 0.5 ? `, ~${Math.max(1, Math.round(mm))} мм` : "";
    return { from_hour: s.from, to_hour: s.to, mm, label: `${what} ${hh(s.from)}–${hh(s.to)}${amount}` };
  });
}

/** Опади від години [fromHour] до кінця доби, мм, і чи є мокрі години (мряка без мм). */
export function restOfDay(day: DayWeather, fromHour: number): { mm: number; wet: boolean } | null {
  const hours = day.hours;
  if (!hours) return null;
  let mm = 0, wet = false;
  hours.h.forEach((h, i) => {
    if (h < fromHour) return;
    mm += hours.rain[i] ?? 0;
    wet ||= wetHour(hours, i);
  });
  return { mm: Math.round(mm * 10) / 10, wet };
}

/**
 * Небезпечна погода дня для вкладки «Безпека» (ADR-022 §22.3 п.12) — короткі підписи:
 * гроза (коди WMO 95–99) з годинами, спека від 30°, мороз від −1°. Нічого — порожньо.
 */
export function dayHazards(day: DayWeather): string[] {
  const out: string[] = [];
  const hours = day.hours;
  const storm = (c: number | null | undefined) => typeof c === "number" && c >= 95;
  if (hours && hours.h.length) {
    const idx = hours.h.map((h, i) => (storm(hours.code[i]) ? i : -1)).filter((i) => i >= 0);
    if (idx.length) {
      const from = hours.h[idx[0]], to = hours.h[idx[idx.length - 1]] + 1;
      out.push(`Гроза ${hh(from)}–${hh(to)}: не стійте під поодинокими високими деревами, на галявинах і пагорбах`);
    }
  } else if (storm(day.code)) {
    out.push("Гроза протягом дня: не стійте під поодинокими високими деревами, на галявинах і пагорбах");
  }
  if (day.tempMax >= 30) out.push(`Спека до ${Math.round(day.tempMax)}°: візьміть більше води й головний убір`);
  if (day.tempMin <= -1) out.push(`Мороз до ${Math.round(day.tempMin)}°: тепло вдягніться, візьміть рукавиці й гарячий чай`);
  return out;
}
