import fs from "node:fs";

const JS_CATALOG = "web-guardian/public/mushroom_catalog.js";
const SUPABASE_URL = "https://wrukmuxdbkbmkygfasai.supabase.co";
const BUCKET = "mushroom-photos";

// 6 проблемних грибів, у яких імена файлів не співпадають з id
const SPECIAL = {
  "Гомф булавоподібний": "gomphus_clavatus.webp",
  "Квітохвісник Арчера": "anthurus_archeri.webp",
  "Міріостома шийкова": "myriostoma_coliforme.webp",
  "Фелоринія геркулесова": "phellorinia_herculeana.webp",
  "Хрящ-молочник чорний": "lactarius_lignyotus.webp",
  "Шишкогриб лускатий": "strobilomyces_strobilaceus.webp",
};

function filenameFor(species) {
  if (SPECIAL[species.name]) return SPECIAL[species.name];
  return `${species.id}.webp`;
}

function cleanPhotoUrl(raw) {
  if (typeof raw !== "string") return null;
  let p = raw.trim();
  // прибрати оточляючі кавички (включає екраніровані)
  while (p.startsWith('"') || p.startsWith('\\"')) p = p.slice(1);
  while (p.endsWith('"') || p.endsWith('\\"')) p = p.slice(0, -1);
  p = p.replace(/\\"/g, '"').trim();
  if (p.startsWith("http://") || p.startsWith("https://")) return p;
  return null;
}

const src = fs.readFileSync(JS_CATALOG, "utf8");
const marker = "window.MUSHROOM_CATALOG = ";
const idx = src.indexOf(marker);
if (idx === -1) throw new Error("Не знайдено window.MUSHROOM_CATALOG у " + JS_CATALOG);

const tail = src.slice(idx + marker.length).replace(/;\s*$/, "").trim();
const obj = JSON.parse(tail);
const species = Array.isArray(obj.species) ? obj.species : [];

let patched = 0;
let fixedPhotos = 0;

for (const s of species) {
  if (s.has_photo !== true) continue;

  const fileName = filenameFor(s);
  s.photo_url = `${SUPABASE_URL.replace(/\/$/, "")}/storage/v1/object/public/${BUCKET}/${fileName}`;

  // виправити photos масив: photos[0] завжди = photo_url, решта — валідні http URL
  if (Array.isArray(s.photos)) {
    const cleaned = s.photos.map(cleanPhotoUrl).filter(Boolean);
    // залишаємо лише фото з правильного бакета
    const onBucket = cleaned.filter(p => p.includes(`/storage/v1/object/public/${BUCKET}/`));
    s.photos = [s.photo_url, ...onBucket.filter(p => p !== s.photo_url)];
    fixedPhotos++;
  } else {
    s.photos = [s.photo_url];
    fixedPhotos++;
  }

  patched++;
}

const out =
  "// mushroom_catalog.js\n" +
  "// Автогенеровано scripts/restore_all_photo_urls.mjs. Не редагувати вручну.\n" +
  "window.MUSHROOM_CATALOG = " +
  JSON.stringify(obj) +
  ";\n";

fs.writeFileSync(JS_CATALOG, out, "utf8");
console.log(`Готово: photo_url поставлено ${patched} грибам; photos виправлено у ${fixedPhotos}`);
