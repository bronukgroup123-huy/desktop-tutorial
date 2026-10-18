// ============================================================================
// DIAGNOSTIC: audit_missing_photos.mjs
// Знаходить файли з mushroom_catalog.json (has_photo: true), яких немає локально.
// ============================================================================
import fs from "node:fs";
import path from "node:path";

const CANDIDATE_PATHS = [
  "web-guardian/public/mushroom_catalog.json",
  "mushroom_catalog.json",
];

function resolveCatalogPath() {
  for (const p of CANDIDATE_PATHS) {
    if (fs.existsSync(p)) {
      return p;
    }
  }
  throw new Error(
    "Не знайдено mushroom_catalog.json (перевірено: " +
    CANDIDATE_PATHS.join(", ") + ")"
  );
}

const CATALOG_PATH = resolveCatalogPath();
const catalog = JSON.parse(fs.readFileSync(CATALOG_PATH, "utf8"));
const species = Array.isArray(catalog.species) ? catalog.species : [];

const withPhoto = species.filter((s) => s.has_photo === true);

console.log(`Каталог: ${CATALOG_PATH}`);
console.log(`Всього видів: ${species.length}`);
console.log(`Види з has_photo: true: ${withPhoto.length}`);

let missingCount = 0;

for (const s of withPhoto) {
  const photos = Array.isArray(s.photos) ? s.photos : [];
  for (const expected of photos) {
    if (fs.existsSync(expected)) {
      continue;
    }

    missingCount++;
    const dir = path.dirname(expected);
    let realFiles = [];
    try {
      realFiles = fs.readdirSync(dir).sort();
    } catch (e) {
      realFiles = [`<не вдалося прочитати теку: ${e.message}`];
    }

    console.log("\n=== ФАЙЛ ВІДСУТНІЙ ЛОКАЛЬНО ===");
    console.log(`ID гриба: ${s.id}`);
    console.log(`Назва: ${s.name}`);
    console.log(`Очікуваний шлях: ${expected}`);
    console.log(`Реальні файли в теці (${dir}):`);
    if (realFiles.length === 0) {
      console.log(`  (тека порожня або не існує)`);
    } else {
      realFiles.forEach((f) => console.log(`  ${f}`));
    }
  }
}

console.log("\n=== РЕЗУЛЬТАТ АУДИТУ ===");
console.log(`Відсутніх локальних файлів: ${missingCount}`);
if (missingCount === 0) {
  console.log("Всі файли з has_photo: true існують локально.");
}
