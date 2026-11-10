// ============================================================================
// Генератор файлу лісів області (рішення PO 2026-11-10: ліси — файлами, не в Postgres)
//
// OSM (Overpass) → GeoJSON → лише ліси всередині кордону області, ≥ 1 га,
// спрощені (~15 м) → FeatureCollection у ТОМУ Ж форматі, що й v1-forest-zones
// (id, forest_type, type_label, type_color), тож застосунок розбирає його тим
// самим кодом. Тут лише чисті функції — тестуються без мережі.
// ============================================================================

import * as turf from "npm:@turf/turf@7.2.0";
import osmtogeojson from "npm:osmtogeojson@3.0.0-beta.5";
import { forestTypeStyle } from "../../supabase/functions/_shared/v1/forest-styles.ts";

export const MIN_AREA_M2 = 10_000; // 1 га
export const SIMPLIFY_TOLERANCE_DEG = 0.00015; // ≈ 15 м
export const COORD_PRECISION = 5; // ≈ 1 м

// deno-lint-ignore no-explicit-any
type Geo = any;

/** Тип лісу з тегів OSM (species / genus / leaf_type / wood). null — невідомо. */
export function classifyForestType(tags: Record<string, string> = {}): string | null {
  const text = [tags.species, tags["species:en"], tags.genus, tags.taxon, tags["genus:en"]]
    .filter(Boolean).join(" ").toLowerCase();
  const bySpecies: Array<[RegExp, string]> = [
    [/pinus|pine|сосн/, "pine"],
    [/picea|spruce|ялин/, "spruce"],
    [/quercus|oak|дуб/, "oak"],
    [/betula|birch|берез/, "birch"],
    [/populus tremula|aspen|осик/, "aspen"],
    [/alnus|alder|вільх/, "alder"],
    [/fagus|beech|бук/, "beech"],
    [/carpinus|hornbeam|граб/, "hornbeam"],
  ];
  for (const [re, type] of bySpecies) if (re.test(text)) return type;

  const leaf = (tags.leaf_type ?? "").toLowerCase();
  const wood = (tags.wood ?? "").toLowerCase();
  if (leaf === "needleleaved" || wood === "coniferous") return "coniferous";
  if (leaf === "broadleaved" || wood === "deciduous") return "deciduous";
  if (leaf === "mixed" || wood === "mixed") return "mixed";
  return null;
}

/** Сира відповідь Overpass → GeoJSON-полігони (way і relation). */
export function osmToPolygons(osm: unknown): Geo[] {
  const fc = osmtogeojson(osm, { flatProperties: true }) as Geo;
  return (fc.features ?? []).filter((f: Geo) =>
    f.geometry && (f.geometry.type === "Polygon" || f.geometry.type === "MultiPolygon")
  );
}

export interface BuildStats {
  input: number;
  outsideRegion: number;
  tooSmall: number;
  duplicates: number;
  output: number;
}

/**
 * Ліси області у форматі v1-forest-zones.
 * Залишає полігони, «точка на полігоні» яких лежить у межах [region]
 * (та сама логіка, що й у БД), площею ≥ 1 га; спрощує й округлює координати.
 */
export function buildRegionForests(
  polygons: Geo[],
  region: Geo,
  opts: { minAreaM2?: number; tolerance?: number } = {},
): { collection: Geo; stats: BuildStats } {
  const minArea = opts.minAreaM2 ?? MIN_AREA_M2;
  const tolerance = opts.tolerance ?? SIMPLIFY_TOLERANCE_DEG;
  const regionFeature = region.type === "Feature" ? region : turf.feature(region);
  const regionBbox = turf.bbox(regionFeature);
  const stats: BuildStats = { input: polygons.length, outsideRegion: 0, tooSmall: 0, duplicates: 0, output: 0 };
  const seen = new Set<string>();
  const out: Geo[] = [];

  for (const f of polygons) {
    const id = String(f.id ?? f.properties?.id ?? "").replace("/", "").replace(/^way/, "w").replace(/^relation/, "r");
    if (!id || seen.has(id)) {
      stats.duplicates++;
      continue;
    }
    const [minX, minY, maxX, maxY] = turf.bbox(f);
    if (maxX < regionBbox[0] || minX > regionBbox[2] || maxY < regionBbox[1] || minY > regionBbox[3]) {
      stats.outsideRegion++;
      continue;
    }
    if (turf.area(f) < minArea) {
      stats.tooSmall++;
      continue;
    }
    if (!turf.booleanPointInPolygon(turf.pointOnFeature(f), regionFeature)) {
      stats.outsideRegion++;
      continue;
    }
    seen.add(id);

    const simplified = turf.truncate(
      turf.simplify(f, { tolerance, highQuality: false }),
      { precision: COORD_PRECISION, mutate: true },
    );
    const forestType = classifyForestType(f.properties ?? {});
    const style = forestTypeStyle(forestType);
    out.push({
      type: "Feature",
      id,
      geometry: simplified.geometry,
      properties: {
        id,
        forest_type: forestType,
        stand_age_years: null,
        type_label: style.label,
        type_color: style.color,
      },
    });
  }
  stats.output = out.length;
  return { collection: { type: "FeatureCollection", features: out }, stats };
}

/** Розбиває bbox на клітинки ≤ [stepDeg] — Overpass краще тягне невеликі запити. */
export function splitBbox(
  [minX, minY, maxX, maxY]: [number, number, number, number],
  stepDeg = 1,
): Array<[number, number, number, number]> {
  const cells: Array<[number, number, number, number]> = [];
  for (let y = minY; y < maxY; y += stepDeg) {
    for (let x = minX; x < maxX; x += stepDeg) {
      cells.push([x, y, Math.min(x + stepDeg, maxX), Math.min(y + stepDeg, maxY)]);
    }
  }
  return cells;
}

/** Запит Overpass: ліси (way + relation) у клітинці. bbox Overpass — (south,west,north,east). */
export function overpassQuery([minX, minY, maxX, maxY]: [number, number, number, number]): string {
  const b = `${minY},${minX},${maxY},${maxX}`;
  return `[out:json][timeout:600];
(
  way["landuse"="forest"](${b});
  way["natural"="wood"](${b});
  relation["landuse"="forest"](${b});
  relation["natural"="wood"](${b});
);
out geom;`;
}
