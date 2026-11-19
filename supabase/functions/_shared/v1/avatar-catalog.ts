// ============================================================================
// Грибний аватар-наліпка (ADR-021 §21.7): персонаж + деталі, і хто що може вибрати.
//
// Персонаж — одна з наліпок (форма, колір, емоція, поза вже намальовані). Деталі — капелюх, річ,
// ефект — додаються поверх. Кожна позиція відкривається рівно одним способом: безкоштовно · за
// рівень (ADR-013, не купується) · за «спори» (поки «спор» немає — замок «скоро») · у Pro (поки Pro
// немає — замок). Сезонні — лише у свій сезон. Каталог — на сервері: нові наліпки й деталі без
// релізу застосунку (малює застосунок; невідомий йому id просто не малюється). Аватар статичний.
// ============================================================================
import { HttpError } from "../http.ts";
import { type Level, levelOf } from "./profile-rules.ts";

export type Unlock =
  | { type: "free" }
  | { type: "level"; level: Level["id"] }
  | { type: "spores"; price: number }
  | { type: "pro" };

export interface Part {
  id: string;
  label: string;
  unlock: Unlock;
  /** Сезон «ММ-ДД»…«ММ-ДД» (може переходити через Новий рік). */
  season?: { from: string; to: string; label: string };
}

export interface Category {
  id: "sticker" | "hat" | "item" | "fx";
  label: string;
  /** Деталь, яку можна не вибирати (капелюх, річ, ефект). */
  optional: boolean;
  parts: Part[];
}

const free: Unlock = { type: "free" };
const level = (l: Level["id"]): Unlock => ({ type: "level", level: l });
const pro: Unlock = { type: "pro" };

export const AVATAR_CATALOG: Category[] = [
  {
    id: "sticker",
    label: "Персонаж",
    optional: false,
    parts: [
      { id: "kind", label: "Добряк", unlock: free },
      { id: "laugh", label: "Реготун", unlock: free },
      { id: "wow", label: "Здивована", unlock: free },
      { id: "cool", label: "Крутий", unlock: free },
      { id: "love", label: "Закоханий", unlock: free },
      { id: "sleepy", label: "Сплюх", unlock: free },
      { id: "tease", label: "Пустунка", unlock: free },
      { id: "sly", label: "Хитрун", unlock: free },
      { id: "dizzy", label: "Запаморочений", unlock: free },
      { id: "scared", label: "Боягуз", unlock: free },
      { id: "grumpy", label: "Бурчуни", unlock: free },
      { id: "cry", label: "Плакса", unlock: free },
      { id: "hello", label: "Привітна", unlock: free },
      { id: "shy", label: "Сором'язливий", unlock: free },
      { id: "excited", label: "Захоплений", unlock: level("tracker") },
      { id: "friends", label: "Друзі-опеньки", unlock: level("tracker") },
      { id: "sage", label: "Мудрець", unlock: level("expert") },
      { id: "strong", label: "Силач", unlock: level("expert") },
      { id: "fashion", label: "Модниця", unlock: level("forester") },
      { id: "brave", label: "Сміливець", unlock: level("forester") },
      { id: "golden", label: "Золотий боровик", unlock: level("keeper") },
      { id: "giant", label: "Велетень", unlock: level("master") },
      { id: "cosmic", label: "Космічний", unlock: pro },
      { id: "firefly", label: "Світлячок", unlock: pro },
      { id: "frost", label: "Морозко", unlock: pro },
      { id: "rainbow", label: "Райдужний", unlock: pro },
      { id: "sorceress", label: "Чарівниця", unlock: pro },
      { id: "nightcap", label: "Нічний мухомор", unlock: pro },
    ],
  },
  {
    id: "hat",
    label: "Капелюх",
    optional: true,
    parts: [
      { id: "leaf", label: "Листочок", unlock: free },
      { id: "wreath", label: "Віночок", unlock: free },
      { id: "cap", label: "Кепка", unlock: free },
      { id: "beanie", label: "Шапочка", unlock: free },
      { id: "straw", label: "Солом'яний", unlock: free },
      { id: "ranger", label: "Лісника", unlock: level("forester") },
      { id: "wizard", label: "Чарівника", unlock: { type: "spores", price: 80 } },
      { id: "tophat", label: "Циліндр", unlock: pro },
      { id: "crown", label: "Корона Грибного Майстра", unlock: level("master") },
      { id: "santa", label: "Новорічна", unlock: free, season: { from: "12-01", to: "01-15", label: "1 грудня — 15 січня" } },
      { id: "pumpkin", label: "Гарбуз", unlock: free, season: { from: "10-15", to: "11-05", label: "15 жовтня — 5 листопада" } },
    ],
  },
  {
    id: "item",
    label: "Річ",
    optional: true,
    parts: [
      { id: "basket", label: "Кошик", unlock: free },
      { id: "glasses", label: "Окуляри", unlock: free },
      { id: "scarf", label: "Шарф", unlock: free },
      { id: "flower", label: "Квітка", unlock: free },
      { id: "map", label: "Мапа", unlock: level("tracker") },
      { id: "magnifier", label: "Лупа", unlock: level("expert") },
      { id: "backpack", label: "Наплічник", unlock: level("forester") },
      { id: "medal", label: "Медаль Хранителя", unlock: level("keeper") },
      { id: "bowtie", label: "Метелик", unlock: { type: "spores", price: 40 } },
      { id: "lantern", label: "Ліхтарик", unlock: pro },
    ],
  },
  {
    id: "fx",
    label: "Ефект",
    optional: true,
    parts: [
      { id: "sparkle", label: "Іскри", unlock: free },
      { id: "hearts", label: "Сердечка", unlock: free },
      { id: "notes", label: "Ноти", unlock: free },
      { id: "leaves", label: "Листопад", unlock: free },
      { id: "cloud", label: "Хмаринка", unlock: free },
      { id: "butterfly", label: "Метелики", unlock: level("tracker") },
      { id: "fireflies", label: "Світлячки", unlock: pro },
      { id: "snow", label: "Сніжинки", unlock: free, season: { from: "12-01", to: "02-28", label: "1 грудня — 28 лютого" } },
    ],
  },
];

