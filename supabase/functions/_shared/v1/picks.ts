// ============================================================================
// v1-picks — «Тук-тук» (BACKEND_PLAN B3.0 + B3.1; ADR-002, ADR-018)
//
// POST v1-picks/upload-url  { client_id, content_type, size_bytes }
//   → 200 { data: { upload_url, path, token, expires_at } }
// POST v1-picks             { client_id, path, lat, lng, captured_at, visibility,
//                             species_id, description?, ai_check? }
//   → 201 { data: { id, visibility, status_label, marker_color } }   (повтор → 200)
// GET  v1-picks/map?bbox=&mine=   — точки для карти (B3.3, `picks-map.ts`)
// GET  v1-picks/{id}              — картка точки (B3.3, `picks-map.ts`)
// PATCH v1-picks/{id}  { visibility?, description? } — змінити свою точку (B3.4)
//   → 200 { data: { id, visibility, status_label, marker_color, description } }
// DELETE v1-picks/{id}            — видалити свою точку (soft delete, B3.4) → 200 { data: { deleted: true } }
// GET  v1-picks/species           — список видів для вибору назви (`picks-map.ts`)
//
// Потік клієнта: (1) upload-url → (2) PUT файлу за upload_url → (3) створення точки.
// Фото ніколи не передається як base64. `client_id` — ключ ідемпотентності обох кроків.
//
// Безпека фото: клієнт завантажує файл у «чернетку» `<user_id>/<client_id>.<ext>`.
// Сервер перевіряє його, вирізає метадані й записує очищену копію в `picks/<id>.<ext>` —
// теку, куди клієнти писати не можуть, — а чернетку видаляє. Тому повторне завантаження
// за старим посиланням не поверне у фото EXIF і не підмінить знімок після перевірки.
//
// Залежності (db, storage, verify, now) інжектуються — логіка тестується без мережі.
// ============================================================================

import {
  assertMethod,
  assertRegistered,
  type AuthUser,
  enforceRateLimit,
  HttpError,
  loadHomeRegionId,
  ok,
  readJson,
  requireHomeRegion,
  requireUser,
  type TokenVerifier,
} from "../http.ts";
import { type ExifCheck, type ExifParser, stripImageMetadata, verifyExif } from "../picks/exif.ts";
import { fuzzPoint } from "../picks/fuzz.ts";
import {
  detectImageFormatFromBytes,
  formatFromContentType,
  IMAGE_EXT,
  IMAGE_MIME,
  MAX_PHOTO_BYTES,
} from "../picks/image.ts";
import { type PickPresentation, pickPresentation } from "../picks/presentation.ts";
import { cleanDescription, DESCRIPTION_MAX_LENGTH } from "../picks/text.ts";
import { handlePickCard, handlePickSpecies, handlePicksMap } from "./picks-map.ts";

export { type PickPresentation, pickPresentation };

// ─── Константи ─────────────────────────────────────────────────────────────

/** Тека з перевіреними фото точок. Клієнтські політики Storage її не покривають. */
export const FINAL_PHOTO_PREFIX = "picks";
/** Storage видає посилання для завантаження на 2 години. */
export const UPLOAD_URL_TTL_MS = 2 * 60 * 60 * 1000;
/** Допуск на неточний годинник телефона для `captured_at`. */
export const CAPTURED_AT_MAX_FUTURE_MS = 24 * 60 * 60 * 1000;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UPLOAD_PATH_RE = /^([0-9a-f-]{36})\/([0-9a-f-]{36})\.(jpg|png|webp)$/i;
const AI_LEVELS = ["high", "medium", "low"] as const;
const AI_TOP_MAX = 5;

export type Visibility = "private" | "public";

interface PickRow {
  id: string;
  pick_type: string;
  verification_status: string;
}

function pickResponse(row: PickRow): Record<string, unknown> {
  return {
    id: row.id,
    visibility: row.pick_type,
    ...pickPresentation(row.pick_type, row.verification_status),
  };
}

// ─── Залежності ────────────────────────────────────────────────────────────

