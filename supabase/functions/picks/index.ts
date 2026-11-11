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
// CORS як forecast/index.ts.
//
// Це старий ендпоінт веб-прототипу (фото як base64). Він пише лише приватні точки.
// Flutter використовує v1-picks (Signed Upload URL, ADR-002 / ADR-018).
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
import { checkAndIncrementIpRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts";
// EXIF-логіка спільна з v1-picks (BACKEND_PLAN B3.1).
import { stripImageMetadata, verifyExif } from "../_shared/picks/exif.ts";
import {
  IMAGE_EXT as EXT,
  IMAGE_MIME as MIME,
  MAX_PHOTO_BYTES,
  PICKS_BUCKET as BUCKET,
} from "../_shared/picks/image.ts";

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

  // 5b. CT-13: перевірка EXIF. Вона не робить точку «verified» (ADR-018: підтверджують
  //     люди): збіг GPS і часу → pending, немає EXIF або розбіжність → conditional.
  const exifResult = await verifyExif(photoBuffer, input.lat, input.lng);
  const verificationStatus: "pending" | "conditional" = exifResult.verified ? "pending" : "conditional";
  if (exifResult.hasExif && !exifResult.verified) {
    console.warn(`EXIF verify failed for pick: ${exifResult.reason}`);
  }

  // 5c. Вирізати EXIF перед відправкою в Storage (захист приватності)
  const bufferToUpload = stripImageMetadata(photoBuffer, format);

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
