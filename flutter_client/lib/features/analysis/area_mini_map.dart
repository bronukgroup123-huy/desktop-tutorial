import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point, min;
import 'dart:typed_data';

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

/// Знімок мінікарти ділянки (PNG) на телефоні: один файл на ділянку + підпис, з чим його
/// знято (версія карти, час аналізу, розмір). Інший підпис — знімок застарів, перезняти.
class MiniMapSnapshotStore {
  MiniMapSnapshotStore(this._store);

  final LocalStore _store;

  static String key(String areaId) => 'minimap_${areaId.toLowerCase()}';

  /// Знімок, якщо він знятий саме з таким [signature].
  Future<Uint8List?> load(String areaId, String signature) async {
    final meta = (await _store.read(key(areaId)))?.data;
    if (meta is! Map || meta['signature'] != signature) return null;
    return _store.readBytes(key(areaId));
  }

  Future<void> save(String areaId, String signature, Uint8List png) async {
    await _store.writeBytes(key(areaId), png);
    await _store.write(key(areaId), {'signature': signature});
  }
}

/// Поле довкола ділянки, яке знімається й обрізається: там MapLibre малює свій логотип і підпис.
const double kSnapshotMargin = 48;

/// Версія способу знімання — змінити, щоб перезняти всі знімки.
const int kSnapshotVersion = 2; // 2 — без пунктирної рамки ділянки

/// Мінікарта ділянки у вкладці «Прогноз»: та сама офлайн карта з лісами, нерухома, рівно
/// квадрат ділянки. Поверх неї — гриби, які грибник сам ставить на свої місця (ADR-015 §15.9).
class AreaMiniMap extends ConsumerStatefulWidget {
  const AreaMiniMap({
    super.key,
    required this.areaId,
    required this.bounds,
    required this.species,
    this.analyzedAt,
    this.history = const [],
  });

  final String areaId;
  final GeoBounds bounds;
  final List<StickerSpecies> species;

  /// Коли зроблено аналіз: новий аналіз — знімок перезнімається.
  final DateTime? analyzedAt;

  /// Ваші знахідки торік у ці тижні.
  final List<({LatLng point, String type, String name, String dateLabel})> history;

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

  // ─── Знімок замість живої карти (рішення PO 2026-11-15) ────────────────────
  // Жива MapLibre у списку, що гортається, «просідає» і на мить зникає. Тому карту ділянки
  // знімаємо один раз (після аналізу або оновлення карти) і далі показуємо картинку.

  late final MiniMapSnapshotStore _snapshots = MiniMapSnapshotStore(ref.read(localStoreProvider));
  String? _signature;
  Uint8List? _snapshot;
  bool _snapshotChecked = false;
  bool _snapshotFailed = false;

  void _checkSnapshot(String signature) {
    if (_signature == signature) return;
    _signature = signature;
    _snapshot = null;
    _snapshotChecked = false;
    _snapshotFailed = false;
    _snapshots.load(widget.areaId, signature).then((png) {
      if (!mounted || _signature != signature) return;
      setState(() {
        _snapshot = png;
        _snapshotChecked = true;
      });
    }, onError: (_) {
      if (mounted && _signature == signature) setState(() => _snapshotChecked = true);
    });
  }