export interface PicksDb {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(fn: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

/** Операції з bucket `mushroom-photos` (сумісно з `supabase.storage.from(bucket)`). */
export interface PicksStorage {
  createSignedUploadUrl(
    path: string,
    options: { upsert: boolean },
  ): PromiseLike<{ data: { signedUrl: string; token: string; path: string } | null; error: unknown }>;
  download(path: string): PromiseLike<{ data: Blob | null; error: unknown }>;
  upload(
    path: string,
    body: Uint8Array,
    options: { contentType: string; upsert: boolean },
  ): PromiseLike<{ data: unknown; error: unknown }>;
  remove(paths: string[]): PromiseLike<{ data: unknown; error: unknown }>;
  /** Тимчасове посилання на перегляд фото (картка точки). */
  createSignedUrl(
    path: string,
    expiresIn: number,
  ): PromiseLike<{ data: { signedUrl: string } | null; error: unknown }>;
}

export interface PicksDeps {
  db: PicksDb;
  storage: PicksStorage;
  verify: TokenVerifier;
  /** Серверний секрет для зсуву публічної точки (див. `_shared/picks/fuzz.ts`). */
  fuzzSecret: string;
  now?: () => Date;
  newId?: () => string;
  parseExif?: ExifParser;
}

function validationError(message: string): HttpError {
  return new HttpError(422, "validation_error", message);
}

function dbFail(what: string, error: unknown): never {
  console.error(`[v1-picks] ${what} failed:`, error);
  throw new HttpError(500, "db_error", "Помилка бази даних");
}

function storageFail(what: string, error: unknown): never {
  console.error(`[v1-picks] storage ${what} failed:`, error);
  throw new HttpError(500, "storage_error", "Не вдалося обробити фото. Спробуйте ще раз.");
}

function asObject(body: unknown): Record<string, unknown> {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw validationError("Тіло запиту має бути JSON-об'єктом");
  }
  return body as Record<string, unknown>;
}

function parseClientId(value: unknown): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw validationError("client_id має бути UUID");
  }
  return value.toLowerCase();
}

// ─── B3.0: POST v1-picks/upload-url ────────────────────────────────────────

export interface UploadUrlInput {
  clientId: string;
  format: "jpeg" | "png" | "webp";
  sizeBytes: number;
}

export function validateUploadUrlBody(body: unknown): UploadUrlInput {
  const obj = asObject(body);
  const clientId = parseClientId(obj.client_id);

  const format = formatFromContentType(obj.content_type);
  if (!format) {
    throw new HttpError(400, "invalid_photo_format", "Фото має бути у форматі JPEG, PNG або WebP");
  }
  if (typeof obj.size_bytes !== "number" || !Number.isInteger(obj.size_bytes) || obj.size_bytes <= 0) {
    throw validationError("size_bytes має бути цілим числом байтів");
  }
  if (obj.size_bytes > MAX_PHOTO_BYTES) {
    throw new HttpError(400, "photo_too_large", "Фото завелике — максимум 5 МБ");
  }
  return { clientId, format, sizeBytes: obj.size_bytes };
}

/** Шлях «чернетки» фото: власна тека користувача + client_id. */
export function uploadPath(userId: string, clientId: string, format: "jpeg" | "png" | "webp"): string {
  return `${userId}/${clientId}.${IMAGE_EXT[format]}`;
}

/** Час дії посилання: `exp` із токена Storage, інакше — 2 години від зараз. */
export function uploadUrlExpiresAt(token: string, now: Date): string {
  try {
    const payload = token.split(".")[1];
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    const exp = (JSON.parse(json) as { exp?: unknown }).exp;
    if (typeof exp === "number" && Number.isFinite(exp)) return new Date(exp * 1000).toISOString();
  } catch {
    // токен не у форматі JWT — беремо типовий термін дії
  }
  return new Date(now.getTime() + UPLOAD_URL_TTL_MS).toISOString();
}

async function createUploadUrl(
  req: Request,
  user: AuthUser,
  deps: PicksDeps,
  now: Date,
): Promise<Response> {
  requireHomeRegion(await loadHomeRegionId(deps.db, user.id));
  const input = validateUploadUrlBody(await readJson(req));

  const path = uploadPath(user.id, input.clientId, input.format);
  // upsert: повторний запит із тим самим client_id дає нове посилання на той самий шлях.
  const { data, error } = await deps.storage.createSignedUploadUrl(path, { upsert: true });
  if (error || !data) storageFail("createSignedUploadUrl", error);

  return ok({
    upload_url: data.signedUrl,
    path,
    token: data.token,
    expires_at: uploadUrlExpiresAt(data.token, now),
  }, req);
}

