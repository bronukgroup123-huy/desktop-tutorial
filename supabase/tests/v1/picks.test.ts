import { assert, assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { distanceM } from "../../functions/_shared/picks/fuzz.ts";
import {
  handlePicks,
  parsePicksRoute,
  pickPresentation,
  type PicksStorage,
  uploadUrlExpiresAt,
} from "../../functions/_shared/v1/picks.ts";
import { buildJpeg, buildPng, concat, jpegWithExif } from "../picks/fixtures.ts";
import { type Call, mockDb, req, type Results, RL_BLOCKED, RL_OK, verifyAs, verifyNone } from "./mock-db.ts";

const NOW = new Date("2026-11-10T12:00:00Z");
const USER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const CLIENT = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const PICK_ID = "99999999-9999-4999-8999-999999999999";
const KYIV = { lat: 50.4501, lng: 30.5234 };
const DRAFT = `${USER}/${CLIENT}.jpg`;
const FINAL = `picks/${PICK_ID}.jpg`;
const SECRET = "test-fuzz-secret";
const UPLOAD = "http://localhost/v1-picks/upload-url";
const CREATE = "http://localhost/v1-picks";

const enc = new TextEncoder();
const includesAscii = (bytes: Uint8Array, text: string) => new TextDecoder("latin1").decode(bytes).includes(text);

// ─── Моки ───────────────────────────────────────────────────────────────────

function mockStorage(files: Record<string, Uint8Array> = {}, fail: { download?: unknown; upload?: unknown } = {}) {
  const store = new Map(Object.entries(files));
  const calls: Array<{ op: string; path: string; options?: unknown }> = [];
  let tokens = 0;
  const storage: PicksStorage = {
    createSignedUploadUrl(path, options) {
      calls.push({ op: "sign", path, options });
      const token = `token-${++tokens}`;
      return Promise.resolve({
        data: {
          signedUrl: `https://proj.supabase.co/storage/v1/object/upload/sign/mushroom-photos/${path}?token=${token}`,
          token,
          path,
        },
        error: null,
      });
    },
    download(path) {
      calls.push({ op: "download", path });
      if (fail.download) return Promise.resolve({ data: null, error: fail.download });
      const file = store.get(path);
      return Promise.resolve(
        file
          ? { data: new Blob([file as BlobPart]), error: null }
          : { data: null, error: { status: 400, message: "Object not found" } },
      );
    },
    upload(path, body, options) {
      calls.push({ op: "upload", path, options });
      if (fail.upload) return Promise.resolve({ data: null, error: fail.upload });
      store.set(path, body);
      return Promise.resolve({ data: { path }, error: null });
    },
    remove(paths) {
      for (const path of paths) {
        calls.push({ op: "remove", path });
        store.delete(path);
      }
      return Promise.resolve({ data: [], error: null });
    },
    createSignedUrl(path, expiresIn) {
      calls.push({ op: "sign-read", path, options: expiresIn });
      return Promise.resolve({ data: { signedUrl: `https://proj.supabase.co/signed/${path}?t=1` }, error: null });
    },
  };
  return { storage, store, calls };
}

const created = (visibility: string) => ({
  data: {
    allowed: true,
    created: true,
    pick: { id: PICK_ID, pick_type: visibility, verification_status: "pending" },
  },
  error: null,
});

/** БД «усе добре»: область обрана, точка в області, вид є, ліміт дозволяє. */
function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": { data: { home_region_id: 10 }, error: null },
    "mushroom_picks.select": { data: null, error: null },
    "mushroom_catalog.select": { data: { id: "boletus_edulis" }, error: null },
    "rpc.point_in_region": { data: true, error: null },
    "rpc.can_create_pick": { data: [{ allowed: true, code: null, message: null }], error: null },
    "rpc.create_pick": (call: Call) => created(String((call.args[0] as Record<string, unknown>).p_visibility)),
    ...extra,
  });
}

function body(overrides: Record<string, unknown> = {}) {
  return {
    client_id: CLIENT,
    path: DRAFT,
    lat: KYIV.lat,
    lng: KYIV.lng,
    captured_at: "2026-11-10T09:30:00Z",
    visibility: "private",
    species_id: null,
    ...overrides,
  };
}

interface RunOptions {
  isAnonymous?: boolean;
  files?: Record<string, Uint8Array>;
  storage?: ReturnType<typeof mockStorage>;
}

