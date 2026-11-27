import { assert, assertEquals } from "jsr:@std/assert";
import { handle } from "../../functions/_shared/http.ts";
import { handlePicks, type PicksStorage } from "../../functions/_shared/v1/picks.ts";
import { parseFriendIds, sharedFromLabel, sharedWithLabel } from "../../functions/_shared/v1/pick-shares.ts";
import { type Call, mockDb, req, type Results, RL_OK, verifyAs } from "./mock-db.ts";

// B9.4: поділитися приватною точкою з другом (ADR-021 §21.5)
const USER = "11111111-1111-4111-8111-111111111111";
const FRIEND = "22222222-2222-4222-8222-222222222222";
const PICK = "99999999-9999-4999-8999-999999999999";
const BASE = "http://localhost/v1-picks";
const EXACT = { lat: 50.4501, lng: 30.5234 };

function db(extra: Results = {}) {
  return mockDb({
    ...RL_OK,
    "users.select": { data: { home_region_id: 10 }, error: null },
    "rpc.share_pick": { data: { ok: true, shared: 1, recipients: 2 }, error: null },
    "rpc.revoke_pick_share": { data: { ok: true, revoked: 1 }, error: null },
    "rpc.picks_shared_with_me": { data: [], error: null },
    "rpc.get_picks_map": { data: [], error: null },
    "rpc.get_pick_card": { data: null, error: null },
    ...extra,
  });
}

const never = () => Promise.reject(new Error("not used"));
const storage: PicksStorage = {
  createSignedUploadUrl: never,
  download: never,
  upload: never,
  remove: never,
  createSignedUrl: (path) => Promise.resolve({ data: { signedUrl: `https://s/${path}` }, error: null }),
};

async function run(d: ReturnType<typeof mockDb>, r: Request, isAnonymous = false) {
  const res = await handle((x) => handlePicks(x, { db: d, storage, verify: verifyAs(USER, isAnonymous), fuzzSecret: "s" }))(r);
  return { res, json: await res.json() };
}
const find = (d: ReturnType<typeof mockDb>, key: string): Call | undefined => d.calls.find((c) => c.key === key);

Deno.test("shares: поділитися — id друзів без повторів, підпис «Бачать 2 друзі»", async () => {
  const d = db();
  const { res, json } = await run(d, req("POST", `${BASE}/${PICK}/shares`, { friend_ids: [FRIEND, FRIEND.toUpperCase()] }));
  assertEquals(res.status, 200);
  assertEquals(json.data, { shared: 1, recipients: 2, label: "Бачать 2 друзі" });
  assertEquals(find(d, "rpc.share_pick")!.args[0], { p_user_id: USER, p_pick_id: PICK, p_recipient_ids: [FRIEND] });
});

Deno.test("shares: відмови SQL — у HTTP-статуси з текстом сервера", async () => {
  const cases: Array<[string, number]> = [
    ["not_friend", 403], ["not_private", 409], ["share_limit", 409], ["pick_not_found", 404],
  ];
  for (const [code, status] of cases) {
    const d = db({ "rpc.share_pick": { data: { ok: false, code, message: "Текст" }, error: null } });
    const { res, json } = await run(d, req("POST", `${BASE}/${PICK}/shares`, { friend_ids: [FRIEND] }));
    assertEquals(res.status, status, code);
    assertEquals(json.error, code);
    assertEquals(json.message, "Текст");
  }
});

Deno.test("shares: гість не ділиться; кривий список друзів — 400 без запиту в БД", async () => {
  let d = db();
  let r = await run(d, req("POST", `${BASE}/${PICK}/shares`, { friend_ids: [FRIEND] }), true);
  assertEquals(r.res.status, 403);
  assertEquals(find(d, "rpc.share_pick"), undefined);
  for (const body of [{}, { friend_ids: [] }, { friend_ids: ["x"] }, { friend_ids: Array(21).fill(FRIEND) }, []]) {
    d = db();
    r = await run(d, req("POST", `${BASE}/${PICK}/shares`, body));
    assertEquals(r.res.status, 400, JSON.stringify(body));
    assertEquals(find(d, "rpc.share_pick"), undefined);
  }
});

