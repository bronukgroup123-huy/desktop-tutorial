import { assert, assertEquals } from "jsr:@std/assert";
import {
  dmsToDecimal,
  haversineKm,
  readExifOrientation,
  stripExifFromJpeg,
  stripImageMetadata,
  stripPngMetadata,
  stripWebpMetadata,
  verifyExif,
} from "../../functions/_shared/picks/exif.ts";
import { detectImageFormatFromBytes, formatFromContentType } from "../../functions/_shared/picks/image.ts";
import {
  buildExifPayload,
  buildJpeg,
  buildPng,
  buildWebp,
  concat,
  JPEG_SCAN,
  jpegSegment,
  jpegWithExif,
  pngChunk,
  riffChunk,
  vp8x,
} from "./fixtures.ts";

const enc = new TextEncoder();
const KYIV = { lat: 50.4501, lng: 30.5234 };
const CAPTURED = new Date("2026-11-10T09:30:00Z");

function includesAscii(haystack: Uint8Array, needle: string): boolean {
  const n = enc.encode(needle);
  outer: for (let i = 0; i + n.length <= haystack.length; i++) {
    for (let j = 0; j < n.length; j++) if (haystack[i + j] !== n[j]) continue outer;
    return true;
  }
  return false;
}

// ─── Геометрія ──────────────────────────────────────────────────────────────

Deno.test("exif: dmsToDecimal і haversineKm", () => {
  assertEquals(dmsToDecimal([50, 30, 0], "N"), 50.5);
  assertEquals(dmsToDecimal([30, 15, 0], "W"), -30.25);
  assertEquals(dmsToDecimal([10, 0, 36], "S"), -10.01);
  assertEquals(haversineKm(50, 30, 50, 30), 0);
  // 1° широти ≈ 111.2 км
  assert(Math.abs(haversineKm(50, 30, 51, 30) - 111.19) < 0.1);
});

// ─── verifyExif (справжній exifr) ───────────────────────────────────────────

Deno.test("exif verify: GPS і час збігаються → verified", async () => {
  const jpg = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00" });
  assertEquals(
    await verifyExif(jpg, KYIV.lat, KYIV.lng, { referenceTime: CAPTURED }),
    { hasExif: true, verified: true },
  );
});

Deno.test("exif verify: GPS далі ніж 1 км → gps_mismatch", async () => {
  const jpg = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00" });
  // ~2.2 км на північ
  assertEquals(
    await verifyExif(jpg, KYIV.lat + 0.02, KYIV.lng, { referenceTime: CAPTURED }),
    { hasExif: true, verified: false, reason: "gps_mismatch" },
  );
  // ~0.5 км — у межах допуску
  assertEquals(
    (await verifyExif(jpg, KYIV.lat + 0.0045, KYIV.lng, { referenceTime: CAPTURED })).verified,
    true,
  );
});

Deno.test("exif verify: час зйомки далі 24 год від captured_at → time_mismatch (в обидва боки)", async () => {
  const jpg = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00" });
  const hours = (h: number) => new Date(CAPTURED.getTime() + h * 3_600_000);
  assertEquals((await verifyExif(jpg, KYIV.lat, KYIV.lng, { referenceTime: hours(23) })).verified, true);
  assertEquals((await verifyExif(jpg, KYIV.lat, KYIV.lng, { referenceTime: hours(-23) })).verified, true);
  assertEquals(
    await verifyExif(jpg, KYIV.lat, KYIV.lng, { referenceTime: hours(25) }),
    { hasExif: true, verified: false, reason: "time_mismatch" },
  );
  assertEquals(
    (await verifyExif(jpg, KYIV.lat, KYIV.lng, { referenceTime: hours(-25) })).reason,
    "time_mismatch",
  );
});

Deno.test("exif verify: без GPS → no_gps; без часу → no_datetime", async () => {
  const noGps = jpegWithExif({ dateTimeOriginal: "2026:11:10 09:30:00" });
  assertEquals(
    await verifyExif(noGps, KYIV.lat, KYIV.lng, { referenceTime: CAPTURED }),
    { hasExif: true, verified: false, reason: "no_gps" },
  );
  const noTime = jpegWithExif({ ...KYIV });
  assertEquals(
    await verifyExif(noTime, KYIV.lat, KYIV.lng, { referenceTime: CAPTURED }),
    { hasExif: true, verified: false, reason: "no_datetime" },
  );
});