async function run(d: ReturnType<typeof mockDb>, r: Request, opts: RunOptions = {}) {
  const s = opts.storage ?? mockStorage(opts.files ?? { [DRAFT]: buildJpeg() });
  const res = await handle((x) =>
    handlePicks(x, {
      db: d,
      storage: s.storage,
      verify: verifyAs(USER, opts.isAnonymous ?? false),
      fuzzSecret: SECRET,
      now: () => NOW,
      newId: () => PICK_ID,
    })
  )(r);
  return { res, json: res.status === 204 ? null : await res.json(), ...s };
}

const find = (d: ReturnType<typeof mockDb>, key: string): Call | undefined => d.calls.find((c) => c.key === key);
const createArgs = (d: ReturnType<typeof mockDb>) => find(d, "rpc.create_pick")!.args[0] as Record<string, unknown>;

// ─── Маршрути ───────────────────────────────────────────────────────────────

Deno.test("v1-picks: маршрути", () => {
  assertEquals(parsePicksRoute(new URL("http://x/v1-picks")), { kind: "create" });
  assertEquals(parsePicksRoute(new URL("http://x/v1-picks/")), { kind: "create" });
  assertEquals(parsePicksRoute(new URL("http://x/functions/v1/v1-picks/upload-url")), { kind: "upload-url" });
  assertEquals(parsePicksRoute(new URL("http://x/v1-picks/upload-url/")), { kind: "upload-url" });
  assertEquals(parsePicksRoute(new URL("http://x/v1-picks/map?bbox=1,2,3,4")), { kind: "map" });
  assertEquals(parsePicksRoute(new URL(`http://x/v1-picks/${PICK_ID.toUpperCase()}`)), { kind: "card", id: PICK_ID });
});

Deno.test("v1-picks: невідомий шлях → 404, не-POST → 405, rate limit → 429", async () => {
  assertEquals((await run(db(), req("POST", "http://localhost/v1-picks/unknown", {}))).res.status, 404);
  assertEquals((await run(db(), req("POST", "http://localhost/v1-picks/a/b", {}))).res.status, 404);
  assertEquals((await run(db(), req("GET", CREATE))).res.status, 405);
  assertEquals((await run(db(), req("GET", UPLOAD))).res.status, 405);
  assertEquals((await run(db(), req("POST", "http://localhost/v1-picks/map", {}))).res.status, 405);
  assertEquals((await run(db(), req("POST", `http://localhost/v1-picks/${PICK_ID}`, {}))).res.status, 405);

  const limited = await run(db(RL_BLOCKED), req("POST", CREATE, body()));
  assertEquals(limited.res.status, 429);
  assertEquals(limited.json.error, "rate_limited");
  assertEquals(limited.res.headers.get("Retry-After"), "60");
});

// ─── B3.0: upload-url ───────────────────────────────────────────────────────

const uploadBody = (o: Record<string, unknown> = {}) => ({
  client_id: CLIENT,
  content_type: "image/jpeg",
  size_bytes: 1_500_000,
  ...o,
});

Deno.test("upload-url: 200 — посилання, шлях <user_id>/<client_id>.jpg, токен, термін дії", async () => {
  const { res, json, calls } = await run(db(), req("POST", UPLOAD, uploadBody()));
  assertEquals(res.status, 200);
  assertEquals(json.data.path, DRAFT);
  assertEquals(json.data.token, "token-1");
  assert(json.data.upload_url.includes(`/object/upload/sign/mushroom-photos/${DRAFT}?token=token-1`));
  assertEquals(json.data.expires_at, "2026-11-10T14:00:00.000Z"); // 2 години
  assertEquals(calls, [{ op: "sign", path: DRAFT, options: { upsert: true } }]);
});

Deno.test("upload-url: розширення шляху — за типом фото", async () => {
  const png = await run(db(), req("POST", UPLOAD, uploadBody({ content_type: "image/png" })));
  assertEquals(png.json.data.path, `${USER}/${CLIENT}.png`);
  const webp = await run(db(), req("POST", UPLOAD, uploadBody({ content_type: "image/webp" })));
  assertEquals(webp.json.data.path, `${USER}/${CLIENT}.webp`);
});

Deno.test("upload-url: розмір > 5 МіБ → 400 photo_too_large; рівно 5 МіБ — можна", async () => {
  const big = await run(db(), req("POST", UPLOAD, uploadBody({ size_bytes: 5_242_881 })));
  assertEquals(big.res.status, 400);
  assertEquals(big.json.error, "photo_too_large");
  assertEquals(big.calls.length, 0);

  const edge = await run(db(), req("POST", UPLOAD, uploadBody({ size_bytes: 5_242_880 })));
  assertEquals(edge.res.status, 200);
});

