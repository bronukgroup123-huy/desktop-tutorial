// ============================================================================
// PC-TASK #8: Перезаписати URL фото в mushroom_catalog.js на CDN
// Додає префікс Supabase Storage public bucket.
// ============================================================================
import fs from "node:fs";
import path from "node:path";

const CATALOG_PATH = "web-guardian/public/mushroom_catalog.js";
const CDN_BASE = "https://wrukmuxdbkbmkygfasai.supabase.co/storage/v1/object/public/mushroom-catalog-photos";

function sanitizePath(p) {
  return p
    .replace(/\s+/g, '_')
    .replace(/[()]/g, '')
    .replace(/[^\w\-./]/g, '_');
}

const content = fs.readFileSync(CATALOG_PATH, "utf8");

let replaced = 0, skipped = 0, errors = 0;
const examples = [];

// Знайдемо всі "photos":["..."] масиви і перезапишемо кожен URL
const newContent = content.replace(/"photos":\[([^\]]*)\]/g, (match, inner) => {
  const urls = inner.split(",").map(u => {
    const raw = u.trim().replace(/^"|"$/g, "");
    if (!raw) return `"${raw}"`;
    if (raw.startsWith("http://") || raw.startsWith("https://")) {
      skipped++;
      return `"${raw}"`;
    }
    try {
      const safePath = sanitizePath(raw);
      const cdnUrl = CDN_BASE + "/" + safePath;
      replaced++;
      if (examples.length < 3) examples.push({ from: raw, to: cdnUrl });
      return `"${cdnUrl}"`;
    } catch (e) {
      errors++;
      return `"${raw}"`;
    }
  });
  return `"photos":[${urls.join(",")}]`;
});

fs.writeFileSync(CATALOG_PATH, newContent, "utf8");

console.log("=== РЕЗУЛЬТАТ ПЕРЕЗАПИСУ URL ===");
console.log(`Замінено: ${replaced}`);
console.log(`Пропущено (вже https://): ${skipped}`);
console.log(`Помилок: ${errors}`);
console.log("\nПриклади заміни:");
examples.forEach(ex => console.log(`  ${ex.from}  →  ${ex.to}`));
