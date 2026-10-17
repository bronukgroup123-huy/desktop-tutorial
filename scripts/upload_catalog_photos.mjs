// ============================================================================
// PC-TASK #8: Bulk upload каталогових фото у Supabase Storage
// Запускається на ПК з SUPABASE_SERVICE_ROLE_KEY.
// ============================================================================
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";
import path from "node:path";

const BUCKET = "mushroom-catalog-photos";

function sanitizePath(p) {
  return p
    .replace(/\s+/g, '_')
    .replace(/[()]/g, '')
    .replace(/[^\w\-./]/g, '_');
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
      const buffer = fs.readFileSync(file);
      const storagePath = sanitizePath(file);
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
