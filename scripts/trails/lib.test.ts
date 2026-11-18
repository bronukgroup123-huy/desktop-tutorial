import { assertEquals } from "jsr:@std/assert@1";
import {
  BARRIER_WATER, BARRIER_WETLAND, barrierOf, decode, encode, FLAG_BRIDGE, FLAG_WET, highwayKind, KIND_PATH, KIND_ROAD,
  KIND_TRACK, LINE_RIVER, simplify, TrailBuilder, type TrailGraph,
} from "./lib.ts";

function fixtureGraph(): TrailGraph {
  const b = new TrailBuilder();
  for (const line of Deno.readTextFileSync(new URL("./fixture.geojsonseq", import.meta.url)).split("\n")) {
    if (line.trim()) b.add(JSON.parse(line));
  }
  return b.build();
}

Deno.test("Типи доріг для пішохода: автомагістраль і приватні — ні; міст і брід позначено", () => {
  assertEquals(highwayKind({ highway: "track" }), { kind: KIND_TRACK, flags: 0 });
  assertEquals(highwayKind({ highway: "footway", bridge: "yes" }), { kind: KIND_PATH, flags: FLAG_BRIDGE });
  assertEquals(highwayKind({ highway: "residential" })?.kind, KIND_ROAD);
  assertEquals(highwayKind({ highway: "motorway" }), null);
  assertEquals(highwayKind({ highway: "track", access: "private" }), null);
  assertEquals(highwayKind({ highway: "track", access: "private", foot: "yes" })?.kind, KIND_TRACK);
  assertEquals(highwayKind({ highway: "pedestrian", area: "yes" }), null);
  assertEquals(barrierOf({ natural: "wetland" }, "Polygon"), { line: false, type: BARRIER_WETLAND });
  assertEquals(barrierOf({ natural: "water" }, "MultiPolygon"), { line: false, type: BARRIER_WATER });
  assertEquals(barrierOf({ waterway: "river" }, "LineString"), { line: true, type: LINE_RIVER });
  assertEquals(barrierOf({ waterway: "stream" }, "LineString"), null);
  assertEquals(barrierOf({ landuse: "forest" }, "Polygon"), null);
});

Deno.test("Граф: вузли — перехрестя й кінці; ребро через болото позначено; міст — прапорцем", () => {
  const g = fixtureGraph();
  // Дорога, лісова дорога, стежка, дорога через болото, стежка на захід (3 шматки, один — міст).
  assertEquals(g.edges.length, 7);
  assertEquals(g.nodes.length, 7); // машина, перехрестя, схід, південний схід, два кінці мосту, захід
  const wet = g.edges.filter((e) => e.flags & FLAG_WET);
  assertEquals(wet.length, 1);
  assertEquals(wet[0].kind, KIND_TRACK);
  assertEquals(g.edges.filter((e) => e.flags & FLAG_BRIDGE).length, 1);
  // Проміжні точки прямих доріг спрощено.
  assertEquals(g.edges.every((e) => e.pts.length === 0), true);
  assertEquals(g.polys.map((p) => p.type).sort(), [BARRIER_WATER, BARRIER_WETLAND]);
  assertEquals(g.lines.length, 1);
  assertEquals(g.stats.wet_edges, 1);
});

Deno.test("Двійковий файл: туди й назад без втрат", () => {
  const g = fixtureGraph();
  const back = decode(encode(g));
  assertEquals(back.nodes, g.nodes);
  assertEquals(back.edges, g.edges);
  assertEquals(back.polys, g.polys);
  assertEquals(back.lines, g.lines);
});

Deno.test("Тестовий файл застосунку збігається з тим, що будує генератор", () => {
  const app = Deno.readFileSync(new URL("../../flutter_client/test/fixtures/trails-test.bin", import.meta.url));
  assertEquals(app, encode(fixtureGraph()));
});

Deno.test("Спрощення: точки на прямій зникають, вигин лишається", () => {
  const line: Array<[number, number]> = [[0, 0], [1000, 1], [2000, 0], [2000, 3000]];
  assertEquals(simplify(line, 3), [[0, 0], [2000, 0], [2000, 3000]]);
});
