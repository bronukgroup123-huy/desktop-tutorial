// ============================================================================
// Тук-тук: опис точки (ADR-018 §18.3.4, BACKEND_PLAN B3.1)
//
// Опис — необов'язковий вільний текст («під якими деревами, погода»).
// Сервер обрізає пробіли, обмежує довжину і прибирає контакти:
// телефони, e-mail, посилання та @нікнейми замінюються на «…».
//
// Чисті функції без залежностей — тестуються без мережі.
// ============================================================================

export const DESCRIPTION_MAX_LENGTH = 500;
export const REDACTED = "…";

/** Невидимі символи, якими «розривають» номер чи посилання, щоб обійти фільтр. */
const INVISIBLE_RE = /[​-‍⁠﻿­]/g;
/** Керівні символи, крім переносу рядка і табуляції. */
// deno-lint-ignore no-control-regex
const CONTROL_RE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g;

/** scheme://… та www.… */
const URL_RE = /(?:\b[a-z][a-z0-9+.-]{1,15}:\/\/|\bwww\.)[^\s<>"']+/giu;

const EMAIL_RE = /[\p{L}\p{N}._%+-]+@[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+/gu;

/** Домени без схеми: t.me/abc, olx.ua, instagram.com/nick. */
const BARE_DOMAIN_RE = new RegExp(
  "(?<![\\p{L}\\p{N}@._-])(?:[\\p{L}\\p{N}-]+\\.)+" +
    "(?:com|net|org|info|biz|ua|укр|me|io|app|ly|gg|xyz|site|online|shop|store|club|top|pro|link|page|dev|eu|pl|ru|by|kz|de|uk|us|cc|tv)" +
    "(?![\\p{L}\\p{N}-])(?:\\/[^\\s<>\"']*)?",
  "giu",
);

/** @нікнейми месенджерів і соцмереж. */
const HANDLE_RE = /(?<![\p{L}\p{N}_.@])@[A-Za-z0-9_][A-Za-z0-9_.]{2,}/gu;

/** Телефони: +380 67 123 45 67 · (067) 123-45-67 · 380671234567 · будь-які 10+ цифр поспіль. */
const PHONE_RES: RegExp[] = [
  /\+\d(?:[\s().-]*\d){8,14}/g,
  /(?<![\d.,])(?:3?8[\s-]?)?\(?0\d{2}\)?(?:[\s.-]*\d){7}(?!\d)/g,
  /(?<!\d)\d{10,15}(?!\d)/g,
];

/** Довжина в символах Unicode (як `char_length` у Postgres), а не в UTF-16. */
export function charLength(text: string): number {
  let n = 0;
  for (const _ of text) n++;
  return n;
}

/** Обрізає пробіли й прибирає невидимі та керівні символи. Порожній рядок → null. */
export function normalizeDescription(raw: string): string | null {
  const text = raw
    .replace(/\r\n?/g, "\n")
    .replace(INVISIBLE_RE, "")
    .replace(CONTROL_RE, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/ ?\n ?/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return text.length > 0 ? text : null;
}

/** Замінює телефони, e-mail, посилання і @нікнейми на «…». */
export function redactContacts(text: string): string {
  let out = text
    .replace(URL_RE, REDACTED)
    .replace(EMAIL_RE, REDACTED)
    .replace(BARE_DOMAIN_RE, REDACTED)
    .replace(HANDLE_RE, REDACTED);
  for (const re of PHONE_RES) out = out.replace(re, REDACTED);
  // «… …» після кількох замін поспіль → одна «…»
  return out.replace(/…(?:[ ,;]*…)+/g, REDACTED);
}

export type DescriptionResult =
  | { ok: true; text: string | null; redacted: boolean }
  | { ok: false; reason: "not_a_string" | "too_long" };

/**
 * Готує опис до збереження.
 *  - `undefined` / `null` / порожній рядок → `text: null`;
 *  - довший за 500 символів (після обрізання пробілів) → `too_long`;
 *  - контакти замінюються на «…» (`redacted: true`).
 */
export function cleanDescription(raw: unknown): DescriptionResult {
  if (raw === undefined || raw === null) return { ok: true, text: null, redacted: false };
  if (typeof raw !== "string") return { ok: false, reason: "not_a_string" };

  const normalized = normalizeDescription(raw);
  if (normalized === null) return { ok: true, text: null, redacted: false };
  if (charLength(normalized) > DESCRIPTION_MAX_LENGTH) return { ok: false, reason: "too_long" };

  const text = redactContacts(normalized).trim();
  return { ok: true, text: text.length > 0 ? text : null, redacted: text !== normalized };
}