// ─── B3.1: POST v1-picks ───────────────────────────────────────────────────

export interface AiCheck {
  model_version: string;
  top: Array<{ species_id: string; level: (typeof AI_LEVELS)[number] }>;
  match: boolean;
  twin_alert: boolean;
}

export interface CreatePickInput {
  clientId: string;
  path: string;
  pathUserId: string;
  lat: number;
  lng: number;
  capturedAt: Date;
  visibility: Visibility;
  speciesId: string | null;
  description: string | null;
  aiCheck: AiCheck | null;
  /** Відповідь знахідкою на чужу публічну точку (B3.8, ADR-019 §19.5) — id цієї точки. */
  replyTo?: string | null;
  /** Телефон повідомив, що місце підмінене програмою (Android: mock location) — B3.8b. */
  locationMocked?: boolean | null;
}

/** Підказка ШІ з телефону: лише відомі поля, рівні — словами (жодних відсотків). */
export function validateAiCheck(value: unknown): AiCheck | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw validationError("ai_check має бути об'єктом");
  }
  const obj = value as Record<string, unknown>;
  if (typeof obj.model_version !== "string" || obj.model_version.length < 1 || obj.model_version.length > 64) {
    throw validationError("ai_check.model_version — рядок до 64 символів");
  }
  if (!Array.isArray(obj.top) || obj.top.length > AI_TOP_MAX) {
    throw validationError(`ai_check.top — список до ${AI_TOP_MAX} видів`);
  }
  const top = obj.top.map((item) => {
    const t = (item ?? {}) as Record<string, unknown>;
    if (typeof t.species_id !== "string" || t.species_id.length < 1 || t.species_id.length > 64) {
      throw validationError("ai_check.top[].species_id — id виду з довідника");
    }
    if (typeof t.level !== "string" || !(AI_LEVELS as readonly string[]).includes(t.level)) {
      throw validationError("ai_check.top[].level — high, medium або low (без відсотків)");
    }
    return { species_id: t.species_id, level: t.level as (typeof AI_LEVELS)[number] };
  });
  if (typeof obj.match !== "boolean" || typeof obj.twin_alert !== "boolean") {
    throw validationError("ai_check.match і ai_check.twin_alert — true або false");
  }
  return { model_version: obj.model_version, top, match: obj.match, twin_alert: obj.twin_alert };
}

export function validateCreateBody(body: unknown, now: Date): CreatePickInput {
  const obj = asObject(body);
  const clientId = parseClientId(obj.client_id);

  const pathMatch = typeof obj.path === "string" ? obj.path.match(UPLOAD_PATH_RE) : null;
  if (!pathMatch) {
    throw validationError("path — шлях до фото з відповіді upload-url");
  }
  if (pathMatch[2].toLowerCase() !== clientId) {
    throw validationError("path не відповідає client_id — візьміть path із відповіді upload-url");
  }

  if (typeof obj.lat !== "number" || !Number.isFinite(obj.lat) || obj.lat < -90 || obj.lat > 90) {
    throw validationError("lat — широта від -90 до 90");
  }
  if (typeof obj.lng !== "number" || !Number.isFinite(obj.lng) || obj.lng < -180 || obj.lng > 180) {
    throw validationError("lng — довгота від -180 до 180");
  }

  const capturedAt = typeof obj.captured_at === "string" ? new Date(obj.captured_at) : null;
  if (!capturedAt || Number.isNaN(capturedAt.getTime()) || !/^\d{4}-\d{2}-\d{2}T/.test(obj.captured_at as string)) {
    throw validationError("captured_at — час зйомки у форматі ISO 8601");
  }
  if (capturedAt.getTime() > now.getTime() + CAPTURED_AT_MAX_FUTURE_MS) {
    throw validationError("captured_at не може бути в майбутньому — перевірте час на телефоні");
  }

  if (obj.visibility !== "private" && obj.visibility !== "public") {
    throw validationError("visibility — private або public");
  }

  let speciesId: string | null = null;
  if (obj.species_id !== undefined && obj.species_id !== null) {
    if (typeof obj.species_id !== "string" || obj.species_id.length < 1 || obj.species_id.length > 64) {
      throw validationError("species_id — id виду з довідника або null («Не знаю»)");
    }
    speciesId = obj.species_id;
  }

  const description = cleanDescription(obj.description);
  if (!description.ok) {
    throw validationError(
      description.reason === "too_long"
        ? `Опис — до ${DESCRIPTION_MAX_LENGTH} символів`
        : "description — текст або null",
    );
  }

  let replyTo: string | null = null;
  if (obj.reply_to !== undefined && obj.reply_to !== null) {
    if (typeof obj.reply_to !== "string" || !UUID_RE.test(obj.reply_to)) {
      throw validationError("reply_to — id точки, яку підтверджуєте своєю знахідкою");
    }
    if (obj.visibility !== "public") {
      throw validationError("Відповідь знахідкою — лише публічна точка");
    }
    replyTo = obj.reply_to.toLowerCase();
  }

  if (obj.location_mocked !== undefined && obj.location_mocked !== null && typeof obj.location_mocked !== "boolean") {
    throw validationError("location_mocked — true або false");
  }

  return {
    replyTo,
    locationMocked: typeof obj.location_mocked === "boolean" ? obj.location_mocked : null,
    clientId,
    path: (obj.path as string).toLowerCase(),
    pathUserId: pathMatch[1].toLowerCase(),
    lat: obj.lat,
    lng: obj.lng,
    capturedAt,
    visibility: obj.visibility,
    speciesId,
    description: description.text,
    aiCheck: validateAiCheck(obj.ai_check),
  };
}

