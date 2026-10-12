import { assertEquals, assert } from 'jsr:@std/assert';
import { validateInput } from '../../functions/_shared/forecast/validate.ts';

// Handler (Deno.serve) не тестуємо — чиста валідація ізольована в validate.ts
// (щоб тести не тягли supabase-js через esm.sh — конвенція репо).

Deno.test('validateInput: lat не число → invalid_coordinates', () => {
  const r = validateInput({ lat: '50.45', lng: 30.52 });
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.error, 'invalid_coordinates');
    assertEquals(r.status, 400);
  }
});

Deno.test('validateInput: lat поза [-90,90] → invalid_coordinates', () => {
  const r = validateInput({ lat: 91, lng: 30.52 });
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.error, 'invalid_coordinates');

  const r2 = validateInput({ lat: -95, lng: 0 });
  assertEquals(r2.ok, false);
  if (!r2.ok) assertEquals(r2.error, 'invalid_coordinates');
});

Deno.test('validateInput: lng поза [-180,180] → invalid_coordinates', () => {
  const r = validateInput({ lat: 50.45, lng: 200 });
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.error, 'invalid_coordinates');
});

Deno.test('validateInput: lat = NaN → invalid_coordinates', () => {
  const r = validateInput({ lat: Number.NaN, lng: 30.52 });
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.error, 'invalid_coordinates');
});

Deno.test('validateInput: некоректний date → invalid_date', () => {
  const r = validateInput({ lat: 50.45, lng: 30.52, date: 'не дата' });
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.error, 'invalid_date');
    assertEquals(r.status, 400);
  }
});

Deno.test('validateInput: валідний body → ok + mapped input', () => {
  const r = validateInput({
    lat: 50.45, lng: 30.52,
    date: '2026-10-11',
    forestType: 'pine',
    forestConfirmed: true,
    homeRegionId: 1,
  });
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.input.lat, 50.45);
    assertEquals(r.input.lng, 30.52);
    assertEquals(r.input.date.toISOString().slice(0, 10), '2026-10-11');
    assertEquals(r.input.forestType, 'pine');
    assertEquals(r.input.forestConfirmed, true);
    assertEquals(r.input.homeRegionId, 1);
  }
});

Deno.test('validateInput: date відсутній → default now (не NaN)', () => {
  const before = Date.now();
  const r = validateInput({ lat: 50.45, lng: 30.52 });
  assertEquals(r.ok, true);
  if (r.ok) {
    assert(!Number.isNaN(r.input.date.getTime()));
    assert(r.input.date.getTime() >= before - 1000);
  }
});

Deno.test('validateInput: дефолти — forestType null, confirmed false, homeRegionId null', () => {
  const r = validateInput({ lat: 50.45, lng: 30.52, forestConfirmed: 'yes' });
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.input.forestType, null);
    assertEquals(r.input.forestConfirmed, false);  // 'yes' !== true
    assertEquals(r.input.homeRegionId, null);
  }
});

Deno.test('validateInput: homeRegionId не число → null', () => {
  const r = validateInput({ lat: 50.45, lng: 30.52, homeRegionId: '1' });
  assertEquals(r.ok, true);
  if (r.ok) assertEquals(r.input.homeRegionId, null);
});
