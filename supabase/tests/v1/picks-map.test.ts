import { assert, assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { handlePicks, type PicksStorage } from "../../functions/_shared/v1/picks.ts";
import { dateLabel, MAP_LIMIT, parsePicksMapQuery } from "../../functions/_shared/v1/picks-map.ts";
import { type Call, mockDb, req, type Results, RL_BLOCKED, RL_OK, verifyAs } from "./mock-db.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const PICK = "99999999-9999-4999-8999-999999999999";
const MAP = "http://localhost/v1-picks/map";
const CARD = `http://localhost/v1-picks/${PICK}`;
// Справжнє місце чужої точки — його не має бути в жодній відповіді.
const EXACT = { lat: 50.4501, lng: 30.5234 };
const SHOWN = { lat: 50.4537, lng: 30.5234 };

const foreign = (o: Record<string, unknown> = {}) => ({
  id: PICK,
  lat: SHOWN.lat,
  lng: SHOWN.lng,
  is_exact: false,
  is_mine: false,
  pick_type: "public",
  verification_status: "pending",
  species_id: "boletus_edulis",
  name_ua: "Білий гриб",
  ...o,
});
const own = (o: Record<string, unknown> = {}) =>
  foreign({ lat: EXACT.lat, lng: EXACT.lng, is_exact: true, is_mine: true, ...o });

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": { data: { home_region_id: 10 }, error: null },
    "rpc.get_picks_map": { data: [], error: null },
    "rpc.get_pick_card": { data: null, error: null },
    ...extra,
  });
}

function storage(fail = false) {
  const signed: Array<[string, number]> = [];
  const never = () => Promise.reject(new Error("not used by map endpoints"));
  const s: PicksStorage = {
    createSignedUploadUrl: never,
    download: never,
    upload: never,
    remove: never,
    createSignedUrl(path, expiresIn) {
      signed.push([path, expiresIn]);
      return Promise.resolve(
        fail
          ? { data: null, error: { message: "boom" } }
          : { data: { signedUrl: `https://proj.supabase.co/signed/${path}?token=t` }, error: null },
      );
    },
  };
  return { s, signed };
}

async function run(d: ReturnType<typeof mockDb>, r: Request, st = storage(), isAnonymous = false) {
  const res = await handle((x) =>
    handlePicks(x, { db: d, storage: st.s, verify: verifyAs(USER, isAnonymous), fuzzSecret: "s" })
  )(r);
  return { res, json: await res.json(), signed: st.signed };
}

const find = (d: ReturnType<typeof mockDb>, key: string): Call | undefined => d.calls.find((c) => c.key === key);

// ─── Карта ──────────────────────────────────────────────────────────────────

Deno.test("map: 200 — точки з готовими підписами й кольорами; уся область, без приватних", async () => {
  const d = db({
    "rpc.get_picks_map": {
      data: [
        foreign(),
        foreign({ id: "22222222-2222-4222-8222-222222222222", verification_status: "verified" }),
        own({ id: "33333333-3333-4333-8333-333333333333" }),
      ],
      error: null,
    },
  });
  const { res, json } = await run(d, req("GET", MAP));
  assertEquals(res.status, 200);
  assertEquals(json.data.truncated, false);
  assertEquals(json.data.points, [
    {
      id: PICK, lat: SHOWN.lat, lng: SHOWN.lng, is_exact: false, is_mine: false, visibility: "public",
      species_id: "boletus_edulis", name_label: "Білий гриб", status_label: "Перевіряється", marker_color: "#9e9e9e",
    },
    {
      id: "22222222-2222-4222-8222-222222222222", lat: SHOWN.lat, lng: SHOWN.lng, is_exact: false, is_mine: false,
      visibility: "public", species_id: "boletus_edulis", name_label: "Білий гриб", status_label: "Підтверджено",
      marker_color: "#43a047",
    },
    {
      id: "33333333-3333-4333-8333-333333333333", lat: EXACT.lat, lng: EXACT.lng, is_exact: true, is_mine: true,
      visibility: "public", species_id: "boletus_edulis", name_label: "Білий гриб", status_label: "Перевіряється",
      marker_color: "#9e9e9e",
    },
  ]);
  assertEquals(find(d, "rpc.get_picks_map")!.args[0], {
    p_user_id: USER, p_region_id: 10,
    p_min_lng: null, p_min_lat: null, p_max_lng: null, p_max_lat: null,
    p_include_private: false, p_limit: MAP_LIMIT,
  });
});

