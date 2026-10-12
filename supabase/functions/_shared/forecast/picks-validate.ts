// ============================================================================
// Picks — чиста валідація body Edge Function /picks (group 8.6d)
//
// Без supabase-js (щоб тести не тягли @types/node — конвенція репо).
// Zod — репо-версія: deno.land/x/zod@v3.22.4 (як _shared/guardian/validation.ts).
// ============================================================================

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const PicksInputSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  gpsAccuracy: z.number().min(0).optional(),
  photoBase64: z.string().min(100).max(8_000_000), // ~6MB binary
  mushroomType: z.string().min(1).max(64),
  isIndicator: z.boolean().default(false),
  isNegativeReport: z.boolean().default(false),
  forestType: z.string().max(64).nullable().optional(),
});

export type PicksInput = z.infer<typeof PicksInputSchema>;

export interface ValidationResult {
  ok: boolean;
  input?: PicksInput;
  /** код помилки для відповіді */
  error?: string;
  /** HTTP-статус: 422 — schema, 400 — фото */
  status?: number;
  message?: string;
}

/**
 * Формат зображення по magic bytes (перші байти декодованого base64).
 * JPEG: FF D8 FF | PNG: 89 50 4E 47 | WebP: 'RIFF' .... 'WEBP' (offset 8)
 */
export function detectImageFormat(base64: string): "jpeg" | "png" | "webp" | null {
  // Декодуємо лише початку (24 символа base64 = 18 байт) — не 8M
  let head: Uint8Array;
  try {
    head = Uint8Array.from(atob(base64.slice(0, 24)), (c) => c.charCodeAt(0));
  } catch {
    return null; // невалідний base64
  }

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
    head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50  // 'WEBP'
  ) {
    return "webp";
  }
  return null;
}

/** Валідація body → PicksInput або error + HTTP-статус. */
export function validatePicksBody(body: unknown): ValidationResult {
  const parsed = PicksInputSchema.safeParse(body);
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0];
    const path = firstIssue?.path.join(".") ?? "";
    return {
      ok: false,
      error: "invalid_input",
      status: 422,
      message: path ? `${path}: ${firstIssue?.message ?? "invalid"}` : "invalid input",
    };
  }

  // Magic bytes: jpeg / png / webp
  const format = detectImageFormat(parsed.data.photoBase64);
  if (!format) {
    return {
      ok: false,
      error: "invalid_photo_format",
      status: 400,
      message: "photo must be JPEG, PNG or WebP",
    };
  }

  return { ok: true, input: parsed.data };
}
