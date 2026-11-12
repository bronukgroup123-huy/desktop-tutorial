// ============================================================================
// Генерація файлу лісів ОДНІЄЇ області через Overpass (запасний спосіб; основний —
// build_all.ts з вивантаження Geofabrik) → dist/forests-<slug>.geojson.gz + .json (мета)
//
//   deno run -A scripts/forests/build_region.ts --slug zhytomyrska
//
// Env: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY — кордон області з v1-regions (той самий,
// що й маска на карті). Дані: © OpenStreetMap contributors (ODbL).
// ============================================================================

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { buildRegionForests, osmToPolygons, overpassQuery, splitBbox } from "./lib.ts";
import { writeRegionFiles } from "./output.ts";

// Публічні сервери Overpass часто перевантажені (502/504) — пробуємо кілька по черзі.
const OVERPASS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
];
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

const ATTEMPTS = 9;
const REQUEST_TIMEOUT_MS = 11 * 60_000; // трохи більше за [timeout:600] у запиті

async function overpass(query: string): Promise<unknown> {
  for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
    const endpoint = OVERPASS[attempt % OVERPASS.length];
    let wait = Math.min(180_000, 20_000 * (attempt + 1));
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": USER_AGENT },
        body: new URLSearchParams({ data: query }),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
      if (res.ok) return await res.json();
      const retryAfter = Number(res.headers.get("retry-after"));
      if (Number.isFinite(retryAfter) && retryAfter > 0) wait = Math.min(300_000, retryAfter * 1000);
      await res.body?.cancel();
      console.warn(`  Overpass ${endpoint} → HTTP ${res.status}, retry in ${Math.round(wait / 1000)} s`);
    } catch (e) {
      console.warn(`  Overpass ${endpoint} → ${e}, retry in ${Math.round(wait / 1000)} s`);
    }
    await new Promise((r) => setTimeout(r, wait));
  }
  throw new Error("Overpass failed after retries");
}

type Cell = [number, number, number, number];

/**
 * Ліси клітинки. Якщо сервери не віддають її цілою — ділимо на 4 менші й пробуємо
 * кожну (менший запит перевантажений сервер виконує охочіше). Одна «важка» клітинка
 * більше не валить усю область.
 */
async function cellPolygons(cell: Cell, label: string, depth = 0): Promise<unknown[]> {
  try {
    const p = osmToPolygons(await overpass(overpassQuery(cell)));
    console.log(`  ${label}: ${p.length} polygons`);
    return p;
  } catch (e) {
    if (depth >= 2) throw e;
    const [minX, minY, maxX, maxY] = cell;
    const midX = (minX + maxX) / 2;
    const midY = (minY + maxY) / 2;
    console.warn(`  ${label}: splitting into 4 smaller cells`);
    const parts: Cell[] = [
      [minX, minY, midX, midY],
      [midX, minY, maxX, midY],
      [minX, midY, midX, maxY],
      [midX, midY, maxX, maxY],
    ];
    const out: unknown[] = [];
    for (const [i, part] of parts.entries()) {
      out.push(...await cellPolygons(part, `${label}.${i + 1}`, depth + 1));
      await new Promise((r) => setTimeout(r, 5_000));
    }
    return out;
  }
}

const region = await regionGeometry();
console.log(`Region ${slug} (${region.name}), bbox ${region.bbox.join(",")}`);

const cells = splitBbox(region.bbox, 1);
const polygons: unknown[] = [];
for (const [i, cell] of cells.entries()) {
  console.log(`Overpass cell ${i + 1}/${cells.length}: ${cell.map((v) => v.toFixed(2)).join(",")}`);
  polygons.push(...await cellPolygons(cell, `cell ${i + 1}`));
  await new Promise((r) => setTimeout(r, 5_000)); // ввічливо до Overpass
}

const { collection, stats } = buildRegionForests(polygons, region.geometry);
console.log("Stats:", stats);
if (stats.output === 0) throw new Error("No forests produced — refusing to publish an empty file");
await writeRegionFiles(slug, collection, stats, args.out, { method: "overpass" });
