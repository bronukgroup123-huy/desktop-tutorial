// ============================================================================
// scripts/upload_6_missing.mjs
// Завантажує 6 відсутніх фото у бакет mushroom-catalog-photos
// (потрібні змінні: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
// ============================================================================
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";
import path from "node:path";

const BUCKET = "mushroom-catalog-photos";

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) {
  console.error("ПОМИЛКА: потрібні SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const UPLOADS = [
  { folder: "Гомф булавоподібний, свиняче вухо Gomphus clavatus", target: "gomphus_clavatus.webp" },
  { folder: "Квітохвісник Арчера, антурус Арчера Anthurus archeri", target: "anthurus_archeri.webp" },
  { folder: "Міріостома шийкова (міріостома дірчаста, міріостома стрижневидна) Myriostoma coliforme", target: "myriostoma_coliforme.webp" },
  { folder: "Фелоринія геркулесова, фелоринія пластівчасто-луската Phellorinia herculeana", target: "phellorinia_herculeana.webp" },
  { folder: "Хрящ-молочник чорний, хрящ-молочник деревний Lactarius lignyotus", target: "lactarius_lignyotus.webp" },
  { folder: "Шишкогриб лускатий, лускач Strobilomyces strobilaceus", target: "strobilomyces_strobilaceus.webp" },
];

async function main() {
  let uploaded = 0, failed = 0;
  for (const { folder, target } of UPLOADS) {
    const filePath = path.join("Червона книга (webp)", folder, "large.webp");
    if (!fs.existsSync(filePath)) {
      console.warn(`MISSING: ${filePath}`);
      failed++;
      continue;
    }
    const buffer = fs.readFileSync(filePath);
    const { error } = await supabase.storage
      .from(BUCKET)
      .upload(target, buffer, { upsert: true, contentType: "image/webp" });
    if (error) {
      console.error(`FAILED ${target}:`, error.message);
      failed++;
    } else {
      console.log(`OK ${target}`);
      uploaded++;
    }
  }
  console.log(`\nDone: ${uploaded} uploaded, ${failed} failed`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
