// ============================================================================
// Edge Function: v1-picks — «Тук-тук» (BACKEND_PLAN B3.0 + B3.1; ADR-002, ADR-018)
// POST /functions/v1/v1-picks/upload-url  { client_id, content_type, size_bytes }
// POST /functions/v1/v1-picks             { client_id, path, lat, lng, captured_at,
//                                           visibility, species_id, description?, ai_check? }
// GET  /functions/v1/v1-picks/map?bbox=&mine=   точки для карти Home Region (B3.3)
// GET  /functions/v1/v1-picks/{id}              картка точки (B3.3)
//
// JWT обов'язковий (гість має JWT — ADR-001; гість створює лише приватні точки).
// Фото — тільки через Signed Upload URL, без base64. Логіка — `_shared/v1/picks.ts`.
// ============================================================================

import { handle, HttpError, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { PICKS_BUCKET } from "../_shared/picks/image.ts";
import { handlePicks, type PicksStorage } from "../_shared/v1/picks.ts";

/**
 * Секрет для зсуву публічних точок. Окремий `PICK_FUZZ_SECRET` необов'язковий:
 * без нього використовується ключ service_role, якого клієнти ніколи не бачать.
 */
function fuzzSecret(): string {
  const secret = Deno.env.get("PICK_FUZZ_SECRET") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret) throw new HttpError(500, "internal_error", "Сервер неправильно налаштований");
  return secret;
}

Deno.serve(handle((req) => {
  const db = serviceClient();
  const bucket = db.storage.from(PICKS_BUCKET);
  const storage: PicksStorage = {
    createSignedUploadUrl: (path, options) => bucket.createSignedUploadUrl(path, options),
    download: (path) => bucket.download(path),
    upload: (path, body, options) => bucket.upload(path, body, options),
    remove: (paths) => bucket.remove(paths),
    createSignedUrl: (path, expiresIn) => bucket.createSignedUrl(path, expiresIn),
  };
  return handlePicks(req, { db, storage, verify: supabaseTokenVerifier, fuzzSecret: fuzzSecret() });
}));
