// ============================================================================
// PC-TASK #8: Bulk upload каталогових фото у Supabase Storage
// Запускається на ПК з SUPABASE_SERVICE_ROLE_KEY.
// ============================================================================
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";
import path from "node:path";
import { overrideBase } from "./photo_overrides.mjs";

const BUCKET = "mushroom-catalog-photos";

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
  // 1. Нормалізуємо розділювачі шляхів і приводимо до нижнього регістра
  //    (щоб велика кирилиця також потрапила в мапу транслітерації).
  let s = p.replace(/\\/g, "/").toLowerCase();
  // 2. Транслітеруємо кирилицю (мапу містять лише малі літери).
  s = transliterate(s);
  // 3. Пробіли -> _.
  s = s.replace(/\s+/g, "_");
  // 4. Розділювачі шляхів -> _ (зберігаємо унікальність, уникаємо заборонених символів).
  s = s.replace(/\//g, "_");
  // 5. Залишаємо лише a-z, 0-9, ., _, -; все інше -> _.
  s = s.replace(/[^a-z0-9._-]/g, "_");
  // 6. Схрипуємо послідовні _.
  s = s.replace(/_+/g, "_");
  // 7. Розширення файлу приведено до нижнього регістру.
  const lastDot = s.lastIndexOf(".");
  if (lastDot !== -1 && lastDot < s.length - 1) {
    s = s.slice(0, lastDot) + s.slice(lastDot).toLowerCase();
  }
  return s;
}

/**
 * Очищає суфікс імені файла (без розширення) для побудови унікального
 * сховища-шляха при використанні перевизу: 'large (1)_2' -> 'large_1_2'.
 */
function sanitizeStem(stem) {
  return stem
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

const CATALOG_JSON = "mushroom_catalog.json";
const catalog = JSON.parse(fs.readFileSync(CATALOG_JSON, "utf8"));
const speciesList = Array.isArray(catalog.species) ? catalog.species : [];

// picturePath (відносно кореня проєкту) -> базове ім'я перевизу (без .webp)
const overrideByPath = new Map();
for (const s of speciesList) {
  const base = overrideBase(s.name);
  if (!base) continue;
  for (const p of s.photos || []) {
    overrideByPath.set(p, base);
  }
}

const PHOTO_DIRS = [
  "фото Топ-20 грибів (webp)",
  "фото популярні 55 грибів (webp)",
  "Червона книга (webp)",
  "Отруйні та смертельно отруйні (webp)",
];

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceKey) {
  console.error("ПОМИЛКА: потрібні SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function walkDir(dir, results = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkDir(full, results);
    } else if (entry.name.endsWith(".webp")) {
      results.push(full);
    }
  }
  return results;
}

async function main() {
  let total = 0, uploaded = 0, errors = 0;
  const errorList = [];

  for (const dir of PHOTO_DIRS) {
    const files = walkDir(dir);
    console.log(`[${dir}] знайдено ${files.length} webp`);
    for (const file of files) {
      total++;
      if (!fs.existsSync(file)) {
        console.warn(`Файл не знайдено: ${file}`);
        continue;
      }
      const buffer = fs.readFileSync(file);
      let storagePath;
      const override = overrideByPath.get(file);
      if (override) {
        const stem = path.basename(file, ".webp");
        storagePath = `${override}_${sanitizeStem(stem)}.webp`;
      } else {
        storagePath = sanitizePath(file);
      }
      const { error } = await supabase.storage
        .from(BUCKET)
        .upload(storagePath, buffer, {
          contentType: "image/webp",
          upsert: true,
        });
      if (error) {
        errors++;
        errorList.push({ file, error: error.message });
      } else {
        uploaded++;
      }
      await new Promise(resolve => setTimeout(resolve, 150));
      if (total % 50 === 0) {
        console.log(`  прогрес: ${total} оброблено, ${uploaded} завантажено, ${errors} помилок`);
      }
    }
  }

  console.log("\n=== РЕЗУЛЬТАТ ===");
  console.log(`Всього файлів: ${total}`);
  console.log(`Завантажено: ${uploaded}`);
  console.log(`Помилок: ${errors}`);
  if (errorList.length) {
    console.log("Приклади помилок:");
    errorList.slice(0, 10).forEach(e => console.log(`  ${e.file}: ${e.error}`));
  }
}

main().catch(err => {
  console.error("Фатальна помилка:", err);
  process.exit(1);
});