Deno.test("upload-url: інший тип файлу → 400 invalid_photo_format", async () => {
  for (const content_type of ["image/gif", "application/pdf", "image/heic", "", undefined, 42]) {
    const { res, json, calls } = await run(db(), req("POST", UPLOAD, uploadBody({ content_type })));
    assertEquals(res.status, 400, String(content_type));
    assertEquals(json.error, "invalid_photo_format");
    assertEquals(calls.length, 0);
  }
});

Deno.test("upload-url: повтор з тим самим client_id → нове посилання на той самий шлях", async () => {
  const s = mockStorage();
  const first = await run(db(), req("POST", UPLOAD, uploadBody()), { storage: s });
  const second = await run(db(), req("POST", UPLOAD, uploadBody()), { storage: s });
  assertEquals(second.res.status, 200);
  assertEquals(second.json.data.path, first.json.data.path);
  assert(second.json.data.upload_url !== first.json.data.upload_url);
  // upsert: повторне завантаження на той самий шлях дозволене
  assertEquals(s.calls.map((c) => c.options), [{ upsert: true }, { upsert: true }]);
});

Deno.test("upload-url: без токена або з недійсним → 401", async () => {
  const noToken = new Request(UPLOAD, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(uploadBody()),
  });
  const a = await run(db(), noToken);
  assertEquals(a.res.status, 401);
  assertEquals(a.json.error, "unauthorized");
  assertEquals(a.calls.length, 0);

  const s = mockStorage();
  const res = await handle((x) =>
    handlePicks(x, { db: db(), storage: s.storage, verify: verifyNone, fuzzSecret: SECRET })
  )(req("POST", UPLOAD, uploadBody()));
  assertEquals(res.status, 401);
  assertEquals(s.calls.length, 0);
});

Deno.test("upload-url: гість теж може (приватні точки, ADR-001)", async () => {
  const { res } = await run(db(), req("POST", UPLOAD, uploadBody()), { isAnonymous: true });
  assertEquals(res.status, 200);
});

Deno.test("upload-url: без Home Region → 409 home_region_required", async () => {
  const d = db({ "users.select": { data: { home_region_id: null }, error: null } });
  const { res, json, calls } = await run(d, req("POST", UPLOAD, uploadBody()));
  assertEquals(res.status, 409);
  assertEquals(json.error, "home_region_required");
  assertEquals(calls.length, 0);
});

Deno.test("upload-url: некоректні client_id / size_bytes / тіло → 422 validation_error", async () => {
  for (
    const bad of [
      uploadBody({ client_id: "not-a-uuid" }),
      uploadBody({ client_id: undefined }),
      uploadBody({ size_bytes: "1000" }),
      uploadBody({ size_bytes: 0 }),
      uploadBody({ size_bytes: 10.5 }),
      [1, 2],
      "text",
    ]
  ) {
    const { res, json } = await run(db(), req("POST", UPLOAD, bad));
    assertEquals(res.status, 422, JSON.stringify(bad));
    assertEquals(json.error, "validation_error");
    assert(/[а-яіїє]/i.test(json.message), "message українською");
  }
});

Deno.test("upload-url: client_id у верхньому регістрі → шлях у нижньому", async () => {
  const { json } = await run(db(), req("POST", UPLOAD, uploadBody({ client_id: CLIENT.toUpperCase() })));
  assertEquals(json.data.path, DRAFT);
});

Deno.test("upload-url: термін дії береться з токена Storage (JWT exp)", () => {
  const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const jwt = `${b64({ alg: "HS256" })}.${b64({ exp: 1794312000 })}.sig`;
  assertEquals(uploadUrlExpiresAt(jwt, NOW), new Date(1794312000 * 1000).toISOString());
  assertEquals(uploadUrlExpiresAt("opaque-token", NOW), "2026-11-10T14:00:00.000Z");
});

// ─── B3.1: створення точки ──────────────────────────────────────────────────

Deno.test("create: приватна точка «Не знаю» → 201, підписи з сервера, без display_geom", async () => {
  const d = db();
  const { res, json, store } = await run(d, req("POST", CREATE, body({ description: "  Під сосною  " })));
  assertEquals(res.status, 201);
  assertEquals(json, {
    data: { id: PICK_ID, visibility: "private", status_label: "Приватна точка", marker_color: "#1e88e5" },
  });

  const p = createArgs(d);
  assertEquals(p.p_id, PICK_ID);
  assertEquals(p.p_user_id, USER);
  assertEquals(p.p_client_id, CLIENT);
  assertEquals([p.p_lat, p.p_lng], [KYIV.lat, KYIV.lng]);
  assertEquals(p.p_visibility, "private");
  assertEquals(p.p_species_id, null);
  assertEquals(p.p_description, "Під сосною");
  assertEquals(p.p_captured_at, "2026-11-10T09:30:00.000Z");
  assertEquals(p.p_twin_alert, false);
  assertEquals(p.p_photo_path, FINAL);
  // display_geom — тільки для public
  assertEquals([p.p_display_lat, p.p_display_lng], [null, null]);

  // фото: очищена копія в захищеній теці, чернетку видалено
  assert(store.has(FINAL));
  assertEquals(store.has(DRAFT), false);
});

