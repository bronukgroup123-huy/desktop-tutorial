import { assertEquals } from "jsr:@std/assert@1";
import * as turf from "npm:@turf/turf@7.2.0";
import {
  areaLabel,
  buildRegionForests,
  classifyForest,
  classifyForestType,
  osmToPolygons,
  overpassQuery,
  simplifyForest,
  splitBbox,
} from "./lib.ts";

// «Область» — квадрат 28.0–29.0 × 50.0–51.0.
const REGION = {
  type: "Polygon",
  coordinates: [[[28, 50], [29, 50], [29, 51], [28, 51], [28, 50]]],
};

/** Квадратний ліс з центром (lon, lat) і стороною d° — у форматі Overpass `out geom`. */
function way(id: number, lon: number, lat: number, d: number, tags: Record<string, string>) {
  const h = d / 2;
  const ring = [[lon - h, lat - h], [lon + h, lat - h], [lon + h, lat + h], [lon - h, lat + h], [lon - h, lat - h]];
  return {
    type: "way",
    id,
    tags: { landuse: "forest", ...tags },
    nodes: ring.map((_, i) => id * 10 + (i % 4)),
    geometry: ring.map(([x, y]) => ({ lon: x, lat: y })),
  };
}

const OSM = {
  elements: [
    way(1, 28.5, 50.5, 0.01, { leaf_type: "needleleaved" }), // ~0.8 км² — усередині
    way(2, 28.6, 50.4, 0.01, { species: "Pinus sylvestris" }),
    way(3, 30.5, 50.5, 0.01, {}), // поза областю
    way(4, 28.3, 50.3, 0.0002, {}), // ≈ 0,03 га — замало навіть для гаю
    way(5, 28.4, 50.4, 0.0006, { natural: "wood", name: "Березовий гай" }), // ≈ 0,3 га — малий гай лишається
    way(1, 28.5, 50.5, 0.01, { leaf_type: "needleleaved" }), // дубль з сусідньої клітинки Overpass
  ],
};

Deno.test("forests: ліси області ≥ 0,1 га (малі гаї теж), без дублів, у форматі v1-forest-zones", () => {
  const polygons = osmToPolygons(OSM);
  const { collection, stats } = buildRegionForests(polygons, REGION);
  assertEquals(stats.output, 3);
  assertEquals(stats.outsideRegion, 1);
  assertEquals(stats.tooSmall, 1);
  assertEquals(stats.small, 1);
  assertEquals(stats.typed, 3);
  const ids = collection.features.map((f: { id: string }) => f.id).sort();
  assertEquals(ids, ["w1", "w2", "w5"]);
  const pine = collection.features.find((f: { id: string }) => f.id === "w2");
  assertEquals(pine.properties.forest_type, "pine");
  assertEquals(pine.properties.type_label, "Сосновий ліс");
  assertEquals(pine.properties.type_color, "#81c784");
  assertEquals(pine.properties.type_source_label, "Порода вказана в OpenStreetMap");
  assertEquals(pine.properties.area_label.startsWith("≈ "), true);
  const grove = collection.features.find((f: { id: string }) => f.id === "w5");
  assertEquals([grove.properties.forest_type, grove.properties.type_source], ["birch", "osm_name"]);
  assertEquals(grove.properties.type_source_label, "Визначено за назвою урочища — може бути неточно");
});

Deno.test("forests: малий гай не руйнується спрощенням (площа зберігається)", () => {
  const g = osmToPolygons({ elements: [way(9, 28.4, 50.4, 0.0005, {})] })[0]; // ≈ 35×55 м
  const area = turf.area(g);
  const geometry = simplifyForest(g, area);
  const after = turf.area(turf.feature(geometry));
  assertEquals(geometry.coordinates[0].length >= 4, true);
  assertEquals(after > area * 0.85, true);
});

Deno.test("forests: підпис площі", () => {
  assertEquals(areaLabel(3_000), "≈ 0,3 га");
  assertEquals(areaLabel(125_000), "≈ 13 га");
  assertEquals(areaLabel(3_500_000), "≈ 3,5 км²");
});

Deno.test("forests: координати округлені до 5 знаків", () => {
  const { collection } = buildRegionForests(osmToPolygons(OSM), REGION);
  const coords = JSON.stringify(collection.features[0].geometry.coordinates);
  assertEquals(/\d\.\d{6,}/.test(coords), false);
});

Deno.test("forests: класифікація типу лісу з тегів OSM", () => {
  assertEquals(classifyForestType({ species: "Pinus sylvestris" }), "pine");
  assertEquals(classifyForestType({ genus: "Quercus" }), "oak");
  assertEquals(classifyForestType({ genus: "Betula" }), "birch");
  assertEquals(classifyForestType({ leaf_type: "needleleaved" }), "coniferous");
  assertEquals(classifyForestType({ leaf_type: "broadleaved" }), "deciduous");
  assertEquals(classifyForestType({ wood: "mixed" }), "mixed");
  assertEquals(classifyForestType({}), null);
});

Deno.test("forests: більше порід, кілька порід → мішаний, назва урочища — запасний варіант", () => {
  assertEquals(classifyForest({ species: "Larix decidua" }), { type: "larch", source: "osm_species" });
  assertEquals(classifyForest({ genus: "Populus" }).type, "poplar");
  assertEquals(classifyForest({ species: "Populus tremula" }).type, "aspen");
  assertEquals(classifyForest({ genus: "Tilia" }).type, "linden");
  assertEquals(classifyForest({ "species:uk": "Бук лісовий" }).type, "beech");
  assertEquals(classifyForest({ species: "Pinus sylvestris;Betula pendula" }), { type: "mixed", source: "osm_species" });
  // порода важливіша за leaf_type, leaf_type — за назву
  assertEquals(classifyForest({ species: "Quercus robur", leaf_type: "mixed" }).type, "oak");
  assertEquals(classifyForest({ leaf_type: "needleleaved", name: "Березовий гай" }), {
    type: "coniferous",
    source: "osm_leaf_type",
  });
  assertEquals(classifyForest({ name: "Сосновий бір" }), { type: "pine", source: "osm_name" });
  assertEquals(classifyForest({ name: "Діброва" }), { type: "oak", source: "osm_name" });
  // суперечлива або нейтральна назва — тип невідомий, без вгадування
  assertEquals(classifyForest({ name: "Урочище Березова діброва" }), { type: null, source: null });
  assertEquals(classifyForest({ name: "Урочище Лісове" }), { type: null, source: null });
  assertEquals(classifyForest({ name: "Боровиця" }).type, null);
});

Deno.test("forests: bbox ділиться на клітинки ≤ 1°, запит Overpass — south,west,north,east", () => {
  const cells = splitBbox([27.2, 49.6, 30.6, 51.6], 1);
  assertEquals(cells.length, 4 * 2);
  assertEquals(cells[0], [27.2, 49.6, 28.2, 50.6]);
  const q = overpassQuery([28, 50, 29, 51]);
  assertEquals(q.includes('relation["landuse"="forest"](50,28,51,29)'), true);
  assertEquals(q.includes('way["natural"="wood"](50,28,51,29)'), true);
  assertEquals(q.includes('way["landcover"="trees"](50,28,51,29)'), true);
});
