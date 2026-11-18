import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/hike/hike_nav.dart';

/// Мережа доріг і стежок області (ADR-022 §22.7) — файл `trails-<slug>.bin.gz` (формат MRT1,
/// будує `scripts/trails/lib.ts`). Маршрут «Додому» прокладається на телефоні, без інтернету:
/// дорогами й стежками; річку — лише мостом чи бродом (так у мережі OSM); дорогу через болото —
/// в останню чергу; відрізок навпростець до найближчої стежки — не через воду й болото.

const kKindRoad = 1, kKindTrack = 2, kKindPath = 3;
const kFlagBridge = 1, kFlagFord = 2, kFlagWet = 4;
const kBarrierWater = 1, kBarrierWetland = 2;

NavKind kindName(int kind) => switch (kind) {
      kKindRoad => 'road',
      kKindTrack => 'track',
      _ => 'path',
    };

class _Shape {
  _Shape(this.type, this.lat, this.lng)
      : minLat = lat.reduce(math.min),
        maxLat = lat.reduce(math.max),
        minLng = lng.reduce(math.min),
        maxLng = lng.reduce(math.max);

  final int type;
  final Int32List lat, lng;
  final int minLat, maxLat, minLng, maxLng;
}

class TrailGraph {
  TrailGraph._({
    required this.nodeLat,
    required this.nodeLng,
    required this.edgeA,
    required this.edgeB,
    required this.edgeKind,
    required this.edgeFlags,
    required this.edgeLen,
    required this.geomStart,
    required this.ptLat,
    required this.ptLng,
    required this.adjStart,
    required this.adjEdge,
    required List<_Shape> polys,
    required List<_Shape> lines,
    required Map<int, List<int>> grid,
  })  : _polys = polys,
        _lines = lines,
        _grid = grid;

  /// Розбір файлу MRT1 (розпакованого). Виняток — файл пошкоджено.
  factory TrailGraph.parse(Uint8List bytes) {
    final v = ByteData.sublistView(bytes);
    if (bytes.length < 24 || String.fromCharCodes(bytes.sublist(0, 4)) != 'MRT1') {
      throw const FormatException('Файл стежок пошкоджено');
    }
    var o = 8;
    int u32() {
      final x = v.getUint32(o, Endian.little);
      o += 4;
      return x;
    }

    final nn = u32(), ne = u32(), np = u32(), nl = u32();
    final nodeLat = Int32List(nn), nodeLng = Int32List(nn);
    for (var i = 0; i < nn; i++) {
      nodeLat[i] = v.getInt32(o, Endian.little);
      nodeLng[i] = v.getInt32(o + 4, Endian.little);
      o += 8;
    }
    final edgeA = Uint32List(ne), edgeB = Uint32List(ne);
    final edgeKind = Uint8List(ne), edgeFlags = Uint8List(ne);
    final geomStart = Int32List(ne + 1);
    final lat = <int>[], lng = <int>[];
    for (var i = 0; i < ne; i++) {
      edgeA[i] = u32();
      edgeB[i] = u32();
      edgeKind[i] = v.getUint8(o);
      edgeFlags[i] = v.getUint8(o + 1);
      final n = v.getUint16(o + 2, Endian.little);
      o += 4;
      geomStart[i] = lat.length;
      lat.add(nodeLat[edgeA[i]]);
      lng.add(nodeLng[edgeA[i]]);
      for (var k = 0; k < n; k++) {
        lat.add(v.getInt32(o, Endian.little));
        lng.add(v.getInt32(o + 4, Endian.little));
        o += 8;
      }
      lat.add(nodeLat[edgeB[i]]);
      lng.add(nodeLng[edgeB[i]]);
    }
    geomStart[ne] = lat.length;
    final ptLat = Int32List.fromList(lat), ptLng = Int32List.fromList(lng);
    List<_Shape> shapes(int count) {
      final out = <_Shape>[];
      for (var i = 0; i < count; i++) {
        final type = v.getUint8(o);
        final n = v.getUint32(o + 1, Endian.little);
        o += 5;
        final la = Int32List(n), lo = Int32List(n);
        for (var k = 0; k < n; k++) {
          la[k] = v.getInt32(o, Endian.little);
          lo[k] = v.getInt32(o + 4, Endian.little);
          o += 8;
        }
        if (n >= 2) out.add(_Shape(type, la, lo));
      }
      return out;
    }

    final polys = shapes(np), lines = shapes(nl);

    // Довжини ребер і суміжність (CSR).
    final edgeLen = Float64List(ne);
    final degree = Int32List(nn + 1);
    for (var i = 0; i < ne; i++) {
      var len = 0.0;
      for (var k = geomStart[i] + 1; k < geomStart[i + 1]; k++) {
        len += _distE6(ptLat[k - 1], ptLng[k - 1], ptLat[k], ptLng[k]);
      }
      edgeLen[i] = len;
      degree[edgeA[i]]++;
      degree[edgeB[i]]++;
    }
    final adjStart = Int32List(nn + 1);
    for (var i = 0; i < nn; i++) {
      adjStart[i + 1] = adjStart[i] + degree[i];
    }
    final fill = Int32List.fromList(adjStart.sublist(0, nn));
    final adjEdge = Int32List(adjStart[nn]);
    for (var i = 0; i < ne; i++) {
      adjEdge[fill[edgeA[i]]++] = i;
      adjEdge[fill[edgeB[i]]++] = i;
    }
    // Сітка для пошуку найближчої дороги.
    final grid = <int, List<int>>{};
    for (var i = 0; i < ne; i++) {
      var y0 = 1 << 30, y1 = -(1 << 30), x0 = 1 << 30, x1 = -(1 << 30);
      for (var k = geomStart[i]; k < geomStart[i + 1]; k++) {
        y0 = math.min(y0, ptLat[k]);
        y1 = math.max(y1, ptLat[k]);
        x0 = math.min(x0, ptLng[k]);
        x1 = math.max(x1, ptLng[k]);
      }
      for (var cy = y0 ~/ _cell; cy <= y1 ~/ _cell; cy++) {
        for (var cx = x0 ~/ _cell; cx <= x1 ~/ _cell; cx++) {
          (grid[_cellKey(cy, cx)] ??= []).add(i);
        }
      }
    }
    return TrailGraph._(
      nodeLat: nodeLat,
      nodeLng: nodeLng,
      edgeA: edgeA,
      edgeB: edgeB,
      edgeKind: edgeKind,
      edgeFlags: edgeFlags,
      edgeLen: edgeLen,
      geomStart: geomStart,
      ptLat: ptLat,
      ptLng: ptLng,
      adjStart: adjStart,
      adjEdge: adjEdge,
      polys: polys,
      lines: lines,
      grid: grid,
    );
  }

