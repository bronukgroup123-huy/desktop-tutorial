// ============================================================================
// Мережа стежок однієї області → dist/trails-<slug>.bin.gz + trails-<slug>.json (опис).
//
//   osmium extract … → <slug>.osm.pbf (див. regions_config.ts і workflow «Trails data»)
//   osmium tags-filter <slug>.osm.pbf w/highway wr/natural=water,wetland wr/landuse=reservoir,basin \
//     w/waterway=river,canal,riverbank -o <slug>-trails.osm.pbf
//   osmium export <slug>-trails.osm.pbf -f geojsonseq -o <slug>.geojsonseq
//   deno run -A scripts/trails/build_region.ts --input <slug>.geojsonseq --slug <slug> --out dist
// Дані: © OpenStreetMap contributors (ODbL).
// ============================================================================

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { TextLineStream } from "jsr:@std/streams@1/text-line-stream";
import { encode, FORMAT_VERSION, TrailBuilder } from "./lib.ts";

const args = parseArgs(Deno.args, { string: ["input", "slug", "out"], default: { out: "dist" } });
if (!args.input || !args.slug || !/^[a-z0-9][a-z0-9_-]{1,39}$/.test(args.slug)) {
  console.error("Usage: build_region.ts --input <geojsonseq> --slug <slug> [--out dist]");
  Deno.exit(2);
}

async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const builder = new TrailBuilder();
const file = await Deno.open(args.input, { read: true });
const lines = file.readable.pipeThrough(new TextDecoderStream()).pipeThrough(new TextLineStream());
let bad = 0;
for await (const raw of lines) {
  const line = raw.charCodeAt(0) === 0x1e ? raw.slice(1) : raw;
  if (!line.trim()) continue;
  try {
    builder.add(JSON.parse(line));
  } catch {
    bad++;
  }
}
const graph = builder.build();
if (graph.edges.length === 0) throw new Error(`${args.slug}: no trails — refusing to write an empty file`);
const raw = encode(graph);
const gz = new Uint8Array(
  await new Response(new Blob([raw]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer(),
);
const meta = {
  slug: args.slug,
  version: new Date().toISOString(),
  format: FORMAT_VERSION,
  bytes: gz.length,
  raw_bytes: raw.length,
  sha256: await sha256Hex(gz),
  data_file: `trails-${args.slug}.bin.gz`,
  source: "© OpenStreetMap contributors (ODbL)",
  stats: { ...graph.stats, input: builder.totals.input, parse_errors: bad },
};
await Deno.mkdir(args.out, { recursive: true });
await Deno.writeFile(`${args.out}/trails-${args.slug}.bin.gz`, gz);
await Deno.writeTextFile(`${args.out}/trails-${args.slug}.json`, JSON.stringify(meta, null, 2));
console.log(`${args.slug}: ${JSON.stringify(meta.stats)}, ${(gz.length / 1048576).toFixed(1)} MB gz`);
