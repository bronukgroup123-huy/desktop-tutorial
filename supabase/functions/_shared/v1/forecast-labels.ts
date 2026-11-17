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
import { type FruitingState, flushStages } from "../forecast/fruiting.ts";

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
  // Порода невідома (загальний чи мішаний ліс, тип не визначено) — не пишемо: ліс називаємо
  // тим, що відомо («Хвойний ліс»), без «без породи» / «тип невідомий» (рішення PO 2026-11-14).
  if (reason.startsWith("forest not confirmed") || reason.startsWith("forest group")) return null;
  if (reason === "temp in transition zone") {
    return weatherOk(w) ? `Температура ${deg(w.tempAvg7d)} — на межі сприятливої` : "Температура на межі сприятливої";
  }
  // Негативні правила й так українською («Занадто сиро», «Різкі перепади температур»).
  if (/[А-Яа-яІіЇїЄєҐґ]/.test(reason)) return reason;
  return null;
}

/**
 * Що стримує хвилю (рушій плодоношення): початок / спад хвилі, температура ґрунту.
 * Саме це найчастіше пояснює «Середню» посеред хвилі.
 */
export function fruitingLimitLabels(fr: FruitingState | undefined): string[] {
  if (!fr || fr.phase !== "flush") return [];
  const out: string[] = [];
  if (fr.stage === "rise") out.push("Хвиля тільки починається — гриби ще дрібні й поодинокі");
  if (fr.stage === "decline") out.push("Хвиля спадає — грибів меншає");
  if (fr.soilFit !== undefined && fr.soilFit < 1 && fr.soilT !== undefined) {
    out.push(fr.soilCold !== false
      ? `Ґрунт прохолодний (${deg(fr.soilT)}) — гриби ростуть повільно`
      : `Ґрунт затеплий (${deg(fr.soilT)}) — гриби ростуть гірше`);
  }
  return out;
}

/**
 * «Інші гриби сезону»: чому виду в сезоні сьогодні немає серед грибів зі шансом — одне речення.
 */