Deno.test("map: для чужих точок у відповіді немає полів, яких не дав сервер БД (жодного geom)", async () => {
  const d = db({ "rpc.get_picks_map": { data: [foreign({ geom: "0101...", user_id: "author", exact_lat: EXACT.lat })], error: null } });
  const { json } = await run(d, req("GET", MAP));
  const text = JSON.stringify(json);
  assertEquals(text.includes(String(EXACT.lat)), false);
  assertEquals(/geom|user_id|author/.test(text), false);
  // чужа точка ніколи не позначається як точна, навіть якщо БД помилково так скаже
  const forged = db({ "rpc.get_picks_map": { data: [foreign({ is_exact: true })], error: null } });
  assertEquals((await run(forged, req("GET", MAP))).json.data.points[0].is_exact, false);
});

Deno.test("map: bbox і mine=true передаються в БД; приватна точка — «Приватна точка»", async () => {
  const d = db({
    "rpc.get_picks_map": {
      data: [own({ pick_type: "private", species_id: null, name_ua: null })],
      error: null,
    },
  });
  const { json } = await run(d, req("GET", `${MAP}?bbox=30.2,50.2,30.9,50.7&mine=true`));
  const p = find(d, "rpc.get_picks_map")!.args[0] as Record<string, unknown>;
  assertEquals([p.p_min_lng, p.p_min_lat, p.p_max_lng, p.p_max_lat], [30.2, 50.2, 30.9, 50.7]);
  assertEquals(p.p_include_private, true);
  assertEquals(json.data.points[0].status_label, "Приватна точка");
  assertEquals(json.data.points[0].name_label, "Не знаю, що це");
  assertEquals(json.data.points[0].species_id, null);
});

Deno.test("map: більше точок, ніж ліміт → truncated", async () => {
  const many = Array.from({ length: MAP_LIMIT + 1 }, (_, i) => foreign({ id: `pick-${i}` }));
  const { json } = await run(db({ "rpc.get_picks_map": { data: many, error: null } }), req("GET", MAP));
  assertEquals(json.data.points.length, MAP_LIMIT);
  assertEquals(json.data.truncated, true);
});

Deno.test("map: некоректний / завеликий bbox і mine → 400", async () => {
  for (
    const [query, code] of [
      ["bbox=1,2,3", "invalid_bbox"],
      ["bbox=a,b,c,d", "invalid_bbox"],
      ["bbox=31,50,30,51", "invalid_bbox"],
      ["bbox=30,50,31,95", "invalid_bbox"],
      ["bbox=20,44,41,53", "bbox_too_large"],
      ["mine=yes", "invalid_mine"],
    ]
  ) {
    const d = db();
    const { res, json } = await run(d, req("GET", `${MAP}?${query}`));
    assertEquals(res.status, 400, query);
    assertEquals(json.error, code);
    assertEquals(find(d, "rpc.get_picks_map"), undefined);
  }
  assertEquals(parsePicksMapQuery(new URL(`${MAP}?mine=0`)), { bbox: null, mine: false });
  assertEquals(parsePicksMapQuery(new URL(`${MAP}?mine=1`)).mine, true);
});

Deno.test("map: 401 без токена, 409 без області, 429, гість — можна", async () => {
  const noToken = await run(db(), new Request(MAP));
  assertEquals(noToken.res.status, 401);

  const noRegion = await run(db({ "users.select": { data: { home_region_id: null }, error: null } }), req("GET", MAP));
  assertEquals(noRegion.res.status, 409);
  assertEquals(noRegion.json.error, "home_region_required");

  assertEquals((await run(db(RL_BLOCKED), req("GET", MAP))).res.status, 429);
  assertEquals((await run(db(), req("GET", MAP), storage(), true)).res.status, 200);
});

Deno.test("map: помилка БД → 500 без деталей", async () => {
  const { res, json } = await run(db({ "rpc.get_picks_map": { data: null, error: { message: "secret sql" } } }), req("GET", MAP));
  assertEquals(res.status, 500);
  assertEquals(json.error, "db_error");
  assertEquals(JSON.stringify(json).includes("secret"), false);
});

// ─── Картка ─────────────────────────────────────────────────────────────────

Deno.test("card: чужа публічна — фото, назва, опис, дата, статус, застереження; без автора і точного часу", async () => {
  const d = db({
    "rpc.get_pick_card": {
      data: { ...foreign(), description: "Під сосною", photo_path: `picks/${PICK}.jpg`, taken_at: "2026-11-10T09:30:00Z" },
      error: null,
    },
  });
  const { res, json, signed } = await run(d, req("GET", CARD));
  assertEquals(res.status, 200);
  assertEquals(json.data, {
    id: PICK, lat: SHOWN.lat, lng: SHOWN.lng, is_exact: false, is_mine: false, visibility: "public",
    species_id: "boletus_edulis", name_label: "Білий гриб", status_label: "Перевіряється", marker_color: "#9e9e9e",
    description: "Під сосною",
    date_label: "10 листопада 2026 р.",
    captured_at: null,
    photo_url: `https://proj.supabase.co/signed/picks/${PICK}.jpg?token=t`,
    disclaimer_label: "Фото користувача — не порада їсти гриб",
    actions: [],
  });
  assertEquals(signed, [[`picks/${PICK}.jpg`, 600]]);
  assertEquals(find(d, "rpc.get_pick_card")!.args[0], { p_user_id: USER, p_region_id: 10, p_pick_id: PICK });
  assertEquals(/photo_path|user_id|09:30/.test(JSON.stringify(json)), false);
});

