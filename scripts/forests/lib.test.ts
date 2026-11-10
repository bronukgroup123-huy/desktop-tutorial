import { assertEquals } from "jsr:@std/assert@1";
import { buildRegionForests, classifyForestType, osmToPolygons, overpassQuery, splitBbox } from "./lib.ts";

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
    way(4, 28.3, 50.3, 0.0005, {}), // < 1 га
    way(1, 28.5, 50.5, 0.01, { leaf_type: "needleleaved" }), // дубль з сусідньої клітинки Overpass
  ],
};

Deno.test("forests: лише ліси області ≥ 1 га, без дублів, у форматі v1-forest-zones", () => {
  const polygons = osmToPolygons(OSM);
  const { collection, stats } = buildRegionForests(polygons, REGION);
  assertEquals(stats.output, 2);
  assertEquals(stats.outsideRegion, 1);
  assertEquals(stats.tooSmall, 1);
  const ids = collection.features.map((f: { id: string }) => f.id).sort();
  assertEquals(ids, ["w1", "w2"]);
  const pine = collection.features.find((f: { id: string }) => f.id === "w2");
  assertEquals(pine.properties, {
    id: "w2",
    forest_type: "pine",
    stand_age_years: null,
    type_label: "Сосновий ліс",
    type_color: "#81c784",
  });
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

Deno.test("forests: bbox ділиться на клітинки ≤ 1°, запит Overpass — south,west,north,east", () => {
  const cells = splitBbox([27.2, 49.6, 30.6, 51.6], 1);
  assertEquals(cells.length, 4 * 2);
  assertEquals(cells[0], [27.2, 49.6, 28.2, 50.6]);
  const q = overpassQuery([28, 50, 29, 51]);
  assertEquals(q.includes('relation["landuse"="forest"](50,28,51,29)'), true);
  assertEquals(q.includes('way["natural"="wood"](50,28,51,29)'), true);
});
