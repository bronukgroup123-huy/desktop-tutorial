// ============================================================================
// Генератор файлу лісів області (рішення PO 2026-11-10: ліси — файлами, не в Postgres)
//
// OSM (Overpass) → GeoJSON → лише ліси всередині кордону області, ≥ 0,1 га
// (малі гаї й переліски теж), спрощені під розмір лісу → FeatureCollection у
// ТОМУ Ж форматі, що й v1-forest-zones (id, forest_type, type_label, type_color),
// плюс дані для визначника лісу: площа і звідки взято тип (type_source_label).
// Тут лише чисті функції — тестуються без мережі.
// ============================================================================

import * as turf from "npm:@turf/turf@7.2.0";
import osmtogeojson from "npm:osmtogeojson@3.0.0-beta.5";
import { forestTypeStyle } from "../../supabase/functions/_shared/v1/forest-styles.ts";

/** Мінімальна площа лісу: 0,1 га ≈ 30×30 м — малі гаї й переліски лишаються. */
export const MIN_AREA_M2 = 1_000;
/** Найбільший допуск спрощення (великі масиви): ≈ 15 м. */
export const SIMPLIFY_TOLERANCE_DEG = 0.00015;
export const COORD_PRECISION = 5; // ≈ 1 м
const M_PER_DEG = 111_320;
/** Спрощення не має з'їдати більше за цю частку площі — інакше контур без спрощення. */
const MAX_AREA_LOSS = 0.15;

// deno-lint-ignore no-explicit-any
type Geo = any;

/** Звідки взято тип лісу — показується у визначнику лісу, щоб було видно надійність. */
export type ForestTypeSource = "osm_species" | "osm_leaf_type" | "osm_name";

export const TYPE_SOURCE_LABEL: Record<ForestTypeSource | "none", string> = {
  osm_species: "Порода вказана в OpenStreetMap",
  osm_leaf_type: "У OpenStreetMap вказано лише хвойний / листяний",
  osm_name: "Визначено за назвою урочища — може бути неточно",
  none: "Порода в OpenStreetMap не вказана",
};

// Порядок важливий: осика (Populus tremula) — до тополі (Populus).
const SPECIES: Array<[RegExp, string]> = [
  [/pinus|\bpine\b|сосн/, "pine"],
  [/picea|spruce|ялин|(^|[^а-яіїєґ])ель/, "spruce"],
  [/larix|larch|модрин|лиственн/, "larch"],
  [/abies|\bfir\b|ялиц|пихт/, "fir"],
  [/quercus|\boak\b|дуб/, "oak"],
  [/betula|birch|берез/, "birch"],
  [/populus tremula|aspen|осик|осин/, "aspen"],
  [/alnus|alder|вільх|ольх/, "alder"],
  [/fagus|beech|(^|[^а-яіїєґ])бук([^а-яіїєґ]|$)/, "beech"],
  [/carpinus|hornbeam|граб/, "hornbeam"],
  [/fraxinus|\bash\b|ясен/, "ash"],
  [/\bacer\b|maple|клен/, "maple"],
  [/tilia|linden|(^|[^а-яіїєґ])лип/, "linden"],
  [/robinia|black locust|акаці/, "robinia"],
  [/populus|poplar|топол/, "poplar"],
  [/salix|willow|верб/, "willow"],
];

/** Усі породи, згадані в тексті (тег може містити кілька: `Pinus sylvestris;Betula pendula`). */
function speciesIn(text: string): string[] {
  const found: string[] = [];
  for (const part of text.split(/[;,/]|\s+та\s+|\s+and\s+/)) {
    const p = part.trim();
    if (!p) continue;
    const hit = SPECIES.find(([re]) => re.test(p));
    if (hit && !found.includes(hit[1])) found.push(hit[1]);
  }
  return found;
}

// Назви урочищ: «Сосновий бір», «Березовий гай», «Діброва», «Ялинник»… Лише явні слова.
const NAME_HINTS: Array<[RegExp, string]> = [
  [/сосн|(^|[^а-яіїєґ])(бір|бор)([^а-яіїєґ]|$)/, "pine"],
  [/ялин|ельник/, "spruce"],
  [/дубо?в|дібров|дубняк|дубрав/, "oak"],
  [/берез/, "birch"],
  [/осик|осич|осинник/, "aspen"],
  [/вільш|вільх|ольх/, "alder"],
  [/бучин|букови[йй] ліс/, "beech"],
  [/грабник|грабняк|грабов[ийа]/, "hornbeam"],
];

