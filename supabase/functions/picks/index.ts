// ============================================================================
// Edge Function: picks (group 8.6d)
// POST / — створити знахідку (мухомор-репорт): auth → validate → upload →
// insert mushroom_picks → 201.
//
// Статуси:
//   204 OPTIONS | 404 не-POST | 401 auth | 422 invalid_json / schema |
//   400 photo_format / photo_too_large | 500 storage_error / db_error
//
// Патерн: guardian (withErrorHandling + requireMushroomPicker) +
// CORS як forecast/index.ts. EXIF-верифікація та rate-limit → V2
// (клієнт ре-компресить фото перед upload).
// ============================================================================

import { buildCorsHeaders } from "../_shared/cors.ts";
import {
  requireMushroomPicker,
} from "../_shared/guardian/auth.ts";
import { withErrorHandling, Errors } from "../_shared/guardian/errors.ts";
import {
  validatePicksBody,
  detectImageFormat,
} from "../_shared/forecast/picks-validate.ts";
import { handlePicksListRequest } from "../_shared/forecast/picks-list.ts";
import type { PicksListDbClient } from "../_shared/forecast/picks-list.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import exifr from "npm:exifr";
import { checkAndIncrementIpRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts";

const BUCKET = "mushroom-photos";
const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5 MiB (bucket limit)
const MIME: Record<string, string> = {
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

// ─── CT-13: EXIF server-verify constants ──────────────────────────────────
const EXIF_GPS_RADIUS_KM = 1;      // максимальна відхилнність GPS, км
const EXIF_MAX_AGE_HOURS = 24;     // фото не старіше 24 годин

interface ExifParsed {
  GPSLatitude?: number[];
  GPSLongitude?: number[];
  GPSLatitudeRef?: string;
  GPSLongitudeRef?: string;
  DateTime?: string;
  [key: string]: unknown;
}

/** Д秒/минути/секунди → десяткові ступені */
function dmsToDecimal(dms: number[], ref: string): number {
  const deg = dms[0] + dms[1] / 60 + dms[2] / 3600;
  return ref === "S" || ref === "W" ? -deg : deg;
}

/** Відстань Хаверсина між двома точками (км) */
function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Перевіряє EXIF зображення: GPS збігається з координатами запиту
 * (радіус 1 км) і час створення фото не старший за 24 години.
 * Повертає { hasExif, verified, reason }.
 */
async function verifyExif(
  buffer: Uint8Array,
  inputLat: number,
  inputLng: number
): Promise<{ hasExif: boolean; verified: boolean; reason?: string }> {
  try {
    const exif = (await exifr.parse(buffer, {
      tiff: true,
    })) as ExifParsed;

    if (!exif || Object.keys(exif).length === 0) {
      return { hasExif: false, verified: false };
    }

    // GPS перевірка
    const gpsLat = exif.GPSLatitude;
    const gpsLng = exif.GPSLongitude;
    const gpsLatRef = exif.GPSLatitudeRef;
    const gpsLngRef = exif.GPSLongitudeRef;

    if (!gpsLat || !gpsLng || !gpsLatRef || !gpsLngRef) {
      return { hasExif: true, verified: false, reason: "No GPS in EXIF" };
    }

    const lat = dmsToDecimal(gpsLat, gpsLatRef);
    const lng = dmsToDecimal(gpsLng, gpsLngRef);
    const distance = haversineKm(inputLat, inputLng, lat, lng);

    if (distance > EXIF_GPS_RADIUS_KM) {
      return {
        hasExif: true,
        verified: false,
        reason: `GPS mismatch: ${distance.toFixed(1)} km from declared location`,
      };
    }

    // Часова перевірка
    const dateTime = exif.DateTime;
    if (!dateTime) {
      return { hasExif: true, verified: false, reason: "No DateTime in EXIF" };
    }

    const photoTime = new Date(String(dateTime));
    const now = new Date();
    const diffHours = (now.getTime() - photoTime.getTime()) / (1000 * 60 * 60);

    if (diffHours > EXIF_MAX_AGE_HOURS) {
      return {
        hasExif: true,
        verified: false,
        reason: `Photo too old: ${diffHours.toFixed(1)} hours`,
      };
    }

    return { hasExif: true, verified: true };
  } catch {
    return { hasExif: false, verified: false };
  }
}

/**
 * Вирізає EXIF (APP1 сегмент) з JPEG буфера.
 * Для інших форматів повертає буфер без змін.
 */
function stripExifFromJpeg(buffer: Uint8Array): Uint8Array {
  const result: number[] = [];
  let offset = 0;

  while (offset < buffer.length - 1) {
    const marker = (buffer[offset] << 8) | buffer[offset + 1];

    if (marker === 0xffd8) {
      // SOI
      result.push(buffer[offset], buffer[offset + 1]);
      offset += 2;
    } else if (marker === 0xffd9) {
      // EOI
      result.push(buffer[offset], buffer[offset + 1]);
      break;
    } else if ((marker & 0xff00) === 0xff00) {
      const segLen = (buffer[offset + 2] << 8) | buffer[offset + 3];
      const segEnd = offset + 2 + segLen;

      // APP1 з Exif заголовком — пропускаємо (вирізаємо)
      if (
        marker === 0xffe1 &&
        offset + 10 < buffer.length &&
        String.fromCharCode(...buffer.slice(offset + 4, offset + 10)) ===
          "Exif\0\0"
      ) {
        offset = segEnd;
        continue;
      }

      for (let i = offset; i < Math.min(segEnd, buffer.length); i++) {
        result.push(buffer[i]);
      }
      offset = segEnd;
    } else {
      result.push(buffer[offset]);
      offset++;
    }
  }

  return new Uint8Array(result);
}

/** JSON-відповідь з CORS (successResponse/errorResponse його не додають) */
function jsonResponse(data: unknown, status: number, req: Request): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...buildCorsHeaders(req), "Content-Type": "application/json" },
  });
}