  final Int32List nodeLat, nodeLng;
  final Uint32List edgeA, edgeB;
  final Uint8List edgeKind, edgeFlags;
  final Float64List edgeLen;
  final Int32List geomStart, ptLat, ptLng;
  final Int32List adjStart, adjEdge;
  final List<_Shape> _polys, _lines;
  final Map<int, List<int>> _grid;

  int get nodeCount => nodeLat.length;
  int get edgeCount => edgeA.length;

  static const _cell = 5000; // 0,005° ≈ 350–550 м
  static int _cellKey(int cy, int cx) => cy * 100000 + cx;

  /// Чи перетинає відрізок a→b воду, болото чи річку: `water` / `wetland` / `river` / `null`.
  String? barrierOn(Geo a, Geo b) {
    final ay = (a.lat * 1e6).round(), ax = (a.lng * 1e6).round();
    final by = (b.lat * 1e6).round(), bx = (b.lng * 1e6).round();
    final y0 = math.min(ay, by), y1 = math.max(ay, by), x0 = math.min(ax, bx), x1 = math.max(ax, bx);
    bool boxHit(_Shape s) => !(s.maxLat < y0 || s.minLat > y1 || s.maxLng < x0 || s.minLng > x1);
    for (final s in _lines) {
      if (!boxHit(s)) continue;
      for (var k = 1; k < s.lat.length; k++) {
        if (_segmentsCross(ay, ax, by, bx, s.lat[k - 1], s.lng[k - 1], s.lat[k], s.lng[k])) return 'river';
      }
    }
    String? found;
    for (final s in _polys) {
      if (!boxHit(s)) continue;
      var hit = _inRing(by, bx, s) || _inRing(ay, ax, s) || _inRing((ay + by) ~/ 2, (ax + bx) ~/ 2, s);
      for (var k = 1; !hit && k < s.lat.length; k++) {
        hit = _segmentsCross(ay, ax, by, bx, s.lat[k - 1], s.lng[k - 1], s.lat[k], s.lng[k]);
      }
      if (!hit) continue;
      if (s.type == kBarrierWater) return 'water';
      found = 'wetland';
    }
    return found;
  }

