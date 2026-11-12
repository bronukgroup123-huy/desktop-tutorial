// ============================================================================
// Генерація файлу лісів області → dist/forests-<slug>.geojson.gz + .json (мета)
//
//   deno run -A scripts/forests/build_region.ts --slug zhytomyrska
//
// Env: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY — кордон області з v1-regions (той самий,
// що й маска на карті). Дані: © OpenStreetMap contributors (ODbL).
// ============================================================================

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { buildRegionForests, osmToPolygons, overpassQuery, splitBbox } from "./lib.ts";

const OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"];
const USER_AGENT = "MushroomRadar-forest-builder/1.0 (+https://github.com/bronukgroup123-huy/desktop-tutorial)";

const args = parseArgs(Deno.args, { string: ["slug", "out"], default: { out: "dist" } });
const slug = args.slug;
if (!slug || !/^[a-z0-9][a-z0-9_-]{1,31}$/.test(slug)) {
  console.error("Usage: build_region.ts --slug <region-slug>");
  Deno.exit(2);
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env ${name}`);
  return v;
}

async function regionGeometry(): Promise<{ geometry: unknown; bbox: [number, number, number, number]; name: string }> {
  const url = `${env("SUPABASE_URL")}/functions/v1/v1-regions/${slug}/geometry?detail=high`;
  const res = await fetch(url, { headers: { apikey: env("SUPABASE_PUBLISHABLE_KEY") } });
  if (!res.ok) throw new Error(`Region geometry ${res.status}: ${await res.text()}`);
  const { data } = await res.json();
  return { geometry: data.geometry, bbox: data.bbox, name: data.name };
}

async function overpass(query: string): Promise<unknown> {
  for (let attempt = 0; attempt < 6; attempt++) {
    const endpoint = OVERPASS[attempt % OVERPASS.length];
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": USER_AGENT },
        body: new URLSearchParams({ data: query }),
      });
      if (res.ok) return await res.json();
      console.warn(`  Overpass ${endpoint} → HTTP ${res.status}, retry`);
    } catch (e) {
      console.warn(`  Overpass ${endpoint} → ${e}, retry`);
    }
    await new Promise((r) => setTimeout(r, 15_000 * (attempt + 1)));
  }
  throw new Error("Overpass failed after retries");
}

async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function gzip(bytes: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

const region = await regionGeometry();
console.log(`Region ${slug} (${region.name}), bbox ${region.bbox.join(",")}`);

const cells = splitBbox(region.bbox, 1);
const polygons: unknown[] = [];
for (const [i, cell] of cells.entries()) {
  console.log(`Overpass cell ${i + 1}/${cells.length}: ${cell.map((v) => v.toFixed(2)).join(",")}`);
  const osm = await overpass(overpassQuery(cell));
  const p = osmToPolygons(osm);
  console.log(`  ${p.length} polygons`);
  polygons.push(...p);
  await new Promise((r) => setTimeout(r, 5_000)); // ввічливо до Overpass
}

const { collection, stats } = buildRegionForests(polygons, region.geometry);
console.log("Stats:", stats);
if (stats.output === 0) throw new Error("No forests produced — refusing to publish an empty file");

// Скільки лісів кожного типу і звідки тип — для перевірки достовірності визначника.
const byType: Record<string, number> = {};
const bySource: Record<string, number> = {};
for (const f of collection.features) {
  const t = f.properties.forest_type ?? "unknown";
  const src = f.properties.type_source ?? "none";
  byType[t] = (byType[t] ?? 0) + 1;
  bySource[src] = (bySource[src] ?? 0) + 1;
}
console.log("By type:", byType);
console.log("By type source:", bySource);

const json = new TextEncoder().encode(JSON.stringify(collection));
const gz = await gzip(json);
const version = new Date().toISOString();
const meta = {
  slug,
  version,
  features: stats.output,
  bytes: gz.length,
  raw_bytes: json.length,
  sha256: await sha256Hex(gz),
  data_file: `forests-${slug}.geojson.gz`,
  source: "© OpenStreetMap contributors (ODbL)",
  stats,
  by_type: byType,
  by_type_source: bySource,
};

await Deno.mkdir(args.out, { recursive: true });
await Deno.writeFile(`${args.out}/forests-${slug}.geojson.gz`, gz);
await Deno.writeTextFile(`${args.out}/forests-${slug}.json`, JSON.stringify(meta, null, 2));
console.log(`Wrote ${args.out}/forests-${slug}.geojson.gz — ${(gz.length / 1024 / 1024).toFixed(1)} MB gz, ` +
  `${(json.length / 1024 / 1024).toFixed(1)} MB raw, ${stats.output} forests`);
