import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/forest_lod.dart';
import 'package:flutter_client/data/models/forest_zone.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/models/region.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/forest_area.dart';
import 'package:flutter_client/features/analysis/analysis_square.dart';
import 'package:flutter_client/features/map/basemap_style.dart';
import 'package:flutter_client/features/map/offline_glyphs.dart';
import 'package:flutter_client/features/map/region_camera.dart';
import 'package:flutter_client/features/picks/mushroom_marker.dart';
import 'package:flutter_client/features/picks/new_pick_screen.dart';
import 'package:flutter_client/features/picks/pick_card_sheet.dart';

/// Карта Home Region (план v8.2 §3.2, ADR-015 §15.2).
///
/// Усе, що стосується області, приходить із сервера:
///   * кордон і маска «острова», центр, масштаб — `GET /v1-regions/{slug}/geometry`;
///   * полігони лісів (тільки своєї області) з підписами й кольорами — `GET /v1-forest-zones`;
///   * тук-туки: публічні точки інших людей і власні — `GET /v1-picks/map` (ADR-018);
///   * аналіз ділянки 5×5 / 10×10 км — `/v1-analysis` (ADR-015).
/// Клік по пустому місцю точку не створює — тільки FAB «Тук-тук».
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final region = ref.watch(meProvider).valueOrNull?.homeRegion;
    if (region == null) {
      // Роутер не пускає сюди без області; це лише захист від гонки станів.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final geometry = ref.watch(regionGeometryProvider(region.slug));
    return geometry.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e is ApiException ? e.userMessage : 'Не вдалося завантажити карту області.'),
              TextButton(
                onPressed: () => ref.invalidate(regionGeometryProvider(region.slug)),
                child: const Text('Повторити'),
              ),
            ],
          ),
        ),
      ),
      data: (g) => _OfflineMapGate(key: ValueKey(g.slug), geometry: g),
    );
  }
}

/// Карта показується лише з офлайн карти області (ADR-020): серверних плиток немає.
/// Поки офлайн карту не завантажено — на екрані лише пропозиція завантажити її.
class _OfflineMapGate extends ConsumerWidget {
  const _OfflineMapGate({super.key, required this.geometry});

  final RegionGeometry geometry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localBasemapProvider(geometry.slug));
    final file = local.valueOrNull;
    if (local.isLoading && file == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (file == null) return _OfflineMapPrompt(geometry: geometry);
    final glyphs = ref.watch(_glyphsProvider);
    return glyphs.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => ref.invalidate(_glyphsProvider),
            child: const Text('Не вдалося підготувати карту. Повторити'),
          ),
        ),
      ),
      data: (glyphsDir) => _RegionMap(
        // Нова версія файлу — нова карта (MapLibre перечитує файл і скидає кеш).
        key: ValueKey('${file.path}@${file.meta.version}'),
        geometry: geometry,
        pmtilesPath: file.path,
        glyphsDir: glyphsDir,
        basemapVersion: file.meta.version,
      ),
    );
  }
}

/// «Офлайн карта»: по центру екрана — лише ця пропозиція; після завантаження з'являється
/// карта разом з усім іншим.
class _OfflineMapPrompt extends ConsumerStatefulWidget {
  const _OfflineMapPrompt({required this.geometry});

  final RegionGeometry geometry;

  @override
  ConsumerState<_OfflineMapPrompt> createState() => _OfflineMapPromptState();
}

class _OfflineMapPromptState extends ConsumerState<_OfflineMapPrompt> {
  double? _progress;
  String? _error;

  String get _slug => widget.geometry.slug;

