// ============================================================================
// Людські підписи прогнозу (BACKEND_PLAN B2.2, B2.3 — Response Shaping)
//
// Рушій прогнозу пояснює рішення технічними рядками англійською
// (`temp 13 within fruiting range`, `rain3d ok`). Клієнт не повинен їх показувати
// чи перекладати — сервер віддає готові українські підписи:
//   * why_labels — «чому» (лише позитивні, зрозумілі людині причини);
//   * when_label — «коли» (хвиля + скільки днів після дощу);
//   * forest_label — тип і вік лісу;
//   * weather — блок погоди з готовими рядками.
// ============================================================================

import type { Wave, WeatherData } from "../forecast/types.ts";
import { FOREST_TYPE_STYLE } from "./forest-zones.ts";

export const WAVE_LABEL: Record<Wave, string> = {
  spring: "Весняна хвиля",
  summer1: "Рання літня хвиля",
  summer2: "Літня хвиля",
  autumn: "Осіння хвиля",
  late: "Пізня хвиля",
};

/** Максимум причин «чому» у відповіді — коротко й по суті. */
export const MAX_WHY = 4;

const deg = (t: number) => `${Math.round(t)}°`;
const mm = (v: number) => `${Math.round(v)} мм`;

/** Українська форма «день/дні/днів». */
export function days(n: number): string {
  const a = Math.abs(n) % 100;
  const b = a % 10;
  if (a > 10 && a < 20) return `${n} днів`;
  if (b === 1) return `${n} день`;
  if (b >= 2 && b <= 4) return `${n} дні`;
  return `${n} днів`;
}

function weatherOk(w: WeatherData | null | undefined): w is WeatherData {
  return !!w && w.source !== "unavailable";
}

function forestName(type: string): string {
  return FOREST_TYPE_STYLE[type]?.label ?? "ліс";
}

/**
 * Технічна причина рушія → український підпис або `null` (не показувати).
 * Негативні, службові та невідомі англійські рядки відкидаються.
 */
export function humanizeReason(reason: string, w: WeatherData | null | undefined): string | null {
  let m: RegExpMatchArray | null;

  if ((m = reason.match(/^forest match: (\w+)/))) return `Підходящий ліс: ${forestName(m[1]).toLowerCase()}`;
  if ((m = reason.match(/^stand age (\d+)y in /))) return `Вік деревостану ${m[1]} р. — підходить`;
  if (reason.startsWith("relief match")) return "Підходящий рельєф";
  if ((m = reason.match(/^temp (-?[\d.]+) within fruiting range/))) {
    return `Температура ${deg(Number(m[1]))} — підходить для плодоношення`;
  }
  if (reason.startsWith("in peak temp")) return "Температура в оптимумі для виду";
  if (reason === "humidity ok") return weatherOk(w) ? `Вологість ${Math.round(w.humidity)}% — достатня` : "Достатня вологість";
  if (reason === "rain3d ok") return weatherOk(w) ? `Дощ ${mm(w.rain3d)} за останні 3 дні` : "Були дощі";
  if (reason === "drought → rain trigger") return "Дощ після посухи — сигнал до росту";
  if ((m = reason.match(/^daysAfterRain (\d+) in /))) return `${days(Number(m[1]))} після дощу — вдалий час`;
  if (/^\d\d-\d\d in season$/.test(reason)) return "Сезон цього виду";
  if (reason.startsWith("peak wave") || reason.startsWith("peak month")) return "Пік сезону";
  if (reason === "wet → ×1.0" || reason === "normal → ×1.0") return "Ґрунт достатньо вологий";

  // Причини правил і краудсорсингу вже українською — показуємо як є,
  // крім назв хвиль (їх покриває when_label).
  if (/[А-Яа-яІіЇїЄєҐґ]/.test(reason) && !/хвиля/i.test(reason)) return reason;

  return null;
}

/** «Чому»: перекладені причини без дублів, не більше [MAX_WHY]. */
export function whyLabels(matched: string[], w: WeatherData | null | undefined): string[] {
  const out: string[] = [];
  for (const r of matched) {
    const label = humanizeReason(r, w);
    if (label && !out.includes(label)) out.push(label);
    if (out.length >= MAX_WHY) break;
  }
  return out;
}

/** «Коли»: «Зараз — 3 дні після дощу · Осіння хвиля». */
export function whenLabel(wave: Wave | null, w: WeatherData | null | undefined): string {
  const waveLabel = wave ? WAVE_LABEL[wave] : "Весь сезон";
  if (weatherOk(w) && w.daysAfterRain >= 0 && w.daysAfterRain <= 14) {
    const when = w.daysAfterRain === 0 ? "Зараз — у день дощу" : `Зараз — ${days(w.daysAfterRain)} після дощу`;
    return `${when} · ${waveLabel}`;
  }
  return waveLabel;
}

/** Тип і вік лісу для заголовка прогнозу. */
export function forestLabel(forestType: string | null | undefined, standAge: number | null | undefined): string {
  if (!forestType) return "Тип лісу невідомий — прогноз базовий";
  const name = forestName(forestType);
  return standAge ? `${name}, ~${standAge} р.` : name;
}

export type WeatherIcon = "sun" | "cloud" | "rain" | "unknown";

export interface WeatherBlock {
  icon: WeatherIcon;
  temp_label: string;
  humidity_label: string;
  rain_label: string;
  rain_recent_label: string;
  pressure_label: string;
}

const PRESSURE_TREND: Record<string, string> = {
  rising: "зростає",
  falling: "падає",
  stable: "стабільний",
  smooth_decline_before_rain: "плавно падає — можливий дощ",
};

/** Блок погоди (B2.3). `null`, якщо погода недоступна — клієнт ховає блок. */
export function weatherBlock(w: WeatherData | null | undefined): WeatherBlock | null {
  if (!weatherOk(w)) return null;
  const icon: WeatherIcon = w.rain1d >= 1 ? "rain" : w.humidity >= 80 ? "cloud" : "sun";
  return {
    icon,
    temp_label: `${deg(w.tempMin)}…${deg(w.tempMax)}, у середньому ${deg(w.tempAvg7d)} за тиждень`,
    humidity_label: `Вологість ${Math.round(w.humidity)}%`,
    rain_label: `Опади: ${mm(w.rain3d)} за 3 дні, ${mm(w.rain7d)} за тиждень`,
    rain_recent_label: w.daysAfterRain <= 30
      ? (w.daysAfterRain === 0 ? "Сильний дощ сьогодні" : `Сильний дощ ${days(w.daysAfterRain)} тому`)
      : "Сильних дощів давно не було",
    pressure_label: `Тиск ${Math.round(w.pressure)} гПа, ${PRESSURE_TREND[w.pressureTrend] ?? "без змін"}`,
  };
}
