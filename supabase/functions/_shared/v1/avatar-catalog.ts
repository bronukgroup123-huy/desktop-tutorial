// ============================================================================
// Конструктор грибного аватара (ADR-021 §21.7): каталог деталей і хто що може вибрати.
//
// Кожна деталь відкривається рівно одним способом: безкоштовно · за рівень (ADR-013, не
// купується) · за «спори» (поки «спор» немає — замок «скоро») · у Pro (поки Pro немає — замок).
// Сезонні деталі — лише у свій сезон. Каталог — на сервері: нові деталі без релізу застосунку
// (малює застосунок; невідомий йому id просто не малюється). Аватар статичний.
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
  id: "shape" | "color" | "face" | "arms" | "hat" | "item";
  label: string;
  /** Деталь, яку можна не вибирати (капелюх, річ). */
  optional: boolean;
  parts: Part[];
}

const free: Unlock = { type: "free" };

export const AVATAR_CATALOG: Category[] = [
  {
    id: "shape",
    label: "Гриб",
    optional: false,
    parts: [
      { id: "bolete", label: "Боровик", unlock: free },
      { id: "amanita", label: "Мухомор", unlock: free },
      { id: "chanterelle", label: "Лисичка", unlock: free },
      { id: "honey", label: "Опеньок", unlock: free },
      { id: "puffball", label: "Дощовик", unlock: free },
      { id: "morel", label: "Зморшок", unlock: { type: "level", level: "tracker" } },
    ],
  },
  {
    id: "color",
    label: "Колір шапки",
    optional: false,
    parts: [
      { id: "brown", label: "Коричневий", unlock: free },
      { id: "chestnut", label: "Каштановий", unlock: free },
      { id: "red", label: "Червоний", unlock: free },
      { id: "orange", label: "Помаранчевий", unlock: free },
      { id: "yellow", label: "Жовтий", unlock: free },
      { id: "cream", label: "Кремовий", unlock: free },
      { id: "violet", label: "Фіолетовий", unlock: { type: "spores", price: 30 } },
      { id: "gold", label: "Золотий", unlock: { type: "level", level: "keeper" } },
      { id: "night", label: "Нічний", unlock: { type: "pro" } },
    ],
  },
  {
    id: "face",
    label: "Обличчя",
    optional: false,
    parts: [
      { id: "kind", label: "Добрий", unlock: free },
      { id: "happy", label: "Веселий", unlock: free },
      { id: "sly", label: "Хитрий", unlock: free },
      { id: "angry", label: "Злий", unlock: free },
      { id: "sleepy", label: "Сонний", unlock: free },
      { id: "surprised", label: "Здивований", unlock: free },
      { id: "wink", label: "Підморгує", unlock: { type: "level", level: "tracker" } },
      { id: "dizzy", label: "Запаморочений", unlock: { type: "spores", price: 20 } },
    ],
  },
  {
    id: "arms",
    label: "Руки",
    optional: false,
    parts: [
      { id: "down", label: "Спокійно", unlock: free },
      { id: "wave", label: "Вітається", unlock: free },
      { id: "up", label: "Ура", unlock: free },
      { id: "hips", label: "Руки в боки", unlock: free },
      { id: "out", label: "Обійми", unlock: { type: "level", level: "tracker" } },
    ],
  },
  {
    id: "hat",
    label: "Капелюх",
    optional: true,
    parts: [
      { id: "cap", label: "Кепка", unlock: free },
      { id: "straw", label: "Солом'яний", unlock: free },
      { id: "beanie", label: "Шапочка", unlock: free },
      { id: "ranger", label: "Лісника", unlock: { type: "level", level: "forester" } },
      { id: "wizard", label: "Чарівника", unlock: { type: "spores", price: 80 } },
      { id: "crown", label: "Корона Грибного Майстра", unlock: { type: "level", level: "master" } },
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
      { id: "boots", label: "Чоботи", unlock: free },
      { id: "flower", label: "Квітка", unlock: free },
      { id: "backpack", label: "Наплічник", unlock: { type: "level", level: "forester" } },
      { id: "bowtie", label: "Метелик", unlock: { type: "spores", price: 40 } },
      { id: "lantern", label: "Ліхтарик", unlock: { type: "pro" } },
      { id: "medal", label: "Медаль Хранителя", unlock: { type: "level", level: "keeper" } },
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
  shape: string;
  color: string;
  face: string;
  arms: string;
  hat: string | null;
  item: string | null;
};

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
  return {
    kind: "custom",
    shape: pick("shape")!,
    color: pick("color")!,
    face: pick("face")!,
    arms: pick("arms")!,
    hat: pick("hat"),
    item: pick("item"),
  };
}

/**
 * Права на деталі: закрита деталь — 403 з причиною («З рівня «Лісовик»»). Деталь, яка вже стоїть
 * в аватарі ([current]), лишається — навіть якщо сезон минув чи підписка скінчилась.
 */
export function assertAvatarAllowed(a: CustomAvatar, v: Viewer, current: Record<string, unknown> | null): void {
  for (const c of AVATAR_CATALOG) {
    const id = a[c.id];
    if (id === null) continue;
    if (current?.kind === "custom" && current[c.id] === id) continue;
    const part = c.parts.find((p) => p.id === id)!;
    const access = partAccess(part, v);
    if (!access.open) {
      throw new HttpError(403, "avatar_part_locked", `«${part.label}» — ${access.reason.charAt(0).toLowerCase()}${access.reason.slice(1)}`);
    }
  }
}
