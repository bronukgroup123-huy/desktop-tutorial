// ============================================================================
// «Розширені дані погоди» прогнозу ділянки (рішення PO 2026-11-15)
//
// Сирий графік температури й опадів грибнику нічого не каже. Тут — те, що відповідає на
// «чи будуть гриби і коли»:
//   * смужка «дощ → гриби»: опади за 14 днів і прогноз, дощі, що промочили ґрунт (поштовх),
//     крапка температури дня (заморозок / холодно / добре / спека) і вікно хвилі найкращого виду;
//   * «що вже сталося» — 2–3 події простими словами;
//   * шкали: вологість ґрунту, тепло для росту, дощ за 2 тижні;
//   * «що далі» — одне речення про прогноз.
// Лише готові підписи й звичайні числа погоди (мм) — без ймовірностей (Заборона №1).
// ============================================================================

import type { DayWeather, ForecastResult, ScoredSpecies } from "../forecast/types.ts";
import { days as daysWord } from "./forecast-labels.ts";

/** Дощ за добу, що промочує ґрунт (поштовх для більшості видів), мм. */
export const SOAKING_RAIN_MM = 8;
/** Дощ за 2 тижні, якого грибам зазвичай досить, мм (позначка на шкалі). */
export const ENOUGH_RAIN14_MM = 20;
const RAIN14_SCALE_MM = 40;

export type DayTemp = "frost" | "cold" | "ok" | "hot";

const deg = (t: number) => `${Math.round(t)}°`;
const mm = (v: number) => `${Math.round(v)} мм`;
const dm = (date: string) => `${date.slice(8, 10)}.${date.slice(5, 7)}`;

function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export function dayTemp(d: DayWeather): DayTemp {
  if (d.tempMin <= -1) return "frost";
  if (d.tempMax >= 28) return "hot";
  if ((d.tempMin + d.tempMax) / 2 < 5) return "cold";
  return "ok";
}

/**
 * [results] — прогони рушія на дні горизонту (перший тип лісу), [top] — найкращий вид
 * сьогодні, [dayLabel] — «Сьогодні» / «Завтра» / «Вт 17».
 */
