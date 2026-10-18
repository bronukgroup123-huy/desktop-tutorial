import fs from "node:fs";
import path from "node:path";

const JS_CATALOG = "web-guardian/public/mushroom_catalog.js";
const SUPABASE_URL = process.env.SUPABASE_URL || "https://wrukmuxdbkbmkygfasai.supabase.co";
const BUCKET = process.env.SUPABASE_BUCKET || "mushroom-photos";

const PATCHES = {
  "Гомф булавоподібний": "gomphus_clavatus.webp",
  "Квітохвісник Арчера": "anthurus_archeri.webp",
  "Міріостома шийкова": "myriostoma_coliforme.webp",
  "Фелоринія геркулесова": "phellorinia_herculeana.webp",
  "Хрящ-молочник чорний": "lactarius_lignyotus.webp",
  "Шишкогриб лускатий": "strobilomyces_strobilaceus.webp",
};

async function main() {
  const src = fs.readFileSync(JS_CATALOG, "utf8");

  // Extract the JSON object from window.MUSHROOM_CATALOG = {...};
  const marker = "window.MUSHROOM_CATALOG = ";
  const idx = src.indexOf(marker);
  if (idx === -1) {
    throw new Error("Не знайдено window.MUSHROOM_CATALOG у " + JS_CATALOG);
  }

  const tail = src.slice(idx + marker.length).replace(/;\s*$/, "").trim();
  const obj = JSON.parse(tail);

  const species = Array.isArray(obj.species) ? obj.species : (Array.isArray(obj.rows) ? obj.rows : []);

  let patched = 0;
  let notFound = [];

  for (const s of species) {
    const targetFile = PATCHES[s.name];
    if (!targetFile) continue;

    s.has_photo = true;
    s.photo_url = `${SUPABASE_URL.replace(/\/$/, "")}/storage/v1/object/public/${BUCKET}/${targetFile}`;

    // Also fix the photos array: remove escaped quotes from existing URLs
    if (Array.isArray(s.photos)) {
      s.photos = s.photos.map((p) => {
        if (typeof p === "string") {
          // Remove surrounding escaped quotes if present
          return p.replace(/^"|"$/g, "").replace(/\\"/g, "");
        }
        return p;
      });
    }

    patched++;
    console.log(`PATCHED: ${s.name} (${s.id}) -> ${s.photo_url}`);
  }

  if (patched === 0) {
    console.warn("Не знаємо жодного гриба для патчу");
  }

  // Write back
  const out =
    "// mushroom_catalog.js\n" +
    "// Автогенеровано scripts/patch_js_catalog.mjs. Не редагувати вручну.\n" +
    "window.MUSHROOM_CATALOG = " +
    JSON.stringify(obj) +
    ";\n";

  fs.writeFileSync(JS_CATALOG, out, "utf8");
  console.log(`\nГотово: патчено ${patched} грибів у ${JS_CATALOG}`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
