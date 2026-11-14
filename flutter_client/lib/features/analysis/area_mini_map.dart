import 'dart:convert';
import 'dart:math' show Point, min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart';
import 'package:flutter_client/features/map/basemap_style.dart';
import 'package:flutter_client/features/map/offline_glyphs.dart';
import 'package:flutter_client/features/map/region_camera.dart';

/// Де грибник поставив гриби на мінікарті ділянки (вид → точка). На телефоні, працює без
/// інтернету; видаляється разом із ділянкою не обов'язково — ключ за id ділянки.
class StickerPositionsStore {
  StickerPositionsStore(this._store);

  final LocalStore _store;

  static String key(String areaId) => 'stickers_${areaId.toLowerCase()}';

  Future<Map<String, LatLng>> load(String areaId) async {
    final raw = (await _store.read(key(areaId)))?.data;
    if (raw is! Map) return {};
    final out = <String, LatLng>{};
    raw.forEach((k, v) {
      if (k is String && v is List && v.length == 2 && v[0] is num && v[1] is num) {
        out[k] = LatLng((v[0] as num).toDouble(), (v[1] as num).toDouble());
      }
    });
    return out;
  }

  Future<void> save(String areaId, Map<String, LatLng> positions) => _store.write(key(areaId), {
        for (final e in positions.entries) e.key: [e.value.latitude, e.value.longitude],
      });
}

/// Мінікарта ділянки у вкладці «Прогноз»: та сама офлайн карта з лісами, нерухома, рівно
/// квадрат ділянки. Поверх неї — гриби, які грибник сам ставить на свої місця (ADR-015 §15.9).
class AreaMiniMap extends ConsumerStatefulWidget {
  const AreaMiniMap({super.key, required this.areaId, required this.bounds, required this.species});

  final String areaId;
  final GeoBounds bounds;
  final List<StickerSpecies> species;

  @override
  ConsumerState<AreaMiniMap> createState() => _AreaMiniMapState();
}

class _AreaMiniMapState extends ConsumerState<AreaMiniMap> {
  Map<String, LatLng> _positions = {};
  late StickerPositionsStore _store;

  @override
  void initState() {
    super.initState();
    _store = StickerPositionsStore(ref.read(localStoreProvider));
    _load();
  }

  @override
  void didUpdateWidget(AreaMiniMap old) {
    super.didUpdateWidget(old);
    if (old.areaId != widget.areaId) _load();
  }

  Future<void> _load() async {
    final p = await _store.load(widget.areaId);
    if (mounted) setState(() => _positions = p);
  }

  void _update(Map<String, LatLng> next) {
    setState(() => _positions = next);
    _store.save(widget.areaId, next);
  }

  @override
  Widget build(BuildContext context) {
    final slug = ref.watch(meProvider).valueOrNull?.homeRegion?.slug;
    final basemap = slug == null ? null : ref.watch(localBasemapProvider(slug)).valueOrNull;
    final glyphs = ref.watch(offlineGlyphsProvider).valueOrNull;

    return LayoutBuilder(builder: (context, box) {
      // Рівно квадрат ділянки (рішення PO 2026-11-14): квадратна мінікарта, ділянка на весь
      // розмір — більший масштаб, видно лише ліс ділянки.
      final side = min(box.maxWidth, 440.0);
      final size = Size(side, side);
      final fit = fitRegion(widget.bounds, size, padding: EdgeInsets.zero, cover: true);
      final camera = StickerCamera(center: fit.center, zoom: fit.zoom, size: size);
      final map = basemap != null && glyphs != null
          ? _MiniMapLibre(
              key: ValueKey('${widget.areaId}@${basemap.meta.version}'),
              pmtilesPath: basemap.path,
              glyphsDir: glyphs,
              bounds: widget.bounds,
              center: fit.center,
              zoom: fit.zoom,
            )
          : Container(
              color: const Color(0xfff3f1ec),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Text(
                'Мінікарта з лісами з\'явиться після завантаження офлайн карти на вкладці «Карта».',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.7)),
              ),
            );
      return StickerBoard(
        camera: camera,
        species: widget.species,
        positions: _positions,
        map: map,
        onMove: (type, p) => _update({..._positions, type: p}),
        onRemove: (type) => _update({..._positions}..remove(type)),
      );
    });
  }
}

/// Нерухома карта MapLibre рівно на ділянку: без жестів (тягнемо гриби, а не карту).
class _MiniMapLibre extends StatefulWidget {
  const _MiniMapLibre({
    super.key,
    required this.pmtilesPath,
    required this.glyphsDir,
    required this.bounds,
    required this.center,
    required this.zoom,
  });

  final String pmtilesPath;
  final String glyphsDir;
  final GeoBounds bounds;
  final LatLng center;
  final double zoom;

  @override
  State<_MiniMapLibre> createState() => _MiniMapLibreState();
}

class _MiniMapLibreState extends State<_MiniMapLibre> {
  late final String _style = jsonEncode(miniMapStyle(
    pmtilesPath: widget.pmtilesPath,
    glyphsDir: widget.glyphsDir,
    bounds: widget.bounds,
  ));

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: ml.MapLibreMap(
          styleString: _style,
          initialCameraPosition: ml.CameraPosition(
            target: ml.LatLng(widget.center.latitude, widget.center.longitude),
            zoom: widget.zoom,
          ),
          rotateGesturesEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          tiltGesturesEnabled: false,
          doubleClickZoomEnabled: false,
          dragEnabled: false,
          compassEnabled: false,
          // Атрибуція OpenStreetMap — обов'язкова за ліцензією (ODbL), маленька кнопка в куті.
          attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
          attributionButtonMargins: const Point(4, 4),
        ),
      );
}

/// Стиль мінікарти: підкладка з лісами (як на великій карті), без маски області, з контуром
/// квадрата ділянки.
Map<String, dynamic> miniMapStyle({required String pmtilesPath, required String glyphsDir, required GeoBounds bounds}) {
  final style = offlineMapStyle(pmtilesPath: pmtilesPath, glyphsDir: glyphsDir, region: const []);
  final sources = Map<String, dynamic>.from(style['sources'] as Map)..remove('app_mask');
  final sw = bounds.southWest, ne = bounds.northEast;
  sources['mini_area'] = {
    'type': 'geojson',
    'data': {
      'type': 'Feature',
      'properties': <String, dynamic>{},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [sw.longitude, sw.latitude],
          [ne.longitude, sw.latitude],
          [ne.longitude, ne.latitude],
          [sw.longitude, ne.latitude],
          [sw.longitude, sw.latitude],
        ],
      },
    },
  };
  final layers = [
    for (final l in (style['layers'] as List).cast<Map<String, dynamic>>())
      if (l['source'] != 'app_mask') l,
    {
      'id': 'mini_area_line',
      'type': 'line',
      'source': 'mini_area',
      'paint': {'line-color': '#14532d', 'line-width': 2, 'line-dasharray': [3, 2]},
    },
  ];
  return {...style, 'sources': sources, 'layers': layers};
}
