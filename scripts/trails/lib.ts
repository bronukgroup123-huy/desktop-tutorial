// ============================================================================
// Мережа доріг і стежок області для маршруту «Додому» без інтернету (ADR-022 §22.7).
//
// З OpenStreetMap (вивантаження Geofabrik, вирізане по області):
//   * дороги, лісові дороги (highway=track), стежки (path, footway, bridleway, cycleway…);
//     мости й броди позначаються — річку застосунок «перетинає» лише ними;
//   * вода (озера, ставки, водосховища, широкі річки — полігони) і болота (natural=wetland) —
//     перешкоди: відрізок навпростець через них застосунок не пропонує, а дорогу через болото
//     ставить в останню чергу;
//   * річки й канали (лінії) — теж перешкода для «навпростець».
// Граф: вузли — перехрестя й кінці доріг; ребро — шматок дороги між ними з проміжними точками.
// Файл — двійковий (`MRT1`, little-endian), gzip; формат дзеркально читає застосунок
// (`flutter_client/lib/features/safety/hike/trails.dart`).
// Дані: © OpenStreetMap contributors (ODbL).
// ============================================================================

// deno-lint-ignore no-explicit-any
type Feature = any;

export const KIND_ROAD = 1;
export const KIND_TRACK = 2;
export const KIND_PATH = 3;

export const FLAG_BRIDGE = 1;
export const FLAG_FORD = 2;
/** Середина ребра в болоті — застосунок обирає його в останню чергу. */
export const FLAG_WET = 4;

export const BARRIER_WATER = 1;
export const BARRIER_WETLAND = 2;
export const LINE_RIVER = 1;
export const LINE_CANAL = 2;

const ROADS = new Set([
  "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link",
  "unclassified", "residential", "living_street", "service", "road",
]);
const PATHS = new Set(["path", "footway", "bridleway", "cycleway", "steps", "pedestrian"]);

/** Тип дороги для пішохода; `null` — не для ходьби (автомагістраль, будується, закрито). */
export function highwayKind(tags: Record<string, string> = {}): { kind: number; flags: number } | null {
  const h = tags.highway;
  if (!h) return null;
  const kind = h === "track" ? KIND_TRACK : PATHS.has(h) ? KIND_PATH : ROADS.has(h) ? KIND_ROAD : 0;
  if (!kind) return null;
  if (tags.area === "yes") return null;
  const access = tags.foot ?? tags.access;
  if (access === "no" || access === "private") return null;
  let flags = 0;
  if (tags.bridge && tags.bridge !== "no") flags |= FLAG_BRIDGE;
  if (tags.ford && tags.ford !== "no") flags |= FLAG_FORD;
  return { kind, flags };
}

/** Вода / болото (полігон) або річка / канал (лінія); `null` — не перешкода. */
export function barrierOf(tags: Record<string, string> = {}, geometry: string): { line: boolean; type: number } | null {
  const poly = geometry === "Polygon" || geometry === "MultiPolygon";
  if (poly) {
    if (tags.natural === "wetland") return { line: false, type: BARRIER_WETLAND };
    if (tags.natural === "water" || tags.landuse === "reservoir" || tags.landuse === "basin" || tags.waterway === "riverbank") {
      return { line: false, type: BARRIER_WATER };
    }
    return null;
  }
  if (geometry === "LineString" || geometry === "MultiLineString") {
    if (tags.waterway === "river") return { line: true, type: LINE_RIVER };
    if (tags.waterway === "canal") return { line: true, type: LINE_CANAL };
  }
  return null;
}

/** Координата в мільйонних градуса (≈ 0,1 м) — спільні вузли OSM збігаються точно. */
export type Pt = [number, number]; // [lat1e6, lng1e6]

const q = (v: number) => Math.round(v * 1e6);

function distM(a: Pt, b: Pt): number {
  const k = Math.cos((a[0] / 1e6) * Math.PI / 180) * 0.111320;
  const dx = (b[1] - a[1]) * k, dy = (b[0] - a[0]) * 0.111320;
  return Math.sqrt(dx * dx + dy * dy);
}

