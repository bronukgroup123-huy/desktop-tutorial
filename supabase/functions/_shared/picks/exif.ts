// ============================================================================
// Тук-тук: перевірка і вирізання метаданих фото (ADR-002, ADR-018)
//
// Спільний модуль для старого `POST /picks` (base64) і нового `POST v1-picks`.
//
//  * verifyExif — GPS у фото збігається із заявленими координатами (≤ 1 км),
//    час зйомки — не далі 24 год від опорного часу. Це лише підказка:
//    EXIF не робить точку «verified» (ADR-018 — перевіряють люди).
//  * stripImageMetadata — прибирає EXIF / XMP / IPTC / коментарі з JPEG, PNG і
//    WebP, щоб координати зйомки не потрапили до інших людей разом із фото.
//    Орієнтація JPEG зберігається (інакше портретні фото лягали б набік).
// ============================================================================

import exifr from "npm:exifr@7.1.3";
import type { ImageFormat } from "./image.ts";

export const EXIF_GPS_RADIUS_KM = 1; // максимальне відхилення GPS, км
export const EXIF_MAX_AGE_HOURS = 24; // фото не далі 24 год від опорного часу

// ─── Геометрія ──────────────────────────────────────────────────────────────

/** Градуси / хвилини / секунди → десяткові градуси. */
export function dmsToDecimal(dms: number[], ref: string): number {
  const deg = dms[0] + dms[1] / 60 + dms[2] / 3600;
  return ref === "S" || ref === "W" ? -deg : deg;
}

/** Відстань між двома точками за формулою гаверсинуса, км. */
export function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ─── Перевірка EXIF ─────────────────────────────────────────────────────────

export type ExifFailReason = "no_gps" | "gps_mismatch" | "no_datetime" | "time_mismatch";

export interface ExifCheck {
  hasExif: boolean;
  verified: boolean;
  reason?: ExifFailReason;
}

/** Розбір EXIF (інжектується в тестах). За замовчуванням — exifr. */
export type ExifParser = (buffer: Uint8Array) => Promise<unknown>;

// ihdr: false — заголовок PNG (розміри зображення) не є EXIF.
const defaultParser: ExifParser = (buffer) => exifr.parse(buffer, { tiff: true, ihdr: false });

function exifGps(exif: Record<string, unknown>): { lat: number; lng: number } | null {
  if (typeof exif.latitude === "number" && typeof exif.longitude === "number") {
    return { lat: exif.latitude, lng: exif.longitude };
  }
  const { GPSLatitude: lat, GPSLongitude: lng, GPSLatitudeRef: latRef, GPSLongitudeRef: lngRef } = exif;
  if (
    Array.isArray(lat) && lat.length === 3 && Array.isArray(lng) && lng.length === 3 &&
    typeof latRef === "string" && typeof lngRef === "string"
  ) {
    return { lat: dmsToDecimal(lat as number[], latRef), lng: dmsToDecimal(lng as number[], lngRef) };
  }
  return null;
}