Deno.test("create: публічна точка → 201 «Перевіряється», зсув 300–500 м, точних координат у відповіді немає", async () => {
  const d = db();
  const { res, json } = await run(d, req("POST", CREATE, body({ visibility: "public", species_id: "boletus_edulis" })));
  assertEquals(res.status, 201);
  assertEquals(json, {
    data: { id: PICK_ID, visibility: "public", status_label: "Перевіряється", marker_color: "#9e9e9e" },
  });
  const text = JSON.stringify(json);
  assertEquals(text.includes(String(KYIV.lat)) || text.includes(String(KYIV.lng)), false);

  const p = createArgs(d);
  assertEquals(p.p_species_id, "boletus_edulis");
  const shift = distanceM(KYIV.lat, KYIV.lng, p.p_display_lat as number, p.p_display_lng as number);
  assert(shift >= 300 && shift <= 500, `shift ${shift} m`);
  // точне місце зберігається окремо — для автора і прогнозу
  assertEquals([p.p_lat, p.p_lng], [KYIV.lat, KYIV.lng]);
});

Deno.test("create: зсув публічної точки стабільний для того самого id", async () => {
  const a = db();
  const b = db();
  const input = body({ visibility: "public", species_id: "boletus_edulis" });
  await run(a, req("POST", CREATE, input));
  await run(b, req("POST", CREATE, input));
  assertEquals(
    [createArgs(a).p_display_lat, createArgs(a).p_display_lng],
    [createArgs(b).p_display_lat, createArgs(b).p_display_lng],
  );
});

Deno.test("create: гість + public → 403 registration_required (до решти перевірок)", async () => {
  const d = db();
  const { res, json, calls } = await run(
    d,
    req("POST", CREATE, body({ visibility: "public", species_id: "boletus_edulis" })),
    { isAnonymous: true },
  );
  assertEquals(res.status, 403);
  assertEquals(json.error, "registration_required");
  assert(json.message.length > 0);
  assertEquals(find(d, "rpc.create_pick"), undefined);
  assertEquals(calls.length, 0);

  // навіть якщо решта тіла некоректна — гість спершу бачить «потрібна реєстрація»
  const bad = await run(db(), req("POST", CREATE, { visibility: "public" }), { isAnonymous: true });
  assertEquals(bad.json.error, "registration_required");
});

Deno.test("create: гість + private → 201", async () => {
  const { res } = await run(db(), req("POST", CREATE, body()), { isAnonymous: true });
  assertEquals(res.status, 201);
});

Deno.test("create: «Не знаю» + public → 422 species_required", async () => {
  for (const species_id of [null, undefined]) {
    const d = db();
    const { res, json, calls } = await run(d, req("POST", CREATE, body({ visibility: "public", species_id })));
    assertEquals(res.status, 422);
    assertEquals(json.error, "species_required");
    assertEquals(find(d, "rpc.create_pick"), undefined);
    assertEquals(calls.length, 0);
  }
});

Deno.test("create: вид, якого немає в довіднику → 422 unknown_species", async () => {
  const d = db({ "mushroom_catalog.select": { data: null, error: null } });
  const { res, json } = await run(d, req("POST", CREATE, body({ species_id: "amanita_fantastica" })));
  assertEquals(res.status, 422);
  assertEquals(json.error, "unknown_species");
  assertEquals(find(d, "mushroom_catalog.select")!.filters, [["id", "amanita_fantastica"]]);
  assertEquals(find(d, "rpc.create_pick"), undefined);
});

Deno.test("create: повтор client_id → 200 з тією самою точкою, без другої вставки", async () => {
  const d = db({
    "mushroom_picks.select": {
      data: { id: "77777777-7777-4777-8777-777777777777", pick_type: "public", verification_status: "verified" },
      error: null,
    },
  });
  const { res, json, calls, store } = await run(d, req("POST", CREATE, body({ visibility: "public", species_id: "boletus_edulis" })));
  assertEquals(res.status, 200);
  assertEquals(json.data, {
    id: "77777777-7777-4777-8777-777777777777",
    visibility: "public",
    status_label: "Підтверджено",
    marker_color: "#43a047",
  });
  assertEquals(find(d, "mushroom_picks.select")!.filters, [["user_id", USER], ["client_id", CLIENT]]);
  // нічого не вставлялось і фото не чіпалось; ліміт на повтор не діє
  assertEquals(find(d, "rpc.create_pick"), undefined);
  assertEquals(find(d, "rpc.can_create_pick"), undefined);
  assertEquals(calls.length, 0);
  assert(store.has(DRAFT));
});

