import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { normalizePhone, buildSmsText } from "./sms.ts";

Deno.test("normalizePhone — +380XXXXXXXXX", () => {
  assertEquals(normalizePhone("+380501234567"), "+380501234567");
});

Deno.test("normalizePhone — 380XXXXXXXXX", () => {
  assertEquals(normalizePhone("380501234567"), "+380501234567");
});

Deno.test("normalizePhone — 0XXXXXXXXX", () => {
  assertEquals(normalizePhone("0501234567"), "+380501234567");
});

Deno.test("normalizePhone — з пробілами та дужками", () => {
  assertEquals(normalizePhone("+38 (050) 123-45-67"), "+380501234567");
});

Deno.test("normalizePhone — невалідний", () => {
  assertEquals(normalizePhone("123"), null);
  assertEquals(normalizePhone("+1234567890"), null);
});

Deno.test("buildSmsText — обрізає до 480 символів", () => {
  const text = buildSmsText(
    { title: "A".repeat(300), body: "B".repeat(300), url: "https://x" },
    "Олег"
  );
  assertEquals(text.length, 480);
});