export function weatherInsight(
  results: ForecastResult[],
  today: string,
  top: ScoredSpecies | null,
  dayLabel: (date: string) => string,
): Record<string, unknown> | null {
  const todayRes = results.find((r) => r.weather?.day?.date === today) ?? results[0];
  const w = todayRes?.weather;
  if (!w || w.source === "unavailable") return null;
  const byDate = new Map<string, DayWeather>();
  for (const d of w.recent ?? []) byDate.set(d.date, d);
  for (const r of results) {
    const d = r.weather?.day;
    if (d && r.weather?.source !== "unavailable") byDate.set(d.date, d);
  }
  const list = [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date));
  if (list.length < 2) return null;

  const past = list.filter((d) => d.date <= today);
  const future = list.filter((d) => d.date > today);
  const fr = top?.fruiting;
  const name = top?.name_ua ?? null;

  // Вікно хвилі найкращого виду: триває — від першого дня до кінця; дозріває — «з …».
  let wave: Record<string, unknown> | null = null;
  if (fr?.phase === "flush" && fr.flushDay && fr.flushDays) {
    const from = addDays(today, -(fr.flushDay - 1));
    const to = addDays(from, fr.flushDays - 1);
    wave = { from, to, label: `${name}: гриби ${dm(from)}–${dm(to)}` };
  } else if (fr?.phase === "maturing" && fr.expectedStart) {
    wave = { from: fr.expectedStart, to: null, label: `${name}: чекаємо з ${dm(fr.expectedStart)}` };
  }

  // Що вже сталося — найсвіжіші події, до трьох.
  const events: Array<{ date: string; icon: string; label: string }> = [];
  const lastSoak = [...past].reverse().find((d) => d.rain >= SOAKING_RAIN_MM);
  if (lastSoak) {
    events.push({ date: lastSoak.date, icon: "rain", label: `Дощ ${mm(lastSoak.rain)}, ${dm(lastSoak.date)} — ґрунт промочило` });
  }
  const lastFrost = [...past].reverse().find((d) => d.tempMin <= -1);
  if (lastFrost) {
    events.push({
      date: lastFrost.date,
      icon: "frost",
      label: `Заморозок ${deg(lastFrost.tempMin)}, ${dm(lastFrost.date)} — ріст пригальмував`,
    });
  }
  if (fr?.triggerDate && top && fr.triggerDate <= today && fr.phase !== "idle") {
    const thaw = top.matched.concat(top.missed).some((r) => / thaw /.test(r)) && (fr.triggerRain ?? 0) === 0;
    if (thaw) {
      events.push({ date: fr.triggerDate, icon: "thaw", label: `Відлига ${dm(fr.triggerDate)} — грибниця рушила в ріст` });
    }
  }
  if (w.droughtDays >= 10) {
    events.push({ date: today, icon: "dry", label: `Без дощу вже ${daysWord(w.droughtDays)} — ґрунт пересихає` });
  }
  events.sort((a, b) => b.date.localeCompare(a.date));

  // Шкали.
  const soilIndex = { dry: 0, normal: 1, wet: 2, waterlogged: 3 }[w.soilState] ?? 1;
  const t7 = w.tempAvg7d;
  const warmIndex = t7 < 5 ? 0 : t7 < 10 ? 1 : t7 <= 22 ? 2 : 3;
  const rain14 = w.rain14d;
  const gauges = [
    {
      key: "soil",
      title: "Вологість ґрунту",
      steps: ["сухо", "норма", "волого", "перезволожено"],
      index: soilIndex,
      tone: soilIndex === 0 ? "bad" : soilIndex === 2 ? "good" : "neutral",
    },
    {
      key: "warmth",
      title: "Тепло для росту",
      steps: ["холодно", "прохолодно", "добре", "жарко"],
      index: warmIndex,
      tone: warmIndex === 2 ? "good" : warmIndex === 0 || warmIndex === 3 ? "bad" : "neutral",
      hint: warmIndex === 0 ? "ростуть лише зимові гриби" : null,
    },
    {
      key: "rain14",
      title: "Дощ за 2 тижні",
      value_label: `${mm(rain14)} — ${rain14 >= ENOUGH_RAIN14_MM ? "достатньо" : rain14 >= ENOUGH_RAIN14_MM / 2 ? "помірно" : "замало"}`,
      fill: Math.round(Math.min(1, rain14 / RAIN14_SCALE_MM) * 100) / 100,
      mark: ENOUGH_RAIN14_MM / RAIN14_SCALE_MM,
      mark_label: `від ${ENOUGH_RAIN14_MM} мм — досить`,
      tone: rain14 >= ENOUGH_RAIN14_MM ? "good" : rain14 >= ENOUGH_RAIN14_MM / 2 ? "neutral" : "bad",
    },
  ];

  // Що далі.
  const rainy = future.find((d) => d.rain >= 5);
  const frost = future.find((d) => d.tempMin <= -1);
  let outlook: string;
  if (rainy) {
    outlook = `${dayLabel(rainy.date)} — дощ ${mm(rainy.rain)}: ` +
      (fr?.phase === "flush" ? "підтримає хвилю" : "промочить ґрунт — за 1–2 тижні можлива хвиля");
  } else if (frost) {
    outlook = `${dayLabel(frost.date)} — заморозок ${deg(frost.tempMin)}: ріст пригальмує`;
  } else if (future.length > 0 && future.every((d) => d.rain < 1)) {
    outlook = `Без дощу до ${dayLabel(future[future.length - 1].date).toLowerCase()} — ґрунт підсихатиме`;
  } else {
    outlook = "Суттєвих змін погоди не очікується";
  }

  return {
    strip_title: "Дощі й гриби",
    days: list.map((d) => ({
      date: d.date,
      label: dayLabel(d.date) === "Сьогодні" ? "сьог." : dayLabel(d.date).split(" ")[0],
      date_label: d.date.slice(8, 10),
      rain: Math.round(d.rain * 10) / 10,
      soaking: d.rain >= SOAKING_RAIN_MM,
      temp: dayTemp(d),
      forecast: d.date > today,
      today: d.date === today,
    })),
    wave,
    legend_labels: {
      soaking: "дощ промочив ґрунт",
      frost: "заморозок",
      cold: "холодно",
      ok: "добре",
      hot: "спека",
    },
    events_title: "Що вже сталося",
    events: events.slice(0, 3).map(({ icon, label }) => ({ icon, label })),
    gauges,
    outlook_title: "Що далі",
    outlook_label: outlook,
  };
}