/** Тип лісу з тегів OSM і звідки він. `type: null` — невідомо. */
export function classifyForest(tags: Record<string, string> = {}): {
  type: string | null;
  source: ForestTypeSource | null;
} {
  const text = [
    tags.species, tags["species:en"], tags["species:uk"], tags["species:ru"],
    tags.genus, tags["genus:en"], tags["genus:uk"], tags.taxon, tags["taxon:en"], tags["taxon:uk"],
  ].filter(Boolean).join(";").toLowerCase();
  const species = speciesIn(text);
  if (species.length === 1) return { type: species[0], source: "osm_species" };
  if (species.length > 1) return { type: "mixed", source: "osm_species" };

  const leaf = (tags.leaf_type ?? "").toLowerCase();
  const wood = (tags.wood ?? "").toLowerCase();
  if (leaf === "needleleaved" || wood === "coniferous") return { type: "coniferous", source: "osm_leaf_type" };
  if (leaf === "broadleaved" || wood === "deciduous") return { type: "deciduous", source: "osm_leaf_type" };
  if (leaf === "mixed" || wood === "mixed") return { type: "mixed", source: "osm_leaf_type" };

  const name = [tags.name, tags["name:uk"], tags["name:ru"]].filter(Boolean).join(" ").toLowerCase();
  if (name) {
    const hits = [...new Set(NAME_HINTS.filter(([re]) => re.test(name)).map(([, t]) => t))];
    if (hits.length === 1) return { type: hits[0], source: "osm_name" };
  }
  return { type: null, source: null };
}

/** Сумісність: лише тип лісу з тегів OSM. */
export function classifyForestType(tags: Record<string, string> = {}): string | null {
  return classifyForest(tags).type;
}

/** Площа українською: «≈ 0,4 га», «≈ 12 га», «≈ 3,5 км²». */
export function areaLabel(m2: number): string {
  if (m2 >= 1_000_000) {
    const km2 = m2 / 1_000_000;
    return `≈ ${(km2 < 10 ? km2.toFixed(1) : String(Math.round(km2))).replace(".", ",")} км²`;
  }
  const ha = m2 / 10_000;
  return `≈ ${(ha < 10 ? ha.toFixed(1) : String(Math.round(ha))).replace(".", ",")} га`;
}

/** Допуск спрощення під розмір лісу: малий гай не має перетворитися на трикутник. */
export function toleranceFor(areaM2: number, maxTolerance = SIMPLIFY_TOLERANCE_DEG): number {
  // ≈ 1/15 сторони квадрата тієї ж площі, але не більше за maxTolerance.
  return Math.min(maxTolerance, Math.sqrt(areaM2) / 15 / M_PER_DEG);
}

/** Спрощення, яке не руйнує малі контури: інакше повертається неспрощений (округлений). */
export function simplifyForest(f: Geo, areaM2: number, maxTolerance = SIMPLIFY_TOLERANCE_DEG): Geo {
  const original = turf.truncate(turf.feature(f.geometry), { precision: COORD_PRECISION });
  try {
    const simplified = turf.truncate(
      turf.simplify(turf.feature(f.geometry), { tolerance: toleranceFor(areaM2, maxTolerance), highQuality: false }),
      { precision: COORD_PRECISION, mutate: true },
    );
    const rings: number[][][] = simplified.geometry.type === "Polygon"
      ? simplified.geometry.coordinates
      : simplified.geometry.coordinates.flat();
    if (rings.some((r) => r.length < 4)) return original.geometry;
    if (turf.area(simplified) < areaM2 * (1 - MAX_AREA_LOSS)) return original.geometry;
    return simplified.geometry;
  } catch {
    return original.geometry;
  }
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
  /** Ліси 0,1–1 га (раніше відкидались). */
  small: number;
  /** Ліси з відомим типом. */
  typed: number;
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
  const stats: BuildStats = {
    input: polygons.length, outsideRegion: 0, tooSmall: 0, duplicates: 0, output: 0, small: 0, typed: 0,
  };
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
    const area = turf.area(f);
    if (area < minArea) {
      stats.tooSmall++;
      continue;
    }
    if (!turf.booleanPointInPolygon(turf.pointOnFeature(f), regionFeature)) {
      stats.outsideRegion++;
      continue;
    }
    seen.add(id);
    if (area < 10_000) stats.small++;

    const { type: forestType, source } = classifyForest(f.properties ?? {});
    if (forestType) stats.typed++;
    const style = forestTypeStyle(forestType);
    out.push({
      type: "Feature",
      id,
      geometry: simplifyForest(f, area, tolerance),
      properties: {
        id,
        forest_type: forestType,
        stand_age_years: null,
        type_label: style.label,
        type_color: style.color,
        // Визначник лісу: площа і надійність типу (готові підписи — Thin Client).
        area_m2: Math.round(area),
        area_label: areaLabel(area),
        type_source: source,
        type_source_label: TYPE_SOURCE_LABEL[source ?? "none"],
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
  way["landcover"="trees"](${b});
  relation["landuse"="forest"](${b});
  relation["natural"="wood"](${b});
  relation["landcover"="trees"](${b});
);
out geom;`;
}
