// ============================================================================
// scripts/revert_to_original_bucket.mjs
// Повертає photo_url у mushroom_catalog.js на оригінальний бакет
// mushroom-catalog-photos і оновлює photos[0] для всіх 132 грибів.
// ============================================================================
import fs from "node:fs";

const JS_CATALOG = "web-guardian/public/mushroom_catalog.js";
const JSON_CATALOG = "mushroom_catalog.json";
const SUPABASE_URL = "https://wrukmuxdbkbmkygfasai.supabase.co";
const BUCKET = "mushroom-catalog-photos";

// 6 проблемних грибів — використовуємо латинські імена файлів
const SPECIAL = {
  "Гомф булавоподібний": "gomphus_clavatus.webp",
  "Квітохвісник Арчера": "anthurus_archeri.webp",
  "Міріостома шийкова": "myriostoma_coliforme.webp",
  "Фелоринія геркулесова": "phellorinia_herculeana.webp",
  "Хрящ-молочник чорний": "lactarius_lignyotus.webp",
  "Шишкогриб лускатий": "strobilomyces_strobilaceus.webp",
};

function cdnUrl(bucket, path) {
  return `${SUPABASE_URL.replace(/\/$/, "")}/storage/v1/object/public/${bucket}/${path}`;
}

// Читаємо JSON каталог (джерело локальних шляхов до фото)
const jsonSrc = fs.readFileSync(JSON_CATALOG, "utf8");
const jsonObj = JSON.parse(jsonSrc);
const jsonSpecies = Array.isArray(jsonObj.species) ? jsonObj.species : [];
const localPhotoById = new Map();
for (const s of jsonSpecies) {
  if (s.photos && s.photos.length) {
    localPhotoById.set(s.id, s.photos[0]);
  }
}

// Читаємо JS каталог
const jsSrc = fs.readFileSync(JS_CATALOG, "utf8");
const marker = "window.MUSHROOM_CATALOG = ";
const idx = jsSrc.indexOf(marker);
if (idx === -1) throw new Error("Не знайдено window.MUSHROOM_CATALOG у " + JS_CATALOG);
const tail = jsSrc.slice(idx + marker.length).replace(/;\s*$/, "").trim();
const obj = JSON.parse(tail);
const species = Array.isArray(obj.species) ? obj.species : [];

let updated = 0;
let skipped = 0;

for (const s of species) {
  if (s.has_photo !== true) continue;

  let filePath;
  if (SPECIAL[s.name]) {
    filePath = SPECIAL[s.name];
  } else {
    const local = localPhotoById.get(s.id);
    if (!local) {
      skipped++;
      console.warn(`Пропущено (немає шляху): ${s.id} — ${s.name}`);
      continue;
    }
    filePath = local;
  }

  s.photo_url = cdnUrl(BUCKET, filePath);
  if (Array.isArray(s.photos) && s.photos.length) {
    s.photos[0] = s.photo_url;
  } else {
    s.photos = [s.photo_url];
  }

  updated++;
}

// Записуємо оновлений JS каталог
const out =
  "// mushroom_catalog.js\n" +
  "// Автогенеровано scripts/revert_to_original_bucket.mjs. Не редагувати вручну.\n" +
  "window.MUSHROOM_CATALOG = " +
  JSON.stringify(obj) +
  ";\n";

fs.writeFileSync(JS_CATALOG, out, "utf8");

console.log("\n=== ЗВІТ ===");
console.log(`Оновлено URL на бакет "${BUCKET}": ${updated}`);
console.log(`Пропущено (немає локального шляху): ${skipped}`);
