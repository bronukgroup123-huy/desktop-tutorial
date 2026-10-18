// ============================================================================
// PC-TASK #8: Примусово оновити photo_url та has_photo для 6 проблемних видів
// у mushroom_catalog.json, використовуючи photo_overrides.
// ============================================================================
import fs from "node:fs";
import path from "node:path";
import { resolveOverride, overrideBase } from "./photo_overrides.mjs";

const CATALOG_JSON = "mushroom_catalog.json";
const SUPABASE_URL = process.env.SUPABASE_URL || "https://wrukmuxdbkbmkygfasai.supabase.co";
const CDN_BASE = SUPABASE_URL.replace(/\/$/, "") + "/storage/v1/object/public/mushroom-catalog-photos";

function sanitizeStem(stem) {
  return stem
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function primaryPhotoUrl(species) {
  const base = overrideBase(species.name);
  if (!base) return null;
  const photos = Array.isArray(species.photos) ? species.photos : [];
  const first = photos.find((p) => typeof p === "string" && p.endsWith(".webp"));
  if (!first) return null;
  const stem = path.basename(first, ".webp");
  return CDN_BASE + "/" + `${base}_${sanitizeStem(stem)}.webp`;
}

const catalog = JSON.parse(fs.readFileSync(CATALOG_JSON, "utf8"));
const species = Array.isArray(catalog.species) ? catalog.species : [];

let updated = 0;
const report = [];

for (const s of species) {
  const override = resolveOverride(s.name);
  if (!override) continue;

  const url = primaryPhotoUrl(s);
  const before = { has_photo: s.has_photo, photo_url: s.photo_url };
  s.has_photo = true;
  if (url) s.photo_url = url;
  updated++;
  report.push({
    id: s.id,
    name: s.name,
    override,
    before,
    after: { has_photo: s.has_photo, photo_url: s.photo_url },
  });
}

fs.writeFileSync(CATALOG_JSON, JSON.stringify(catalog, null, 2) + "\n", "utf8");

console.log("=== ОНОВЛЕННЯ mushroom_catalog.json (photo_overrides) ===");
console.log(`Оновлено видів: ${updated}`);
report.forEach((r) => {
  console.log(`\n${r.id} — ${r.name}`);
  console.log(`  перевиз: ${r.override}`);
  console.log(`  has_photo: ${r.before.has_photo} -> ${r.after.has_photo}`);
  console.log(`  photo_url: ${r.before.photo_url} -> ${r.after.photo_url}`);
});