Deno.test("exif verify: південна і західна півкулі", async () => {
  const jpg = jpegWithExif({ lat: -33.8688, lng: -151.2093, dateTimeOriginal: "2026:11:10 09:30:00" });
  assertEquals(
    (await verifyExif(jpg, -33.8688, -151.2093, { referenceTime: CAPTURED })).verified,
    true,
  );
  assertEquals(
    (await verifyExif(jpg, 33.8688, 151.2093, { referenceTime: CAPTURED })).reason,
    "gps_mismatch",
  );
});

Deno.test("exif verify: фото без EXIF, пошкоджений файл, не зображення → hasExif = false", async () => {
  const none = { hasExif: false, verified: false };
  assertEquals(await verifyExif(buildJpeg(), KYIV.lat, KYIV.lng), none);
  assertEquals(await verifyExif(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), KYIV.lat, KYIV.lng), none);
  assertEquals(await verifyExif(new Uint8Array(0), KYIV.lat, KYIV.lng), none);
  assertEquals(await verifyExif(buildPng(), KYIV.lat, KYIV.lng), none);
});

Deno.test("exif verify: за замовчуванням опорний час — зараз (старий POST /picks)", async () => {
  const pad = (n: number) => String(n).padStart(2, "0");
  const now = new Date();
  const stamp = `${now.getUTCFullYear()}:${pad(now.getUTCMonth() + 1)}:${pad(now.getUTCDate())} ` +
    `${pad(now.getUTCHours())}:${pad(now.getUTCMinutes())}:${pad(now.getUTCSeconds())}`;
  assertEquals((await verifyExif(jpegWithExif({ ...KYIV, dateTimeOriginal: stamp }), KYIV.lat, KYIV.lng)).verified, true);
  const old = jpegWithExif({ ...KYIV, dateTimeOriginal: "2020:01:01 10:00:00" });
  assertEquals((await verifyExif(old, KYIV.lat, KYIV.lng)).reason, "time_mismatch");
});

// ─── verifyExif (інжектований парсер) ───────────────────────────────────────

Deno.test("exif verify: теги у «сирому» вигляді (масиви DMS, рядок часу)", async () => {
  const parse = () =>
    Promise.resolve({
      GPSLatitude: [50, 27, 0.36],
      GPSLatitudeRef: "N",
      GPSLongitude: [30, 31, 24.24],
      GPSLongitudeRef: "E",
      CreateDate: "2026:11:10 09:30:00",
    });
  assertEquals(
    await verifyExif(new Uint8Array(1), KYIV.lat, KYIV.lng, { referenceTime: CAPTURED, parse }),
    { hasExif: true, verified: true },
  );
});

Deno.test("exif verify: помилка парсера і об'єкт лише з errors → без EXIF", async () => {
  const none = { hasExif: false, verified: false };
  const boom = () => Promise.reject(new Error("boom"));
  assertEquals(await verifyExif(new Uint8Array(1), 0, 0, { parse: boom }), none);
  const errorsOnly = () => Promise.resolve({ errors: [new Error("x")] });
  assertEquals(await verifyExif(new Uint8Array(1), 0, 0, { parse: errorsOnly }), none);
  assertEquals(await verifyExif(new Uint8Array(1), 0, 0, { parse: () => Promise.resolve(undefined) }), none);
});

// ─── Вирізання метаданих: JPEG ──────────────────────────────────────────────

Deno.test("exif strip JPEG: після вирізання немає GPS, часу і самого EXIF", async () => {
  const jpg = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00" });
  assertEquals((await verifyExif(jpg, KYIV.lat, KYIV.lng, { referenceTime: CAPTURED })).hasExif, true);

  const stripped = stripExifFromJpeg(jpg);
  assert(stripped.length < jpg.length);
  assertEquals(includesAscii(stripped, "Exif"), false);
  assertEquals(includesAscii(stripped, "2026:11:10"), false);
  assertEquals(await verifyExif(stripped, KYIV.lat, KYIV.lng), { hasExif: false, verified: false });
  // зображення лишилось цілим: без метаданих воно збігається з таким самим JPEG без EXIF
  assertEquals(stripped, buildJpeg());
  assertEquals(detectImageFormatFromBytes(stripped), "jpeg");
});

Deno.test("exif strip JPEG: орієнтація зберігається, решта EXIF — ні", async () => {
  const jpg = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00", orientation: 6 });
  const stripped = stripExifFromJpeg(jpg);

  const exif = await verifyExif(stripped, KYIV.lat, KYIV.lng, { referenceTime: CAPTURED });
  assertEquals(exif, { hasExif: true, verified: false, reason: "no_gps" }); // лишився тільки Orientation
  assertEquals(includesAscii(stripped, "2026:11:10"), false);

  // у файлі рівно один APP1 і в ньому Orientation = 6
  const app1 = stripped.findIndex((b, i) => b === 0xff && stripped[i + 1] === 0xe1);
  assert(app1 > 0);
  assertEquals(readExifOrientation(stripped.subarray(app1 + 10)), 6);

  // орієнтація 1 («як є») не потребує EXIF взагалі
  const normal = stripExifFromJpeg(jpegWithExif({ ...KYIV, orientation: 1 }));
  assertEquals(normal, buildJpeg());
});

