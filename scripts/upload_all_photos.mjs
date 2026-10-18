// ============================================================================
// scripts/upload_all_photos.mjs
// Завантажує всі фото грибів у Supabase Storage бакет mushroom-photos.
// Потрібні змінні оточення: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ============================================================================
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";
import path from "node:path";

const JS_CATALOG = "web-guardian/public/mushroom_catalog.js";
const JSON_CATALOG = "mushroom_catalog.json";
const BUCKET = "mushroom-photos";

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceKey) {
  console.error("ПОМИЛКА: потрібні змінні оточення SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Читаємо mushroom_catalog.js (джерело ids, has_photo, photo_url)
function loadJsCatalog() {
  const src = fs.readFileSync(JS_CATALOG, "utf8");
  const marker = "window.MUSHROOM_CATALOG = ";
  const idx = src.indexOf(marker);
  if (idx === -1) throw new Error("Не знайдено window.MUSHROOM_CATALOG у " + JS_CATALOG);
  const tail = src.slice(idx + marker.length).replace(/;\s*$/, "").trim();
  return JSON.parse(tail);
}

// Читаємо mushroom_catalog.json (джерело локальних шляхів до файлів фото)
function loadJsonCatalog() {
  const src = fs.readFileSync(JSON_CATALOG, "utf8");
  const obj = JSON.parse(src);
  return Array.isArray(obj.species) ? obj.species : [];
}

const jsCatalog = loadJsCatalog();
const jsonSpecies = loadJsonCatalog();
// Мапінг id -> локальний шлях до першого фото
const localPhotoById = new Map();
for (const s of jsonSpecies) {
  if (s.photos && s.photos.length) {
    localPhotoById.set(s.id, s.photos[0]);
  }
}

async function ensureBucket() {
  const { data: buckets, error: listErr } = await supabase.storage.listBuckets();
  if (listErr) throw new Error("Не вдалося отримати список бакетів: " + listErr.message);
  const exists = buckets.some(b => b.name === BUCKET);
  if (!exists) {
    console.log(`Бакет "${BUCKET}" не знайдено, створюю...`);
    const { error: createErr } = await supabase.storage.createBucket(BUCKET, { public: true });
    if (createErr) throw new Error("Не вдалося створити бакет: " + createErr.message);
    console.log(`Бакет "${BUCKET}" створено (public).`);
  } else {
    console.log(`Бакет "${BUCKET}" вже існує.`);
  }
}

async function main() {
  await ensureBucket();

  const toUpload = jsCatalog.filter(s => s.has_photo === true);
  console.log(`Грибів з has_photo===true: ${toUpload.length}`);

  let uploaded = 0;
  let skipped = 0;
  let errors = 0;
  const errorList = [];

  for (const s of toUpload) {
    const localPath = localPhotoById.get(s.id);
    if (!localPath) {
      skipped++;
      errorList.push({ id: s.id, name: s.name, reason: "немає локального шляху до фото" });
      continue;
    }
    if (!fs.existsSync(localPath)) {
      skipped++;
      errorList.push({ id: s.id, name: s.name, reason: `файл не знайдено: ${localPath}` });
      continue;
    }

    const buffer = fs.readFileSync(localPath);
    const storagePath = `${s.id}.webp`;

    const { error } = await supabase.storage
      .from(BUCKET)
      .upload(storagePath, buffer, {
        contentType: "image/webp",
        upsert: true,
      });

    if (error) {
      errors++;
      errorList.push({ id: s.id, name: s.name, reason: error.message });
      console.warn(`  ПОМИЛКА ${s.id}: ${error.message}`);
    } else {
      uploaded++;
    }
    await new Promise(r => setTimeout(r, 80));
    if ((uploaded + skipped + errors) % 25 === 0) {
      console.log(`  прогрес: завантажено ${uploaded}, пропущено ${skipped}, помилок ${errors}`);
    }
  }

  console.log("\n=== РЕЗУЛЬТАТ ЗАВАНТАЖЕННЯ ===");
  console.log(`Оброблено: ${toUpload.length}`);
  console.log(`Завантажено: ${uploaded}`);
  console.log(`Пропущено: ${skipped}`);
  console.log(`Помилок: ${errors}`);
  if (errorList.length) {
    console.log("\nПриклади пропусків/помилок:");
    errorList.slice(0, 15).forEach(e => console.log(`  ${e.id} (${e.name}): ${e.reason}`));
  }

  // ---------------------------------------------------------------
  // Перевірка: кожен URL у mushroom_catalog.js веде на існуючий файл
  // ---------------------------------------------------------------
  console.log("\n=== ПЕРЕВІРКА URL ===");
  const cdnBase = url.replace(/\/$/, "") + `/storage/v1/object/public/${BUCKET}`;
  let ok = 0, bad = 0;
  for (const s of toUpload) {
    const expectedUrl = `${cdnBase}/${s.id}.webp`;
    const actual = s.photo_url;
    if (actual === expectedUrl) {
      ok++;
    } else {
      bad++;
      console.warn(`  НЕСПІВАЄ ${s.id}: поточне=${actual}, очікуване=${expectedUrl}`);
    }
  }
  console.log(`URL співпадають з очікуваними: ${ok}/${toUpload.length}`);
  if (bad > 0) {
    console.log("Зверніть увагу: деякі photo_url не співпадають з очікуваними.");
  }
}

main().catch(err => {
  console.error("Фатальна помилка:", err);
  process.exit(1);
});