Deno.test("card: своя приватна — точні координати й час зйомки, без застереження", async () => {
  const d = db({
    "rpc.get_pick_card": {
      data: {
        ...own({ pick_type: "private", species_id: null, name_ua: null }),
        description: null, photo_path: `picks/${PICK}.jpg`, taken_at: "2026-11-10T22:30:00Z",
      },
      error: null,
    },
  });
  const { json } = await run(d, req("GET", CARD));
  assertEquals([json.data.lat, json.data.lng, json.data.is_exact], [EXACT.lat, EXACT.lng, true]);
  assertEquals(json.data.captured_at, "2026-11-10T22:30:00Z");
  assertEquals(json.data.date_label, "11 листопада 2026 р."); // київський час — уже наступна доба
  assertEquals(json.data.status_label, "Приватна точка");
  assertEquals(json.data.disclaimer_label, null);
  assertEquals(json.data.name_label, "Не знаю, що це");
});

Deno.test("card: точки немає або її не можна бачити → 404 pick_not_found", async () => {
  const { res, json, signed } = await run(db(), req("GET", CARD));
  assertEquals(res.status, 404);
  assertEquals(json.error, "pick_not_found");
  assertEquals(signed.length, 0);
});

Deno.test("card: фото без шляху або збій підпису → photo_url: null, картка все одно відкривається", async () => {
  const row = { ...foreign(), description: null, photo_path: null, taken_at: "2026-11-10T09:30:00Z" };
  const noPhoto = await run(db({ "rpc.get_pick_card": { data: row, error: null } }), req("GET", CARD));
  assertEquals(noPhoto.json.data.photo_url, null);
  assertEquals(noPhoto.signed.length, 0);

  const failed = await run(
    db({ "rpc.get_pick_card": { data: { ...row, photo_path: "picks/x.jpg" }, error: null } }),
    req("GET", CARD),
    storage(true),
  );
  assertEquals(failed.res.status, 200);
  assertEquals(failed.json.data.photo_url, null);
});

Deno.test("card: 401 без токена; 409 без області; некоректний id → 404 not_found", async () => {
  assertEquals((await run(db(), new Request(CARD))).res.status, 401);
  const noRegion = await run(db({ "users.select": { data: { home_region_id: null }, error: null } }), req("GET", CARD));
  assertEquals(noRegion.res.status, 409);
  const bad = await run(db(), req("GET", "http://localhost/v1-picks/not-a-uuid"));
  assertEquals(bad.res.status, 404);
  assertEquals(bad.json.error, "not_found");
});

Deno.test("species: список видів для вибору назви + «Не знаю, що це»; кешується на годину", async () => {
  const d = db({
    "mushroom_catalog.select": {
      data: [
        { id: "boletus_edulis", name_ua: "Білий гриб", name_lat: "Boletus edulis" },
        { id: "cantharellus_cibarius", name_ua: "Лисичка справжня", name_lat: null },
      ],
      error: null,
    },
  });
  const { res, json } = await run(d, req("GET", "http://localhost/v1-picks/species"));
  assertEquals(res.status, 200);
  assertEquals(json.data, {
    species: [
      { id: "boletus_edulis", name_label: "Білий гриб", latin_label: "Boletus edulis" },
      { id: "cantharellus_cibarius", name_label: "Лисичка справжня", latin_label: null },
    ],
    unknown_label: "Не знаю, що це",
  });
  assertEquals(res.headers.get("Cache-Control"), "private, max-age=3600");
  assertEquals(find(d, "mushroom_catalog.select")!.filters, [["order", "name_ua"]]);

  assertEquals((await run(db(), new Request("http://localhost/v1-picks/species"))).res.status, 401);
  assertEquals((await run(db(), req("POST", "http://localhost/v1-picks/species", {}))).res.status, 405);
});

Deno.test("dateLabel: дата українською за київським часом", () => {
  assertEquals(dateLabel("2026-11-10T09:30:00Z"), "10 листопада 2026 р.");
  assertEquals(dateLabel("2026-01-01T00:30:00+02:00"), "1 січня 2026 р.");
  assertEquals(dateLabel("нісенітниця"), null);
  assertEquals(dateLabel(null), null);
  assert(dateLabel("2026-06-15T12:00:00Z")!.includes("червня"));
});
