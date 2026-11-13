// ============================================================================
// Ліси ВСІХ областей за один прохід — з вивантаження OpenStreetMap (Geofabrik),
// без запитів до перевантажених публічних серверів Overpass.
//
//   osmium tags-filter ukraine-latest.osm.pbf wr/landuse=forest wr/natural=wood wr/landcover=trees -o forests.osm.pbf
//   osmium export forests.osm.pbf -f geojsonseq --geometry-types=polygon -u type_id -o forests.geojsonseq
//   deno run -A scripts/forests/build_all.ts --input forests.geojsonseq --out dist [--only zhytomyrska]
//     [--satellite satellite.json]   ← тип лісу за супутником (scripts/forest_type/zonal.py)
//
// Env: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY — список і кордони областей (ті самі, що
// й маска на карті). Дані: © OpenStreetMap contributors (ODbL).
// ============================================================================

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { TextLineStream } from "jsr:@std/streams@1/text-line-stream";
import { ForestCollector, type RegionInput, type SatelliteTypes } from "./lib.ts";
import { writeRegionFiles } from "./output.ts";

const args = parseArgs(Deno.args, { string: ["input", "out", "only", "satellite"], default: { out: "dist" } });
if (!args.input) {
  console.error("Usage: build_all.ts --input forests.geojsonseq [--out dist] [--only <slug>] [--satellite <json>]");
  Deno.exit(2);
}
if (args.only && !/^[a-z0-9][a-z0-9_-]{1,39}$/.test(args.only)) {
  console.error(`Bad --only slug: ${args.only}`);
  Deno.exit(2);
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env ${name}`);
  return v;
}

async function api(path: string): Promise<unknown> {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(`${env("SUPABASE_URL")}/functions/v1/${path}`, {
      headers: { apikey: env("SUPABASE_PUBLISHABLE_KEY") },
    });
    if (res.ok) return await res.json();
    const body = await res.text();
    if (attempt >= 4 || (res.status < 500 && res.status !== 429)) throw new Error(`${path} → ${res.status}: ${body}`);
    await new Promise((r) => setTimeout(r, 5_000 * attempt));
  }
}

// ─── Області ───────────────────────────────────────────────────────────────
const slugs: string[] = args.only
  ? [args.only]
  : ((await api("regions")) as { data: Array<{ slug: string }> }).data.map((r) => r.slug).sort();
const regions: RegionInput[] = [];
for (const slug of slugs) {
  const { data } = (await api(`v1-regions/${slug}/geometry?detail=high`)) as { data: { geometry: unknown } };
  if (!data?.geometry) {
    console.warn(`⚠ ${slug}: no boundary — skipped`);
    continue;
  }
  regions.push({ slug, geometry: data.geometry });
}
console.log(`Regions: ${regions.length} (${regions.map((r) => r.slug).join(", ")})`);

// ─── Тип лісу за супутником (необов'язково): id лісу → ймовірність «хвойний», % ──
let satellite: SatelliteTypes | undefined;
if (args.satellite) {
  const raw = JSON.parse(await Deno.readTextFile(args.satellite)) as Record<string, number>;
  satellite = new Map(Object.entries(raw).filter(([, v]) => Number.isFinite(v) && v >= 0 && v <= 100));
  console.log(`Satellite forest types: ${satellite.size}`);
}

// ─── Ліси: потоком, по одному об'єкту (файл для всієї України — гігабайти) ────
const collector = new ForestCollector(regions, { satellite });
const file = await Deno.open(args.input, { read: true });
const lines = file.readable.pipeThrough(new TextDecoderStream()).pipeThrough(new TextLineStream());
let parseErrors = 0;
const started = Date.now();
for await (const raw of lines) {
  // geojsonseq (RFC 8142): кожен запис може починатися з символу RS (0x1E).
  const line = raw.charCodeAt(0) === 0x1e ? raw.slice(1) : raw;
  if (!line.trim()) continue;
  let feature: unknown;
  try {
    feature = JSON.parse(line);
  } catch {
    parseErrors++;
    continue;
  }
  collector.add(feature);
  if (collector.totals.input % 100_000 === 0) {
    console.log(`  … ${collector.totals.input} objects, ${Math.round((Date.now() - started) / 1000)} s`);
  }
}
console.log("Totals:", { ...collector.totals, parseErrors });

// ─── Файли областей ────────────────────────────────────────────────────────
let written = 0;
const empty: string[] = [];
for (const { slug } of regions) {
  const { collection, stats } = collector.collection(slug);
  if (stats.output === 0) {
    empty.push(slug); // порожній файл не публікуємо — лишається попередній
    continue;
  }
  await writeRegionFiles(slug, collection, stats, args.out, {
    method: "geofabrik",
    ...(stats.satellite
      ? {
        source: "© OpenStreetMap contributors (ODbL); тип лісу без породи в OSM — " +
          "Copernicus Sentinel-2 (модифіковані дані), ESA WorldCover 2021 (CC BY 4.0)",
      }
      : {}),
  });
  written++;
}
if (empty.length) console.warn(`⚠ No forests for: ${empty.join(", ")} — not written`);
if (written === 0) throw new Error("No forests produced — refusing to publish empty data");
console.log(`Done: ${written} regions in ${Math.round((Date.now() - started) / 1000)} s`);
