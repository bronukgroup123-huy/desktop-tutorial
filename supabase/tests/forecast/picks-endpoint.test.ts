import { assertEquals, assert } from 'jsr:@std/assert';
import {
  validatePicksBody,
  detectImageFormat,
  PicksInputSchema,
} from '../../functions/_shared/forecast/picks-validate.ts';

// Handler (Deno.serve) не тестуємо — чиста валідація ізольована
// (щоб тести не тягли supabase-js через esm.sh — конвенція репо).

// Валідне base64 зображення (JPEG magic + паддінг до 100+ символів)
const JPEG_B64 = btoa('\xFF\xD8\xFF\xE0' + 'A'.repeat(200));
const PNG_B64 = btoa('\x89PNG\r\n\x1A\n' + 'A'.repeat(200));
const WEBP_B64 = btoa('RIFF' + 'A'.repeat(4) + 'WEBP' + 'A'.repeat(200));
const GIF_B64 = btoa('GIF89a' + 'A'.repeat(200));

function validBody(overrides: Record<string, unknown> = {}) {
  return {
    lat: 50.45, lng: 30.52,
    photoBase64: JPEG_B64,
    mushroomType: 'boletus_edulis',
    ...overrides,
  };
}

// ─── validatePicksBody ───────────────────────────────────────

Deno.test('validatePicksBody: валідний body → ok + input', () => {
  const r = validatePicksBody(validBody());
  assertEquals(r.ok, true);
  assert(r.input !== undefined);
  assertEquals(r.input?.lat, 50.45);
  assertEquals(r.input?.mushroomType, 'boletus_edulis');
  assertEquals(r.input?.isIndicator, false);   // default
  assertEquals(r.input?.isNegativeReport, false); // default
});

Deno.test('validatePicksBody: lat поза [-90,90] → invalid_input / 422', () => {
  const r = validatePicksBody(validBody({ lat: 91 }));
  assertEquals(r.ok, false);
  assertEquals(r.error, 'invalid_input');
  assertEquals(r.status, 422);
});

Deno.test('validatePicksBody: lng поза [-180,180] → invalid_input / 422', () => {
  const r = validatePicksBody(validBody({ lng: -181 }));
  assertEquals(r.ok, false);
  assertEquals(r.error, 'invalid_input');
});

Deno.test('validatePicksBody: photoBase64 закороткий → invalid_input', () => {
  const r = validatePicksBody(validBody({ photoBase64: 'short' }));
  assertEquals(r.ok, false);
  assertEquals(r.error, 'invalid_input');
});

Deno.test('validatePicksBody: photoBase64 не string → invalid_input', () => {
  const r = validatePicksBody(validBody({ photoBase64: 12345 }));
  assertEquals(r.ok, false);
  assertEquals(r.error, 'invalid_input');
});

Deno.test('validatePicksBody: mushroomType порожній → invalid_input', () => {
  const r = validatePicksBody(validBody({ mushroomType: '' }));
  assertEquals(r.ok, false);
  assertEquals(r.error, 'invalid_input');
});

Deno.test('validatePicksBody: GIF base64 (schema ok) → invalid_photo_format / 400', () => {
  const r = validatePicksBody(validBody({ photoBase64: GIF_B64 }));
  assertEquals(r.ok, false);
  assertEquals(r.error, 'invalid_photo_format');
  assertEquals(r.status, 400);
});

Deno.test('validatePicksBody: не-база64 → invalid_photo_format / 400', () => {
  const r = validatePicksBody(validBody({ photoBase64: '!'.repeat(120) }));
  assertEquals(r.ok, false);
  assertEquals(r.error, 'invalid_photo_format');
});

Deno.test('validatePicksBody: PNG та WebP проходять', () => {
  assertEquals(validatePicksBody(validBody({ photoBase64: PNG_B64 })).ok, true);
  assertEquals(validatePicksBody(validBody({ photoBase64: WEBP_B64 })).ok, true);
});

Deno.test('validatePicksBody: gpsAccuracy + isIndicator опційні', () => {
  const r = validatePicksBody(validBody({ gpsAccuracy: 12.5, isIndicator: true }));
  assertEquals(r.ok, true);
  assertEquals(r.input?.gpsAccuracy, 12.5);
  assertEquals(r.input?.isIndicator, true);
});

// ─── detectImageFormat ───────────────────────────────────────

Deno.test('detectImageFormat: JPEG magic → jpeg', () => {
  assertEquals(detectImageFormat(JPEG_B64), 'jpeg');
});

Deno.test('detectImageFormat: PNG magic → png', () => {
  assertEquals(detectImageFormat(PNG_B64), 'png');
});

Deno.test('detectImageFormat: WebP magic (RIFF..WEBP) → webp', () => {
  assertEquals(detectImageFormat(WEBP_B64), 'webp');
});

Deno.test('detectImageFormat: невідомий формат → null', () => {
  assertEquals(detectImageFormat(GIF_B64), null);
});

Deno.test('detectImageFormat: невалідний base64 → null', () => {
  assertEquals(detectImageFormat('!!!not-base64!!!'), null);
});

// ─── PicksInputSchema: межі розміру ──────────────────────────

Deno.test('PicksInputSchema: photoBase64 > 8M символів → reject', () => {
  const r = PicksInputSchema.safeParse(validBody({
    photoBase64: 'A'.repeat(8_000_001),
  }));
  assertEquals(r.success, false);
});
