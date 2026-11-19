import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  assertAvatarAllowed,
  AVATAR_CATALOG,
  catalogFor,
  FREE_STICKERS,
  parseCustomAvatar,
  publicAvatar,
  type Viewer,
} from "../../functions/_shared/v1/avatar-catalog.ts";
import { HttpError } from "../../functions/_shared/http.ts";

const viewer = (rating: number, now = "2026-08-10T12:00:00Z", pro = false): Viewer => ({ rating, pro, owned: new Set(), now: new Date(now) });
const part = (cat: string, id: string, v: Viewer) =>
  catalogFor(v).categories.find((c) => c.id === cat)!.parts.find((p) => p.id === id)!;

Deno.test("Каталог: 25–30 наліпок — безкоштовні, за рівень і в Pro; у кожній категорії є безкоштовні; id унікальні", () => {
  const stickers = AVATAR_CATALOG.find((c) => c.id === "sticker")!.parts;
  assertEquals(stickers.length >= 25 && stickers.length <= 30, true);
  for (const t of ["free", "level", "pro"]) assertEquals(stickers.some((p) => p.unlock.type === t), true, t);
  assertEquals(FREE_STICKERS.length >= 12, true);
  for (const c of AVATAR_CATALOG) {
    assertEquals(c.parts.some((p) => p.unlock.type === "free" && !p.season), true, c.id);
    assertEquals(new Set(c.parts.map((p) => p.id)).size, c.parts.length, `${c.id}: дублікати id`);
  }
});

Deno.test("Замки: за рівень — відкривається рівнем; за спори — поки закрито; Pro — з Pro; сезонне — лише в сезон", () => {
  assertEquals(part("sticker", "kind", viewer(0)), { id: "kind", label: "Добряк", open: true, badge: null, lock_label: null });
  assertEquals(part("sticker", "excited", viewer(0)).lock_label, "З рівня «Слідопит»");
  assertEquals(part("sticker", "cosmic", viewer(0)).lock_label, "У Pro");
  assertEquals(part("sticker", "cosmic", viewer(0, undefined, true)).badge, "Pro");
  assertEquals(part("hat", "ranger", viewer(100)).lock_label, "З рівня «Лісовик»");
  assertEquals(part("hat", "ranger", viewer(300)), { id: "ranger", label: "Лісника", open: true, badge: "За рівень «Лісовик»", lock_label: null });
  assertEquals(part("hat", "crown", viewer(5000)).open, false); // Майстер — лише з тестами знань
  assertEquals(part("hat", "wizard", viewer(5000)).lock_label, "80 спор — скоро");
  assertEquals(part("item", "lantern", viewer(0)).lock_label, "У Pro");
  assertEquals(part("hat", "santa", viewer(0)).lock_label, "Лише 1 грудня — 15 січня");
  assertEquals(part("hat", "santa", viewer(0, "2026-12-20T12:00:00Z")).open, true);
  assertEquals(part("hat", "santa", viewer(0, "2027-01-10T12:00:00Z")).open, true); // через Новий рік
  assertEquals(part("fx", "snow", viewer(0, "2027-02-10T12:00:00Z")).open, true);
});

Deno.test("Збереження: невідома деталь — 400; закрита — 403 з причиною; уже вибрана раніше — лишається", () => {
  const ok = parseCustomAvatar({ kind: "custom", sticker: "dizzy", hat: "none", item: "basket" });
  assertEquals(ok, { kind: "custom", sticker: "dizzy", hat: null, item: "basket", fx: null });
  assertThrows(() => parseCustomAvatar({ kind: "custom", sticker: "unicorn" }), HttpError, "Невідома деталь");
  assertThrows(() => parseCustomAvatar({ kind: "custom", hat: "cap" }), HttpError);
  assertThrows(() => parseCustomAvatar({ kind: "custom", sticker: "kind", fx: "fireworks" }), HttpError);
  const ranger = parseCustomAvatar({ kind: "custom", sticker: "kind", hat: "ranger" });
  assertThrows(() => assertAvatarAllowed(ranger, viewer(10), null), HttpError, "«Лісника» — з рівня «Лісовик»");
  assertAvatarAllowed(ranger, viewer(300), null);
  // Новорічна шапка після сезону й Pro-наліпка після підписки — лишаються, якщо вже були.
  const santa = parseCustomAvatar({ kind: "custom", sticker: "cosmic", hat: "santa" });
  assertThrows(() => assertAvatarAllowed(santa, viewer(0), null), HttpError);
  assertAvatarAllowed(santa, viewer(0), { kind: "custom", sticker: "cosmic", hat: "santa" });
});

Deno.test("Аватар у відповіді: завжди наліпка; старий стандартний — безкоштовний персонаж; невідоме — прибрано", () => {
  assertEquals(publicAvatar({ kind: "standard", id: 1 }).sticker, FREE_STICKERS[0]);
  assertEquals(publicAvatar({ kind: "standard", id: FREE_STICKERS.length + 2 }).sticker, FREE_STICKERS[1]);
  assertEquals(publicAvatar(null).sticker, FREE_STICKERS[0]);
  assertEquals(publicAvatar({ kind: "custom", sticker: "gone", hat: "cap", item: "old", fx: "notes" }), {
    kind: "custom", sticker: FREE_STICKERS[0], hat: "cap", item: null, fx: "notes",
  });
});