const LEVEL_RANK: Record<Level["id"], number> = { traveler: 1, tracker: 2, expert: 3, forester: 4, keeper: 5, master: 6 };
const LEVEL_LABEL: Record<Level["id"], string> = {
  traveler: "Мандрівник", tracker: "Слідопит", expert: "Грибознавець", forester: "Лісовик", keeper: "Хранитель лісу", master: "Грибний Майстер",
};

export interface Viewer {
  rating: number;
  certified?: boolean;
  pro: boolean;
  /** Куплені за «спори» деталі (поки «спор» немає — порожньо). */
  owned: ReadonlySet<string>;
  now: Date;
}

function inSeason(season: Part["season"], now: Date): boolean {
  if (!season) return true;
  const md = `${String(now.getUTCMonth() + 1).padStart(2, "0")}-${String(now.getUTCDate()).padStart(2, "0")}`;
  return season.from <= season.to ? md >= season.from && md <= season.to : md >= season.from || md <= season.to;
}

/** Чи може глядач вибрати деталь; якщо ні — чому (для замка). */
export function partAccess(part: Part, v: Viewer): { open: true; badge: string | null } | { open: false; reason: string } {
  if (!inSeason(part.season, v.now)) return { open: false, reason: `Лише ${part.season!.label}` };
  switch (part.unlock.type) {
    case "free":
      return { open: true, badge: part.season ? `До ${part.season.label.split("— ")[1]}` : null };
    case "level": {
      const need = part.unlock.level;
      const mine = levelOf(v.rating, v.certified).id;
      return LEVEL_RANK[mine] >= LEVEL_RANK[need]
        ? { open: true, badge: `За рівень «${LEVEL_LABEL[need]}»` }
        : { open: false, reason: `З рівня «${LEVEL_LABEL[need]}»` };
    }
    case "spores":
      return v.owned.has(part.id)
        ? { open: true, badge: "Куплено за спори" }
        : { open: false, reason: `${part.unlock.price} спор — скоро` };
    case "pro":
      return v.pro ? { open: true, badge: "Pro" } : { open: false, reason: "У Pro" };
  }
}