async function findExistingPick(db: PicksDb, userId: string, clientId: string): Promise<PickRow | null> {
  const { data, error } = await db
    .from("mushroom_picks")
    .select("id, pick_type, verification_status")
    .eq("user_id", userId)
    .eq("client_id", clientId)
    .maybeSingle();
  if (error) dbFail("mushroom_picks select", error);
  return (data as PickRow | null) ?? null;
}

async function assertInHomeRegion(db: PicksDb, userId: string, lat: number, lng: number): Promise<void> {
  const regionId = requireHomeRegion(await loadHomeRegionId(db, userId));
  const { data, error } = await db.rpc("point_in_region", { lat, lng, region_id: regionId });
  if (error) dbFail("point_in_region", error);
  if (data !== true) {
    throw new HttpError(
      403,
      "outside_home_region",
      "Точка поза вашою областю. Тук-тук можна створити лише у своїй області.",
    );
  }
}

async function assertSpecies(db: PicksDb, input: CreatePickInput): Promise<void> {
  if (input.speciesId === null) {
    if (input.visibility === "public") {
      throw new HttpError(
        422,
        "species_required",
        "Щоб зробити точку публічною, оберіть вид зі списку. «Не знаю» — лише для приватних точок.",
      );
    }
    return;
  }
  const { data, error } = await db
    .from("mushroom_catalog")
    .select("id")
    .eq("id", input.speciesId)
    .maybeSingle();
  if (error) dbFail("mushroom_catalog select", error);
  if (!data) {
    throw new HttpError(422, "unknown_species", "Такого виду немає в довіднику. Оберіть вид зі списку.");
  }
}

const LIMIT_STATUS: Record<string, number> = {
  level_required: 403,
  // ADR-019 §19.10: до 5 приватних одночасно; тижневі ліміти нових приватних і публічних
  private_limit_reached: 429,
  weekly_limit_reached: 429,
  daily_limit_reached: 429, // старі БД до міграції 20261125100000
  validation_error: 422,
  species_required: 422,
  pick_not_found: 404,
};

/** Відмова БД-функції лімітів → помилка API з її кодом і текстом. */
function limitError(code: unknown, message: unknown): HttpError {
  const c = typeof code === "string" && code ? code : "forbidden";
  return new HttpError(LIMIT_STATUS[c] ?? 403, c, typeof message === "string" ? message : undefined);
}