export function otherReasonLabel(missed: string[], w: WeatherData | null | undefined): string {
  for (const r of missed) {
    let m: RegExpMatchArray | null;
    if ((m = r.match(/^temp (-?[\d.]+) < min (-?[\d.]+)/))) {
      return `Холодно: ${deg(Number(m[1]))} за тиждень, потрібно від ${deg(Number(m[2]))}`;
    }
    if ((m = r.match(/^temp (-?[\d.]+) > max (-?[\d.]+)/))) {
      return `Затепло: ${deg(Number(m[1]))} за тиждень, потрібно до ${deg(Number(m[2]))}`;
    }
    if ((m = r.match(/^forest mismatch: need ([\w|]+)/))) {
      const TREE: Record<string, string> = {
        pine: "сосна", spruce: "ялина", oak: "дуб", birch: "береза", aspen: "осика",
        beech: "бук", hornbeam: "граб", alder: "вільха",
      };
      const names = m[1].split("|").map((t) => TREE[t]).filter((t): t is string => !!t).slice(0, 3);
      return names.length ? `У лісах ділянки немає його дерев (${names.join(", ")})` : "У лісах ділянки немає його дерев";
    }
    const label = humanizeLimit(r, w);
    if (label) return label;
  }
  return "Умови для нього поки не склалися";
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
  fruiting?: FruitingState,
): string[] {
  const out: string[] = [...fruitingLimitLabels(fruiting)];
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

const REASON_PREFIX: Record<string, string> = {
  peak: "Чому пік",
  high: "Чому висока",
  medium: "Чому середня",
  low: "Чому низька",
};

const lowerFirst = (t: string) => t.charAt(0).toLowerCase() + t.slice(1);

/**
 * Одне речення над карткою виду: чому саме такий рівень («Чому середня: хвиля тільки
 * починається — гриби ще дрібні й поодинокі»). Низька / середня — головне, що заважає;
 * висока / пік — головне, що сприяє.
 */
export function levelReasonLabel(
  level: string,
  limits: string[],
  why: string[],
  fr: FruitingState | undefined,
): string | null {
  const prefix = REASON_PREFIX[level];
  if (!prefix) return null;
  if (level === "low" || level === "medium") {
    const main = limits[0] ?? why[0];
    return main ? `${prefix}: ${lowerFirst(main)}` : null;
  }
  if (fr?.phase === "flush") {
    const text = fr.stage === "rise"
      ? "хвиля набирає силу — грибів більшає щодня"
      : fr.stage === "decline"
      ? "хвиля ще триває, хоч уже спадає"
      : "хвиля в розпалі — грибів найбільше";
    return `${prefix}: ${text}`;
  }
  return why[0] ? `${prefix}: ${lowerFirst(why[0])}` : null;
}

/**
 * Хвиля для смужки на картці виду: день і стадії (підйом / розпал / спад) — лише дні й
 * підписи, без чисел сили хвилі. Не хвиля — лише фаза й підпис.
 */
export function waveBlock(fr: FruitingState | undefined): Record<string, unknown> | null {
  if (!fr) return null;
  const label = fruitingWhenLabel(fr);
  if (fr.phase !== "flush" || !fr.flushDay || !fr.flushDays) return { phase: fr.phase, label };
  const n = fr.flushDays;
  const { rise, fallFrom } = flushStages(n);
  const declineFrom = Math.min(n, Math.ceil(fallFrom));
  return {
    phase: "flush",
    day: fr.flushDay,
    days: n,
    stage: fr.stage ?? null,
    label,
    segments: [
      { days: rise, label: "підйом" },
      { days: Math.max(0, declineFrom - rise), label: "розпал" },
      { days: n - declineFrom, label: "спад" },
    ].filter((x) => x.days > 0),
  };
}

export type WeatherScene =
  | "sunny" | "partly_cloudy" | "cloudy" | "rain" | "heavy_rain" | "fog" | "frost" | "snow" | "heat";

export const SCENE_LABEL: Record<WeatherScene, string> = {
  sunny: "Сонячно",
  partly_cloudy: "Мінлива хмарність",
  cloudy: "Хмарно",
  rain: "Дощ",
  heavy_rain: "Злива",
  fog: "Туман",
  frost: "Заморозок",
  snow: "Сніг",
  heat: "Спека",
};

/**
 * Сцена погоди дня для анімованого блоку (маскот-гриб): за кодом погоди WMO, а без нього
 * (старий кеш) — за опадами, температурою й вологістю. Спека — лише разом із посухою.
 */
export function weatherScene(
  day: { tempMin: number; tempMax: number; rain: number; humidity: number; code?: number | null },
  w: WeatherData | null | undefined,
): WeatherScene {
  const c = day.code ?? null;
  const inCodes = (...xs: Array<number | [number, number]>) =>
    c !== null && xs.some((x) => (Array.isArray(x) ? c >= x[0] && c <= x[1] : c === x));
  if (inCodes([71, 77], 85, 86) || (day.rain >= 1 && day.tempMax <= 1)) return "snow";
  if (inCodes(65, 67, 82, [95, 99]) || day.rain >= 15) return "heavy_rain";
  if (inCodes([51, 64], 66, 80, 81) || day.rain >= 1) return "rain";
  if (inCodes(45, 48) || (c === null && day.humidity >= 97)) return "fog";
  if (day.tempMin <= -1) return "frost";
  const dry = weatherOk(w) && (w.droughtDays >= 7 || w.rain7d < 5);
  if (day.tempMax >= 28 && dry) return "heat";
  if (inCodes(0, 1)) return "sunny";
  if (inCodes(2)) return "partly_cloudy";
  if (inCodes(3)) return "cloudy";
  return day.humidity >= 85 ? "cloudy" : day.humidity >= 75 ? "partly_cloudy" : "sunny";
}

/** Скільки молодих грибів навколо маскота: за стадією хвилі найкращого виду дня. */
export function sceneSprouts(fr: FruitingState | undefined): "none" | "few" | "many" {
  if (fr?.phase !== "flush") return "none";
  return fr.stage === "peak" ? "many" : "few";
}

/** «Схід 07:12 · захід 16:08 · світла 8 год 56 хв»; немає даних — null. */
export function sunLabel(day: { sunrise?: string | null; sunset?: string | null; daylightMin?: number | null }): string | null {
  if (!day.sunrise || !day.sunset) return null;
  const light = typeof day.daylightMin === "number"
    ? ` · світла ${Math.floor(day.daylightMin / 60)} год${day.daylightMin % 60 ? ` ${day.daylightMin % 60} хв` : ""}`
    : "";
  return `Схід ${day.sunrise} · захід ${day.sunset}${light}`;
}

/**
 * Що взяти в ліс за погодою дня — коротко: дощовик, гумові чоботи, тепле, вода, ліхтарик
 * (короткий день). Нічого особливого — null.
 */
export function takeLabel(
  day: { tempMin: number; tempMax: number; rain: number; daylightMin?: number | null },
  w: WeatherData | null | undefined,
): string | null {
  const items: string[] = [];
  if (day.rain >= 1) items.push("дощовик");
  if (day.rain >= 3 || (weatherOk(w) && (w.rain3d >= 10 || w.soilState === "wet" || w.soilState === "waterlogged"))) {
    items.push("гумові чоботи");
  }
  if (day.tempMin <= 2) items.push("тепла куртка й рукавиці");
  if (day.tempMax >= 26) items.push("вода й кепка");
  if (typeof day.daylightMin === "number" && day.daylightMin < 600) items.push("ліхтарик — день короткий");
  return items.length ? `Візьміть: ${items.join(", ")}` : null;
}

export type WeatherTone = "good" | "neutral" | "bad";

/**
 * Що погода на день означає для грибів — одне речення й тон (зелений / сірий / помаранчевий).
 * Вікна (опади за 3/7/14 днів, температура тижня, посуха) закінчуються цим днем.
 */
export function weatherVerdict(w: WeatherData | null | undefined): { label: string; tone: WeatherTone } | null {
  if (!weatherOk(w)) return null;
  if (w.droughtDays >= 10 || w.rain14d < 5) {
    return { label: "Сухо: дощу майже не було — гриби майже не ростуть", tone: "bad" };
  }
  if (w.tempAvg7d < 3) {
    return { label: "Холодно — ростуть лише зимові гриби (зимовий опеньок)", tone: "neutral" };
  }
  if (w.tempAvg7d > 24 && w.rain7d < 10) return { label: "Спекотно й сухо — гриби ховаються", tone: "bad" };
  if (w.rain3d >= 10) return { label: "Свіжий дощ промочив ґрунт — за кілька днів можлива нова хвиля", tone: "good" };
  if (w.rain7d >= 15 || (w.rain14d >= 20 && w.humidity >= 75)) {
    return { label: "Ґрунт вологий після дощів — добре для грибів", tone: "good" };
  }
  return { label: "Помірно волого — гриби ростуть, але без поспіху", tone: "neutral" };
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
  if (!forestType) return "Ліс";
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