/** Каталог для екрана конструктора: деталі з позначкою «відкрито» / причиною замка. */
export function catalogFor(v: Viewer) {
  return {
    categories: AVATAR_CATALOG.map((c) => ({
      id: c.id,
      label: c.label,
      optional: c.optional,
      parts: c.parts.map((p) => {
        const a = partAccess(p, v);
        return { id: p.id, label: p.label, open: a.open, badge: a.open ? a.badge : null, lock_label: a.open ? null : a.reason };
      }),
    })),
  };
}

export type CustomAvatar = {
  kind: "custom";
  sticker: string;
  hat: string | null;
  item: string | null;
  fx: string | null;
};

const ids = (cat: Category["id"]) => AVATAR_CATALOG.find((c) => c.id === cat)!.parts;

/** Перевірка форми запиту (без прав) — у validateUpdateMe. */
export function parseCustomAvatar(raw: Record<string, unknown>): CustomAvatar {
  const pick = (cat: Category["id"]): string | null => {
    const c = AVATAR_CATALOG.find((x) => x.id === cat)!;
    const v = raw[cat];
    if ((v === null || v === undefined || v === "none") && c.optional) return null;
    if (typeof v !== "string" || !c.parts.some((p) => p.id === v)) {
      throw new HttpError(400, "invalid_avatar", `Невідома деталь аватара: ${c.label.toLowerCase()}`);
    }
    return v;
  };
  return { kind: "custom", sticker: pick("sticker")!, hat: pick("hat"), item: pick("item"), fx: pick("fx") };
}

/** Безкоштовні персонажі — для аватара за замовчуванням і старих «стандартних» (1…20). */
export const FREE_STICKERS = ids("sticker").filter((p) => p.unlock.type === "free").map((p) => p.id);

/**
 * Аватар для відповіді: завжди наліпка. Старий «стандартний» гриб (id 1…20, до наліпок) —
 * безкоштовний персонаж за номером; невідомі деталі (прибрали з каталогу) — без них.
 */
export function publicAvatar(stored: Record<string, unknown> | null | undefined): CustomAvatar {
  if (stored?.kind === "custom") {
    const known = (cat: Category["id"]) => {
      const v = stored[cat];
      return typeof v === "string" && ids(cat).some((p) => p.id === v) ? v : null;
    };
    return { kind: "custom", sticker: known("sticker") ?? FREE_STICKERS[0], hat: known("hat"), item: known("item"), fx: known("fx") };
  }
  const n = Number.isInteger(stored?.id) ? (stored!.id as number) : 1;
  return { kind: "custom", sticker: FREE_STICKERS[(Math.max(n, 1) - 1) % FREE_STICKERS.length], hat: null, item: null, fx: null };
}

/**
 * Права на деталі: закрита деталь — 403 з причиною («З рівня «Лісовик»»). Деталь, яка вже стоїть
 * в аватарі ([current]), лишається — навіть якщо сезон минув чи підписка скінчилась.
 */
export function assertAvatarAllowed(a: CustomAvatar, v: Viewer, current: Record<string, unknown> | null): void {
  const was = current ? publicAvatar(current) : null;
  for (const c of AVATAR_CATALOG) {
    const id = a[c.id];
    if (id === null) continue;
    if (was?.[c.id] === id) continue;
    const part = c.parts.find((p) => p.id === id)!;
    const access = partAccess(part, v);
    if (!access.open) {
      throw new HttpError(403, "avatar_part_locked", `«${part.label}» — ${access.reason.charAt(0).toLowerCase()}${access.reason.slice(1)}`);
    }
  }
}