  /// Найближчі точки на дорогах біля [p] (до [maxM] м): по одній на ребро, від ближчих.
  List<_Snap> _snaps(Geo p, double maxM, int limit) {
    final py = (p.lat * 1e6).round(), px = (p.lng * 1e6).round();
    final ry = (maxM / 0.11132 / _cell).ceil();
    final rx = (maxM / (0.11132 * math.cos(p.lat * math.pi / 180)) / _cell).ceil();
    final cy0 = py ~/ _cell, cx0 = px ~/ _cell;
    final seen = <int>{};
    final out = <_Snap>[];
    for (var cy = cy0 - ry; cy <= cy0 + ry; cy++) {
      for (var cx = cx0 - rx; cx <= cx0 + rx; cx++) {
        for (final e in _grid[_cellKey(cy, cx)] ?? const <int>[]) {
          if (!seen.add(e)) continue;
          var best = double.infinity, bestAlong = 0.0, along = 0.0;
          var bestLat = 0.0, bestLng = 0.0;
          for (var k = geomStart[e] + 1; k < geomStart[e + 1]; k++) {
            final aLat = ptLat[k - 1] / 1e6, aLng = ptLng[k - 1] / 1e6, bLat = ptLat[k] / 1e6, bLng = ptLng[k] / 1e6;
            final seg = _distE6(ptLat[k - 1], ptLng[k - 1], ptLat[k], ptLng[k]);
            final c = math.cos(aLat * math.pi / 180);
            final dx = (bLng - aLng) * c, dy = bLat - aLat;
            final qx = (p.lng - aLng) * c, qy = p.lat - aLat;
            final l2 = dx * dx + dy * dy;
            final t = l2 == 0 ? 0.0 : ((qx * dx + qy * dy) / l2).clamp(0.0, 1.0);
            final sLat = aLat + (bLat - aLat) * t, sLng = aLng + (bLng - aLng) * t;
            final d = distanceM(p, (lat: sLat, lng: sLng));
            if (d < best) {
              best = d;
              bestAlong = along + seg * t;
              bestLat = sLat;
              bestLng = sLng;
            }
            along += seg;
          }
          if (best <= maxM) out.add(_Snap(e, bestAlong, (lat: bestLat, lng: bestLng), best));
        }
      }
    }
    out.sort((a, b) => a.dist.compareTo(b.dist));
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  /// Вартість ребра: стежка трохи «дорожча» за дорогу; брід — утричі; болото — вчетверо.
  double _cost(int e, double len) {
    var k = edgeKind[e] == kKindPath ? 1.15 : 1.0;
    final f = edgeFlags[e];
    if (f & kFlagWet != 0) k *= 4;
    if (f & kFlagFord != 0) k *= 3;
    return len * k;
  }

  /// Точки ребра від кінця [fromB] (`false` — від a) на відстанях [d0]…[d1] вздовж ребра.
  List<Geo> _piece(int e, double d0, double d1) {
    final pts = <Geo>[];
    final forward = d1 >= d0;
    final lo = math.min(d0, d1), hi = math.max(d0, d1);
    var along = 0.0;
    for (var k = geomStart[e]; k < geomStart[e + 1]; k++) {
      if (k > geomStart[e]) along += _distE6(ptLat[k - 1], ptLng[k - 1], ptLat[k], ptLng[k]);
      if (along > lo && along < hi) pts.add((lat: ptLat[k] / 1e6, lng: ptLng[k] / 1e6));
    }
    return forward ? pts : pts.reversed.toList();
  }
}

class _Snap {
  _Snap(this.edge, this.along, this.point, this.dist);
  final int edge;
  final double along;
  final Geo point;
  final double dist;
}

double _distE6(int aLat, int aLng, int bLat, int bLng) {
  final k = math.cos(aLat / 1e6 * math.pi / 180) * 0.11132;
  final dx = (bLng - aLng) * k, dy = (bLat - aLat) * 0.11132;
  return math.sqrt(dx * dx + dy * dy);
}

bool _segmentsCross(int ay, int ax, int by, int bx, int cy, int cx, int dy, int dx) {
  double orient(int py, int px, int qy, int qx, int ry, int rx) => (qx - px) * (ry - py).toDouble() - (qy - py) * (rx - px).toDouble();
  final d1 = orient(cy, cx, dy, dx, ay, ax), d2 = orient(cy, cx, dy, dx, by, bx);
  final d3 = orient(ay, ax, by, bx, cy, cx), d4 = orient(ay, ax, by, bx, dy, dx);
  return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0)) && d1 != 0 && d2 != 0 && d3 != 0 && d4 != 0;
}