/** Час зйомки. exifr повертає Date; «сирий» рядок EXIF має вигляд "2026:11:10 09:30:00". */
function exifTime(exif: Record<string, unknown>): Date | null {
  const raw = exif.DateTimeOriginal ?? exif.CreateDate ?? exif.ModifyDate ?? exif.DateTime;
  if (raw instanceof Date) return Number.isNaN(raw.getTime()) ? null : raw;
  if (typeof raw === "string") {
    const m = raw.match(/^(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
    const d = m ? new Date(`${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}Z`) : new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/**
 * Перевіряє EXIF: GPS збігається із заявленими координатами (≤ 1 км) і час зйомки —
 * не далі 24 год від `referenceTime` (для v1-picks це `captured_at`, для старого
 * `POST /picks` — поточний час).
 */
export async function verifyExif(
  buffer: Uint8Array,
  inputLat: number,
  inputLng: number,
  opts: { referenceTime?: Date; parse?: ExifParser } = {},
): Promise<ExifCheck> {
  let exif: Record<string, unknown>;
  try {
    const parsed = await (opts.parse ?? defaultParser)(buffer);
    if (!parsed || typeof parsed !== "object") return { hasExif: false, verified: false };
    exif = parsed as Record<string, unknown>;
  } catch {
    return { hasExif: false, verified: false };
  }
  if (Object.keys(exif).filter((k) => k !== "errors").length === 0) {
    return { hasExif: false, verified: false };
  }

  const gps = exifGps(exif);
  if (!gps) return { hasExif: true, verified: false, reason: "no_gps" };
  if (haversineKm(inputLat, inputLng, gps.lat, gps.lng) > EXIF_GPS_RADIUS_KM) {
    return { hasExif: true, verified: false, reason: "gps_mismatch" };
  }

  const photoTime = exifTime(exif);
  if (!photoTime) return { hasExif: true, verified: false, reason: "no_datetime" };
  const reference = opts.referenceTime ?? new Date();
  const diffHours = Math.abs(reference.getTime() - photoTime.getTime()) / 3_600_000;
  if (diffHours > EXIF_MAX_AGE_HOURS) {
    return { hasExif: true, verified: false, reason: "time_mismatch" };
  }

  return { hasExif: true, verified: true };
}

// ─── Вирізання метаданих ────────────────────────────────────────────────────

function concatBytes(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

function startsWithAscii(buffer: Uint8Array, offset: number, text: string): boolean {
  if (offset + text.length > buffer.length) return false;
  for (let i = 0; i < text.length; i++) {
    if (buffer[offset + i] !== text.charCodeAt(i)) return false;
  }
  return true;
}

/** EXIF Orientation (1..8) з TIFF-блоку або null. */
export function readExifOrientation(tiff: Uint8Array): number | null {
  if (tiff.length < 14) return null;
  const little = tiff[0] === 0x49 && tiff[1] === 0x49;
  const big = tiff[0] === 0x4d && tiff[1] === 0x4d;
  if (!little && !big) return null;
  const u16 = (o: number) => little ? tiff[o] | (tiff[o + 1] << 8) : (tiff[o] << 8) | tiff[o + 1];
  const u32 = (o: number) =>
    little
      ? (tiff[o] | (tiff[o + 1] << 8) | (tiff[o + 2] << 16) | (tiff[o + 3] << 24)) >>> 0
      : ((tiff[o] << 24) | (tiff[o + 1] << 16) | (tiff[o + 2] << 8) | tiff[o + 3]) >>> 0;
  if (u16(2) !== 42) return null;
  const ifd = u32(4);
  if (ifd + 2 > tiff.length) return null;
  const count = u16(ifd);
  for (let i = 0; i < count; i++) {
    const entry = ifd + 2 + i * 12;
    if (entry + 12 > tiff.length) return null;
    if (u16(entry) !== 0x0112) continue;
    const type = u16(entry + 2);
    const value = type === 3 ? u16(entry + 8) : type === 4 ? u32(entry + 8) : 0;
    return value >= 1 && value <= 8 ? value : null;
  }
  return null;
}

/** Мінімальний сегмент APP1 «Exif», що містить лише Orientation. */
function orientationSegment(orientation: number): Uint8Array {
  const payload = [
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00, // TIFF little-endian, IFD0 за зміщенням 8
    0x01, 0x00, // один запис
    0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, orientation, 0x00, 0x00, 0x00, // Orientation SHORT
    0x00, 0x00, 0x00, 0x00, // наступного IFD немає
  ];
  const len = payload.length + 2;
  return new Uint8Array([0xff, 0xe1, (len >> 8) & 0xff, len & 0xff, ...payload]);
}

/** Кінець стиснутих даних скану: наступний справжній маркер (не FF00, не RSTn, не заповнювач). */
function endOfScanData(buffer: Uint8Array, offset: number): number {
  let i = offset;
  while (i + 1 < buffer.length) {
    if (buffer[i] === 0xff) {
      const next = buffer[i + 1];
      if (next === 0x00 || (next >= 0xd0 && next <= 0xd7)) {
        i += 2;
        continue;
      }
      if (next !== 0xff) return i;
    }
    i++;
  }
  return buffer.length;
}

/**
 * Прибирає з JPEG усі метадані: APP1 (EXIF, XMP), APP13 (IPTC), інші APPn, коментарі
 * та все, що йде після кінця зображення. Лишає JFIF, ICC-профіль і маркер Adobe
 * (потрібні для кольору) та орієнтацію з EXIF. Не-JPEG повертає без змін.
 */
export function stripExifFromJpeg(buffer: Uint8Array): Uint8Array {
  if (buffer.length < 4 || buffer[0] !== 0xff || buffer[1] !== 0xd8) return buffer;

  const parts: Uint8Array[] = [buffer.subarray(0, 2)];
  let orientationWritten = false;
  let offset = 2;

  while (offset + 1 < buffer.length) {
    if (buffer[offset] !== 0xff) {
      // Пошкоджена структура — решту копіюємо як є, щоб не зіпсувати зображення.
      parts.push(buffer.subarray(offset));
      break;
    }
    const marker = buffer[offset + 1];
    if (marker === 0xff) { // байт-заповнювач перед маркером
      offset++;
      continue;
    }
    if (marker === 0xd9) { // EOI — кінець; усе після нього відкидаємо
      parts.push(buffer.subarray(offset, offset + 2));
      break;
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { // маркери без довжини
      parts.push(buffer.subarray(offset, offset + 2));
      offset += 2;
      continue;
    }
    if (offset + 4 > buffer.length) {
      parts.push(buffer.subarray(offset));
      break;
    }
    const segEnd = Math.min(offset + 2 + ((buffer[offset + 2] << 8) | buffer[offset + 3]), buffer.length);
    const data = offset + 4;

    if (marker === 0xda) { // SOS: заголовок + стиснуті дані до наступного маркера
      const scanEnd = endOfScanData(buffer, segEnd);
      parts.push(buffer.subarray(offset, scanEnd));
      offset = scanEnd;
      continue;
    }

    const isApp = marker >= 0xe0 && marker <= 0xef;
    const keepApp = (marker === 0xe0 && startsWithAscii(buffer, data, "JFIF\0")) ||
      (marker === 0xe2 && startsWithAscii(buffer, data, "ICC_PROFILE\0")) ||
      (marker === 0xee && startsWithAscii(buffer, data, "Adobe"));

    if (isApp && !keepApp) {
      if (marker === 0xe1 && startsWithAscii(buffer, data, "Exif\0\0") && !orientationWritten) {
        const orientation = readExifOrientation(buffer.subarray(data + 6, segEnd));
        if (orientation !== null && orientation !== 1) {
          parts.push(orientationSegment(orientation));
          orientationWritten = true;
        }
      }
    } else if (marker !== 0xfe) { // 0xFE — текстовий коментар
      parts.push(buffer.subarray(offset, segEnd));
    }
    offset = segEnd;
  }

  return concatBytes(parts);
}

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const PNG_METADATA_CHUNKS = new Set(["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]);

/** Прибирає з PNG чанки з метаданими (eXIf, текстові, tIME) і все після IEND. */
export function stripPngMetadata(buffer: Uint8Array): Uint8Array {
  if (buffer.length < 8 || PNG_SIGNATURE.some((b, i) => buffer[i] !== b)) return buffer;

  const parts: Uint8Array[] = [buffer.subarray(0, 8)];
  let offset = 8;
  while (offset + 12 <= buffer.length) {
    const length = ((buffer[offset] << 24) | (buffer[offset + 1] << 16) | (buffer[offset + 2] << 8) |
      buffer[offset + 3]) >>> 0;
    const type = String.fromCharCode(...buffer.subarray(offset + 4, offset + 8));
    const end = offset + 12 + length;
    if (end > buffer.length) { // обрізаний файл — решту лишаємо як є
      parts.push(buffer.subarray(offset));
      break;
    }
    if (!PNG_METADATA_CHUNKS.has(type)) parts.push(buffer.subarray(offset, end));
    offset = end;
    if (type === "IEND") break;
  }
  return concatBytes(parts);
}

/** Прибирає з WebP чанки EXIF і XMP та знімає відповідні прапорці у VP8X. */
export function stripWebpMetadata(buffer: Uint8Array): Uint8Array {
  if (buffer.length < 12 || !startsWithAscii(buffer, 0, "RIFF") || !startsWithAscii(buffer, 8, "WEBP")) {
    return buffer;
  }
  const u32 = (o: number) =>
    (buffer[o] | (buffer[o + 1] << 8) | (buffer[o + 2] << 16) | (buffer[o + 3] << 24)) >>> 0;
  const limit = Math.min(buffer.length, 8 + u32(4));

  const chunks: Uint8Array[] = [];
  let offset = 12;
  while (offset + 8 <= limit) {
    const size = u32(offset + 4);
    const end = Math.min(offset + 8 + size + (size & 1), limit);
    if (startsWithAscii(buffer, offset, "EXIF") || startsWithAscii(buffer, offset, "XMP ")) {
      // метадані — пропускаємо
    } else if (startsWithAscii(buffer, offset, "VP8X") && size >= 1) {
      const chunk = buffer.slice(offset, end);
      chunk[8] &= ~(0x08 | 0x04); // прапорці «є EXIF» та «є XMP»
      chunks.push(chunk);
    } else {
      chunks.push(buffer.subarray(offset, end));
    }
    offset = end;
  }

  const body = concatBytes(chunks);
  const riffSize = 4 + body.length;
  const header = new Uint8Array([
    0x52, 0x49, 0x46, 0x46, // "RIFF"
    riffSize & 0xff, (riffSize >> 8) & 0xff, (riffSize >> 16) & 0xff, (riffSize >>> 24) & 0xff,
    0x57, 0x45, 0x42, 0x50, // "WEBP"
  ]);
  return concatBytes([header, body]);
}

/** Прибирає метадані з фото відповідно до формату. */
export function stripImageMetadata(buffer: Uint8Array, format: ImageFormat): Uint8Array {
  switch (format) {
    case "jpeg":
      return stripExifFromJpeg(buffer);
    case "png":
      return stripPngMetadata(buffer);
    case "webp":
      return stripWebpMetadata(buffer);
  }
}
