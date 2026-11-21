import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import { handleMe } from "../../functions/_shared/v1/me.ts";
import { countPlaces, type FindRow, findMetrics, newlyEarned, speciesConfirmed, TROPHIES, trophyViews } from "../../functions/_shared/v1/trophy-catalog.ts";
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
    "rpc.trophy_stats": { data: { friends: 5 }, error: null },
    "rpc.trophy_finds": { data: [find({})], error: null },
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

/** Знахідка: за замовчуванням — білий гриб, ШІ погодився («найімовірніше»), приватна. */
function find(o: Partial<FindRow>): FindRow {
  return {
    species_id: "boletus_edulis", pick_type: "private", lat: 50.4, lng: 28.6, local_at: "2026-09-10T10:00:00",
    ai_species: "boletus_edulis", ai_level: "high", moderated: false, red_listed: false, ...o,
  };
}
const NORTH_100M = 0.0009;

Deno.test("Одне місце за день — одна знахідка: 10 фото одного гриба й сімейка білих поруч — 1", () => {
  const same = Array.from({ length: 10 }, (_, i) => find({ lat: 50.4 + i * 0.00002, local_at: `2026-09-10T10:${String(i).padStart(2, "0")}:00` }));
  assertEquals(countPlaces(same), 1);
  // інший день, те саме місце — нова знахідка (гриби виросли знову)
  assertEquals(countPlaces([...same, find({ local_at: "2026-09-11T10:00:00" })]), 2);
  // 100 м далі — інше місце
  assertEquals(countPlaces([find({}), find({ lat: 50.4 + NORTH_100M, local_at: "2026-09-10T11:00:00" })]), 2);
});

Deno.test("У залік — не більше 5 знахідок на день", () => {
  const day = Array.from({ length: 9 }, (_, i) => find({ lat: 50.4 + i * NORTH_100M, local_at: `2026-09-10T1${i}:00:00` }));
  assertEquals(countPlaces(day), 5);
});

Deno.test("Вид підтверджено — лише розпізнавання (перша підказка, найімовірніше / можливо) або модератор", () => {
  assertEquals(speciesConfirmed(find({})), true);
  assertEquals(speciesConfirmed(find({ ai_level: "medium" })), true);
  assertEquals(speciesConfirmed(find({ ai_level: "low" })), false); // «менш імовірно» — ні
  assertEquals(speciesConfirmed(find({ ai_species: "cantharellus_cibarius" })), false); // ШІ назвав інший вид
  assertEquals(speciesConfirmed(find({ ai_species: null, ai_level: null })), false); // просто вибрали зі списку
  assertEquals(speciesConfirmed(find({ ai_species: null, ai_level: null, moderated: true })), true);
  assertEquals(speciesConfirmed(find({ species_id: null })), false); // «Не знаю, що це»
});

Deno.test("Король лісу: білі гриби з підтвердженим видом у різних місцях; вибрані зі списку не рахуються", () => {
  const rows = [
    ...Array.from({ length: 7 }, (_, i) => find({ lat: 50.4 + i * NORTH_100M, local_at: `2026-09-1${i}T10:00:00` })),
    ...Array.from({ length: 5 }, (_, i) => find({ lat: 51 + i * NORTH_100M, ai_species: null, ai_level: null, local_at: `2026-08-0${i + 1}T10:00:00` })),
  ];
  const m = findMetrics(rows, new Date("2026-11-21T12:00:00Z"));
  assertEquals(m.porcini, 7);
  assertEquals(m.finds, 12); // знахідки загалом — рахуються всі фото на місці
  assertEquals(m.species_season, 1);
});

Deno.test("Червона книга — лише після модератора й лише приватна точка; сезонні — за місяцем", () => {
  const now = new Date("2026-11-21T12:00:00Z");
  const red = find({ species_id: "zz_red", ai_species: null, ai_level: null, red_listed: true });
  assertEquals(findMetrics([red], now).red_book_private, 0);
  assertEquals(findMetrics([{ ...red, moderated: true }], now).red_book_private, 1);
  assertEquals(findMetrics([{ ...red, moderated: true, pick_type: "public" }], now).red_book_private, 0);
  const morel = find({ species_id: "morchella_esculenta", ai_species: "morchella_esculenta", local_at: "2026-04-20T10:00:00" });
  assertEquals(findMetrics([morel], now).morels_spring, 1);
  assertEquals(findMetrics([{ ...morel, local_at: "2026-06-20T10:00:00" }], now).morels_spring, 0);
  const honey = find({ species_id: "flammulina_velutipes", ai_species: "flammulina_velutipes", local_at: "2026-01-15T10:00:00" });
  assertEquals(findMetrics([honey], now).winter_honey, 1);
});

Deno.test("Колекція — лише поточний рік і лише підтверджені види; Розпізнавач — збіг ШІ", () => {
  const now = new Date("2026-11-21T12:00:00Z");
  const rows = [
    find({}),
    find({ species_id: "cantharellus_cibarius", ai_species: "cantharellus_cibarius", local_at: "2026-07-01T10:00:00" }),
    find({ species_id: "lactarius_resimus", ai_species: null, ai_level: null, local_at: "2026-08-01T10:00:00" }),
    find({ species_id: "suillus_luteus", ai_species: "suillus_luteus", local_at: "2025-09-01T10:00:00" }),
  ];
  const m = findMetrics(rows, now);
  assertEquals(m.species_season, 2);
  assertEquals(m.ai_match, 3);
  assertEquals(m.chanterelle, 1);
});
