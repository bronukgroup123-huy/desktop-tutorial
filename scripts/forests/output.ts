// ============================================================================
// Запис файлу лісів області: dist/forests-<slug>.geojson.gz + forests-<slug>.json (опис).
// Опис (версія, розмір, sha256) застосунок перевіряє раз на добу й перекачує файл
// лише при новій версії. Спільне для збірки з Overpass і з вивантаження Geofabrik.
// ============================================================================

import type { BuildStats } from "./lib.ts";

// deno-lint-ignore no-explicit-any
type Geo = any;

export async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function gzip(bytes: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Скільки лісів кожного типу і звідки тип — для перевірки достовірності визначника. */
export function typeCounts(collection: Geo): { byType: Record<string, number>; bySource: Record<string, number> } {
  const byType: Record<string, number> = {};
  const bySource: Record<string, number> = {};
  for (const f of collection.features) {
    const t = f.properties.forest_type ?? "unknown";
    const src = f.properties.type_source ?? "none";
    byType[t] = (byType[t] ?? 0) + 1;
    bySource[src] = (bySource[src] ?? 0) + 1;
  }
  return { byType, bySource };
}

export async function writeRegionFiles(
  slug: string,
  collection: Geo,
  stats: BuildStats,
  outDir: string,
  extra: Record<string, unknown> = {},
): Promise<{ bytes: number; rawBytes: number }> {
  const { byType, bySource } = typeCounts(collection);
  const json = new TextEncoder().encode(JSON.stringify(collection));
  const gz = await gzip(json);
  const meta = {
    slug,
    version: new Date().toISOString(),
    features: stats.output,
    bytes: gz.length,
    raw_bytes: json.length,
    sha256: await sha256Hex(gz),
    data_file: `forests-${slug}.geojson.gz`,
    source: "© OpenStreetMap contributors (ODbL)",
    ...extra,
    stats,
    by_type: byType,
    by_type_source: bySource,
  };
  await Deno.mkdir(outDir, { recursive: true });
  await Deno.writeFile(`${outDir}/forests-${slug}.geojson.gz`, gz);
  await Deno.writeTextFile(`${outDir}/forests-${slug}.json`, JSON.stringify(meta, null, 2));
  console.log(
    `${slug}: ${stats.output} forests (${stats.small} small, ${stats.typed} typed), ` +
      `${(gz.length / 1024 / 1024).toFixed(1)} MB gz, ${(json.length / 1024 / 1024).toFixed(1)} MB raw; ` +
      `types ${JSON.stringify(byType)}; sources ${JSON.stringify(bySource)}`,
  );
  return { bytes: gz.length, rawBytes: json.length };
}
