// ============================================================================
// PC-TASK #8: Перезаписати URL фото в mushroom_catalog.js на CDN
// Додає префікс Supabase Storage public bucket. У Manifest-спосіб:
// читає relativ-шляхи з mushroom_catalog.json (там є контекст виду),
// обчислює CDN URL (з урахуванням photo_overrides для 6 проблемних видів)
// і записує назад у web-guardian/public/mushroom_catalog.js.
// ============================================================================
import fs from "node:fs";
import path from "node:path";
import { overrideBase } from "./photo_overrides.mjs";

const CATALOG_JSON = "mushroom_catalog.json";
const JS_CATALOG = "web-guardian/public/mushroom_catalog.js";
const BUCKET = "mushroom-catalog-photos";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://wrukmuxdbkbmkygfasai.supabase.co";
const CDN_BASE = SUPABASE_URL.replace(/\/$/, "") + `/storage/v1/object/public/${BUCKET}`;

const CYRILLIC_MAP = {
  а: "a", б: "b", в: "v", г: "h", ґ: "g", д: "d", е: "e", ё: "e", є: "ie",
  ж: "zh", з: "z", и: "y", і: "i", ї: "i", й: "y", к: "k", л: "l", м: "m",
  н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f", х: "h",
  ц: "ts", ч: "ch", ш: "sh", щ: "shch", ъ: "", ы: "y", ь: "", э: "e",
  ю: "yu", я: "ya",
};

function transliterate(s) {
  let out = "";
  for (const ch of s) {
    const mapped = CYRILLIC_MAP[ch];
    out += mapped !== undefined ? mapped : ch;
  }
  return out;
}

function sanitizePath(p) {
  let s = p.replace(/\\/g, "/").toLowerCase();
  s = transliterate(s);
  s = s.replace(/\s+/g, "_");
  s = s.replace(/\//g, "_");
  s = s.replace(/[^a-z0-9._-]/g, "_");
  s = s.replace(/_+/g, "_");
  const lastDot = s.lastIndexOf(".");
  if (lastDot !== -1 && lastDot < s.length - 1) {
    s = s.slice(0, lastDot) + s.slice(lastDot).toLowerCase();
  }
  return s;
}

/**
 * Очищає суфікс імені файла (без розширення) для побудови унікального
 * сховища-шляха при використанні перевизу.
 */
function sanitizeStem(stem) {
  return stem
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

/**
 * Обчислює сховище-шлях для одного фото виду.
 * Якщо для вида задано перевиз — використовує його (з унікальним суфіксом фото),
 * інакше — старий sanitizePath.
 */
function storagePathFor(species, photoPath) {
  const base = overrideBase(species.name);
  if (base) {
    const stem = path.basename(photoPath, ".webp");
    return `${base}_${sanitizeStem(stem)}.webp`;
  }
  return sanitizePath(photoPath);
}

function photoUrlFor(species, photoPath) {
  return CDN_BASE + "/" + storagePathFor(species, photoPath);
}

// --- Завантажити JSON-каталог та передобрахувати URL для кожного виду ---
const catalog = JSON.parse(fs.readFileSync(CATALOG_JSON, "utf8"));
const speciesList = Array.isArray(catalog.species) ? catalog.species : [];

const urlsById = new Map();
for (const s of speciesList) {
  const urls = (s.photos || []).map((p) => photoUrlFor(s, p));
  urlsById.set(s.id, urls);
}

// --- Прочитати JS-каталог як JSON, замінити масиви photos, записати назад ---
const jsSrc = fs.readFileSync(JS_CATALOG, "utf8");
const marker = "window.MUSHROOM_CATALOG = ";
const idx = jsSrc.indexOf(marker);
if (idx === -1) {
  throw new Error("Не знайдено 'window.MUSHROOM_CATALOG = ' у " + JS_CATALOG);
}
const tail = jsSrc.slice(idx + marker.length).replace(/;\s*$/, "").trim();
const jsObj = JSON.parse(tail);

let replaced = 0, skipped = 0;
const jsSpecies = Array.isArray(jsObj.species) ? jsObj.species : [];
for (const s of jsSpecies) {
  const urls = urlsById.get(s.id);
  if (!urls) {
    continue;
  }
  const old = s.photos || [];
  const next = [];
  for (let i = 0; i < old.length; i++) {
    const raw = old[i];
    if (typeof raw === "string" && (raw.startsWith("http://") || raw.startsWith("https://"))) {
      // Перевизначуємо лише для видів з перевизом; для решти залишаємо як є,
      // щоб не зламати вже завантажені 126 фото.
      if (overrideBase(jsSpecies.find((x) => x.id === s.id)?.name || "")) {
        next.push(`"${urls[i] || raw}"`);
        replaced++;
      } else {
        next.push(`"${raw}"`);
        skipped++;
      }
      continue;
    }
    next.push(`"${urls[i] || raw}"`);
    replaced++;
  }
  s.photos = next;
}

fs.writeFileSync(JS_CATALOG, "// mushroom_catalog.js\n// Автогенеровано scripts/rewrite_catalog_photo_urls.mjs. Не редагувати вручну.\nwindow.MUSHROOM_CATALOG = " + JSON.stringify(jsObj) + ";\n", "utf8");

console.log("=== РЕЗУЛЬТАТ ПЕРЕЗАПИСУ URL ===");
console.log(`Оброблено видів: ${jsSpecies.length}`);
console.log(`Фото URL оновлено: ${replaced}`);
console.log(`Фото URL залишено без змін (вже https, без перевизу): ${skipped}`);
console.log(`CDN_BASE: ${CDN_BASE}`);
