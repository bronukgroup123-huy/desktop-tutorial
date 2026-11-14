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
import type { FruitingState } from "../forecast/fruiting.ts";

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

  if ((m = reason.match(/^fruiting flush (\d+)\/(\d+) (\w+) (\d+) ([\d.]+)/))) {
    return `Хвиля плодоношення: ${m[1]}-й день з ${m[2]} — ${triggerPhrase(m[3], Number(m[4]), m[5])}`;
  }
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
  // «Температура в оптимумі» вже каже більше, ніж «температура підходить» — без дублю.
  const inPeak = matched.some((r) => r.startsWith("in peak temp"));
  for (const r of matched) {
    if (inPeak && /^temp (-?[\d.]+) within fruiting range/.test(r)) continue;
    const label = humanizeReason(r, w);
    if (label && !out.includes(label)) out.push(label);
    if (out.length >= MAX_WHY) break;
  }
  return out;
}

/** Що запустило хвилю — за видом поштовху: «після дощу 18 мм (12.09)», «після відлиги (10.11)». */
export function triggerPhrase(kind: string, rain: number, date: string): string {
  switch (kind) {
    case "spring_warm":
      return `після прогріву ґрунту (${date})`;
    case "thaw":
      return rain > 0 ? `після дощу ${rain} мм у холод (${date})` : `після відлиги (${date})`;
    case "rain_cool":
      return `після дощу ${rain} мм і похолодання (${date})`;
    default:
      return `після дощу ${rain} мм (${date})`;
  }
}

/** Хвилі немає: чого чекаємо — за видом поштовху. */
const IDLE_LABEL: Record<string, (mm: string) => string> = {
  rain: (v) => `Хвилі зараз немає — потрібен дощ від ${v} мм`,
  rain_cool: (v) => `Хвилі зараз немає — потрібні дощ від ${v} мм і похолодання`,
  spring_warm: () => "Ґрунт ще не прогрівся до 8° — сморчки з'являться після прогріву",
  thaw: () => "Чекаємо відлиги після заморозків",
};

/** «Коли» з рушія плодоношення — одне коротке речення для картки виду. */
export function fruitingWhenLabel(fr: FruitingState | undefined): string | null {
  if (!fr) return null;
  const d = (x?: string) => (x ? `${x.slice(8, 10)}.${x.slice(5, 7)}` : "");
  switch (fr.phase) {
    case "flush":
      return `Хвиля зараз — ${fr.flushDay}-й день з ${fr.flushDays}`;
    case "maturing":
      return fr.expectedStart ? `Хвиля орієнтовно з ${d(fr.expectedStart)}` : "Грибниця дозріває — хвиля за кілька днів";
    case "after":
      return "Хвиля минула — чекаємо нового дощу";
    case "idle":
      return "Хвилі зараз немає";
  }
}

/**
 * Обмежувальний фактор рушія (`ScoredSpecies.missed`) → український підпис.
 * Показуються з іконкою-попередженням, щоб було видно, ЧОМУ рівень не вищий.
 */
export function humanizeLimit(reason: string, w: WeatherData | null | undefined): string | null {
  let m: RegExpMatchArray | null;
  if ((m = reason.match(/^fruiting maturing (\w+) (\d+) ([\d.]+) until (\S+)/))) {
    const when = m[4] === "?" ? "за кілька днів" : `орієнтовно з ${m[4]}`;
    return `Грибниця дозріває ${triggerPhrase(m[1], Number(m[2]), m[3])} — гриби ${when}`;
  }
  if ((m = reason.match(/^fruiting after (\S+)/))) return `Хвиля минула (до ${m[1]}) — потрібен новий дощ`;
  if ((m = reason.match(/^fruiting idle (\w+) ([\d.]+)/))) return IDLE_LABEL[m[1]]?.(m[2]) ?? null;
  if ((m = reason.match(/^humidity ([\d.]+) < ([\d.]+)/))) {
    return `Вологість ${Math.round(Number(m[1]))}% — замало (краще від ${Math.round(Number(m[2]))}%)`;
  }
  if ((m = reason.match(/^rain3d ([\d.]+) < ([\d.]+)/))) {
    return `Мало дощу: ${mm(Number(m[1]))} за 3 дні (краще від ${mm(Number(m[2]))})`;
  }
  if ((m = reason.match(/^drought (\d+)d /))) return `Посуха ${days(Number(m[1]))} без дощу`;
  if ((m = reason.match(/^daysAfterRain (\d+) outside/))) return `${days(Number(m[1]))} після дощу — не найкращий час`;
  if ((m = reason.match(/^stand age (\d+)y outside/))) return `Вік деревостану ${m[1]} р. — не оптимальний`;
  if (reason.startsWith("relief soft-miss")) return "Рельєф не найкращий для виду";
  if (reason.startsWith("dry →")) return "Сухий ґрунт";
  if (reason.startsWith("waterlogged →")) return "Ґрунт перезволожений";
  if (reason.startsWith("forest not confirmed")) return "Тип лісу не визначено";
  if (reason === "forest group: mixed") return "Ліс мішаний — невідомо, чи є тут потрібні дерева. Уточніть ліс";
  if ((m = reason.match(/^forest group: (\w+)/))) {
    return `${forestName(m[1])} без відомої породи — уточніть ліс, щоб прогноз був точнішим`;
  }
  if (reason === "temp in transition zone") {
    return weatherOk(w) ? `Температура ${deg(w.tempAvg7d)} — на межі сприятливої` : "Температура на межі сприятливої";
  }
  // Негативні правила й так українською («Занадто сиро», «Різкі перепади температур»).
  if (/[А-Яа-яІіЇїЄєҐґ]/.test(reason)) return reason;
  return null;
}

/**
 * «Що заважає»: перекладені обмежувальні фактори. Якщо рівень нижчий за «високий», а
 * явних факторів немає — пояснюємо сезон, щоб «✓» не суперечили бейджу рівня.
 */
export function limitLabels(
  missed: string[],
  matched: string[],
  level: string,
  w: WeatherData | null | undefined,
): string[] {
  const out: string[] = [];
  for (const r of missed) {
    const label = humanizeLimit(r, w);
    if (label && !out.includes(label)) out.push(label);
    if (out.length >= MAX_WHY) break;
  }
  if (out.length === 0 && (level === "low" || level === "medium")) {
    const peak = matched.some((r) => r.startsWith("peak wave") || r.startsWith("peak month"));
    out.push(peak ? "Умови сприятливі лише частково" : "Не пік сезону для цього виду");
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