Deno.test("create: паралельний повтор (БД каже created = false) → 200, зайве фото прибрано", async () => {
  const d = db({
    "rpc.create_pick": {
      data: {
        allowed: true,
        created: false,
        pick: { id: "77777777-7777-4777-8777-777777777777", pick_type: "private", verification_status: "pending" },
      },
      error: null,
    },
  });
  const { res, json, store } = await run(d, req("POST", CREATE, body()));
  assertEquals(res.status, 200);
  assertEquals(json.data.id, "77777777-7777-4777-8777-777777777777");
  assertEquals(store.has(FINAL), false);
});

Deno.test("create: фото не завантажено → 422 photo_not_uploaded", async () => {
  const d = db();
  const { res, json } = await run(d, req("POST", CREATE, body()), { files: {} });
  assertEquals(res.status, 422);
  assertEquals(json.error, "photo_not_uploaded");
  assertEquals(find(d, "rpc.create_pick"), undefined);
});

Deno.test("create: чернетки вже немає, бо точку створив паралельний запит → 200", async () => {
  let selects = 0;
  const d = db({
    "mushroom_picks.select": () => ({
      data: ++selects === 1 ? null : { id: PICK_ID, pick_type: "private", verification_status: "pending" },
      error: null,
    }),
  });
  const { res, json } = await run(d, req("POST", CREATE, body()), { files: {} });
  assertEquals(res.status, 200);
  assertEquals(json.data.id, PICK_ID);
});

Deno.test("create: збій Storage (5xx) → 500 storage_error, а не «фото не завантажено»", async () => {
  const s = mockStorage({}, { download: { status: 503, message: "unavailable" } });
  const { res, json } = await run(db(), req("POST", CREATE, body()), { storage: s });
  assertEquals(res.status, 500);
  assertEquals(json.error, "storage_error");
});

Deno.test("create: чужий path → 403 forbidden", async () => {
  const d = db();
  const { res, json, calls } = await run(d, req("POST", CREATE, body({ path: `${OTHER}/${CLIENT}.jpg` })), {
    files: { [`${OTHER}/${CLIENT}.jpg`]: buildJpeg() },
  });
  assertEquals(res.status, 403);
  assertEquals(json.error, "forbidden");
  assertEquals(calls.length, 0); // чужий файл навіть не читається
  assertEquals(find(d, "rpc.create_pick"), undefined);
});

Deno.test("create: path не з upload-url (інша назва, тека picks/, вихід із теки) → 422", async () => {
  for (
    const path of [
      `${USER}/${OTHER}.jpg`, // чужий client_id — це могло б зачепити інше фото
      `picks/${CLIENT}.jpg`,
      `${USER}/../${OTHER}/${CLIENT}.jpg`,
      `${USER}/${CLIENT}.gif`,
      `${USER}/${CLIENT}`,
      "",
      42,
    ]
  ) {
    const { res, json, calls } = await run(db(), req("POST", CREATE, body({ path })));
    assertEquals(res.status, 422, String(path));
    assertEquals(json.error, "validation_error");
    assertEquals(calls.length, 0);
  }
});

Deno.test("create: точка поза областю користувача → 403 outside_home_region", async () => {
  const d = db({ "rpc.point_in_region": { data: false, error: null } });
  const { res, json, calls } = await run(d, req("POST", CREATE, body()));
  assertEquals(res.status, 403);
  assertEquals(json.error, "outside_home_region");
  assertEquals(find(d, "rpc.point_in_region")!.args[0], { lat: KYIV.lat, lng: KYIV.lng, region_id: 10 });
  assertEquals(find(d, "rpc.create_pick"), undefined);
  assertEquals(calls.length, 0);
});

Deno.test("create: без Home Region → 409 home_region_required", async () => {
  const d = db({ "users.select": { data: { home_region_id: null }, error: null } });
  const { res, json } = await run(d, req("POST", CREATE, body()));
  assertEquals(res.status, 409);
  assertEquals(json.error, "home_region_required");
});