async function assertCanCreate(db: PicksDb, userId: string, visibility: Visibility): Promise<void> {
  const { data, error } = await db.rpc("can_create_pick", { p_user_id: userId, p_visibility: visibility });
  if (error) dbFail("can_create_pick", error);
  const row = (Array.isArray(data) ? data[0] : data) as
    | { allowed?: boolean; code?: string; message?: string }
    | null
    | undefined;
  if (!row) dbFail("can_create_pick", "empty result");
  if (row.allowed !== true) throw limitError(row.code, row.message);
}

/** HTTP-статус помилки Storage (у різних версіях SDK він лежить у різних полях). */
function storageStatus(error: unknown): number | null {
  if (!error || typeof error !== "object") return null;
  const e = error as { status?: unknown; statusCode?: unknown; originalError?: { status?: unknown } };
  for (const value of [e.status, e.statusCode, e.originalError?.status]) {
    const n = Number(value);
    if (value !== undefined && value !== null && Number.isFinite(n)) return n;
  }
  return null;
}

interface CheckedPhoto {
  bytes: Uint8Array;
  format: "jpeg" | "png" | "webp";
  exif: ExifCheck;
}

/** Читає «чернетку» зі Storage, перевіряє розмір, формат і EXIF, вирізає метадані. */
async function loadAndCheckPhoto(deps: PicksDeps, input: CreatePickInput): Promise<CheckedPhoto | null> {
  const { data, error } = await deps.storage.download(input.path);
  if (error || !data) {
    const status = storageStatus(error);
    if (status !== null && status >= 500) storageFail("download", error);
    return null; // файлу немає
  }
  if (data.size > MAX_PHOTO_BYTES) {
    await removeQuietly(deps.storage, input.path);
    throw new HttpError(400, "photo_too_large", "Фото завелике — максимум 5 МБ");
  }
  const original = new Uint8Array(await data.arrayBuffer());
  const format = detectImageFormatFromBytes(original);
  if (!format) {
    await removeQuietly(deps.storage, input.path);
    throw new HttpError(400, "invalid_photo_format", "Фото має бути у форматі JPEG, PNG або WebP");
  }
  // EXIF — лише підказка (ADR-018): перевіряємо до вирізання, результат зберігаємо в ai_check.
  const exif = await verifyExif(original, input.lat, input.lng, {
    referenceTime: input.capturedAt,
    parse: deps.parseExif,
  });
  return { bytes: stripImageMetadata(original, format), format, exif };
}

async function removeQuietly(storage: PicksStorage, path: string): Promise<void> {
  try {
    const { error } = await storage.remove([path]);
    if (error) console.warn(`[v1-picks] could not remove ${path}:`, error);
  } catch (err) {
    console.warn(`[v1-picks] could not remove ${path}:`, err);
  }
}

