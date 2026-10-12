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

import { corsHeaders } from "../_shared/cors.ts";
import {
  requireMushroomPicker,
} from "../_shared/guardian/auth.ts";
import { withErrorHandling, Errors } from "../_shared/guardian/errors.ts";
import {
  validatePicksBody,
  detectImageFormat,
} from "../_shared/forecast/picks-validate.ts";

const BUCKET = "mushroom-photos";
const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5 MiB (bucket limit)
const MIME: Record<string, string> = {
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

/** JSON-відповідь з CORS (successResponse/errorResponse його не додають) */
function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const EXT: Record<string, string> = { jpeg: "jpg", png: "png", webp: "webp" };

Deno.serve(withErrorHandling(async (req: Request) => {
  // 1. CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    throw Errors.notFound("Method not allowed");
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
    );
  }
  const input = v.input;

  // 5. Decode base64 + size check
  let photoBuffer: Uint8Array;
  try {
    photoBuffer = Uint8Array.from(atob(input.photoBase64), (c) => c.charCodeAt(0));
  } catch {
    return jsonResponse({ error: "invalid_photo_format" }, 400);
  }
  if (photoBuffer.length > MAX_PHOTO_BYTES) {
    return jsonResponse(
      { error: "photo_too_large", message: "max 5 MiB" },
      400,
    );
  }
  const format = detectImageFormat(input.photoBase64);
  if (!format) {
    return jsonResponse({ error: "invalid_photo_format" }, 400);
  }

  // 6. Upload to Storage (service_role обходить storage RLS)
  const pickId = crypto.randomUUID();
  const photoPath = `${userId}/${pickId}.${EXT[format]}`;

  const { error: uploadErr } = await db.storage
    .from(BUCKET)
    .upload(photoPath, photoBuffer, {
      contentType: MIME[format],
      upsert: false,
    });

  if (uploadErr) {
    console.error("storage upload failed:", uploadErr);
    return jsonResponse({ error: "storage_error" }, 500);
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
      verification_status: "pending",
      is_indicator: input.isIndicator,
      is_negative: input.isNegativeReport,
    })
    .select("id, verification_status")
    .single();

  if (insertErr || !inserted) {
    // Rollback: видалити завантажене фото
    await db.storage.from(BUCKET).remove([photoPath]);
    console.error("insert failed:", insertErr);
    return jsonResponse({ error: "db_error" }, 500);
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
  );
}));