Deno.test("create: добовий ліміт → 429 daily_limit_reached з текстом із БД", async () => {
  const message = "Ліміт — 5 приватних точок на добу. Спробуйте пізніше.";
  const d = db({ "rpc.can_create_pick": { data: [{ allowed: false, code: "daily_limit_reached", message }], error: null } });
  const { res, json, calls } = await run(d, req("POST", CREATE, body()));
  assertEquals(res.status, 429);
  assertEquals(json, { error: "daily_limit_reached", message });
  assertEquals(find(d, "rpc.can_create_pick")!.args[0], { p_user_id: USER, p_visibility: "private" });
  // відмова — до роботи з файлом
  assertEquals(calls.length, 0);
  assertEquals(find(d, "rpc.create_pick"), undefined);
});

Deno.test("create: public нижче рівня «Лісовик» → 403 level_required", async () => {
  const message = "Публічні точки — з рівня Лісовик. Поки що зробіть приватний тук-тук.";
  const d = db({ "rpc.can_create_pick": { data: [{ allowed: false, code: "level_required", message }], error: null } });
  const { res, json } = await run(d, req("POST", CREATE, body({ visibility: "public", species_id: "boletus_edulis" })));
  assertEquals(res.status, 403);
  assertEquals(json, { error: "level_required", message });
});

Deno.test("create: ліміт вичерпав паралельний запит (відмова під час вставки) → 429, фото прибрано", async () => {
  const d = db({
    "rpc.create_pick": {
      data: { allowed: false, created: false, code: "daily_limit_reached", message: "Ліміт" },
      error: null,
    },
  });
  const { res, json, store } = await run(d, req("POST", CREATE, body()));
  assertEquals(res.status, 429);
  assertEquals(json.error, "daily_limit_reached");
  assertEquals(store.has(FINAL), false);
  assert(store.has(DRAFT)); // чернетка лишається — точку можна створити пізніше
});

Deno.test("create: verification завжди pending — навіть з ідеальним EXIF і підказкою ШІ «збігається»", async () => {
  const d = db();
  const photo = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00" });
  const { res, json } = await run(
    d,
    req("POST", CREATE, body({
      visibility: "public",
      species_id: "boletus_edulis",
      ai_check: { model_version: "bioclip2-int8-1", top: [{ species_id: "boletus_edulis", level: "high" }], match: true, twin_alert: false },
    })),
    { files: { [DRAFT]: photo } },
  );
  assertEquals(res.status, 201);
  assertEquals(json.data.status_label, "Перевіряється");
  const p = createArgs(d);
  // EXIF справді пройшов перевірку…
  assertEquals((p.p_ai_check as Record<string, unknown>).exif, { has_exif: true, verified: true, reason: null });
  // …але обробник не передає в БД жодного статусу: 'pending' виставляє сама create_pick
  assertEquals(Object.keys(p).filter((k) => /status|verif/i.test(k)), []);
  assertEquals(JSON.stringify(p).includes('"verified":true,"reason":null}'), true);
  assertEquals(Object.values(p).includes("verified"), false);
});

Deno.test("create: EXIF вирізається — у збереженому фото немає GPS; результат перевірки — в ai_check", async () => {
  const d = db();
  const photo = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00", orientation: 6 });
  const { res, store, calls } = await run(d, req("POST", CREATE, body()), { files: { [DRAFT]: photo } });
  assertEquals(res.status, 201);

  const saved = store.get(FINAL)!;
  assert(saved.length < photo.length);
  assertEquals(includesAscii(saved, "2026:11:10"), false);
  assertEquals(includesAscii(saved, "GPS"), false);
  assertEquals(Array.from(saved.subarray(0, 3)), [0xff, 0xd8, 0xff]);
  assertEquals(calls.find((c) => c.op === "upload"), {
    op: "upload",
    path: FINAL,
    options: { contentType: "image/jpeg", upsert: true },
  });
  assertEquals((createArgs(d).p_ai_check as Record<string, unknown>).exif, {
    has_exif: true,
    verified: true,
    reason: null,
  });
});

Deno.test("create: EXIF з іншим місцем — точка створюється, але ai_check.exif.verified = false", async () => {
  const d = db();
  const photo = jpegWithExif({ lat: 49.0, lng: 24.0, dateTimeOriginal: "2026:11:10 09:30:00" });
  const { res } = await run(d, req("POST", CREATE, body()), { files: { [DRAFT]: photo } });
  assertEquals(res.status, 201);
  assertEquals((createArgs(d).p_ai_check as Record<string, unknown>).exif, {
    has_exif: true,
    verified: false,
    reason: "gps_mismatch",
  });
});

Deno.test("create: фото без EXIF → ai_check.exif.has_exif = false", async () => {
  const d = db();
  await run(d, req("POST", CREATE, body()));
  assertEquals(createArgs(d).p_ai_check, { exif: { has_exif: false, verified: false, reason: null } });
});