async function createPick(
  req: Request,
  user: AuthUser,
  deps: PicksDeps,
  now: Date,
): Promise<Response> {
  const body = await readJson(req);

  // 1. Гість (ADR-001) не створює публічних точок — ще до решти перевірок.
  if (body !== null && typeof body === "object" && (body as Record<string, unknown>).visibility === "public") {
    assertRegistered(user);
  }

  // 2. Валідація тіла (разом з очищенням опису від контактів).
  const input = validateCreateBody(body, now);

  // 3. Фото — тільки зі своєї теки.
  if (input.pathUserId !== user.id.toLowerCase()) {
    throw new HttpError(403, "forbidden", "Це фото належить іншому користувачу");
  }

  // 4. Ідемпотентність: повтор з офлайн-черги повертає ту саму точку.
  const existing = await findExistingPick(deps.db, user.id, input.clientId);
  if (existing) return ok(pickResponse(existing), req, 200);

  // 5. Тільки у своїй області (ADR-015 §15.2).
  await assertInHomeRegion(deps.db, user.id, input.lat, input.lng);

  // 6. Вид: «Не знаю» — лише приватна точка; id має бути в довіднику.
  await assertSpecies(deps.db, input);

  // 6б. Відповідь знахідкою (B3.8): чи можна підтверджувати цю точку — до створення (без відстані:
  //     її сервер перевіряє вже після, щоб не підказувати справжнє місце).
  if (input.replyTo) await assertCanConfirm(deps.db, user.id, input.replyTo, input.speciesId);

  // 7. Опис уже очищено від контактів під час валідації (`_shared/picks/text.ts`).

  // 8. Ліміти (ADR-010/011/013) — рання відмова, до роботи з файлом.
  await assertCanCreate(deps.db, user.id, input.visibility);

  // 9. Фото: є у Storage, не завелике, справжнє зображення; метадані вирізаються.
  const photo = await loadAndCheckPhoto(deps, input);
  if (!photo) {
    // Чернетку міг уже прибрати паралельний запит, який створив цю саму точку.
    const created = await findExistingPick(deps.db, user.id, input.clientId);
    if (created) return ok(pickResponse(created), req, 200);
    throw new HttpError(
      422,
      "photo_not_uploaded",
      "Фото ще не завантажено. Спершу завантажте його за посиланням з upload-url.",
    );
  }

  const id = (deps.newId ?? (() => crypto.randomUUID()))();

  // 10. Публічна точка: чужі бачать лише стабільно зсунуте місце (ADR-018 §18.5).
  const display = input.visibility === "public"
    ? await fuzzPoint(id, input.lat, input.lng, deps.fuzzSecret)
    : null;

  const finalPath = `${FINAL_PHOTO_PREFIX}/${id}.${IMAGE_EXT[photo.format]}`;
  const uploaded = await deps.storage.upload(finalPath, photo.bytes, {
    contentType: IMAGE_MIME[photo.format],
    upsert: true,
  });
  if (uploaded.error) storageFail("upload", uploaded.error);

  // 11. Атомарна вставка: БД ще раз перевіряє client_id і ліміт під блокуванням
  //     користувача. Статус завжди 'pending' — його виставляє сама функція.
  const aiCheck = {
    ...(input.aiCheck ?? {}),
    exif: { has_exif: photo.exif.hasExif, verified: photo.exif.verified, reason: photo.exif.reason ?? null },
    // Що телефон сказав про джерело місця (null — старий застосунок, не повідомив).
    location: { mocked: input.locationMocked ?? null },
  };
  let inserted: { data: unknown; error: unknown };
  try {
    inserted = await deps.db.rpc("create_pick", {
      p_id: id,
      p_user_id: user.id,
      p_client_id: input.clientId,
      p_lat: input.lat,
      p_lng: input.lng,
      p_photo_path: finalPath,
      p_visibility: input.visibility,
      p_species_id: input.speciesId,
      p_description: input.description,
      p_ai_check: aiCheck,
      p_twin_alert: input.aiCheck?.twin_alert === true,
      p_captured_at: input.capturedAt.toISOString(),
      p_display_lat: display?.lat ?? null,
      p_display_lng: display?.lng ?? null,
    });
  } catch (err) {
    inserted = { data: null, error: err };
  }
  const { data, error } = inserted;
  const result = data as
    | { allowed?: boolean; created?: boolean; code?: string; message?: string; pick?: PickRow }
    | null;
  if (error || !result) {
    await removeQuietly(deps.storage, finalPath);
    dbFail("create_pick", error ?? "empty result");
  }
  if (result.allowed !== true) { // ліміт вичерпав паралельний запит
    await removeQuietly(deps.storage, finalPath);
    throw limitError(result.code, result.message);
  }
  if (!result.pick) {
    await removeQuietly(deps.storage, finalPath);
    dbFail("create_pick", "no pick in result");
  }
  if (result.created !== true) { // цю точку щойно створив паралельний повтор запиту
    await removeQuietly(deps.storage, finalPath);
    return ok(pickResponse(result.pick), req, 200);
  }

  await removeQuietly(deps.storage, input.path); // чернетка більше не потрібна
  console.log(
    `[v1-picks] created ${id} visibility=${input.visibility} exif=${
      photo.exif.verified ? "ok" : photo.exif.reason ?? "none"
    }`,
  );

  // 12. Відповідь знахідкою: зарахувати підтвердження (відстань, EXIF, взаємний ліміт) і бали.
  const confirmation = input.replyTo ? await confirmByReply(deps.db, user.id, input.replyTo, id) : undefined;

  // 13. Підписи й кольори — із сервера.
  return ok({ ...pickResponse(result.pick), ...(confirmation ? { confirmation } : {}) }, req, 201);
}

// ─── Підтвердження відповіддю знахідкою (B3.8, ADR-019 §19.5) ──────────────

