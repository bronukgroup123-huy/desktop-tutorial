import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handle } from "../../functions/_shared/http.ts";
import { handleRegionGeometry, zoomForBbox } from "../../functions/_shared/v1/regions.ts";
import { mockDb, RL_OK } from "./mock-db.ts";

const ROW = {
  id: 10, slug: "kyivska", name: "Київська",
  bbox: [29.3, 49.2, 32.2, 51.6], center: [30.6, 50.4],
  geometry: { type: "MultiPolygon", coordinates: [] },
};

const run = (db: ReturnType<typeof mockDb>, url: string, headers: Record<string, string> = {}) =>
  handle((r) => handleRegionGeometry(r, { db }))(new Request(url, { headers }));

Deno.test("regions: /v1-regions/{slug}/geometry → кордон, bbox, центр, zoom", async () => {
  const db = mockDb({ ...RL_OK, "rpc.get_region_geometry": { data: ROW, error: null } });
  const res = await run(db, "http://localhost/v1-regions/kyivska/geometry");
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.data.slug, "kyivska");
  assertEquals(body.data.center, [30.6, 50.4]);
  assertEquals(typeof body.data.zoom, "number");
  assertEquals(res.headers.get("Cache-Control"), "public, max-age=86400");
  const p = db.calls.find((c) => c.key === "rpc.get_region_geometry")!.args[0] as Record<string, unknown>;
  assertEquals(p, { p_slug: "kyivska", p_tolerance: 0.005 });
});

Deno.test("regions: ETag → 304 Not Modified", async () => {
  const db = mockDb({ ...RL_OK, "rpc.get_region_geometry": { data: ROW, error: null } });
  const first = await run(db, "http://localhost/v1-regions/kyivska/geometry");
  const etag = first.headers.get("ETag")!;
  const second = await run(db, "http://localhost/v1-regions/kyivska/geometry", { "If-None-Match": etag });
  assertEquals(second.status, 304);
});

Deno.test("regions: невідомий slug → 404 region_not_found", async () => {
  const db = mockDb({ ...RL_OK, "rpc.get_region_geometry": { data: null, error: null } });
  const res = await run(db, "http://localhost/v1-regions/atlantis/geometry");
  assertEquals(res.status, 404);
  assertEquals((await res.json()).error, "region_not_found");
});

Deno.test("regions: некоректний slug / detail → 400", async () => {
  const db = mockDb(RL_OK);
  assertEquals((await run(db, "http://localhost/v1-regions/BAD!/geometry")).status, 400);
  assertEquals((await run(db, "http://localhost/v1-regions/kyivska/geometry?detail=ultra")).status, 400);
});

Deno.test("regions: detail=low → грубший допуск", async () => {
  const db = mockDb({ ...RL_OK, "rpc.get_region_geometry": { data: ROW, error: null } });
  await run(db, "http://localhost/v1-regions/kyivska/geometry?detail=low");
  const p = db.calls.find((c) => c.key === "rpc.get_region_geometry")!.args[0] as Record<string, unknown>;
  assertEquals(p.p_tolerance, 0.02);
});

Deno.test("regions: zoomForBbox — область вміщується в 5..12", () => {
  assertEquals(zoomForBbox([29.3, 49.2, 32.2, 51.6]), 6);
  assertEquals(zoomForBbox([30.4, 50.4, 30.6, 50.5]), 10);
  assertEquals(zoomForBbox([0, 0, 0.0001, 0.0001]), 12);
  assertEquals(zoomForBbox([-180, -90, 180, 90]), 5);
});