Deno.test("create: формат визначається за вмістом файлу, а не за назвою", async () => {
  const d = db();
  const { res, store, calls } = await run(d, req("POST", CREATE, body()), { files: { [DRAFT]: buildPng() } });
  assertEquals(res.status, 201);
  assertEquals(createArgs(d).p_photo_path, `picks/${PICK_ID}.png`);
  assert(store.has(`picks/${PICK_ID}.png`));
  assertEquals(calls.find((c) => c.op === "upload")!.options, { contentType: "image/png", upsert: true });
});

Deno.test("create: файл — не зображення → 400 invalid_photo_format, чернетку видалено", async () => {
  const d = db();
  const { res, json, store } = await run(d, req("POST", CREATE, body()), {
    files: { [DRAFT]: enc.encode("<html><script>alert(1)</script></html>") },
  });
  assertEquals(res.status, 400);
  assertEquals(json.error, "invalid_photo_format");
  assertEquals(store.size, 0);
  assertEquals(find(d, "rpc.create_pick"), undefined);
});

Deno.test("create: файл більший за 5 МіБ → 400 photo_too_large", async () => {
  const d = db();
  const huge = concat(buildJpeg(), new Uint8Array(5 * 1024 * 1024));
  const { res, json, store } = await run(d, req("POST", CREATE, body()), { files: { [DRAFT]: huge } });
  assertEquals(res.status, 400);
  assertEquals(json.error, "photo_too_large");
  assertEquals(store.size, 0);
  assertEquals(find(d, "rpc.create_pick"), undefined);
});

Deno.test("create: помилка БД під час вставки → 500, записане фото прибрано", async () => {
  const d = db({ "rpc.create_pick": { data: null, error: { message: "boom" } } });
  const { res, json, store } = await run(d, req("POST", CREATE, body()));
  assertEquals(res.status, 500);
  assertEquals(json.error, "db_error");
  assertEquals(JSON.stringify(json).includes("boom"), false);
  assertEquals(store.has(FINAL), false);
  assert(store.has(DRAFT));
});

Deno.test("create: виняток під час вставки (обрив зв'язку з БД) → 500, записане фото прибрано", async () => {
  const d = db({ "rpc.create_pick": () => { throw new Error("connection reset"); } });
  const { res, json, store } = await run(d, req("POST", CREATE, body()));
  assertEquals(res.status, 500);
  assertEquals(json.error, "db_error");
  assertEquals(store.has(FINAL), false);
  assert(store.has(DRAFT));
});

Deno.test("create: помилка Storage у старому форматі SDK (originalError.status) → 500 storage_error", async () => {
  const s = mockStorage({}, { download: { name: "StorageUnknownError", originalError: { status: 502 } } });
  const { res, json } = await run(db(), req("POST", CREATE, body()), { storage: s });
  assertEquals(res.status, 500);
  assertEquals(json.error, "storage_error");
});

Deno.test("create: не вдалося записати фото → 500 storage_error, вставки немає", async () => {
  const d = db();
  const s = mockStorage({ [DRAFT]: buildJpeg() }, { upload: { message: "disk full" } });
  const { res, json } = await run(d, req("POST", CREATE, body()), { storage: s });
  assertEquals(res.status, 500);
  assertEquals(json.error, "storage_error");
  assertEquals(find(d, "rpc.create_pick"), undefined);
});

Deno.test("create: опис — контакти замінюються на «…»", async () => {
  const d = db();
  await run(d, req("POST", CREATE, body({ description: "Під дубом. Дзвоніть +380671234567 або t.me/lisovyk" })));
  assertEquals(createArgs(d).p_description, "Під дубом. Дзвоніть … або …");
});

Deno.test("create: підказка ШІ зберігається лише з відомими полями; twin_alert → прапорець точки", async () => {
  const d = db();
  await run(
    d,
    req("POST", CREATE, body({
      species_id: "boletus_edulis",
      ai_check: {
        model_version: "bioclip2-int8-1",
        top: [{ species_id: "boletus_edulis", level: "high", probability: 0.93 }, { species_id: "tylopilus_felleus", level: "low" }],
        match: true,
        twin_alert: true,
        confidence: 0.87,
        exif: { verified: true }, // клієнт не може підробити серверну перевірку EXIF
      },
    })),
  );
  const p = createArgs(d);
  assertEquals(p.p_twin_alert, true);
  assertEquals(p.p_ai_check, {
    model_version: "bioclip2-int8-1",
    top: [{ species_id: "boletus_edulis", level: "high" }, { species_id: "tylopilus_felleus", level: "low" }],
    match: true,
    twin_alert: true,
    exif: { has_exif: false, verified: false, reason: null },
  });
  // жодних числових ймовірностей
  assertEquals(/0\.93|0\.87|probability|confidence/.test(JSON.stringify(p)), false);
});