  Future<void> _onSnapshot(String signature, Uint8List? png) async {
    if (!mounted || _signature != signature) return;
    if (png == null) {
      setState(() => _snapshotFailed = true); // лишається жива карта
      return;
    }
    setState(() => _snapshot = png);
    try {
      await _snapshots.save(widget.areaId, signature, png);
    } catch (_) {
      // не збереглось — наступного разу знімемо ще раз
    }
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
      Widget? map;
      if (basemap != null && glyphs != null) {
        final signature = [
          kSnapshotVersion,
          widget.areaId.toLowerCase(),
          basemap.meta.version,
          widget.analyzedAt?.toIso8601String() ?? '-',
          side.round(),
          MediaQuery.devicePixelRatioOf(context).toStringAsFixed(2),
        ].join('|');
        _checkSnapshot(signature);
        if (_snapshot != null) {
          map = _SnapshotMap(png: _snapshot!, side: side);
        } else if (_snapshotChecked) {
          map = _MiniMapLibre(
            key: ValueKey('${widget.areaId}@$signature'),
            pmtilesPath: basemap.path,
            glyphsDir: glyphs,
            bounds: widget.bounds,
            center: fit.center,
            zoom: fit.zoom,
            snapshotSide: _snapshotFailed ? null : side,
            onSnapshot: (png) => _onSnapshot(signature, png),
          );
        } else {
          map = const ColoredBox(color: Color(0xfff3f1ec)); // мить, поки читається знімок
        }
      }
      map ??= Container(
              color: const Color(0xfff3f1ec),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Text(
                'Мінікарта з лісами з\'явиться після завантаження офлайн карти на вкладці «Карта».',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted),
              ),
            );
      return StickerBoard(
        camera: camera,
        species: widget.species,
        positions: _positions,
        map: map,
        history: widget.history,
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
    this.snapshotSide,
    this.onSnapshot,
  });

  /// Зняти знімок квадрата зі стороною [snapshotSide] (+ поля) після завантаження стилю;
  /// `null` — не знімати (минулого разу не вдалось).
  final double? snapshotSide;
  final void Function(Uint8List? png)? onSnapshot;

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

  ml.MapLibreMapController? _controller;
  bool _shot = false;

  Future<void> _takeSnapshot() async {
    final side = widget.snapshotSide, c = _controller;
    if (_shot || side == null || c == null || widget.onSnapshot == null) return;
    _shot = true;
    // Знімок трохи більший за ділянку з тим самим центром і масштабом: поле з логотипом і
    // підписом MapLibre потім обрізається, ділянка лишається рівно на весь квадрат.
    final px = (side + 2 * kSnapshotMargin).round();
    Uint8List? png;
    try {
      png = await c.takeSnapshot(width: px, height: px).timeout(const Duration(seconds: 20));
    } catch (_) {
      png = null;
    }
    if (mounted) widget.onSnapshot!(png);
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: ml.MapLibreMap(
          styleString: _style,
          onMapCreated: (c) => _controller = c,
          onStyleLoadedCallback: _takeSnapshot,
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
          // Лівий нижній кут: правий — для кошика.
          attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
          attributionButtonMargins: const Point(4, 4),
        ),
      );
}

/// Стиль мінікарти: підкладка з лісами (як на великій карті), без маски області. Пунктирну
/// рамку квадрата прибрано (рішення PO 2026-11-17): карта й так рівно в межах ділянки.
Map<String, dynamic> miniMapStyle({required String pmtilesPath, required String glyphsDir, required GeoBounds bounds}) {
  final style = offlineMapStyle(pmtilesPath: pmtilesPath, glyphsDir: glyphsDir, region: const []);
  final sources = Map<String, dynamic>.from(style['sources'] as Map)..remove('app_mask');
  final layers = [
    for (final l in (style['layers'] as List).cast<Map<String, dynamic>>())
      if (l['source'] != 'app_mask') l,
  ];
  return {...style, 'sources': sources, 'layers': layers};
}

/// Знімок ділянки: центральний квадрат без полів, звичайна картинка (легко гортати).
/// Атрибуція OpenStreetMap — та сама кнопка ⓘ, як на живій карті (ODbL).
class _SnapshotMap extends StatelessWidget {
  const _SnapshotMap({required this.png, required this.side});

  final Uint8List png;
  final double side;

  @override
  Widget build(BuildContext context) {
    final full = side + 2 * kSnapshotMargin;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: OverflowBox(
            minWidth: full,
            maxWidth: full,
            minHeight: full,
            maxHeight: full,
            child: Image.memory(
              png,
              key: const ValueKey('mini-map-snapshot'),
              width: full,
              height: full,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const Positioned(left: 4, bottom: 4, child: MapAttributionButton()),
      ],
    );
  }
}

/// ⓘ як у MapLibre: торкнутися — звідки дані карти.
class MapAttributionButton extends StatelessWidget {
  const MapAttributionButton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Дані карти',
        child: GestureDetector(
          key: const ValueKey('map-attribution'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Дані карти'),
              content: const Text(
                '© OpenStreetMap contributors\n'
                'Дані доступні за ліцензією Open Database License (ODbL), openstreetmap.org/copyright.\n'
                'Карта відображається за допомогою MapLibre.',
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Зрозуміло'))],
            ),
          ),
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xccffffff), shape: BoxShape.circle),
            child: const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xff1e88a8)),
          ),
        ),
      );
}