Deno.test("shares: відкликати в одного й у всіх", async () => {
  let d = db();
  let r = await run(d, req("DELETE", `${BASE}/${PICK}/shares/${FRIEND}`));
  assertEquals(r.res.status, 200);
  assertEquals(r.json.data, { revoked: 1 });
  assertEquals(find(d, "rpc.revoke_pick_share")!.args[0], { p_user_id: USER, p_pick_id: PICK, p_recipient_id: FRIEND });
  d = db();
  r = await run(d, req("DELETE", `${BASE}/${PICK}/shares`));
  assertEquals(find(d, "rpc.revoke_pick_share")!.args[0], { p_user_id: USER, p_pick_id: PICK, p_recipient_id: null });
  // POST на конкретного друга — не той метод
  r = await run(db(), req("POST", `${BASE}/${PICK}/shares/${FRIEND}`, { friend_ids: [FRIEND] }));
  assertEquals(r.res.status, 405);
});

Deno.test("shared: список точок, якими поділились зі мною — точне місце й «Від @нік»", async () => {
  const d = db({
    "rpc.picks_shared_with_me": {
      data: [{ id: PICK, ...EXACT, species_id: "boletus_edulis", name_ua: "Білий гриб", from_handle: "Олена", shared_at: "2026-11-20T10:00:00Z" }],
      error: null,
    },
  });
  const { res, json } = await run(d, req("GET", `${BASE}/shared`));
  assertEquals(res.status, 200);
  assertEquals(json.data.picks, [{
    id: PICK, ...EXACT, is_exact: true, species_id: "boletus_edulis", name_label: "Білий гриб",
    shared_from_label: "Від @Олена", date_label: "20 листопада 2026 р.",
  }]);
});

Deno.test("card: поширена мені — точне місце, «Від @нік», лише «Відкрити в картах», без «з ким поділились»", async () => {
  const d = db({
    "rpc.get_pick_card": {
      data: {
        id: PICK, ...EXACT, is_exact: true, is_mine: false, pick_type: "private", verification_status: "pending",
        species_id: "boletus_edulis", name_ua: "Білий гриб", description: "біля берези", photo_path: null,
        taken_at: "2026-11-20T10:00:00Z", shared_from: "Олена", shared_with: null,
      },
      error: null,
    },
  });
  const { json } = await run(d, req("GET", `${BASE}/${PICK}`));
  assertEquals(json.data.shared_from_label, "Від @Олена");
  assertEquals(json.data.is_exact, true);
  assertEquals(json.data.lat, EXACT.lat);
  assertEquals(json.data.actions, ["open_in_maps"]);
  assertEquals(json.data.captured_at, null);
  assert(!("shared_with" in json.data));
  // перевірок «Я теж знайшов тут» для поширеної точки немає
  assertEquals(find(d, "rpc.can_confirm_pick"), undefined);
});

Deno.test("card: своя приватна — з ким поділився і «Бачать 1 друг»; без поля автора в чужій", async () => {
  const d = db({
    "rpc.get_pick_card": {
      data: {
        id: PICK, ...EXACT, is_exact: true, is_mine: true, pick_type: "private", verification_status: "pending",
        species_id: "boletus_edulis", name_ua: "Білий гриб", description: null, photo_path: null, taken_at: null,
        shared_from: null, shared_with: [{ user_id: FRIEND, handle: "Петро", avatar: null, active: true }],
      },
      error: null,
    },
  });
  const { json } = await run(d, req("GET", `${BASE}/${PICK}`));
  assertEquals(json.data.shared_with, [{ user_id: FRIEND, handle: "Петро", avatar: null }]);
  assertEquals(json.data.shared_with_label, "Бачать 1 друг");
  assertEquals(json.data.shared_from_label, null);
  assert(json.data.actions.includes("share"));
});

Deno.test("map: поширена мені точка — точне місце й «Від @нік»", async () => {
  const d = db({
    "rpc.get_picks_map": {
      data: [{
        id: PICK, ...EXACT, is_exact: true, is_mine: false, pick_type: "private", verification_status: "pending",
        species_id: "boletus_edulis", name_ua: "Білий гриб", shared_from: "Олена",
      }],
      error: null,
    },
  });
  const { json } = await run(d, req("GET", `${BASE}/map`));
  assertEquals(json.data.points[0].is_exact, true);
  assertEquals(json.data.points[0].shared_from_label, "Від @Олена");
});

Deno.test("labels: підписи й розбір списку друзів", () => {
  assertEquals(sharedFromLabel(null), null);
  assertEquals(sharedFromLabel(""), "Від друга");
  assertEquals(sharedWithLabel(0), null);
  assertEquals([1, 2, 5, 11, 21, 22].map(sharedWithLabel), [
    "Бачать 1 друг", "Бачать 2 друзі", "Бачать 5 друзів", "Бачать 11 друзів", "Бачать 21 друг", "Бачать 22 друзі",
  ]);
  assertEquals(parseFriendIds({ friend_ids: [FRIEND, FRIEND] }), [FRIEND]);
});
