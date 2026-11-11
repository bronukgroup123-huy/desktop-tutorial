// ============================================================================
// Тук-тук: формати фото (ADR-002). Без залежностей.
// Bucket `mushroom-photos`: приватний, до 5 МіБ, JPEG / PNG / WebP.
// ============================================================================

export type ImageFormat = "jpeg" | "png" | "webp";

export const PICKS_BUCKET = "mushroom-photos";
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5 242 880 — ліміт bucket

export const IMAGE_MIME: Record<ImageFormat, string> = {
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

export const IMAGE_EXT: Record<ImageFormat, string> = { jpeg: "jpg", png: "png", webp: "webp" };

/** Формат за `Content-Type`; інші типи — null. */
export function formatFromContentType(contentType: unknown): ImageFormat | null {
  if (typeof contentType !== "string") return null;
  const found = (Object.keys(IMAGE_MIME) as ImageFormat[]).find((f) => IMAGE_MIME[f] === contentType);
  return found ?? null;
}

/**
 * Формат зображення за magic bytes файлу.
 * JPEG: FF D8 FF | PNG: 89 50 4E 47 | WebP: 'RIFF' .... 'WEBP' (зміщення 8)
 */
export function detectImageFormatFromBytes(head: Uint8Array): ImageFormat | null {
  if (head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) {
    return "jpeg";
  }
  if (
    head.length >= 4 &&
    head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4e && head[3] === 0x47
  ) {
    return "png";
  }
  if (
    head.length >= 12 &&
    head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46 && // 'RIFF'
    head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50 // 'WEBP'
  ) {
    return "webp";
  }
  return null;
}
