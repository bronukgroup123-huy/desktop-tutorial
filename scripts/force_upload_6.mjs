import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";
import path from "node:path";
import dotenv from "dotenv";

dotenv.config();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = process.env.SUPABASE_BUCKET || "mushroom-photos";

const RED_BOOK_DIR = "/workspaces/desktop-tutorial/Червона книга (webp)";

const UPLOADS = [
  { folder: "Гомф булавоподібний, свиняче вухо Gomphus clavatus", target: "gomphus_clavatus.webp" },
  { folder: "Квітохвісник Арчера, антурус Арчера Anthurus archeri", target: "anthurus_archeri.webp" },
  { folder: "Міріостома шийкова (міріостома дірчаста, міріостома стрижневидна) Myriostoma coliforme", target: "myriostoma_coliforme.webp" },
  { folder: "Фелоринія геркулесова, фелоринія пластівчасто-луската Phellorinia herculeana", target: "phellorinia_herculeana.webp" },
  { folder: "Хрящ-молочник чорний, хрящ-молочник деревний Lactarius lignyotus", target: "lactarius_lignyotus.webp" },
  { folder: "Шишкогриб лускатий, лускач Strobilomyces strobilaceus", target: "strobilomyces_strobilaceus.webp" },
];

async function main() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars");
    process.exit(1);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let uploaded = 0;
  let failed = 0;

  for (const { folder, target } of UPLOADS) {
    const filePath = path.join(RED_BOOK_DIR, folder, "large.webp");

    if (!fs.existsSync(filePath)) {
      console.error(`MISSING: ${filePath}`);
      failed++;
      continue;
    }

    const buffer = fs.readFileSync(filePath);

    const { data, error } = await supabase.storage
      .from(BUCKET)
      .upload(target, buffer, {
        upsert: true,
        contentType: "image/webp",
      });

    if (error) {
      console.error(`FAILED ${target}:`, error.message);
      failed++;
    } else {
      console.log(`OK ${target} -> ${data.path} (${buffer.length} bytes)`);
      uploaded++;
    }
  }

  console.log(`\nDone: ${uploaded} uploaded, ${failed} failed`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