const CONFIRM_STATUS: Record<string, number> = {
  pick_not_found: 404,
  own_pick: 422,
  species_mismatch: 422,
  already_confirmed: 409,
  attempts_exhausted: 409,
};

/** Чому відповідь не зарахована — словами для людини (без відстаней і координат). */
export const CONFIRM_REASON_LABEL: Record<string, string> = {
  too_far: "Знахідка далі ніж 200 м від точки — збережено як вашу публічну точку, але точку не підтверджено",
  exif_unverified: "Не вдалося перевірити місце фото — точку збережено, але не підтверджено",
  pair_limit: "Ви вже кілька разів підтверджували точки цього грибника — цю знахідку збережено без підтвердження",
  mock_location: "Телефон повідомив, що місце підмінене програмою — знахідку збережено, але точку не підтверджено",
  location_unknown: "Оновіть застосунок, щоб підтверджувати точки — знахідку збережено без підтвердження",
};

async function assertCanConfirm(db: PicksDb, userId: string, targetId: string, speciesId: string | null): Promise<void> {
  const { data, error } = await db.rpc("can_confirm_pick", {
    p_user_id: userId,
    p_target_id: targetId,
    p_species_id: speciesId,
  });
  if (error) dbFail("can_confirm_pick", error);
  const r = (data ?? {}) as { allowed?: boolean; code?: string; message?: string };
  if (r.allowed === true) return;
  const code = r.code ?? "validation_error";
  throw new HttpError(CONFIRM_STATUS[code] ?? 422, code, r.message ?? "Цю точку зараз не можна підтвердити");
}

async function confirmByReply(
  db: PicksDb,
  userId: string,
  targetId: string,
  replyId: string,
): Promise<Record<string, unknown>> {
  // Точку-відповідь уже створено — збій тут не скасовує її, лише лишає без підтвердження.
  try {
    const { data, error } = await db.rpc("confirm_pick", {
      p_user_id: userId,
      p_target_id: targetId,
      p_reply_pick_id: replyId,
    });
    if (error) throw error;
    const r = (data ?? {}) as { ok?: boolean; counted?: boolean; reason?: string | null; message?: string };
    if (r.ok !== true) {
      return { counted: false, label: r.message ?? "Точку збережено, але не підтверджено" };
    }
    return {
      counted: r.counted === true,
      label: r.counted === true
        ? "Дякуємо! Ви підтвердили точку своєю знахідкою"
        : CONFIRM_REASON_LABEL[r.reason ?? ""] ?? "Точку збережено, але не підтверджено",
    };
  } catch (err) {
    console.error("[v1-picks] confirm_pick failed:", err);
    return { counted: false, label: "Точку збережено, але підтвердження не вдалося — спробуйте пізніше" };
  }
}

// ─── Маршрутизація ─────────────────────────────────────────────────────────

export type PicksRoute =
  | { kind: "create" }
  | { kind: "upload-url" }
  | { kind: "map" }
  | { kind: "species" }
  | { kind: "card"; id: string };

// ─── Зміна й видалення своєї точки (B3.4) ──────────────────────────────────

interface UpdatePickInput {
  visibility: Visibility | null;
  /** undefined — опис не змінюється; null — прибрати. */
  description: string | null | undefined;
}

export function validateUpdateBody(body: unknown): UpdatePickInput {
  if (body === null || typeof body !== "object" || Array.isArray(body)) throw validationError("Очікується JSON-об'єкт");
  const obj = body as Record<string, unknown>;
  const unknownKeys = Object.keys(obj).filter((k) => k !== "visibility" && k !== "description");
  if (unknownKeys.length) {
    throw validationError(`Змінити можна лише видимість і опис (фото й вид не змінюються): ${unknownKeys.join(", ")}`);
  }
  let visibility: Visibility | null = null;
  if (obj.visibility !== undefined) {
    if (obj.visibility !== "private" && obj.visibility !== "public") throw validationError("visibility — private або public");
    visibility = obj.visibility;
  }
  let description: string | null | undefined;
  if ("description" in obj) {
    const d = cleanDescription(obj.description);
    if (!d.ok) {
      throw validationError(d.reason === "too_long" ? `Опис — до ${DESCRIPTION_MAX_LENGTH} символів` : "description — текст або null");
    }
    description = d.text;
  }
  if (visibility === null && description === undefined) throw validationError("Нічого змінювати: передайте visibility або description");
  return { visibility, description };
}