function segDistM(p: Pt, a: Pt, b: Pt): number {
  const k = Math.cos((a[0] / 1e6) * Math.PI / 180) * 0.111320;
  const bx = (b[1] - a[1]) * k, by = (b[0] - a[0]) * 0.111320;
  const px = (p[1] - a[1]) * k, py = (p[0] - a[0]) * 0.111320;
  const len2 = bx * bx + by * by;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, (px * bx + py * by) / len2));
  const dx = px - bx * t, dy = py - by * t;
  return Math.sqrt(dx * dx + dy * dy);
}

/** Спрощення лінії (Дуглас — Пекер), кінці лишаються. */
export function simplify(pts: Pt[], tolM: number): Pt[] {
  if (pts.length <= 2) return pts;
  const keep = new Uint8Array(pts.length);
  keep[0] = keep[pts.length - 1] = 1;
  const stack: Array<[number, number]> = [[0, pts.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop()!;
    let max = -1, at = -1;
    for (let i = a + 1; i < b; i++) {
      const d = segDistM(pts[i], pts[a], pts[b]);
      if (d > max) {
        max = d;
        at = i;
      }
    }
    if (max > tolM) {
      keep[at] = 1;
      stack.push([a, at], [at, b]);
    }
  }
  return pts.filter((_, i) => keep[i]);
}

function pointInRing(p: Pt, ring: Pt[]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [yi, xi] = ring[i], [yj, xj] = ring[j];
    if ((yi > p[0]) !== (yj > p[0]) && p[1] < ((xj - xi) * (p[0] - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function ringAreaM2(ring: Pt[]): number {
  if (ring.length < 3) return 0;
  const k = Math.cos((ring[0][0] / 1e6) * Math.PI / 180) * 0.111320;
  let s = 0;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    s += (ring[j][1] * k) * (ring[i][0] * 0.111320) - (ring[i][1] * k) * (ring[j][0] * 0.111320);
  }
  return Math.abs(s / 2);
}

export interface TrailGraph {
  nodes: Pt[];
  edges: Array<{ a: number; b: number; kind: number; flags: number; pts: Pt[] }>;
  polys: Array<{ type: number; ring: Pt[] }>;
  lines: Array<{ type: number; pts: Pt[] }>;
  stats: Record<string, number>;
}

/** Збирає граф області з об'єктів GeoJSON (osmium export, теги — у properties). */
export class TrailBuilder {
  private ways: Array<{ pts: Pt[]; kind: number; flags: number }> = [];
  private polys: Array<{ type: number; ring: Pt[] }> = [];
  private lines: Array<{ type: number; pts: Pt[] }> = [];
  totals = { input: 0, ways: 0, polys: 0, lines: 0, skipped: 0 };

  constructor(private opts: { minPolyM2?: number; edgeTolM?: number; barrierTolM?: number } = {}) {}

  add(f: Feature): void {
    this.totals.input++;
    const g = f?.geometry;
    const tags = (f?.properties ?? {}) as Record<string, string>;
    if (!g?.type || !g.coordinates) return void this.totals.skipped++;
    const hw = g.type === "LineString" ? highwayKind(tags) : null;
    if (hw) {
      const pts = (g.coordinates as number[][]).map(([lng, lat]) => [q(lat), q(lng)] as Pt);
      if (pts.length >= 2) {
        this.ways.push({ pts, ...hw });
        this.totals.ways++;
      }
      return;
    }
    const barrier = barrierOf(tags, g.type);
    if (!barrier) return void this.totals.skipped++;
    const tol = this.opts.barrierTolM ?? 8;
    if (barrier.line) {
      const parts: number[][][] = g.type === "LineString" ? [g.coordinates] : g.coordinates;
      for (const part of parts) {
        const pts = simplify(part.map(([lng, lat]) => [q(lat), q(lng)] as Pt), tol);
        if (pts.length >= 2) {
          this.lines.push({ type: barrier.type, pts });
          this.totals.lines++;
        }
      }
      return;
    }
    const polys: number[][][][] = g.type === "Polygon" ? [g.coordinates] : g.coordinates;
    for (const poly of polys) {
      const ring = simplify((poly[0] ?? []).map(([lng, lat]) => [q(lat), q(lng)] as Pt), tol);
      if (ring.length < 4 || ringAreaM2(ring) < (this.opts.minPolyM2 ?? 1500)) continue;
      this.polys.push({ type: barrier.type, ring });
      this.totals.polys++;
    }
  }

  build(): TrailGraph {
    // Вузли графа — точки, через які проходять ≥ 2 дороги, і кінці доріг.
    const key = (p: Pt) => `${p[0]}:${p[1]}`;
    const uses = new Map<string, number>();
    for (const w of this.ways) {
      for (let i = 0; i < w.pts.length; i++) {
        const k = key(w.pts[i]);
        const end = i === 0 || i === w.pts.length - 1;
        uses.set(k, (uses.get(k) ?? 0) + (end ? 2 : 1));
      }
    }
    const nodeIdx = new Map<string, number>();
    const nodes: Pt[] = [];
    const node = (p: Pt) => {
      const k = key(p);
      let i = nodeIdx.get(k);
      if (i === undefined) {
        i = nodes.length;
        nodeIdx.set(k, i);
        nodes.push(p);
      }
      return i;
    };
    const wet = new BarrierIndex(this.polys.filter((p) => p.type === BARRIER_WETLAND));
    const edges: TrailGraph["edges"] = [];
    const seen = new Set<string>();
    const tol = this.opts.edgeTolM ?? 3;
    let lengthM = 0;
    for (const w of this.ways) {
      let from = 0;
      for (let i = 1; i < w.pts.length; i++) {
        if (i < w.pts.length - 1 && (uses.get(key(w.pts[i])) ?? 0) < 2) continue;
        const piece = w.pts.slice(from, i + 1);
        from = i;
        let len = 0;
        for (let j = 1; j < piece.length; j++) len += distM(piece[j - 1], piece[j]);
        if (len < 0.5) continue;
        const a = node(piece[0]), b = node(piece[piece.length - 1]);
        if (a === b && len < 5) continue;
        const dup = a < b ? `${a}-${b}-${Math.round(len)}` : `${b}-${a}-${Math.round(len)}`;
        if (seen.has(dup)) continue; // та сама дорога двічі (дубль у OSM)
        seen.add(dup);
        const mid = piece[Math.floor(piece.length / 2)];
        const flags = w.flags | (wet.contains(midpointOf(piece, len, mid)) ? FLAG_WET : 0);
        edges.push({ a, b, kind: w.kind, flags, pts: simplify(piece, tol).slice(1, -1) });
        lengthM += len;
      }
    }
    return {
      nodes,
      edges,
      polys: this.polys,
      lines: this.lines,
      stats: {
        nodes: nodes.length,
        edges: edges.length,
        length_km: Math.round(lengthM / 1000),
        wet_edges: edges.filter((e) => e.flags & FLAG_WET).length,
        water_polys: this.polys.filter((p) => p.type === BARRIER_WATER).length,
        wetland_polys: this.polys.filter((p) => p.type === BARRIER_WETLAND).length,
        river_lines: this.lines.length,
      },
    };
  }
}

/** Точка на половині довжини лінії. */
function midpointOf(pts: Pt[], len: number, fallback: Pt): Pt {
  let acc = 0;
  for (let j = 1; j < pts.length; j++) {
    const d = distM(pts[j - 1], pts[j]);
    if (acc + d >= len / 2 && d > 0) {
      const t = (len / 2 - acc) / d;
      return [Math.round(pts[j - 1][0] + (pts[j][0] - pts[j - 1][0]) * t), Math.round(pts[j - 1][1] + (pts[j][1] - pts[j - 1][1]) * t)];
    }
    acc += d;
  }
  return fallback;
}

/** Швидка перевірка «точка в болоті»: сітка по рамках полігонів. */
class BarrierIndex {
  private cells = new Map<string, number[]>();
  private boxes: Array<[number, number, number, number]>;
  private static readonly CELL = 5000; // 0,005° ≈ 500 м

  constructor(private polys: Array<{ ring: Pt[] }>) {
    this.boxes = polys.map(({ ring }) => {
      let y0 = Infinity, x0 = Infinity, y1 = -Infinity, x1 = -Infinity;
      for (const [y, x] of ring) {
        y0 = Math.min(y0, y);
        y1 = Math.max(y1, y);
        x0 = Math.min(x0, x);
        x1 = Math.max(x1, x);
      }
      return [y0, x0, y1, x1];
    });
    const C = BarrierIndex.CELL;
    this.boxes.forEach(([y0, x0, y1, x1], i) => {
      for (let cy = Math.floor(y0 / C); cy <= Math.floor(y1 / C); cy++) {
        for (let cx = Math.floor(x0 / C); cx <= Math.floor(x1 / C); cx++) {
          const k = `${cy}:${cx}`;
          (this.cells.get(k) ?? this.cells.set(k, []).get(k)!).push(i);
        }
      }
    });
  }

  contains(p: Pt): boolean {
    const C = BarrierIndex.CELL;
    for (const i of this.cells.get(`${Math.floor(p[0] / C)}:${Math.floor(p[1] / C)}`) ?? []) {
      const [y0, x0, y1, x1] = this.boxes[i];
      if (p[0] < y0 || p[0] > y1 || p[1] < x0 || p[1] > x1) continue;
      if (pointInRing(p, this.polys[i].ring)) return true;
    }
    return false;
  }
}

// ─── Двійковий файл MRT1 ────────────────────────────────────────────────────
// "MRT1" | u32 version | u32 nodes | u32 edges | u32 polys | u32 lines
// nodes: (i32 lat1e6, i32 lng1e6)…
// edges: u32 a, u32 b, u8 kind, u8 flags, u16 n, n × (i32, i32) — проміжні точки
// polys: u8 type, u32 n, n × (i32, i32) — зовнішній контур
// lines: u8 type, u32 n, n × (i32, i32)

export const FORMAT_VERSION = 1;

export function encode(g: TrailGraph): Uint8Array<ArrayBuffer> {
  let size = 24 + g.nodes.length * 8;
  for (const e of g.edges) size += 12 + Math.min(e.pts.length, 65535) * 8;
  for (const p of g.polys) size += 5 + p.ring.length * 8;
  for (const l of g.lines) size += 5 + l.pts.length * 8;
  const buf = new Uint8Array(size);
  const v = new DataView(buf.buffer);
  let o = 0;
  buf.set([0x4d, 0x52, 0x54, 0x31], 0); // MRT1
  o = 4;
  for (const n of [FORMAT_VERSION, g.nodes.length, g.edges.length, g.polys.length, g.lines.length]) {
    v.setUint32(o, n, true);
    o += 4;
  }
  const pt = (p: Pt) => {
    v.setInt32(o, p[0], true);
    v.setInt32(o + 4, p[1], true);
    o += 8;
  };
  for (const n of g.nodes) pt(n);
  for (const e of g.edges) {
    const pts = e.pts.slice(0, 65535);
    v.setUint32(o, e.a, true);
    v.setUint32(o + 4, e.b, true);
    v.setUint8(o + 8, e.kind);
    v.setUint8(o + 9, e.flags);
    v.setUint16(o + 10, pts.length, true);
    o += 12;
    pts.forEach(pt);
  }
  for (const list of [g.polys.map((p) => ({ type: p.type, pts: p.ring })), g.lines]) {
    for (const x of list) {
      v.setUint8(o, x.type);
      v.setUint32(o + 1, x.pts.length, true);
      o += 5;
      x.pts.forEach(pt);
    }
  }
  return buf;
}

export function decode(buf: Uint8Array): Omit<TrailGraph, "stats"> {
  const v = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  if (String.fromCharCode(...buf.slice(0, 4)) !== "MRT1") throw new Error("not MRT1");
  let o = 4;
  const u32 = () => {
    const x = v.getUint32(o, true);
    o += 4;
    return x;
  };
  const pt = (): Pt => {
    const p: Pt = [v.getInt32(o, true), v.getInt32(o + 4, true)];
    o += 8;
    return p;
  };
  u32(); // version
  const [nn, ne, np, nl] = [u32(), u32(), u32(), u32()];
  const nodes = Array.from({ length: nn }, pt);
  const edges = Array.from({ length: ne }, () => {
    const a = u32(), b = u32();
    const kind = v.getUint8(o), flags = v.getUint8(o + 1), n = v.getUint16(o + 2, true);
    o += 4;
    return { a, b, kind, flags, pts: Array.from({ length: n }, pt) };
  });
  const list = (count: number) =>
    Array.from({ length: count }, () => {
      const type = v.getUint8(o);
      const n = v.getUint32(o + 1, true);
      o += 5;
      return { type, pts: Array.from({ length: n }, pt) };
    });
  const polys = list(np).map((p) => ({ type: p.type, ring: p.pts }));
  return { nodes, edges, polys, lines: list(nl) };
}