Deno.test("create: некоректна підказка ШІ (відсотки замість рівнів тощо) → 422", async () => {
  const ok = { model_version: "m1", top: [], match: false, twin_alert: false };
  for (
    const ai_check of [
      { ...ok, top: [{ species_id: "boletus_edulis", level: 0.93 }] },
      { ...ok, top: [{ species_id: "boletus_edulis", level: "93%" }] },
      { ...ok, top: [{ level: "high" }] },
      { ...ok, top: new Array(6).fill({ species_id: "boletus_edulis", level: "low" }) },
      { ...ok, top: "boletus_edulis" },
      { ...ok, model_version: "" },
      { ...ok, match: "yes" },
      { ...ok, twin_alert: undefined },
      "match",
      [ok],
    ]
  ) {
    const { res, json } = await run(db(), req("POST", CREATE, body({ ai_check })));
    assertEquals(res.status, 422, JSON.stringify(ai_check));
    assertEquals(json.error, "validation_error");
  }
});

Deno.test("create: валідація тіла → 422 validation_error з текстом українською", async () => {
  for (
    const bad of [
      body({ client_id: "123" }),
      body({ lat: 91 }),
      body({ lat: "50.45" }),
      body({ lng: -181 }),
      body({ lng: null }),
      body({ captured_at: "вчора" }),
      body({ captured_at: "10.11.2026 09:30" }),
      body({ captured_at: 1794303000 }),
      body({ captured_at: "2026-11-12T12:00:01Z" }), // більш ніж на добу в майбутньому
      body({ visibility: "friends" }),
      body({ visibility: undefined }),
      body({ species_id: 42 }),
      body({ species_id: "" }),
      body({ description: 42 }),
      body({ description: "я".repeat(501) }),
      [body()],
      null,
    ]
  ) {
    const d = db();
    const { res, json, calls } = await run(d, req("POST", CREATE, bad));
    assertEquals(res.status, 422, JSON.stringify(bad));
    assertEquals(json.error, "validation_error");
    assert(/[а-яіїє]/i.test(json.message), `message українською: ${json.message}`);
    assertEquals(find(d, "rpc.create_pick"), undefined);
    assertEquals(calls.length, 0);
  }
});

Deno.test("create: не JSON → 400 invalid_json; без токена → 401", async () => {
  const raw = new Request(CREATE, {
    method: "POST",
    headers: { Authorization: "Bearer test-jwt", "Content-Type": "application/json" },
    body: "{not json",
  });
  const a = await run(db(), raw);
  assertEquals(a.res.status, 400);
  assertEquals(a.json.error, "invalid_json");

  const noToken = new Request(CREATE, { method: "POST", body: JSON.stringify(body()) });
  const b = await run(db(), noToken);
  assertEquals(b.res.status, 401);
});

Deno.test("create: час зйомки до доби в майбутньому (неточний годинник) приймається", async () => {
  const { res } = await run(db(), req("POST", CREATE, body({ captured_at: "2026-11-11T11:00:00+02:00" })));
  assertEquals(res.status, 201);
});

Deno.test("create: порядок перевірок — область → вид → ліміт → фото → вставка", async () => {
  const d = db();
  await run(d, req("POST", CREATE, body({ visibility: "public", species_id: "boletus_edulis" })));
  const order = d.calls.map((c) => c.key).filter((k) => !k.includes("rate_limit"));
  assertEquals(order, [
    "mushroom_picks.select", // ідемпотентність
    "users.select", // Home Region
    "rpc.point_in_region",
    "mushroom_catalog.select",
    "rpc.can_create_pick",
    "rpc.create_pick",
  ]);
});

Deno.test("pickPresentation: підписи й кольори для всіх станів", () => {
  assertEquals(pickPresentation("private", "pending").status_label, "Приватна точка");
  assertEquals(pickPresentation("private", "verified").status_label, "Приватна точка");
  assertEquals(pickPresentation("public", "pending"), { status_label: "Перевіряється", marker_color: "#9e9e9e" });
  assertEquals(pickPresentation("public", "conditional").status_label, "Перевіряється");
  assertEquals(pickPresentation("public", "verified"), { status_label: "Підтверджено", marker_color: "#43a047" });
  assertEquals(pickPresentation("public", "rejected").status_label, "Відхилено");
  assertEquals(pickPresentation("public", "???").status_label, "Перевіряється");
});