  Future<void> _download() async {
    final files = widget.geometry.basemap;
    if (files == null || _progress != null) return;
    setState(() {
      _progress = 0;
      _error = null;
    });
    final repo = ref.read(basemapRepositoryProvider);
    try {
      await for (final p in repo.download(_slug, files)) {
        if (mounted) setState(() => _progress = p);
      }
      ref.invalidate(localBasemapProvider(_slug));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FormatException
            ? e.message
            : 'Не вдалося завантажити. Перевірте інтернет і спробуйте ще раз.');
      }
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteBasemapProvider(_slug));
    final meta = remote.valueOrNull;
    final progress = _progress;
    final muted = AppTheme.darkGreen.withValues(alpha: 0.65);

    final Widget action;
    if (progress != null) {
      action = Column(
        children: [
          LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 8),
          Text('Завантаження… ${(progress * 100).round()}%', style: TextStyle(color: muted)),
        ],
      );
    } else if (remote.isLoading) {
      action = const CircularProgressIndicator();
    } else if (remote.hasError) {
      action = Column(
        children: [
          Text('Потрібен інтернет, щоб завантажити офлайн карту.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
          TextButton(onPressed: () => ref.invalidate(remoteBasemapProvider(_slug)), child: const Text('Повторити')),
        ],
      );
    } else if (meta == null) {
      action = Text(
        'Офлайн карта для вашої області ще готується. Спробуйте пізніше.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted),
      );
    } else {
      action = FilledButton.icon(
        onPressed: _download,
        style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, minimumSize: const Size.fromHeight(50)),
        icon: const Icon(Icons.download_rounded),
        label: Text('Завантажити · ${meta.sizeLabel}'),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_rounded, size: 64, color: AppTheme.darkGreen),
                const SizedBox(height: 16),
                Text(
                  'Офлайн карта',
                  style: GoogleFonts.merriweather(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                ),
                const SizedBox(height: 10),
                Text(
                  'Карта «${widget.geometry.name}» завантажується один раз і далі працює без '
                  'інтернету — і в лісі теж. Краще через Wi-Fi.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                action,
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionMap extends ConsumerStatefulWidget {
  const _RegionMap({
    super.key,
    required this.geometry,
    required this.pmtilesPath,
    required this.glyphsDir,
    required this.basemapVersion,
  });

  final RegionGeometry geometry;

  /// Файл офлайн карти області на телефоні (PMTiles: підкладка + ліси).
  final String pmtilesPath;

  /// Тека з гліфами шрифту підписів на телефоні.
  final String glyphsDir;

  /// Версія офлайн карти на телефоні (для «Оновити офлайн карту»).
  final String basemapVersion;

  @override
  ConsumerState<_RegionMap> createState() => _RegionMapState();
}

class _RegionMapState extends ConsumerState<_RegionMap> {
  /// Карта MapLibre (малює відеокарта телефона); `null` — ще створюється.
  ml.MapLibreMapController? _ml;

  /// Стиль готовий — можна оновлювати шари застосунку (тук-туки, ділянки…).
  bool _styleReady = false;

  /// Стиль — один рядок на весь час життя карти (інакше MapLibre перезавантажує стиль).
  late final String _style = jsonEncode(offlineMapStyle(
    pmtilesPath: widget.pmtilesPath,
    glyphsDir: widget.glyphsDir,
    region: widget.geometry.polygons,
  ));

  // Що вже передано в шари карти — оновлюємо лише змінене.
  Object? _pushedPicks;
  Object? _pushedAreas;
  Object? _pushedAnalysis;
  Object? _pushedPin;
  final Set<String> _icons = {};
  bool _locating = false;
  bool _startingPick = false;

  // Аналіз ділянки (ADR-015): центр обирається дотиком до карти.
  bool _analysisMode = false;
  bool _analyzing = false;
  int _analysisSizeKm = 5;
  LatLng? _analysisCenter;

  /// Визначник лісу: тип лісу, по якому торкнулися, і де показати підпис.
  ({LatLng point, ForestZone zone})? _forestLabel;

  ({LatLng center, double zoom})? _fit;
  Size? _fitSize;

  // Ліси МАЛЮЄ офлайн карта (шар `forests` у файлі карти). Тут — лише ліси з файлу лісів
  // і їхній індекс для визначника, аналізу ділянки й уточнення.
  List<ForestZone>? _lodFor;
  ForestLod? _lod;

  /// Оновлення офлайн карти: частка 0…1; `null` — не качаємо.
  double? _updateProgress;

  RegionGeometry get _g => widget.geometry;

  /// «Оновити офлайн карту»: нова версія (щомісяця — нові ліси й дороги) замінює стару.
  Future<void> _updateBasemap() async {
    final files = _g.basemap;
    if (files == null || _updateProgress != null) return;
    setState(() => _updateProgress = 0);
    try {
      await for (final p in ref.read(basemapRepositoryProvider).download(_g.slug, files)) {
        if (mounted) setState(() => _updateProgress = p);
      }
      ref.invalidate(localBasemapProvider(_g.slug));
      ref.invalidate(remoteBasemapProvider(_g.slug));
      if (mounted) showToast(context, 'Офлайн карту оновлено');
    } catch (e) {
      if (mounted) {
        showToast(context, e is FormatException ? e.message : 'Не вдалося оновити карту. Спробуйте пізніше.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _updateProgress = null);
    }
  }

  @override
  void initState() {
    super.initState();
    // «Показати на карті» з вкладки «Прогноз», якщо карта ще не була відкрита.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final area = ref.read(mapFocusAreaProvider);
      if (mounted && area != null) _focusArea(area);
    });
  }

  /// Навести камеру на ділянку і скинути запит.
  void _focusArea(AnalysisArea area) {
    final c = _ml;
    if (c == null) return; // карта ще створюється — наведемо, коли буде готова
    final b = boundsOf(squareAround(area.center, area.sizeKm));
    c.animateCamera(ml.CameraUpdate.newLatLngBounds(
      ml.LatLngBounds(southwest: _mlLatLng(b.southWest), northeast: _mlLatLng(b.northEast)),
      left: regionPadding.left,
      top: regionPadding.top,
      right: regionPadding.right,
      bottom: regionPadding.bottom + 80,
    ));
    ref.read(mapFocusAreaProvider.notifier).state = null;
  }

  static ml.LatLng _mlLatLng(LatLng p) => ml.LatLng(p.latitude, p.longitude);

  void _moveTo(LatLng p, double zoom) => _ml?.animateCamera(ml.CameraUpdate.newLatLngZoom(_mlLatLng(p), zoom));

  /// Індекс лісів для тапу (визначник лісу) — один раз на набір лісів. Повний файл області
  /// вже підготовлено в ізоляті; запасні плитки — тут.
  void _ensureLod(ForestLoad? load) {
    final zones = load?.zones ?? const <ForestZone>[];
    if (identical(zones, _lodFor)) return;
    _lodFor = zones;
    _lod = load?.lod ?? buildForestLod(zones);
  }

  /// Тап по карті MapLibre: спершу тук-тук чи підпис ділянки під пальцем, далі — як раніше.
  Future<void> _onMapClick(Point<double> screen, ml.LatLng at) async {
    final point = LatLng(at.latitude, at.longitude);
    final c = _ml;
    if (c != null && _styleReady && !_analysisMode) {
      try {
        final hits = await c.queryRenderedFeatures(screen, [MapLayers.picks, MapLayers.areaLabels], null);
        for (final h in hits) {
          final props = _propsOf(h);
          final pickId = props['pick_id'];
          if (pickId is String) {
            if (mounted) showPickCard(context, pickId);
            return;
          }
          final areaId = props['area_id'];
          if (areaId is String) {
            final area = ref.read(analysisOverviewProvider).valueOrNull?.areaById(areaId);
            if (area != null) _openArea(area);
            return;
          }
        }
      } catch (_) {
        // запит до карти не вдався — обробляємо тап як звичайний
      }
    }
    if (mounted) _onMapTap(point);
  }

  static Map<String, dynamic> _propsOf(Object? feature) {
    final f = feature is String ? jsonDecode(feature) : feature;
    final props = f is Map ? f['properties'] : null;
    return props is Map ? props.cast<String, dynamic>() : const {};
  }

  /// Тап по карті: у режимі аналізу — центр ділянки; інакше — визначник лісу
  /// (підпис типу на лісі). Прогноз — лише для ділянки аналізу, не для точки.
  void _onMapTap(LatLng point) {
    if (_analysisMode) {
      _setAnalysisCenter(point);
      return;
    }
    final zones = _lodFor;
    final hits = (zones == null || _lod == null)
        ? const <ForestZone>[]
        : _lod!.zonesAt(point, zones, level: forestLodLevelFor(_ml?.cameraPosition?.zoom ?? 12));
    if (hits.isEmpty) {
      if (_forestLabel != null) setState(() => _forestLabel = null);
      return;
    }
    // Під пальцем може бути кілька контурів OSM — беремо найдостовірніший і найточніший.
    setState(() => _forestLabel = (point: point, zone: pickForestAt(hits)));
  }

  /// Масштаб «вся область» під поточний розмір карти. При повороті екрана
  /// перераховується; поточне місце на карті зберігається, лише якщо воно
  /// стало далі за нову межу — повертаємо до всієї області.
  ({LatLng center, double zoom}) _fitFor(Size size, GeoBounds bounds) {
    if (_fit != null && _fitSize == size) return _fit!;
    final rotated = _fit != null;
    _fitSize = size;
    final fit = _fit = fitRegion(bounds, size);
    if (rotated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if ((_ml?.cameraPosition?.zoom ?? fit.zoom) < fit.zoom) _moveTo(fit.center, fit.zoom);
      });
    }
    return fit;
  }

  /// Кнопка «Вся область».
  void _showWholeRegion() {
    final fit = _fit;
    if (fit != null) _moveTo(fit.center, fit.zoom);
  }

  /// Місцезнаходження телефона. `null` — недоступне (пояснення вже показано).
  Future<LatLng?> _currentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showToast(context, 'Дозвольте доступ до геолокації в налаштуваннях', isError: true);
        return null;
      }
      // Обмеження часу: у приміщенні GPS може шукати супутники дуже довго.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: Duration(seconds: 20)),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося визначити місцезнаходження', isError: true);
      return null;
    }
  }

  Future<void> _onMyLocationPressed() async {
    setState(() => _locating = true);
    try {
      final here = await _currentPosition();
      if (here == null || !mounted) return;
      if (!isInsideRegion(here, _g.polygons)) {
        showToast(context, 'Ви поза своєю областю (${_g.name})');
        return;
      }
      _moveTo(here, 14);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// «Тук-тук»: місце з телефона → камера (один кадр, без галереї) → форма.
  /// Точка поза своєю областю не створюється (ADR-015 §15.2).
  Future<void> _onAddPickPressed() async {
    if (_startingPick) return;
    setState(() => _startingPick = true);
    try {
      final here = await _currentPosition();
      if (here == null || !mounted) return;
      if (!isInsideRegion(here, _g.polygons)) {
        showToast(context, 'Тук-тук можна створити лише у своїй області (${_g.name})', isError: true);
        return;
      }
      final photo = await takePickPhoto();
      if (photo == null || !mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => NewPickScreen(photo: photo, point: here, capturedAt: DateTime.now()),
        ),
      );
      if (mounted) ref.invalidate(picksMapProvider);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося відкрити камеру', isError: true);
    } finally {
      if (mounted) setState(() => _startingPick = false);
    }
  }

  // ─── Аналіз ділянки ────────────────────────────────────────────────────────

  void _toggleAnalysisMode() {
    setState(() {
      _analysisMode = !_analysisMode;
      _analysisCenter = null;
      _forestLabel = null;
    });
  }

  void _setAnalysisCenter(LatLng point) {
    if (!isInsideRegion(point, _g.polygons)) {
      showToast(context, 'Оберіть місце в межах своєї області');
      return;
    }
    setState(() => _analysisCenter = point);
  }

  void _setAnalysisSize(AnalysisSizeOption option) {
    if (!option.available) {
      // Чи доступний розмір — вирішує сервер; показуємо його пояснення.
      showToast(context, '${option.label}: ${option.lockLabel ?? 'недоступно'}');
      return;
    }
    setState(() => _analysisSizeKm = option.sizeKm);
  }

  /// Створити ділянку в обраному місці й одразу проаналізувати. Пересунути
  /// ділянку потім не можна (ADR-015 §15.4) — результат і подальша робота з нею
  /// у вкладці «Прогноз».
  Future<void> _createArea() async {
    final center = _analysisCenter;
    if (center == null || _analyzing) return;
    setState(() => _analyzing = true);
    try {
      // Ліс у квадраті — з тих самих полігонів, що на карті (у БД сервера є не всі
      // області; раніше через це під видимим лісом приходило «лісів немає»).
      final zones = ref.read(regionForestsProvider(_g.slug)).valueOrNull?.zones ?? const <ForestZone>[];
      final forest = zones.isEmpty ? null : forestInSquare(zones, squareAround(center, _analysisSizeKm)).toJson();
      final result = await ref
          .read(analysisRepositoryProvider)
          .createArea(center: center, sizeKm: _analysisSizeKm, forest: forest);
      if (!mounted) return;
      ref.read(selectedAreaIdProvider.notifier).state = result.area.id;
      ref.invalidate(analysisOverviewProvider);
      setState(() {
        _analysisMode = false;
        _analysisCenter = null;
      });
      context.go('/forecast');
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, isError: true);
      if (e.code == 'area_limit_reached') ref.invalidate(analysisOverviewProvider);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося виконати аналіз. Спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  /// Відкрити ділянку у вкладці «Прогноз».
  void _openArea(AnalysisArea area) {
    ref.read(selectedAreaIdProvider.notifier).state = area.id;
    context.go('/forecast');
  }

  // ─── Шари застосунку на карті (GeoJSON) ────────────────────────────────────

  static List<List<double>> _ring(List<LatLng> corners) =>
      [for (final p in [...corners, corners.first]) [p.longitude, p.latitude]];

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Map<String, dynamic> _areasGeoJson(List<AnalysisArea> areas) => {
        'type': 'FeatureCollection',
        'features': [
          for (final a in areas) ...[
            {
              'type': 'Feature',
              'properties': {'area_id': a.id},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [_ring(squareAround(a.center, a.sizeKm))],
              },
            },
            {
              'type': 'Feature',
              // північно-західний кут — підпис «Ділянка N · прогноз» (тап — відкрити прогноз)
              'properties': {'area_id': a.id, 'label': 'Ділянка ${a.slot} · прогноз'},
              'geometry': {
                'type': 'Point',
                'coordinates': [squareAround(a.center, a.sizeKm)[3].longitude, squareAround(a.center, a.sizeKm)[3].latitude],
              },
            },
          ],
        ],
      };

  Map<String, dynamic> _squareGeoJson(List<LatLng>? square) => square == null
      ? emptyFeatureCollection
      : {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [_ring(square)],
          },
        };

  Map<String, dynamic> _pinGeoJson(({LatLng point, ForestZone zone})? label) => label == null
      ? emptyFeatureCollection
      : {
          'type': 'Feature',
          'properties': {'color': _hex(label.zone.typeColor)},
          'geometry': {
            'type': 'Point',
            'coordinates': [label.point.longitude, label.point.latitude],
          },
        };

  static String _iconName(MapPick p) =>
      'pick-${p.markerColor.toARGB32()}-${p.visibility == PickVisibility.private ? 1 : 0}';

  Future<Map<String, dynamic>> _picksGeoJson(List<MapPick> picks) async {
    final c = _ml!;
    for (final p in picks) {
      final name = _iconName(p);
      if (_icons.add(name)) {
        final png = await mushroomMarkerPng(color: p.markerColor, isPrivate: p.visibility == PickVisibility.private);
        await c.addImage(name, png, false, 3);
      }
    }
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final p in picks)
          {
            'type': 'Feature',
            'properties': {'pick_id': p.id, 'icon': _iconName(p)},
            'geometry': {
              'type': 'Point',
              'coordinates': [p.point.longitude, p.point.latitude],
            },
          },
      ],
    };
  }

  /// Передати в карту лише те, що змінилося (без перемальовування всього щокадру).
  Future<void> _syncOverlays({
    required List<MapPick> picks,
    required List<AnalysisArea> areas,
    required List<LatLng>? square,
    required ({LatLng point, ForestZone zone})? pin,
  }) async {
    final c = _ml;
    if (c == null || !_styleReady || !mounted) return;
    try {
      if (!identical(picks, _pushedPicks)) {
        _pushedPicks = picks;
        await c.setGeoJsonSource(MapSources.picks, await _picksGeoJson(picks));
      }
      if (!identical(areas, _pushedAreas)) {
        _pushedAreas = areas;
        await c.setGeoJsonSource(MapSources.areas, _areasGeoJson(areas));
      }
      final squareKey = square == null ? null : '${square.first}${square[2]}';
      if (squareKey != _pushedAnalysis) {
        _pushedAnalysis = squareKey;
        await c.setGeoJsonSource(MapSources.analysis, _squareGeoJson(square));
      }
      if (!identical(pin, _pushedPin)) {
        _pushedPin = pin;
        await c.setGeoJsonSource(MapSources.forestPin, _pinGeoJson(pin));
      }
    } catch (e) {
      debugPrint('[map] overlay sync failed: $e');
    }
  }

  void _onStyleLoaded() {
    _styleReady = true;
    _pushedPicks = _pushedAreas = _pushedAnalysis = _pushedPin = null;
    _icons.clear();
    if (!mounted) return;
    setState(() {}); // перебудова передасть шари застосунку
    final area = ref.read(mapFocusAreaProvider);
    if (area != null) _focusArea(area);
  }

  @override
  Widget build(BuildContext context) {
    // Ліси всієї області — з телефону; мережа лише раз на добу (офлайн-карта).
    final forests = ref.watch(regionForestsProvider(_g.slug));
    final load = forests.valueOrNull;
    _ensureLod(load);
    // Нова версія офлайн карти (щомісяця) — пропонуємо оновити; без мережі — нічого.
    final remoteMap = ref.watch(remoteBasemapProvider(_g.slug)).valueOrNull;
    final mapUpdate = remoteMap != null && remoteMap.version != widget.basemapVersion ? remoteMap : null;
    final offline = load?.offline ?? false;
    final loading = forests.isLoading || (load != null && !load.complete);
    final showError = (forests.hasError && !forests.isLoading) ||
        (load != null && load.complete && load.failed > 0);
    final bounds = _g.bounds;
    final picks = ref.watch(picksMapProvider).valueOrNull?.points ?? const <MapPick>[];
    final showPrivate = ref.watch(showPrivatePicksProvider);
    final center = _analysisCenter;
    final square = _analysisMode && center != null ? squareAround(center, _analysisSizeKm) : null;
    final overview = ref.watch(analysisOverviewProvider);
    final areas = overview.valueOrNull?.areas ?? const <AnalysisArea>[];
    final forestLabel = _forestLabel;
    ref.listen(mapFocusAreaProvider, (_, area) {
      if (area != null) _focusArea(area);
    });
    // Шари застосунку на карті — після кадру й лише змінене.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncOverlays(picks: picks, areas: areas, square: square, pin: forestLabel),
    );

    return Scaffold(
      body: Stack(
        children: [
          LayoutBuilder(builder: (context, box) {
            final fit = _fitFor(box.biggest, bounds);
            return ml.MapLibreMap(
              styleString: _style,
              initialCameraPosition: ml.CameraPosition(target: _mlLatLng(fit.center), zoom: fit.zoom),
              // Віддалитися далі, ніж уміщується вся область, не можна; ближче z17 — без сенсу.
              minMaxZoomPreference: ml.MinMaxZoomPreference(fit.zoom, 17),
              // «Острів»: центр карти не виходить за межі області.
              cameraTargetBounds: ml.CameraTargetBounds(
                ml.LatLngBounds(southwest: _mlLatLng(bounds.southWest), northeast: _mlLatLng(bounds.northEast)),
              ),
              // Без випадкового обертання й нахилу — північ завжди вгорі.
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              trackCameraPosition: true,
              attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
              attributionButtonMargins: const Point(12, 8),
              onMapCreated: (c) => _ml = c,
              onStyleLoadedCallback: _onStyleLoaded,
              // У режимі аналізу дотик обирає центр ділянки; інакше — тук-тук, ділянка або ліс.
              onMapClick: _onMapClick,
            );
          }),
          if (forestLabel != null)
            Positioned(
              left: 16,
              right: 80,
              top: MediaQuery.of(context).padding.top + (showError ? 136 : 76),
              child: _ForestCard(zone: forestLabel.zone, onClose: () => setState(() => _forestLabel = null)),
            ),
          _Header(title: _g.name, loading: loading, offline: offline),
          if (forests.hasError && !forests.isLoading)
            _ErrorBanner(
              message: forests.error is ApiException
                  ? (forests.error as ApiException).userMessage
                  : 'Не вдалося завантажити ліси',
              onRetry: () => ref.invalidate(regionForestsProvider(_g.slug)),
            )
          else if (load != null && load.complete && load.failed > 0)
            _ErrorBanner(
              message: offline
                  ? 'Немає інтернету — частину лісів не завантажено'
                  : 'Частину лісів не вдалося завантажити',
              onRetry: () => ref.invalidate(regionForestsProvider(_g.slug)),
            ),
          // Інструменти карти — праворуч під заголовком, однакового вигляду.
          Positioned(
            right: 16,
            // під банером помилки, якщо він показаний
            top: MediaQuery.of(context).padding.top + (showError ? 136 : 76),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapToolButton(
                  heroTag: 'whole_region',
                  tooltip: 'Вся область',
                  icon: Icons.zoom_out_map_rounded,
                  onPressed: _showWholeRegion,
                ),
                const SizedBox(height: 10),
                _MapToolButton(
                  heroTag: 'my_location',
                  tooltip: 'Моє місцезнаходження',
                  icon: Icons.my_location_rounded,
                  busy: _locating,
                  onPressed: _locating ? null : _onMyLocationPressed,
                ),
              ],
            ),
          ),
          if (_analysisMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 60,
              child: _AnalysisPanel(
                overview: overview,
                sizeKm: _analysisSizeKm,
                centerSelected: _analysisCenter != null,
                busy: _analyzing,
                onSize: _setAnalysisSize,
                onAnalyze: _createArea,
                onClose: _toggleAnalysisMode,
                onRetry: () => ref.invalidate(analysisOverviewProvider),
                onOpenAreas: () => context.go('/forecast'),
              ),
            )
          else ...[
            // Режими карти — внизу ліворуч, з підписами.
            Positioned(
              left: 16,
              bottom: 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mapUpdate != null) ...[
                    _MapPill(
                      icon: Icons.system_update_alt_rounded,
                      label: _updateProgress == null
                          ? 'Оновити офлайн карту · ${mapUpdate.sizeLabel}'
                          : 'Оновлення карти… ${(_updateProgress! * 100).round()}%',
                      onPressed: _updateBasemap,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _MapPill(
                    icon: Icons.crop_free_rounded,
                    label: 'Аналіз ділянки',
                    onPressed: _toggleAnalysisMode,
                  ),
                  const SizedBox(height: 8),
                  _MapPill(
                    icon: showPrivate ? Icons.lock_rounded : Icons.lock_open_rounded,
                    label: 'Приватні точки',
                    active: showPrivate,
                    onPressed: () => ref.read(showPrivatePicksProvider.notifier).state = !showPrivate,
                  ),
                ],
              ),
            ),
            // Головна дія — окремо, внизу праворуч.
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton.extended(
                heroTag: 'add_pick',
                onPressed: _startingPick ? null : _onAddPickPressed,
                backgroundColor: AppTheme.darkGreen,
                foregroundColor: Colors.white,
                icon: _startingPick
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.photo_camera_rounded),
                label: Text(showPrivate ? 'Приватний тук-тук' : 'Тук-тук'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.loading, this.offline = false});

  final String title;
  final bool loading;

  /// Немає інтернету — ліси показано зі збереженої копії.
  final bool offline;

  @override
  Widget build(BuildContext context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: AppTheme.darkGreen.withValues(alpha: 0.1), blurRadius: 8),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.forest_rounded, size: 20, color: AppTheme.darkGreen),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                ),
                if (loading) ...[
                  const SizedBox(width: 10),
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                if (offline) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.cloud_off_rounded, size: 18, color: AppTheme.accentOrange),
                  const SizedBox(width: 4),
                  const Text('офлайн', style: TextStyle(color: AppTheme.accentOrange, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Positioned(
        top: MediaQuery.of(context).padding.top + 64,
        left: 16,
        right: 16,
        child: Material(
          color: AppTheme.errorRed,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            dense: true,
            textColor: Colors.white,
            title: Text(message),
            trailing: TextButton(
              onPressed: onRetry,
              child: const Text('Повторити', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );
}

/// Кругла кнопка-інструмент карти (бежева з зеленою іконкою).
class _MapToolButton extends StatelessWidget {
  const _MapToolButton({
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String heroTag;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
        heroTag: heroTag,
        tooltip: tooltip,
        onPressed: onPressed,
        backgroundColor: AppTheme.backgroundColor,
        foregroundColor: AppTheme.darkGreen,
        elevation: 3,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkGreen),
              )
            : Icon(icon),
      );
}

/// Кнопка режиму карти з підписом (бежева; активна — зелена).
class _MapPill extends StatelessWidget {
  const _MapPill({required this.icon, required this.label, required this.onPressed, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final background = active ? AppTheme.darkGreen : AppTheme.backgroundColor;
    final foreground = active ? Colors.white : AppTheme.darkGreen;
    return Material(
      color: background,
      elevation: 3,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Панель аналізу ділянки: підказка, розміри, ліміт на сьогодні, кнопка запуску.
/// Розміри, їхня доступність («Доступно в Pro») і ліміт приходять із сервера.
class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({
    required this.overview,
    required this.sizeKm,
    required this.centerSelected,
    required this.busy,
    required this.onSize,
    required this.onAnalyze,
    required this.onClose,
    required this.onRetry,
    required this.onOpenAreas,
  });

  final AsyncValue<AnalysisOverview> overview;
  final int sizeKm;
  final bool centerSelected;
  final bool busy;
  final ValueChanged<AnalysisSizeOption> onSize;
  final VoidCallback onAnalyze;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback onOpenAreas;

  @override
  Widget build(BuildContext context) {
    final data = overview.valueOrNull;
    final muted = AppTheme.darkGreen.withValues(alpha: 0.65);
    return Material(
      color: AppTheme.backgroundColor,
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.crop_free_rounded, color: AppTheme.darkGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Аналіз ділянки',
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрити',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: AppTheme.darkGreen),
                ),
              ],
            ),
            if (data == null && overview.isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (data == null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        overview.error is ApiException
                            ? (overview.error as ApiException).userMessage
                            : 'Не вдалося завантажити налаштування аналізу.',
                      ),
                    ),
                    TextButton(onPressed: onRetry, child: const Text('Повторити')),
                  ],
                ),
              )
            else if (!data.canCreate) ...[
              // Ділянку не пересувають: нова — лише після видалення старої (або в Pro).
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(data.createHintLabel ?? 'Вільного місця для нової ділянки немає.'),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: onOpenAreas,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.darkGreen,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.insights_rounded),
                  label: const Text('Мої ділянки'),
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  centerSelected
                      ? 'Центр обрано. Перед створенням його можна змінити — торкніться іншого місця. '
                          'Після створення ділянку пересунути не можна.'
                      : data.hintLabel,
                  style: TextStyle(color: muted),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final option in data.sizes)
                    ChoiceChip(
                      avatar: option.available ? null : const Icon(Icons.lock_outline_rounded, size: 16),
                      label: Text(option.available ? option.label : '${option.label} · ${option.lockLabel ?? ''}'),
                      selected: option.available && option.sizeKm == sizeKm,
                      onSelected: busy ? null : (_) => onSize(option),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: centerSelected && !busy ? onAnalyze : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.darkGreen,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.insights_rounded),
                  label: Text(busy ? 'Аналізуємо…' : 'Створити ділянку й аналізувати'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Гліфи шрифту підписів офлайн карти — на диску (копіюються з ресурсів один раз).
final _glyphsProvider = FutureProvider<String>((ref) => ensureOfflineGlyphs());

/// Визначник лісу: тип (і вік), площа, звідки тип. Тап — закрити.
class _ForestCard extends StatelessWidget {
  const _ForestCard({required this.zone, required this.onClose});

  final ForestZone zone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final title = zone.standAgeYears == null ? zone.typeLabel : '${zone.typeLabel}, ~${zone.standAgeYears} р.';
    final details = [if (zone.areaLabel != null) zone.areaLabel!, if (zone.typeSourceLabel != null) zone.typeSourceLabel!];
    return GestureDetector(
      onTap: onClose,
      child: Container(
        key: const ValueKey('forest-label'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: zone.typeColor, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.forest_rounded, size: 16, color: zone.typeColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.darkGreen),
                  ),
                ),
                Icon(Icons.close_rounded, size: 16, color: AppTheme.darkGreen.withValues(alpha: 0.5)),
              ],
            ),
            for (final d in details)
              Text(
                d,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.7)),
              ),
          ],
        ),
      ),
    );
  }
}

