// ============================================================================
// Нік, ім'я, аватар і рівень профілю (ADR-021 §21.2.1, §21.7; ADR-013)
//
// Нік (`@Олена_лісова`) — лише українські літери (без латиниці й без ы/э/ъ/ё — немає
// двійників на кшталт кириличної «о» і латинської «o»), цифри, `_`, `.`, апостроф; 3–20 символів,
// з літери; унікальний без урахування великих літер (ключ — `handleKey`). Ім'я — обов'язкове,
// українські літери, пробіл, дефіс, апостроф, до 30 символів.
// ============================================================================

import { HttpError } from "../http.ts";

/** Один апостроф для всіх варіантів (' ’ ‘ ` ʼ) — інакше «Мар'яна» можна було б набрати трьома способами. */
export const APOSTROPHE = "ʼ";
const APOSTROPHES = /['’‘`ʼ]/g;

const UA_LETTER = "А-ЩЬЮЯЄІЇҐа-щьюяєіїґ";
export const HANDLE_RE = new RegExp(`^[${UA_LETTER}][${UA_LETTER}0-9_.${APOSTROPHE}]{2,19}$`);
export const NAME_RE = new RegExp(`^[${UA_LETTER}${APOSTROPHE}]+(?:[ -][${UA_LETTER}${APOSTROPHE}]+)*$`);
export const NAME_MAX = 30;
export const HANDLE_CHANGE_DAYS = 30;

/** Корені нецензурних і образливих слів та зарезервовані ніки (без урахування регістру). */
const BLOCKED_ROOTS = [
  "хуй", "хуя", "хує", "хуї", "хуйн", "пизд", "пізд", "єба", "їба", "ебан", "єбан", "бляд", "блят",
  "муда", "підор", "підар", "педик", "залуп", "шлюх", "курв", "гандон", "сучар", "сучк",
  "дебіл", "дебил", "срак", "гівн", "жоп", "дроч",
];
const RESERVED = [
  "адмін", "адміністратор", "модератор", "підтримка", "служба_підтримки", "грибний_радар",
  "грибнийрадар", "радар", "наглядач", "система", "офіційний",
];

export function normalizeApostrophes(s: string): string {
  return s.replace(APOSTROPHES, APOSTROPHE);
}

/** Ключ унікальності ніка: малі літери, один апостроф. */
export function handleKey(handle: string): string {
  return normalizeApostrophes(handle).toLocaleLowerCase("uk");
}

/** Перевірка й нормалізація ніка; кидає 400 з поясненням українською. */
export function validateHandle(raw: unknown): string {
  if (typeof raw !== "string") throw new HttpError(400, "invalid_handle", "Нік — рядок");
  const h = normalizeApostrophes(raw.trim().replace(/^@/, ""));
  if (h.length < 3 || h.length > 20) {
    throw new HttpError(400, "invalid_handle", "Нік — від 3 до 20 символів");
  }
  if (/[A-Za-z]/.test(h)) {
    throw new HttpError(400, "invalid_handle", "Нік — лише українськими літерами, без латиниці");
  }
  if (/[ЁёЪъЫыЭэ]/.test(h)) {
    throw new HttpError(400, "invalid_handle", "Нік — українськими літерами (без ы, э, ъ, ё)");
  }
  if (!HANDLE_RE.test(h)) {
    throw new HttpError(
      400,
      "invalid_handle",
      "Нік починається з літери; можна українські літери, цифри, «_», «.» і апостроф",
    );
  }
  const key = handleKey(h);
  if (BLOCKED_ROOTS.some((r) => key.includes(r))) {
    throw new HttpError(400, "handle_not_allowed", "Такий нік не можна — оберіть інший");
  }
  if (RESERVED.includes(key)) {
    throw new HttpError(400, "handle_not_allowed", "Цей нік зарезервовано — оберіть інший");
  }
  return h;
}

/** Ім'я: українські літери, пробіл, дефіс, апостроф; зайві пробіли прибираються. */
export function validateName(raw: unknown): string {
  if (typeof raw !== "string") throw new HttpError(400, "invalid_name", "Ім'я — рядок");
  const n = normalizeApostrophes(raw.trim().replace(/\s+/g, " "));
  if (n.length < 2 || n.length > NAME_MAX) {
    throw new HttpError(400, "invalid_name", `Ім'я — від 2 до ${NAME_MAX} символів`);
  }
  if (!NAME_RE.test(n)) {
    throw new HttpError(400, "invalid_name", "Ім'я — українськими літерами (можна пробіл, дефіс і апостроф)");
  }
  if (BLOCKED_ROOTS.some((r) => n.toLocaleLowerCase("uk").includes(r))) {
    throw new HttpError(400, "name_not_allowed", "Таке ім'я не можна — напишіть інше");
  }
  return n;
}

/** Чи відповідає збережене ім'я правилам (старі імена з Google — латиницею чи email). */
export function isValidName(name: string | null | undefined): boolean {
  if (!name) return false;
  try {
    return validateName(name) === name;
  } catch {
    return false;
  }
}

// ─── Аватар ────────────────────────────────────────────────────────────────

/** Стандартні гриби-персонажі (ADR-021 §21.7) — номери 1…20. */
export const STANDARD_AVATARS = 20;

export type Avatar = { kind: "standard"; id: number };

/** Аватар із запиту. Конструктор (`kind: "custom"`) — окремим кроком, з каталогом деталей. */
export function validateAvatar(raw: unknown): Avatar {
  const a = raw as Record<string, unknown> | null;
  if (a && typeof a === "object" && a.kind === "standard" && Number.isInteger(a.id) &&
    (a.id as number) >= 1 && (a.id as number) <= STANDARD_AVATARS) {
    return { kind: "standard", id: a.id as number };
  }
  throw new HttpError(400, "invalid_avatar", `Аватар — один із ${STANDARD_AVATARS} стандартних грибів`);
}

/** Поки аватар не вибрано — стандартний гриб, стабільний для користувача. */
export function defaultAvatar(userId: string): Avatar {
  let h = 0;
  for (const c of userId) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return { kind: "standard", id: (h % STANDARD_AVATARS) + 1 };
}

// ─── Рівень (ADR-013 §13.1) ────────────────────────────────────────────────

export interface Level {
  id: "traveler" | "tracker" | "expert" | "forester" | "keeper" | "master";
  label: string;
  /** Межі балів рівня і наступний рівень — для смужки прогресу. */
  from: number;
  to: number | null;
  next_label: string | null;
  progress_label: string;
}

const LEVELS: Array<{ id: Level["id"]; label: string; from: number; to: number | null }> = [
  { id: "traveler", label: "Мандрівник", from: 0, to: 50 },
  { id: "tracker", label: "Слідопит", from: 51, to: 200 },
  { id: "forester", label: "Лісовик", from: 201, to: 500 },
  { id: "keeper", label: "Хранитель лісу", from: 501, to: 1000 },
];

/** «1 бал», «3 бали», «12 балів». */
export function points(n: number): string {
  const d = n % 10, dd = n % 100;
  const w = d === 1 && dd !== 11 ? "бал" : d >= 2 && d <= 4 && (dd < 12 || dd > 14) ? "бали" : "балів";
  return `${n} ${w}`;
}

/**
 * Рівень за балами. Сертифікат знань (Грибознавець, «Досвідчений…», Грибний Майстер) — коли
 * з'являться тести (ADR-012); до того Грибний Майстер недосяжний, 1001+ — Хранитель лісу.
 */
export function levelOf(rating: number, certified = false): Level {
  const r = Math.max(0, Math.floor(rating));
  if (certified && r >= 1001) {
    return { id: "master", label: "Грибний Майстер", from: 1001, to: null, next_label: null, progress_label: points(r) };
  }
  if (certified && r >= 51 && r <= 200) {
    return {
      id: "expert", label: "Грибознавець", from: 51, to: 200, next_label: "Лісовик",
      progress_label: `${points(r)} · ще ${points(201 - r)} до рівня «Лісовик»`,
    };
  }
  const i = r > 1000 ? 3 : Math.max(0, LEVELS.findIndex((l) => r >= l.from && (l.to === null || r <= l.to)));
  const lvl = LEVELS[i];
  const next = r > 1000 ? null : LEVELS[i + 1] ?? null;
  const nextLabel = next?.label ?? "Грибний Майстер";
  const target = next ? next.from : 1001;
  return {
    id: lvl.id,
    label: lvl.label,
    from: lvl.from,
    to: lvl.to,
    next_label: nextLabel,
    progress_label: r >= 1001
      ? `${points(r)} · для «Грибного Майстра» — пройти тести знань`
      : `${points(r)} · ще ${points(target - r)} до рівня «${nextLabel}»`,
  };
}
