import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/forest_zone.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/models/region.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/forest_area.dart';
import 'package:flutter_client/features/analysis/analysis_square.dart';
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
      data: (g) => _RegionMap(key: ValueKey(g.slug), geometry: g),
    );
  }
}

class _RegionMap extends ConsumerStatefulWidget {
  const _RegionMap({super.key, required this.geometry});

  final RegionGeometry geometry;

  @override
  ConsumerState<_RegionMap> createState() => _RegionMapState();
}

class _RegionMapState extends ConsumerState<_RegionMap> {
  final MapController _mapController = MapController();
  final LayerHitNotifier<ForestZone> _forestHits = ValueNotifier(null);
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

  // Полігони будуються один раз на набір даних, а не на кожен кадр.
  List<ForestZone>? _zonesBuiltFor;
  List<Polygon<ForestZone>> _polygons = const [];

  RegionGeometry get _g => widget.geometry;

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
    final corners = squareAround(area.center, area.sizeKm);
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(corners),
      padding: regionPadding + const EdgeInsets.only(bottom: 80),
    ));
    ref.read(mapFocusAreaProvider.notifier).state = null;
  }

  @override
  void dispose() {
    _forestHits.dispose();
    super.dispose();
  }

  /// Світ із «дірками» на місці області — усе поза областю затемнене.
  Polygon _mask() => Polygon(
        points: const [
          LatLng(-85, -180),
          LatLng(-85, 180),
          LatLng(85, 180),
          LatLng(85, -180),
        ],
        holePointsList: [for (final p in _g.polygons) p.outer],
        color: AppTheme.backgroundColor.withValues(alpha: 0.85),
        borderColor: AppTheme.darkGreen,
        borderStrokeWidth: 2,
      );

  List<Polygon<ForestZone>> _forestPolygons(List<ForestZone> zones) {
    if (identical(zones, _zonesBuiltFor)) return _polygons;
    _zonesBuiltFor = zones;
    return _polygons = _buildPolygons(zones);
  }

  List<Polygon<ForestZone>> _buildPolygons(List<ForestZone> zones) => [
        for (final z in zones)
          for (final p in z.polygons)
            Polygon<ForestZone>(
              points: p.outer,
              holePointsList: p.holes,
              color: z.typeColor.withValues(alpha: 0.45),
              borderColor: z.typeColor,
              borderStrokeWidth: 1,
              hitValue: z,
            ),
      ];

  /// Тап по лісу — визначник лісу: на лісі з'являється підпис його типу.
  /// Прогноз — лише для ділянки аналізу (вкладка «Прогноз»), не для точки.
  void _onForestTap() {
    final hit = _forestHits.value;
    if (hit == null || hit.hitValues.isEmpty) return;
    if (_analysisMode) {
      _setAnalysisCenter(hit.coordinate);
      return;
    }
    setState(() => _forestLabel = (point: hit.coordinate, zone: hit.hitValues.first));
  }

  /// Масштаб «вся область» під поточний розмір карти. При повороті екрана
  /// перераховується; поточне місце на карті зберігається, лише якщо воно
  /// стало далі за нову межу — повертаємо до всієї області.
  ({LatLng center, double zoom}) _fitFor(Size size, LatLngBounds bounds) {
    if (_fit != null && _fitSize == size) return _fit!;
    final rotated = _fit != null;
    _fitSize = size;
    final fit = _fit = fitRegion(bounds, size);
    if (rotated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_mapController.camera.zoom < fit.zoom) _mapController.move(fit.center, fit.zoom);
      });
    }
    return fit;
  }

  /// Кнопка «Вся область».
  void _showWholeRegion() {
    final fit = _fit;
    if (fit != null) _mapController.move(fit.center, fit.zoom);
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
      _mapController.move(here, 14);
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

  List<Polygon> _areaSquares(List<AnalysisArea> areas) => [
        for (final a in areas)
          Polygon(
            points: squareAround(a.center, a.sizeKm),
            color: AppTheme.darkGreen.withValues(alpha: 0.06),
            borderColor: AppTheme.darkGreen,
            borderStrokeWidth: 2,
            pattern: StrokePattern.dashed(segments: const [10, 6]),
          ),
      ];

  List<Marker> _areaLabels(List<AnalysisArea> areas) => [
        for (final a in areas)
          Marker(
            point: squareAround(a.center, a.sizeKm)[3], // північно-західний кут
            width: 150,
            height: 34,
            alignment: Alignment.bottomRight,
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: AppTheme.darkGreen,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openArea(a),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(
                      'Ділянка ${a.slot} · прогноз',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ];

  /// Підпис визначника лісу над точкою дотику.
  Marker _forestLabelMarker(LatLng point, ForestZone zone) => Marker(
        point: point,
        width: 220,
        height: 56,
        alignment: Alignment.topCenter,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () => setState(() => _forestLabel = null),
            child: Container(
              key: const ValueKey('forest-label'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: zone.typeColor, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forest_rounded, size: 16, color: zone.typeColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      zone.standAgeYears == null ? zone.typeLabel : '${zone.typeLabel}, ~${zone.standAgeYears} р.',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.darkGreen),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  List<Marker> _pickMarkers(List<MapPick> picks) => [
        for (final p in picks)
          Marker(
            point: p.point,
            width: 40,
            height: 44,
            alignment: Alignment.topCenter, // ніжка гриба — у точці на карті
            child: GestureDetector(
              onTap: () => showPickCard(context, p.id),
              child: MushroomMarker(
                color: p.markerColor,
                isPrivate: p.visibility == PickVisibility.private,
                tooltip: '${p.nameLabel} · ${p.statusLabel}',
              ),
            ),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    // Ліси всієї області — з телефону; мережа лише раз на добу (офлайн-карта).
    final forests = ref.watch(regionForestsProvider(_g.slug));
    final load = forests.valueOrNull;
    final zones = load?.zones ?? const <ForestZone>[];
    final offline = load?.offline ?? false;
    final loading = forests.isLoading || (load != null && !load.complete);
    final showError = (forests.hasError && !forests.isLoading) ||
        (load != null && load.complete && load.failed > 0);
    final bounds = LatLngBounds(_g.bounds.southWest, _g.bounds.northEast);
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

    return Scaffold(
      body: Stack(
        children: [
          LayoutBuilder(builder: (context, box) {
            final fit = _fitFor(box.biggest, bounds);
            return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: fit.center,
              initialZoom: fit.zoom,
              // Віддалитися далі, ніж уміщується вся область, не можна.
              minZoom: fit.zoom,
              // Ліси спрощені до ~20 м — далі наближати немає сенсу.
              maxZoom: 17,
              // «Острів»: за кордон видно лише невеликий відступ; камера не блокується.
              cameraConstraint: RegionCameraConstraint(bounds: bounds),
              // Без випадкового обертання двома пальцями — північ завжди вгорі.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              // У режимі аналізу дотик до карти обирає центр ділянки;
              // поза лісом — ховає підпис визначника лісу.
              onTap: (tapPosition, point) {
                if (_analysisMode) {
                  _setAnalysisCenter(point);
                } else if (_forestLabel != null) {
                  setState(() => _forestLabel = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ua.mushroomradar.app',
                maxZoom: 17,
              ),
              GestureDetector(
                onTap: _onForestTap,
                child: PolygonLayer<ForestZone>(
                  polygons: _forestPolygons(zones),
                  hitNotifier: _forestHits,
                ),
              ),
              PolygonLayer(polygons: [_mask()]),
              if (areas.isNotEmpty) PolygonLayer(polygons: _areaSquares(areas)),
              if (square != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: square,
                      color: AppTheme.accentOrange.withValues(alpha: 0.18),
                      borderColor: AppTheme.accentOrange,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              MarkerLayer(markers: _pickMarkers(picks)),
              if (areas.isNotEmpty) MarkerLayer(markers: _areaLabels(areas)),
              if (forestLabel != null) MarkerLayer(markers: [_forestLabelMarker(forestLabel.point, forestLabel.zone)]),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
              ),
            ],
          );
          }),
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
