import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import {
  forestTypeStyle,
  handleForestZones,
  parseForestZonesQuery,
  toleranceForZoom,
} from "../../functions/_shared/v1/forest-zones.ts";
import { mockDb, req, RL_BLOCKED, RL_OK, verifyAs } from "./mock-db.ts";

const URL_BASE = "http://localhost/v1-forest-zones";
const FC = {
  type: "FeatureCollection",
  features: [
    { type: "Feature", id: "a", geometry: {}, properties: { id: "a", forest_type: "pine" } },
    { type: "Feature", id: "b", geometry: {}, properties: { id: "b", forest_type: null } },
  ],
};

function run(db: ReturnType<typeof mockDb>, url: string, user = verifyAs("u1")) {
  return handle((r) => handleForestZones(r, { db, verify: user }))(req("GET", url));
}

Deno.test("forest-zones: полігони тільки Home Region користувача + підписи типів", async () => {
  const db = mockDb({ ...RL_OK, "users.select": { data: { home_region_id: 10 }, error: null }, "rpc.get_forest_zones_geojson_region": { data: FC, error: null } });
  const res = await run(db, `${URL_BASE}?bbox=30,50,31,51&z=10`);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.data.features.length, 2);
  assertEquals(body.data.features[0].properties.type_label, "Сосновий ліс");
  assertEquals(body.data.features[0].properties.type_color, "#81c784");
  assertEquals(body.data.features[1].properties.type_label, "Ліс (тип невідомий)");

  const rpc = db.calls.find((c) => c.key === "rpc.get_forest_zones_geojson_region")!;
  const p = rpc.args[0] as Record<string, unknown>;
  assertEquals(p.p_region_id, 10); // регіон з профілю, а не з запиту
  assertEquals([p.p_min_lng, p.p_min_lat, p.p_max_lng, p.p_max_lat], [30, 50, 31, 51]);
  assertEquals(p.p_tolerance, 0.0002);
});

Deno.test("forest-zones: без bbox — уся область (bbox = null)", async () => {
  const db = mockDb({ ...RL_OK, "users.select": { data: { home_region_id: 3 }, error: null }, "rpc.get_forest_zones_geojson_region": { data: FC, error: null } });
  await run(db, URL_BASE);
  const p = db.calls.find((c) => c.key === "rpc.get_forest_zones_geojson_region")!.args[0] as Record<string, unknown>;
  assertEquals(p.p_min_lng, null);
  assertEquals(p.p_region_id, 3);
});

Deno.test("forest-zones: без області → 409 home_region_required, RPC не викликається", async () => {
  const db = mockDb({ ...RL_OK, "users.select": { data: { home_region_id: null }, error: null } });
  const res = await run(db, URL_BASE);
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error, "home_region_required");
  assertEquals(db.calls.some((c) => c.key.startsWith("rpc.get_forest")), false);
});

Deno.test("forest-zones: bbox більший за область → 400 bbox_too_large", async () => {
  const db = mockDb({ ...RL_OK, "users.select": { data: { home_region_id: 1 }, error: null } });
  const res = await run(db, `${URL_BASE}?bbox=22,44,40,52`);
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "bbox_too_large");
});

Deno.test("forest-zones: некоректний bbox → 400 invalid_bbox", async () => {
  const db = mockDb({ ...RL_OK, "users.select": { data: { home_region_id: 1 }, error: null } });
  for (const bad of ["1,2,3", "31,50,30,51", "a,b,c,d"]) {
    const res = await run(db, `${URL_BASE}?bbox=${bad}`);
    assertEquals(res.status, 400, bad);
    assertEquals((await res.json()).error, "invalid_bbox", bad);
  }
});

Deno.test("forest-zones: без JWT → 401", async () => {
  const db = mockDb(RL_OK);
  const res = await handle((r) => handleForestZones(r, { db, verify: verifyAs("u") }))(new Request(URL_BASE));
  assertEquals(res.status, 401);
});

Deno.test("forest-zones: rate limit → 429", async () => {
  const res = await run(mockDb(RL_BLOCKED), URL_BASE);
  assertEquals(res.status, 429);
  assertEquals((await res.json()).error, "rate_limited");
});

Deno.test("forest-zones: POST → 405", async () => {
  const db = mockDb(RL_OK);
  const res = await handle((r) => handleForestZones(r, { db, verify: verifyAs("u") }))(req("POST", URL_BASE, {}));
  assertEquals(res.status, 405);
});

Deno.test("forest-zones: parse — z і limit", () => {
  assertEquals(parseForestZonesQuery(new URL(`${URL_BASE}?z=9&limit=100`)).limit, 100);
  assertEquals(toleranceForZoom(null), 0);
  assertEquals(toleranceForZoom(14), 0);
  assertEquals(toleranceForZoom(8), 0.0008);
  assertEquals(toleranceForZoom(5), 0.002);
  assertEquals(forestTypeStyle("oak").label, "Дубовий ліс");
});
