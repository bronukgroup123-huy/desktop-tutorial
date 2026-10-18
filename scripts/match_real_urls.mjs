// ============================================================================
// scripts/match_real_urls.mjs
// Знаходить реальні шляхи файлів у бакеті mushroom-catalog-photos
// і оновлює photo_url + всі елементи масиву photos у web-guardian/public/mushroom_catalog.js.
// Потрібні змінні оточення: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// ============================================================================
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";

const JS_CATALOG = "web-guardian/public/mushroom_catalog.js";
const JSON_CATALOG = "mushroom_catalog.json";
const BUCKET = "mushroom-catalog-photos";
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("ПОМИЛКА: потрібні SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function norm(s) {
  return String(s).toLowerCase().replace(/_+/g, " ").replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
}

// Рекурсивно збираємо всі файли з бакета
async function listAllFiles(prefix = "") {
  const files = [];
  async function walk(dir) {
    const { data, error } = await supabase.storage.from(BUCKET).list(dir, {
      limit: 1000,
      offset: 0,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw new Error(`list ${dir || "root"}: ${error.message}`);
    for (const entry of data || []) {
      const fullPath = dir ? `${dir}/${entry.name}` : entry.name;
      if (entry.metadata) {
        // це файл
        files.push(fullPath);
      } else {
        // це папка — заходимо всередину
        await walk(fullPath);
      }
    }
  }
  await walk(prefix);
  return files;
}

// Читаємо JSON каталог (джерело оригінальних шляхів photos[])
const jsonSrc = fs.readFileSync(JSON_CATALOG, "utf8");
const jsonObj = JSON.parse(jsonSrc);
const jsonSpecies = Array.isArray(jsonObj.species) ? jsonObj.species : [];
const allPhotosById = new Map();
for (const s of jsonSpecies) {
  if (s.photos && s.photos.length) {
    allPhotosById.set(s.id, s.photos);
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

async function main() {
  console.log("Отримуємо список файлів з Supabase Storage...");
  const allFiles = await listAllFiles();
  console.log(`Знайдено файлів у бакеті: ${allFiles.length}`);

  // Будуємо індекс: нормалізоване ім'я файлу без розширення -> список реальних шляхів
  const fileIndex = new Map();
  for (const fp of allFiles) {
    const base = fp.split("/").pop();
    const nameNoExt = base.replace(/\.webp$/i, "");
    const key = norm(nameNoExt);
    if (!fileIndex.has(key)) fileIndex.set(key, []);
    fileIndex.get(key).push(fp);
  }

  // Також індексуємо по папках (предпоследній сегмент шляху)
  const folderIndex = new Map();
  for (const fp of allFiles) {
    const parts = fp.split("/");
    if (parts.length > 1) {
      const folderName = parts[parts.length - 2];
      const key = norm(folderName);
      if (!folderIndex.has(key)) folderIndex.set(key, []);
      folderIndex.get(key).push(fp);
    }
  }

  function matchOne(origPath) {
    const parts = origPath.split("/");
    const fileName = parts.pop();
    const fileNameNoExt = fileName.replace(/\.webp$/i, "");
    const folderName = parts.pop() || "";

    const fileKey = norm(fileNameNoExt);
    const folderKey = norm(folderName);

    // Спроба 1: точний збіг імені файлу + папки
    const fileCandidates = fileIndex.get(fileKey) || [];
    const folderCandidates = folderIndex.get(folderKey) || [];
    for (const fp of fileCandidates) {
      if (folderCandidates.includes(fp)) {
        return fp;
      }
    }

    // Спроба 2: збіг лише імені файлу
    if (fileCandidates.length) {
      return fileCandidates[0];
    }

    // Спроба 3: збіг лише папки
    if (folderCandidates.length) {
      const inFolder = folderCandidates.filter(fp => {
        const b = fp.split("/").pop().replace(/\.webp$/i, "");
        return norm(b) === fileKey || norm(b).includes(fileKey) || fileKey.includes(norm(b));
      });
      if (inFolder.length) return inFolder[0];
      return folderCandidates[0];
    }

    return null;
  }

  let speciesUpdated = 0;
  let photosUpdated = 0;
  let notFound = 0;
  const foundExamples = [];

  for (const s of species) {
    if (s.has_photo !== true) continue;

    const origPhotos = allPhotosById.get(s.id);
    if (!origPhotos || !Array.isArray(origPhotos) || origPhotos.length === 0) {
      notFound++;
      console.log(`❌ Не знайдено в Storage для ${s.name} (немає photos)`);
      continue;
    }

    const newPhotos = [];
    let speciesNotFound = false;

    for (const origPath of origPhotos) {
      const matched = matchOne(origPath);
      if (!matched) {
        speciesNotFound = true;
        console.log(`❌ Не знайдено в Storage для ${s.name}: ${origPath}`);
        continue;
      }
      const url = `https://wrukmuxdbkbmkygfasai.supabase.co/storage/v1/object/public/mushroom-catalog-photos/${matched}`;
      newPhotos.push(url);
      photosUpdated++;
    }

    if (speciesNotFound && newPhotos.length === 0) {
      notFound++;
      continue;
    }

    s.photos = newPhotos;
    s.photo_url = newPhotos[0];
    speciesUpdated++;
    if (foundExamples.length < 3) {
      foundExamples.push(`${s.name} -> photos[0]=${newPhotos[0]} (${newPhotos.length} фото)`);
    }
  }

  // Записуємо оновлений JS каталог
  const out =
    "// mushroom_catalog.js\n" +
    "// Автогенеровано scripts/match_real_urls.mjs. Не редагувати вручну.\n" +
    "window.MUSHROOM_CATALOG = " +
    JSON.stringify(obj) +
    ";\n";
  fs.writeFileSync(JS_CATALOG, out, "utf8");

  console.log("\n=== ЗВІТ ===");
  console.log(`Оновлено видів: ${speciesUpdated}`);
  console.log(`Оновлено фото URL: ${photosUpdated}`);
  console.log(`Не знайдено в Storage: ${notFound}`);
  if (foundExamples.length) {
    console.log("\nПриклади:");
    foundExamples.forEach(e => console.log("  " + e));
  }
}

main().catch((err) => {
  console.error("Фатальна помилка:", err);
  process.exit(1);
});