Deno.test("exif strip JPEG: XMP, IPTC, коментарі та чужі APPn видаляються; JFIF, ICC і Adobe лишаються", () => {
  const icc = jpegSegment(0xe2, concat(enc.encode("ICC_PROFILE\0"), new Uint8Array([1, 1, 9, 9, 9])));
  const adobe = jpegSegment(0xee, concat(enc.encode("Adobe"), new Uint8Array([0, 100, 0, 0, 0, 0, 1])));
  const jpg = buildJpeg([
    jpegSegment(0xe1, enc.encode("http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>GPSLatitude=50.45</x:xmpmeta>")),
    icc,
    jpegSegment(0xe2, enc.encode("MPF\0secondary-image-index")),
    jpegSegment(0xed, enc.encode("Photoshop 3.0\0city=Kyiv")),
    adobe,
    jpegSegment(0xfe, enc.encode("comment: home address")),
    jpegSegment(0xe5, enc.encode("vendor-private")),
  ]);
  const stripped = stripExifFromJpeg(jpg);
  for (const secret of ["xmpmeta", "GPSLatitude", "MPF", "Photoshop", "Kyiv", "home address", "vendor-private"]) {
    assertEquals(includesAscii(stripped, secret), false, secret);
  }
  assertEquals(stripped, buildJpeg([icc, adobe]));
});

Deno.test("exif strip JPEG: стиснуті дані (FF 00, RST) не чіпаються; хвіст після кінця зображення відкидається", () => {
  const trailer = enc.encode("MotionPhoto_Data: secret video with GPS");
  const jpg = concat(jpegWithExif({ ...KYIV }), trailer);
  const stripped = stripExifFromJpeg(jpg);
  assertEquals(stripped, buildJpeg());
  assertEquals(includesAscii(stripped, "MotionPhoto"), false);
  // скан із байт-стафінгом FF 00 E1 і маркером рестарту зберігся побайтно
  const scanAt = stripped.length - 2 - JPEG_SCAN.length;
  assertEquals(stripped.subarray(scanAt, scanAt + JPEG_SCAN.length), JPEG_SCAN);
  assertEquals(Array.from(stripped.subarray(-2)), [0xff, 0xd9]);
});

Deno.test("exif strip JPEG: прогресивний JPEG з кількома сканами зберігається повністю", () => {
  const dht = jpegSegment(0xc4, new Uint8Array([0, 1, 2, 3]));
  const jpg = concat(
    new Uint8Array([0xff, 0xd8]),
    jpegSegment(0xe1, buildExifPayload({ ...KYIV })),
    JPEG_SCAN,
    dht,
    JPEG_SCAN,
    new Uint8Array([0xff, 0xd9]),
  );
  assertEquals(
    stripExifFromJpeg(jpg),
    concat(new Uint8Array([0xff, 0xd8]), JPEG_SCAN, dht, JPEG_SCAN, new Uint8Array([0xff, 0xd9])),
  );
});

Deno.test("exif strip JPEG: чистий, обрізаний і не-JPEG файли не ламаються", () => {
  const clean = buildJpeg();
  assertEquals(stripExifFromJpeg(clean), clean);

  const png = buildPng();
  assertEquals(stripExifFromJpeg(png), png); // не JPEG — без змін

  // обрізаний посеред сегмента EXIF: нічого не падає, EXIF у результат не потрапляє
  const truncated = jpegWithExif({ ...KYIV, dateTimeOriginal: "2026:11:10 09:30:00" }).subarray(0, 60);
  assertEquals(includesAscii(stripExifFromJpeg(truncated), "Exif"), false);

  assertEquals(stripExifFromJpeg(new Uint8Array(0)).length, 0);
  assertEquals(Array.from(stripExifFromJpeg(new Uint8Array([0xff, 0xd8, 0xff]))), [0xff, 0xd8, 0xff]);
});

Deno.test("exif: readExifOrientation — обидва порядки байтів і сміття", () => {
  const le = buildExifPayload({ orientation: 8 }).subarray(6);
  assertEquals(readExifOrientation(le), 8);
  // big-endian TIFF: "MM", 42, IFD0 @8, 1 запис Orientation = 3
  const be = new Uint8Array([
    0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, 0x00, 0x01,
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]);
  assertEquals(readExifOrientation(be), 3);
  assertEquals(readExifOrientation(buildExifPayload({ ...KYIV }).subarray(6)), null); // тега немає
  assertEquals(readExifOrientation(new Uint8Array([1, 2, 3])), null);
  assertEquals(readExifOrientation(new Uint8Array(32)), null);
});