bool _inRing(int py, int px, _Shape s) {
  if (py < s.minLat || py > s.maxLat || px < s.minLng || px > s.maxLng) return false;
  var inside = false;
  for (var i = 0, j = s.lat.length - 1; i < s.lat.length; j = i++) {
    final yi = s.lat[i], xi = s.lng[i], yj = s.lat[j], xj = s.lng[j];
    if ((yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/// Автоматичний маршрут: точки, тип кожного сегмента, довжина; [warning] — відрізок навпростець
/// до стежки все ж перетинає воду чи болото (інших доріг поруч немає).
typedef AutoRoute = ({List<Geo> points, List<NavKind> kinds, double lengthM, String? warning});

/// Прокласти маршрут [from] → [to] дорогами й стежками (A*). `null` — поруч немає доріг
/// (далі [maxSnapM] м) або вони не з'єднані.
AutoRoute? planRoute(TrailGraph g, Geo from, Geo to, {double maxSnapM = 800}) {
  // Відрізок навпростець до стежки: не через воду й болото, якщо є інша стежка.
  List<(_Snap, String?)> access(Geo p) {
    final all = g._snaps(p, maxSnapM, 12);
    final clean = <(_Snap, String?)>[];
    final dirty = <(_Snap, String?)>[];
    for (final s in all) {
      final b = s.dist < 5 ? null : g.barrierOn(p, s.point);
      (b == null ? clean : dirty).add((s, b));
    }
    return clean.isNotEmpty ? clean.take(6).toList() : dirty.take(2).toList();
  }

  final starts = access(from), goals = access(to);
  if (starts.isEmpty || goals.isEmpty) return null;
  const offTrail = 3.0; // лісом без стежки — повільніше й ризиковіше: до найближчої стежки
  final n = g.nodeCount;
  final src = n;
  final dist = Float64List(n + 2)..fillRange(0, n + 2, double.infinity);
  final prevNode = Int32List(n + 2)..fillRange(0, n + 2, -1);
  final prevEdge = Int32List(n + 2)..fillRange(0, n + 2, -1);
  // Вихід із джерела — до кінців ребра, де ми «стали» на дорогу.
  final srcLinks = <int, ({int snap, double cost})>{};
  for (final (i, (s, _)) in starts.indexed) {
    for (final (node, part) in [(g.edgeA[s.edge], s.along), (g.edgeB[s.edge], g.edgeLen[s.edge] - s.along)]) {
      final c = s.dist * offTrail + g._cost(s.edge, part);
      if (c < (srcLinks[node]?.cost ?? double.infinity)) srcLinks[node] = (snap: i, cost: c);
    }
  }
  final goalLinks = <int, ({int snap, double cost})>{};
  for (final (i, (s, _)) in goals.indexed) {
    for (final (node, part) in [(g.edgeA[s.edge], s.along), (g.edgeB[s.edge], g.edgeLen[s.edge] - s.along)]) {
      final c = s.dist * offTrail + g._cost(s.edge, part);
      if (c < (goalLinks[node]?.cost ?? double.infinity)) goalLinks[node] = (snap: i, cost: c);
    }
  }
  // Обидві точки на тому самому ребрі — можна й без вузлів.
  var direct = double.infinity;
  (int, int)? directPair;
  for (final (i, (s, _)) in starts.indexed) {
    for (final (j, (t, _)) in goals.indexed) {
      if (s.edge != t.edge) continue;
      final c = s.dist * offTrail + t.dist * offTrail + g._cost(s.edge, (s.along - t.along).abs());
      if (c < direct) {
        direct = c;
        directPair = (i, j);
      }
    }
  }

  double h(int node) => distanceM((lat: g.nodeLat[node] / 1e6, lng: g.nodeLng[node] / 1e6), to);
  final heap = _Heap();
  dist[src] = 0;
  for (final MapEntry(key: node, value: l) in srcLinks.entries) {
    if (l.cost < dist[node]) {
      dist[node] = l.cost;
      prevNode[node] = src;
      prevEdge[node] = -1 - l.snap; // від'ємне — зі старту через «прив'язку» №
      heap.push(node, l.cost + h(node));
    }
  }
  var best = direct;
  var bestGoalNode = -1;
  while (heap.isNotEmpty) {
    final (u, f) = heap.pop();
    if (f >= best) break;
    if (f - h(u) > dist[u] + 1e-6) continue;
    final gl = goalLinks[u];
    if (gl != null && dist[u] + gl.cost < best) {
      best = dist[u] + gl.cost;
      bestGoalNode = u;
    }
    for (var k = g.adjStart[u]; k < g.adjStart[u + 1]; k++) {
      final e = g.adjEdge[k];
      final v = g.edgeA[e] == u ? g.edgeB[e] : g.edgeA[e];
      final nd = dist[u] + g._cost(e, g.edgeLen[e]);
      if (nd < dist[v]) {
        dist[v] = nd;
        prevNode[v] = u;
        prevEdge[v] = e;
        heap.push(v, nd + h(v));
      }
    }
  }
  if (best == double.infinity) return null;

  final pts = <Geo>[from];
  final kinds = <NavKind>[];
  void add(Geo p, NavKind k) {
    if (distanceM(pts.last, p) < 0.5) return;
    pts.add(p);
    kinds.add(k);
  }

  String? warning;
  if (bestGoalNode < 0) {
    final (i, j) = directPair!;
    final s = starts[i].$1, t = goals[j].$1;
    warning = starts[i].$2 ?? goals[j].$2;
    final k = kindName(g.edgeKind[s.edge]);
    add(s.point, 'direct');
    for (final p in g._piece(s.edge, s.along, t.along)) {
      add(p, k);
    }
    add(t.point, k);
    add(to, 'direct');
  } else {
    // Ланцюжок вузлів від старту до вузла біля цілі.
    final chain = <int>[];
    for (var v = bestGoalNode; v != src; v = prevNode[v]) {
      chain.add(v);
    }
    final chainNodes = chain.reversed.toList();
    final first = chainNodes.first;
    final s = starts[-1 - prevEdge[first]];
    warning = s.$2;
    add(s.$1.point, 'direct');
    final se = s.$1.edge;
    final towardA = g.edgeA[se] == first && (g.edgeB[se] != first || s.$1.along <= g.edgeLen[se] / 2);
    for (final p in g._piece(se, s.$1.along, towardA ? 0 : g.edgeLen[se])) {
      add(p, kindName(g.edgeKind[se]));
    }
    add((lat: g.nodeLat[first] / 1e6, lng: g.nodeLng[first] / 1e6), kindName(g.edgeKind[se]));
    for (var i = 1; i < chainNodes.length; i++) {
      final v = chainNodes[i], e = prevEdge[v];
      final fromA = g.edgeA[e] == chainNodes[i - 1];
      final k = kindName(g.edgeKind[e]);
      for (final p in g._piece(e, fromA ? 0 : g.edgeLen[e], fromA ? g.edgeLen[e] : 0)) {
        add(p, k);
      }
      add((lat: g.nodeLat[v] / 1e6, lng: g.nodeLng[v] / 1e6), k);
    }
    final gl = goalLinks[bestGoalNode]!;
    final t = goals[gl.snap];
    warning ??= t.$2;
    final te = t.$1.edge;
    final fromA = g.edgeA[te] == bestGoalNode && (g.edgeB[te] != bestGoalNode || t.$1.along <= g.edgeLen[te] / 2);
    final k = kindName(g.edgeKind[te]);
    for (final p in g._piece(te, fromA ? 0 : g.edgeLen[te], t.$1.along)) {
      add(p, k);
    }
    add(t.$1.point, k);
    add(to, 'direct');
  }
  if (pts.length < 2) return null;
  var len = 0.0;
  for (var i = 1; i < pts.length; i++) {
    len += distanceM(pts[i - 1], pts[i]);
  }
  return (points: pts, kinds: kinds, lengthM: len, warning: warning);
}

class _Heap {
  final _nodes = <int>[];
  final _keys = <double>[];

  bool get isNotEmpty => _nodes.isNotEmpty;

  void push(int node, double key) {
    _nodes.add(node);
    _keys.add(key);
    var i = _nodes.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= _keys[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  (int, double) pop() {
    final top = (_nodes.first, _keys.first);
    final lastN = _nodes.removeLast(), lastK = _keys.removeLast();
    if (_nodes.isNotEmpty) {
      _nodes[0] = lastN;
      _keys[0] = lastK;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _nodes.length && _keys[l] < _keys[m]) m = l;
        if (r < _nodes.length && _keys[r] < _keys[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final n = _nodes[a], k = _keys[a];
    _nodes[a] = _nodes[b];
    _keys[a] = _keys[b];
    _nodes[b] = n;
    _keys[b] = k;
  }
}
