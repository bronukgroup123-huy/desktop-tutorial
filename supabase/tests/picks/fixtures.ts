// Тестові зображення, зібрані побайтно (без файлів і мережі).
// JPEG з EXIF (GPS, час зйомки, орієнтація), PNG і WebP з метаданими.

const enc = new TextEncoder();

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

const u16le = (v: number) => new Uint8Array([v & 0xff, (v >> 8) & 0xff]);
const u32le = (v: number) => new Uint8Array([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >>> 24) & 0xff]);
const u16be = (v: number) => new Uint8Array([(v >> 8) & 0xff, v & 0xff]);
const u32be = (v: number) => new Uint8Array([(v >>> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);

// ─── EXIF (TIFF, little-endian) ─────────────────────────────────────────────

interface Entry { tag: number; type: number; count: number; value: Uint8Array }

const short = (tag: number, v: number): Entry => ({ tag, type: 3, count: 1, value: u16le(v) });
const long = (tag: number, v: number): Entry => ({ tag, type: 4, count: 1, value: u32le(v) });
const ascii = (tag: number, s: string): Entry => {
  const bytes = enc.encode(s + "\0");
  return { tag, type: 2, count: bytes.length, value: bytes };
};
/** Три раціональні числа: градуси, хвилини, секунди (секунди з точністю 1/10000). */
const dms = (tag: number, decimal: number): Entry => {
  const abs = Math.abs(decimal);
  const d = Math.floor(abs);
  const mFloat = (abs - d) * 60;
  const m = Math.floor(mFloat);
  const s = Math.round((mFloat - m) * 60 * 10000);
  return {
    tag,
    type: 5,
    count: 3,
    value: concat(u32le(d), u32le(1), u32le(m), u32le(1), u32le(s), u32le(10000)),
  };
};

/** Серіалізує IFD за зміщенням `offset`; значення > 4 байт кладе одразу після таблиці. */
function ifd(entries: Entry[], offset: number): Uint8Array {
  const sorted = [...entries].sort((a, b) => a.tag - b.tag);
  const tableSize = 2 + sorted.length * 12 + 4;
  let dataOffset = offset + tableSize;
  const table: Uint8Array[] = [u16le(sorted.length)];
  const data: Uint8Array[] = [];
  for (const e of sorted) {
    let valueField: Uint8Array;
    if (e.value.length <= 4) {
      valueField = new Uint8Array(4);
      valueField.set(e.value);
    } else {
      valueField = u32le(dataOffset);
      const padded = e.value.length % 2 === 0 ? e.value : concat(e.value, new Uint8Array(1));
      data.push(padded);
      dataOffset += padded.length;
    }
    table.push(u16le(e.tag), u16le(e.type), u32le(e.count), valueField);
  }
  table.push(u32le(0)); // наступного IFD немає
  return concat(...table, ...data);
}

export interface ExifOptions {
  lat?: number;
  lng?: number;
  /** Час зйомки у форматі EXIF: "2026:11:10 09:30:00". */
  dateTimeOriginal?: string;
  /** EXIF Orientation 1..8. */
  orientation?: number;
}

/** APP1-вміст «Exif\0\0» + TIFF із запитаними тегами. */
export function buildExifPayload(opts: ExifOptions): Uint8Array {
  const exifEntries: Entry[] = [];
  if (opts.dateTimeOriginal) exifEntries.push(ascii(0x9003, opts.dateTimeOriginal));
  const gpsEntries: Entry[] = [];
  if (opts.lat !== undefined && opts.lng !== undefined) {
    gpsEntries.push(
      ascii(0x0001, opts.lat >= 0 ? "N" : "S"),
      dms(0x0002, opts.lat),
      ascii(0x0003, opts.lng >= 0 ? "E" : "W"),
      dms(0x0004, opts.lng),
    );
  }

  const ifd0Count = (opts.orientation ? 1 : 0) + (exifEntries.length ? 1 : 0) + (gpsEntries.length ? 1 : 0);
  const ifd0Size = 2 + ifd0Count * 12 + 4;
  const exifOffset = 8 + ifd0Size;
  const exifBytes = exifEntries.length ? ifd(exifEntries, exifOffset) : new Uint8Array(0);
  const gpsOffset = exifOffset + exifBytes.length;
  const gpsBytes = gpsEntries.length ? ifd(gpsEntries, gpsOffset) : new Uint8Array(0);

  const ifd0Entries: Entry[] = [];
  if (opts.orientation) ifd0Entries.push(short(0x0112, opts.orientation));
  if (exifEntries.length) ifd0Entries.push(long(0x8769, exifOffset));
  if (gpsEntries.length) ifd0Entries.push(long(0x8825, gpsOffset));

  const tiff = concat(enc.encode("II"), u16le(42), u32le(8), ifd(ifd0Entries, 8), exifBytes, gpsBytes);
  return concat(enc.encode("Exif\0\0"), tiff);
}

// ─── JPEG ───────────────────────────────────────────────────────────────────

export function jpegSegment(marker: number, payload: Uint8Array): Uint8Array {
  return concat(new Uint8Array([0xff, marker]), u16be(payload.length + 2), payload);
}

export const JFIF_APP0 = jpegSegment(
  0xe0,
  concat(enc.encode("JFIF\0"), new Uint8Array([1, 1, 0, 0, 1, 0, 1, 0, 0])),
);
/** Заголовок скану + «стиснуті дані» з байт-стафінгом FF 00 і маркером рестарту. */
export const JPEG_SCAN = concat(
  jpegSegment(0xda, new Uint8Array([1, 1, 0, 0, 63, 0])),
  new Uint8Array([0x12, 0x34, 0xff, 0x00, 0xe1, 0x45, 0xff, 0xd0, 0x67, 0x89]),
);
export const JPEG_EOI = new Uint8Array([0xff, 0xd9]);
export const JPEG_SOI = new Uint8Array([0xff, 0xd8]);

/** Мінімальний JPEG: SOI, JFIF, додаткові сегменти, скан, EOI. */
export function buildJpeg(segments: Uint8Array[] = []): Uint8Array {
  return concat(JPEG_SOI, JFIF_APP0, ...segments, JPEG_SCAN, JPEG_EOI);
}

export function jpegWithExif(opts: ExifOptions): Uint8Array {
  return buildJpeg([jpegSegment(0xe1, buildExifPayload(opts))]);
}

// ─── PNG ────────────────────────────────────────────────────────────────────

export const PNG_SIGNATURE = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** PNG-чанк. CRC у тестах не перевіряється (чанки видаляються цілими) — нулі. */
export function pngChunk(type: string, data: Uint8Array): Uint8Array {
  return concat(u32be(data.length), enc.encode(type), data, new Uint8Array(4));
}

export function buildPng(extraChunks: Uint8Array[] = []): Uint8Array {
  return concat(
    PNG_SIGNATURE,
    pngChunk("IHDR", new Uint8Array(13)),
    ...extraChunks,
    pngChunk("IDAT", new Uint8Array([1, 2, 3, 4, 5])),
    pngChunk("IEND", new Uint8Array(0)),
  );
}

// ─── WebP ───────────────────────────────────────────────────────────────────

export function riffChunk(fourcc: string, data: Uint8Array): Uint8Array {
  const pad = data.length % 2 === 1 ? new Uint8Array(1) : new Uint8Array(0);
  return concat(enc.encode(fourcc), u32le(data.length), data, pad);
}

export function buildWebp(chunks: Uint8Array[]): Uint8Array {
  const body = concat(enc.encode("WEBP"), ...chunks);
  return concat(enc.encode("RIFF"), u32le(body.length), body);
}

/** VP8X-заголовок розширеного WebP з прапорцями (EXIF = 0x08, XMP = 0x04). */
export function vp8x(flags: number): Uint8Array {
  return riffChunk("VP8X", new Uint8Array([flags, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
}