// ─── Вирізання метаданих: PNG і WebP ────────────────────────────────────────

Deno.test("exif strip PNG: eXIf і текстові чанки видаляються, зображення лишається", () => {
  const png = concat(
    buildPng([
      pngChunk("eXIf", buildExifPayload({ ...KYIV }).subarray(6)),
      pngChunk("tEXt", enc.encode("Comment\0home address")),
      pngChunk("iTXt", enc.encode("XML:com.adobe.xmp\0\0\0\0\0<x:xmpmeta/>")),
      pngChunk("tIME", new Uint8Array(7)),
      pngChunk("gAMA", new Uint8Array(4)),
    ]),
    enc.encode("trailing secret"),
  );
  const stripped = stripPngMetadata(png);
  assertEquals(stripped, buildPng([pngChunk("gAMA", new Uint8Array(4))]));
  for (const secret of ["eXIf", "home address", "xmpmeta", "tIME", "trailing"]) {
    assertEquals(includesAscii(stripped, secret), false, secret);
  }
  assertEquals(detectImageFormatFromBytes(stripped), "png");

  const clean = buildPng();
  assertEquals(stripPngMetadata(clean), clean);
  const jpg = buildJpeg();
  assertEquals(stripPngMetadata(jpg), jpg); // не PNG — без змін
});

Deno.test("exif strip WebP: чанки EXIF і XMP видаляються, прапорці VP8X знімаються, розмір RIFF оновлюється", () => {
  const image = riffChunk("VP8 ", new Uint8Array([1, 2, 3, 4, 5])); // непарна довжина → доповнення
  const alpha = riffChunk("ALPH", new Uint8Array([9, 9]));
  const webp = buildWebp([
    vp8x(0x08 | 0x04 | 0x10), // EXIF + XMP + альфа
    alpha,
    image,
    riffChunk("EXIF", buildExifPayload({ ...KYIV })),
    riffChunk("XMP ", enc.encode("<x:xmpmeta>GPS</x:xmpmeta>")),
  ]);
  const stripped = stripWebpMetadata(webp);
  assertEquals(stripped, buildWebp([vp8x(0x10), alpha, image]));
  assertEquals(includesAscii(stripped, "Exif"), false);
  assertEquals(includesAscii(stripped, "xmpmeta"), false);
  assertEquals(detectImageFormatFromBytes(stripped), "webp");

  // простий WebP без метаданих не змінюється
  const simple = buildWebp([image]);
  assertEquals(stripWebpMetadata(simple), simple);
  const jpg = buildJpeg();
  assertEquals(stripWebpMetadata(jpg), jpg); // не WebP — без змін
});

Deno.test("exif: stripImageMetadata обирає алгоритм за форматом", () => {
  assertEquals(stripImageMetadata(jpegWithExif({ ...KYIV }), "jpeg"), buildJpeg());
  assertEquals(stripImageMetadata(buildPng([pngChunk("tEXt", enc.encode("a\0b"))]), "png"), buildPng());
  const image = riffChunk("VP8 ", new Uint8Array([1, 2]));
  assertEquals(
    stripImageMetadata(buildWebp([vp8x(0x08), image, riffChunk("EXIF", new Uint8Array(4))]), "webp"),
    buildWebp([vp8x(0), image]),
  );
});

// ─── Формати ────────────────────────────────────────────────────────────────

Deno.test("image: формат за magic bytes і Content-Type", () => {
  assertEquals(detectImageFormatFromBytes(buildJpeg()), "jpeg");
  assertEquals(detectImageFormatFromBytes(buildPng()), "png");
  assertEquals(detectImageFormatFromBytes(buildWebp([])), "webp");
  assertEquals(detectImageFormatFromBytes(enc.encode("GIF89a........")), null);
  assertEquals(detectImageFormatFromBytes(enc.encode("<html><script>")), null);
  assertEquals(detectImageFormatFromBytes(new Uint8Array(0)), null);

  assertEquals(formatFromContentType("image/jpeg"), "jpeg");
  assertEquals(formatFromContentType("image/png"), "png");
  assertEquals(formatFromContentType("image/webp"), "webp");
  assertEquals(formatFromContentType("image/gif"), null);
  assertEquals(formatFromContentType("application/pdf"), null);
  assertEquals(formatFromContentType(undefined), null);
});