async function updatePick(req: Request, pickId: string, user: AuthUser, deps: PicksDeps): Promise<Response> {
  const input = validateUpdateBody(await readJson(req));
  // Гість (ADR-001) не робить точку публічною.
  if (input.visibility === "public") assertRegistered(user);

  // Для публікації потрібне зсунуте місце: його рахує сервер із точних координат (ADR-018 §18.5).
  let display: { lat: number; lng: number } | null = null;
  if (input.visibility === "public") {
    const regionId = requireHomeRegion(await loadHomeRegionId(deps.db, user.id));
    const { data, error } = await deps.db.rpc("get_pick_card", { p_user_id: user.id, p_region_id: regionId, p_pick_id: pickId });
    if (error) dbFail("get_pick_card", error);
    const card = data as { is_mine?: boolean; lat?: number; lng?: number } | null;
    if (!card || card.is_mine !== true || typeof card.lat !== "number" || typeof card.lng !== "number") {
      throw new HttpError(404, "pick_not_found", "Точку не знайдено");
    }
    display = await fuzzPoint(pickId, card.lat, card.lng, deps.fuzzSecret);
  }

  const { data, error } = await deps.db.rpc("update_pick", {
    p_user_id: user.id,
    p_pick_id: pickId,
    p_visibility: input.visibility,
    p_set_description: input.description !== undefined,
    p_description: input.description ?? null,
    p_display_lat: display?.lat ?? null,
    p_display_lng: display?.lng ?? null,
  });
  if (error) dbFail("update_pick", error);
  const res = data as { ok?: boolean; code?: string; message?: string; pick?: PickRow & { description?: string | null } } | null;
  if (!res) dbFail("update_pick", "empty result");
  if (res.ok !== true || !res.pick) throw limitError(res.code, res.message);
  return ok({ ...pickResponse(res.pick), description: res.pick.description ?? null }, req);
}

async function deletePick(req: Request, pickId: string, user: AuthUser, deps: PicksDeps): Promise<Response> {
  const { data, error } = await deps.db.rpc("delete_pick", { p_user_id: user.id, p_pick_id: pickId });
  if (error) dbFail("delete_pick", error);
  // Чужа, вже видалена чи неіснуюча точка — однаково 404 (не розкриваємо чужі точки).
  if (data !== true) throw new HttpError(404, "pick_not_found", "Точку не знайдено");
  return ok({ deleted: true }, req);
}

export function parsePicksRoute(url: URL): PicksRoute {
  const m = url.pathname.match(/\/v1-picks(\/[^/]*)?\/?$/);
  const tail = m ? (m[1] ?? "").replace(/^\//, "") : null;
  if (tail === "") return { kind: "create" };
  if (tail === "upload-url") return { kind: "upload-url" };
  if (tail === "map") return { kind: "map" };
  if (tail === "species") return { kind: "species" };
  if (tail !== null && UUID_RE.test(tail)) return { kind: "card", id: tail.toLowerCase() };
  throw new HttpError(404, "not_found", "Невідомий шлях v1-picks");
}

export async function handlePicks(req: Request, deps: PicksDeps): Promise<Response> {
  const url = new URL(req.url);
  const route = parsePicksRoute(url);
  const reads = route.kind === "map" || route.kind === "species";
  assertMethod(req, route.kind === "card" ? ["GET", "PATCH", "DELETE"] : reads ? ["GET"] : ["POST"]);
  // deno-lint-ignore no-explicit-any
  await enforceRateLimit(deps.db as any, req, "v1-picks");
  const user = await requireUser(req, deps.verify);
  const now = deps.now ? deps.now() : new Date();

  switch (route.kind) {
    case "upload-url":
      return await createUploadUrl(req, user, deps, now);
    case "create":
      return await createPick(req, user, deps, now);
    case "map":
      return await handlePicksMap(req, url, user, deps);
    case "species":
      return await handlePickSpecies(req, deps);
    case "card":
      if (req.method === "PATCH") return await updatePick(req, route.id, user, deps);
      if (req.method === "DELETE") return await deletePick(req, route.id, user, deps);
      return await handlePickCard(req, route.id, user, deps);
  }
}
