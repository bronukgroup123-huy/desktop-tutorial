import { assertEquals } from "jsr:@std/assert";
import {
  charLength,
  cleanDescription,
  DESCRIPTION_MAX_LENGTH,
  normalizeDescription,
  redactContacts,
} from "../../functions/_shared/picks/text.ts";

const clean = (raw: unknown) => {
  const r = cleanDescription(raw);
  if (!r.ok) throw new Error(`unexpected failure: ${r.reason}`);
  return r.text;
};

Deno.test("text: звичайний опис лишається без змін", () => {
  const text = "Під старими соснами, після дощу. Мох, +12°, знайшов 3 білих за 20 хвилин.";
  assertEquals(cleanDescription(text), { ok: true, text, redacted: false });
});

Deno.test("text: пробіли обрізаються, порожній опис → null", () => {
  assertEquals(clean("  під дубом \n"), "під дубом");
  assertEquals(clean("під   дубом\t біля   струмка"), "під дубом біля струмка");
  assertEquals(clean("рядок 1\r\n\r\n\r\n\r\nрядок 2"), "рядок 1\n\nрядок 2");
  assertEquals(clean(""), null);
  assertEquals(clean("   \n\t "), null);
  assertEquals(clean(undefined), null);
  assertEquals(clean(null), null);
});

Deno.test("text: не рядок → not_a_string", () => {
  assertEquals(cleanDescription(42), { ok: false, reason: "not_a_string" });
  assertEquals(cleanDescription({ text: "x" }), { ok: false, reason: "not_a_string" });
});

Deno.test("text: довжина — 500 символів Unicode, 501 → too_long", () => {
  assertEquals(DESCRIPTION_MAX_LENGTH, 500);
  assertEquals(clean("я".repeat(500))?.length, 500);
  assertEquals(cleanDescription("я".repeat(501)), { ok: false, reason: "too_long" });
  // пробіли по краях не рахуються
  assertEquals(clean(`  ${"я".repeat(500)}  `)?.length, 500);
  // емодзі — один символ (як char_length у Postgres), хоча в UTF-16 їх два
  assertEquals(charLength("🍄".repeat(500)), 500);
  assertEquals(cleanDescription("🍄".repeat(500)).ok, true);
  assertEquals(cleanDescription("🍄".repeat(501)), { ok: false, reason: "too_long" });
});

Deno.test("text: телефони замінюються на «…»", () => {
  for (
    const phone of [
      "+380671234567",
      "+38 (067) 123-45-67",
      "+380 67 123 45 67",
      "0671234567",
      "067 123 45 67",
      "(067) 123-45-67",
      "067-123-45-67",
      "380671234567",
      "80671234567",
      "+48 601 234 567",
    ]
  ) {
    const r = cleanDescription(`Дзвоніть ${phone} ввечері`);
    assertEquals(r, { ok: true, text: "Дзвоніть … ввечері", redacted: true }, phone);
  }
});

Deno.test("text: звичайні числа, дати і координати погоди — не телефони", () => {
  for (
    const text of [
      "Знайшов 12 білих і 30 лисичок за 2 години",
      "Був тут 10.11.2026 о 09:30, температура +12",
      "2026-11-10 12:30 — перша хвиля",
      "Висота 350 м, 5 км від села, 1500 кроків",
      "Квартал 45, виділ 12, площа 2.5 га",
    ]
  ) {
    assertEquals(cleanDescription(text), { ok: true, text, redacted: false }, text);
  }
});

Deno.test("text: e-mail замінюється на «…»", () => {
  assertEquals(clean("Пишіть на grybnyk.ua+lis@example.com будь ласка"), "Пишіть на … будь ласка");
  assertEquals(clean("пошта: іван@пошта.укр"), "пошта: …");
});

Deno.test("text: посилання і домени замінюються на «…»", () => {
  assertEquals(clean("Фото тут: https://example.com/album?id=1 дивіться"), "Фото тут: … дивіться");
  assertEquals(clean("http://bit.ly/abc"), "…");
  assertEquals(clean("сайт www.example.org/page"), "сайт …");
  assertEquals(clean("канал t.me/grybnyky_ua"), "канал …");
  assertEquals(clean("шукайте на olx.ua"), "шукайте на …");
  assertEquals(clean("інста instagram.com/lisovyk"), "інста …");
  assertEquals(clean("viber://chat?number=123"), "…");
});

Deno.test("text: @нікнейми замінюються на «…»", () => {
  assertEquals(clean("телеграм @grybnyk_ua"), "телеграм …");
  assertEquals(clean("@lisovyk пишіть"), "… пишіть");
});

Deno.test("text: звичайні скорочення й десяткові числа — не посилання", () => {
  for (const text of ["Гриби т.д. і т.п.", "Сосна, береза та ін. дерева", "Вага 1.5 кг", "с. Іванків, 3.2 км"]) {
    assertEquals(cleanDescription(text), { ok: true, text, redacted: false }, text);
  }
});

Deno.test("text: кілька контактів поспіль → одна «…»", () => {
  assertEquals(clean("Контакти: +380671234567, test@example.com, t.me/abc"), "Контакти: …");
});

Deno.test("text: невидимі символи не допомагають обійти фільтр", () => {
  assertEquals(clean("067​123​45​67"), "…");
  assertEquals(clean("t​.me/abc"), "…");
  assertEquals(normalizeDescription("a\u0000b\u0007c"), "a b c");
});

Deno.test("text: опис лише з контакту → «…», redacted", () => {
  assertEquals(cleanDescription("+380671234567"), { ok: true, text: "…", redacted: true });
});

Deno.test("text: redactContacts не змінює текст без контактів", () => {
  const text = "Дуб, граб, волога низина. Гриби молоді, без червивих.";
  assertEquals(redactContacts(text), text);
});
