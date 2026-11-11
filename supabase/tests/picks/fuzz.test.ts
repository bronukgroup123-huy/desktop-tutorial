import { assert, assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert";
import {
  destinationPoint,
  distanceM,
  FUZZ_MAX_M,
  FUZZ_MIN_M,
  fuzzOffset,
  fuzzPoint,
} from "../../functions/_shared/picks/fuzz.ts";

const SECRET = "test-secret";
const KYIV = { lat: 50.4501, lng: 30.5234 };
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

Deno.test("fuzz: стабільність — та сама точка завжди дає той самий зсув", async () => {
  const id = uuid(1);
  const a = await fuzzPoint(id, KYIV.lat, KYIV.lng, SECRET);
  for (let i = 0; i < 5; i++) {
    assertEquals(await fuzzPoint(id, KYIV.lat, KYIV.lng, SECRET), a);
  }
  // регістр UUID не впливає
  assertEquals(await fuzzPoint(id.toUpperCase(), KYIV.lat, KYIV.lng, SECRET), a);
});

Deno.test("fuzz: відстань зсуву завжди в межах 300–500 м", async () => {
  let min = Infinity;
  let max = -Infinity;
  for (let i = 0; i < 500; i++) {
    const p = await fuzzPoint(uuid(i), KYIV.lat, KYIV.lng, SECRET);
    const d = distanceM(KYIV.lat, KYIV.lng, p.lat, p.lng);
    assert(d >= 300 && d <= 500, `pick ${i}: shift ${d.toFixed(1)} m is outside 300–500 m`);
    min = Math.min(min, d);
    max = Math.max(max, d);
  }
  // зсуви справді різні, а не «всі по 400 м»
  assert(min < 330 && max > 470, `shifts are not spread: ${min.toFixed(0)}–${max.toFixed(0)} m`);
});

Deno.test("fuzz: межі відстані з запасом для еліпсоїда", async () => {
  assert(FUZZ_MIN_M > 300 && FUZZ_MAX_M < 500);
  for (let i = 0; i < 200; i++) {
    const { distanceM: d, bearingDeg } = await fuzzOffset(uuid(i), SECRET);
    assert(d >= FUZZ_MIN_M && d < FUZZ_MAX_M);
    assert(bearingDeg >= 0 && bearingDeg < 360);
  }
});

Deno.test("fuzz: напрямки рівномірні — немає «улюбленого» боку", async () => {
  const quadrants = [0, 0, 0, 0];
  for (let i = 0; i < 400; i++) {
    const { bearingDeg } = await fuzzOffset(uuid(i), SECRET);
    quadrants[Math.floor(bearingDeg / 90)]++;
  }
  for (const q of quadrants) assert(q > 60, `quadrants are skewed: ${quadrants.join(", ")}`);
});

Deno.test("fuzz: різні точки — різні зсуви", async () => {
  const a = await fuzzPoint(uuid(1), KYIV.lat, KYIV.lng, SECRET);
  const b = await fuzzPoint(uuid(2), KYIV.lat, KYIV.lng, SECRET);
  assertNotEquals(a, b);
});

Deno.test("fuzz: без секрету зсув не відтворити — інший секрет дає інше місце", async () => {
  const id = uuid(7);
  const a = await fuzzPoint(id, KYIV.lat, KYIV.lng, SECRET);
  const b = await fuzzPoint(id, KYIV.lat, KYIV.lng, "another-secret");
  assertNotEquals(a, b);
  await assertRejects(() => fuzzPoint(id, KYIV.lat, KYIV.lng, ""), Error, "secret");
});

Deno.test("fuzz: зсунута точка не збігається зі справжньою і має 6 знаків після коми", async () => {
  const p = await fuzzPoint(uuid(3), KYIV.lat, KYIV.lng, SECRET);
  assertNotEquals(p, KYIV);
  assertEquals(p.lat, Number(p.lat.toFixed(6)));
  assertEquals(p.lng, Number(p.lng.toFixed(6)));
});

Deno.test("fuzz: destinationPoint — відомі напрямки", () => {
  const north = destinationPoint(50, 30, 0, 1000);
  assert(north.lat > 50 && Math.abs(north.lng - 30) < 1e-9);
  assert(Math.abs(distanceM(50, 30, north.lat, north.lng) - 1000) < 0.01);

  const east = destinationPoint(50, 30, 90, 1000);
  assert(east.lng > 30 && Math.abs(east.lat - 50) < 1e-3);
  assert(Math.abs(distanceM(50, 30, east.lat, east.lng) - 1000) < 0.01);

  // перехід через 180-й меридіан лишає довготу в [-180, 180)
  const wrap = destinationPoint(0, 179.999, 90, 1000);
  assert(wrap.lng >= -180 && wrap.lng < 180 && wrap.lng < 0);
});
