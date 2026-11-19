import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { assertAvatarAllowed, AVATAR_CATALOG, catalogFor, parseCustomAvatar, type Viewer } from "../../functions/_shared/v1/avatar-catalog.ts";
import { HttpError } from "../../functions/_shared/http.ts";

const viewer = (rating: number, now = "2026-08-10T12:00:00Z"): Viewer => ({ rating, pro: false, owned: new Set(), now: new Date(now) });
const part = (cat: string, id: string, v: Viewer) =>
  catalogFor(v).categories.find((c) => c.id === cat)!.parts.find((p) => p.id === id)!;

Deno.test("Каталог: кожна деталь — рівно один спосіб відкриття; є безкоштовні в кожній категорії", () => {
  for (const c of AVATAR_CATALOG) {
    assertEquals(c.parts.some((p) => p.unlock.type === "free" && !p.season), true, c.id);
    assertEquals(new Set(c.parts.map((p) => p.id)).size, c.parts.length, `${c.id}: дублікати id`);
  }
});

Deno.test("Замки: за рівень — відкривається рівнем; за спори й Pro — поки закрито; сезонне — лише в сезон", () => {
  assertEquals(part("shape", "bolete", viewer(0)), { id: "bolete", label: "Боровик", open: true, badge: null, lock_label: null });
  assertEquals(part("hat", "ranger", viewer(100)).lock_label, "З рівня «Лісовик»");
  assertEquals(part("hat", "ranger", viewer(300)), { id: "ranger", label: "Лісника", open: true, badge: "За рівень «Лісовик»", lock_label: null });
  assertEquals(part("hat", "crown", viewer(5000)).open, false); // Майстер — лише з тестами знань
  assertEquals(part("hat", "wizard", viewer(5000)).lock_label, "80 спор — скоро");
  assertEquals(part("item", "lantern", viewer(0)).lock_label, "У Pro");
  assertEquals(part("hat", "santa", viewer(0)).lock_label, "Лише 1 грудня — 15 січня");
  assertEquals(part("hat", "santa", viewer(0, "2026-12-20T12:00:00Z")).open, true);
  assertEquals(part("hat", "santa", viewer(0, "2027-01-10T12:00:00Z")).open, true); // через Новий рік
});

Deno.test("Збереження: невідома деталь — 400; закрита — 403 з причиною; уже вибрана раніше — лишається", () => {
  const ok = parseCustomAvatar({ kind: "custom", shape: "amanita", color: "red", face: "sly", arms: "wave", hat: "none", item: "basket" });
  assertEquals([ok.hat, ok.item], [null, "basket"]);
  assertThrows(() => parseCustomAvatar({ kind: "custom", shape: "unicorn", color: "red", face: "sly", arms: "wave" }), HttpError, "Невідома деталь");
  assertThrows(() => parseCustomAvatar({ kind: "custom", shape: "bolete", color: "red", face: "sly" }), HttpError);
  const ranger = parseCustomAvatar({ kind: "custom", shape: "bolete", color: "brown", face: "kind", arms: "down", hat: "ranger" });
  assertThrows(() => assertAvatarAllowed(ranger, viewer(10), null), HttpError, "«Лісника» — з рівня «Лісовик»");
  assertAvatarAllowed(ranger, viewer(300), null);
  // Новорічна шапка після сезону — лишається на аватарі, якщо вже була.
  const santa = parseCustomAvatar({ kind: "custom", shape: "bolete", color: "brown", face: "kind", arms: "down", hat: "santa" });
  assertThrows(() => assertAvatarAllowed(santa, viewer(0), null), HttpError);
  assertAvatarAllowed(santa, viewer(0), { kind: "custom", hat: "santa" });
});