/**
 * Клієнти для GET /picks (group 9.4):
 *   readDb  — anon-key + JWT → RLS mushroom_picks_read enforced
 *   adminDb — service_role → enrichment (users/regions/catalog/signed URLs)
 * userId — null для аноніма або невалідного токена (mine/friends → 401).
 */
async function createPicksListClients(req: Request): Promise<{
  readDb: PicksListDbClient;
  adminDb: PicksListDbClient;
  userId: string | null;
}> {
  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  const bearer =
    authHeader && authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length)
      : null;

  const readDb = createClient(url, anonKey, {
    global: bearer ? { headers: { Authorization: `Bearer ${bearer}` } } : {},
    auth: { persistSession: false, autoRefreshToken: false },
  }) as unknown as PicksListDbClient;

  const adminDb = createClient(url, serviceKey, {
    auth: { persistSession: false },
  }) as unknown as PicksListDbClient;

  let userId: string | null = null;
  if (bearer) {
    const authClient = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${bearer}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data } = await authClient.auth.getUser(bearer);
    if (data.user) userId = data.user.id;
  }

  return { readDb, adminDb, userId };
}

const EXT: Record<string, string> = { jpeg: "jpg", png: "png", webp: "webp" };

Deno.serve(withErrorHandling(async (req: Request) => {
  // 1. CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
  }

  // 1b. GET — стрічка трофеїв (group 9.4); POST — існуючий handler нижче
  if (req.method === "GET") {
    const { readDb, adminDb, userId } = await createPicksListClients(req);
    return handlePicksListRequest(readDb, adminDb, userId, req);
  }

  if (req.method !== "POST") {
    throw Errors.notFound("Method not allowed");
  }

  // 2b. CT-14: Rate limit per-IP (10 req/min for /picks)
  const ip = getClientIp(req);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return jsonResponse({ error: "internal_error" }, 500, req);
  }
  const rlDb = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const rl = await checkAndIncrementIpRateLimit(rlDb, ip, "picks");
  if (!rl.allowed) {
    return rateLimitResponse(req, rl.retryAfter ?? 60);
  }

  // 2. Auth — JWT → userId + service_role db
  const { userId, db } = await requireMushroomPicker(req);

  // 3. Parse body
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw Errors.validation("invalid_json");
  }

  // 4. Validate (schema + magic bytes)
  const v = validatePicksBody(body);
  if (!v.ok || !v.input) {
    return jsonResponse(
      { error: v.error, message: v.message },
      v.status ?? 400,
      req,
    );
  }
  const input = v.input;

  // 5. Decode base64 + size check
  let photoBuffer: Uint8Array;
  try {
    photoBuffer = Uint8Array.from(atob(input.photoBase64), (c) => c.charCodeAt(0));
  } catch {
    return jsonResponse({ error: "invalid_photo_format" }, 400, req);
  }
  if (photoBuffer.length > MAX_PHOTO_BYTES) {
    return jsonResponse(
      { error: "photo_too_large", message: "max 5 MiB" },
      400,
      req,
    );
  }
  const format = detectImageFormat(input.photoBase64);
  if (!format) {
    return jsonResponse({ error: "invalid_photo_format" }, 400, req);
  }

  // 5b. CT-13: EXIF server-verify
  const exifResult = await verifyExif(photoBuffer, input.lat, input.lng);
  let verificationStatus: "pending" | "verified" | "conditional" = "pending";
  if (!exifResult.hasExif) {
    // EXIF відсутній (галерея Flutter тощо) — conditional
    verificationStatus = "conditional";
  } else if (exifResult.verified) {
    verificationStatus = "verified";
  } else {
    // EXIF є, але не пройшов перевірку — conditional, не rejected
    verificationStatus = "conditional";
    console.warn(`EXIF verify failed for pick: ${exifResult.reason}`);
  }

  // 5c. Вирізати EXIF перед відправкою в Storage (захист приватності)
  const bufferToUpload =
    format === "jpeg" ? stripExifFromJpeg(photoBuffer) : photoBuffer;

  // 6. Upload to Storage (service_role обходить storage RLS)
  const pickId = crypto.randomUUID();
  const photoPath = `${userId}/${pickId}.${EXT[format]}`;

  const { error: uploadErr } = await db.storage
    .from(BUCKET)
    .upload(photoPath, bufferToUpload, {
      contentType: MIME[format],
      upsert: false,
    });

  if (uploadErr) {
    console.error("storage upload failed:", uploadErr);
    return jsonResponse({ error: "storage_error" }, 500, req);
  }

  // 7. Insert into mushroom_picks (geom — EWKT для PostGIS geography)
  const { data: inserted, error: insertErr } = await db
    .from("mushroom_picks")
    .insert({
      id: pickId,
      user_id: userId,
      geom: `SRID=4326;POINT(${input.lng} ${input.lat})`,
      photo_url: photoPath, // path у bucket, не public URL
      mushroom_type: input.mushroomType,
      forest_type: input.forestType ?? null,
      weather_data: input.gpsAccuracy != null
        ? { gpsAccuracy: input.gpsAccuracy }
        : null,
      pick_type: "private",
      verification_status: verificationStatus,
      is_indicator: input.isIndicator,
      is_negative: input.isNegativeReport,
    })
    .select("id, verification_status")
    .single();

  if (insertErr || !inserted) {
    // Rollback: видалити завантажене фото
    await db.storage.from(BUCKET).remove([photoPath]);
    console.error("insert failed:", insertErr);
    return jsonResponse({ error: "db_error" }, 500, req);
  }

  // 8. Response 201 (форма { data: ... } як successResponse, + CORS)
  return jsonResponse(
    {
      data: {
        id: inserted.id,
        verificationStatus: inserted.verification_status,
      },
    },
    201,
    req,
  );
}));
