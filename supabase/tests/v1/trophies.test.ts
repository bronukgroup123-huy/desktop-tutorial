import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import { handleMe } from "../../functions/_shared/v1/me.ts";
import { newlyEarned, TROPHIES, trophyViews } from "../../functions/_shared/v1/trophy-catalog.ts";
import { mockDb, req, RL_OK, verifyAs } from "./mock-db.ts";

const NOW = new Date("2026-11-21T12:00:00Z");

Deno.test("Каталог: 24 трофеї, унікальні id як у файлах картинок, у кожного — за що й скільки", () => {
  assertEquals(TROPHIES.length, 24);
  assertEquals(new Set(TROPHIES.map((t) => t.id)).size, 24);
  for (const t of TROPHIES) {
    assert(/^[a-z0-9_]{2,40}$/.test(t.id), t.id);
    assert(t.how.length > 10, t.id);
    assert(t.target >= 1, t.id);
  }
  // Лише 3 «скоро»: запрошення й тести знань.
  assertEquals(TROPHIES.filter((t) => t.metric === null).map((t) => t.id).sort(), ["invited_friend", "mycologist", "twin_expert"]);
  // Метали й картинки 01–24 — у тому самому порядку, що й scripts/trophies/build.py.
  const ids = Deno.readTextFileSync(new URL("../../../scripts/trophies/build.py", import.meta.url));
  const order = [...ids.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1]).filter((x) => TROPHIES.some((t) => t.id === x));
  assertEquals(order, TROPHIES.map((t) => t.id));
});

Deno.test("newlyEarned: поріг досягнуто — новий трофей; уже отриманий і «скоро» — ні", () => {
  const fresh = newlyEarned({ finds: 10, friends: 4, hikes_safe: 1 }, new Set(["first_find"]));
  assertEquals(fresh.sort(), ["basket", "first_hike"]);
});

Deno.test("trophyViews: отримані згори, прогрес «3 з 10», ціль 1 — без лічильника, «скоро» — наприкінці", () => {
  const v = trophyViews({ finds: 3, species_season: 4 }, new Map([["first_find", "2026-09-10T08:00:00Z"]]));
  assertEquals(v[0].id, "first_find");
  assertEquals(v[0].earned, true);
  const basket = v.find((x) => x.id === "basket")!;
  assertEquals(basket.progress_label, "3 з 10");
  assertEquals(basket.tier_label, "Срібло");
  assertEquals(v.find((x) => x.id === "under_watch")!.progress_label, null);
  assertEquals(v.slice(-3).every((x) => x.soon), true);
  // найближчі до отримання — одразу після отриманих: «Колекція: 5 видів» (4 з 5)
  assertEquals(v[1].id, "collection_5");
});

Deno.test("v1-me ?trophies=1: гість → 403; акаунт → нові трофеї записуються й показуються з підписом", async () => {
  const run = (db: ReturnType<typeof mockDb>, anon = false) =>
    handle((x) => handleMe(x, { db, verify: verifyAs("u1", anon), now: () => NOW }))(req("GET", "http://localhost/v1-me?trophies=1"));
  const guest = await run(mockDb({ ...RL_OK }), true);
  assertEquals(guest.status, 403);

  const db = mockDb({
    ...RL_OK,
    "rpc.trophy_stats": { data: { finds: 1, friends: 5 }, error: null },
    "user_trophies.select": { data: [], error: null },
  });
  const res = await run(db);
  assertEquals(res.status, 200);
  const { data } = await res.json();
  assertEquals(data.total, 24);
  assertEquals(data.earned_count, 2);
  assertEquals(data.new_labels.sort(), ["Новий трофей: «Грибна компанія»", "Новий трофей: «Перша знахідка»"]);
  const up = db.calls.find((c) => c.key === "user_trophies.upsert")!;
  assertEquals((up.args[0] as Array<{ trophy_id: string }>).map((r) => r.trophy_id).sort(), ["first_find", "mushroom_company"]);
});
