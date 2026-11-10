import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/forest_zone.dart';
import 'package:flutter_client/data/models/region.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';
import 'package:flutter_client/features/map/region_camera.dart';

/// Карта Home Region (план v8.2 §3.2, ADR-015 §15.2).
///
/// Усе, що стосується області, приходить із сервера:
///   * кордон і маска «острова», центр, масштаб — `GET /v1-regions/{slug}/geometry`;
///   * полігони лісів (тільки своєї області) з підписами й кольорами — `GET /v1-forest-zones`.
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
  ({LatLng center, double zoom})? _fit;
  Size? _fitSize;

  // Полігони будуються один раз на набір даних, а не на кожен кадр.
  List<ForestZone>? _zonesBuiltFor;
  List<Polygon<ForestZone>> _polygons = const [];

  RegionGeometry get _g => widget.geometry;

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

  /// Тап по лісу → обрана точка (для вкладки «Прогноз») + прогноз у Bottom Sheet.
  void _onForestTap() {
    final hit = _forestHits.value;
    if (hit == null || hit.hitValues.isEmpty) return;
    final zone = hit.hitValues.first;
    final point = ForecastPoint(
      lat: hit.coordinate.latitude,
      lng: hit.coordinate.longitude,
      forestType: zone.forestType,
      title: zone.typeLabel,
    );
    ref.read(selectedPointProvider.notifier).state = point;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, controller) => ForecastView(point: point, scrollController: controller),
      ),
    );
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

  Future<void> _onMyLocationPressed() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showToast(context, 'Дозвольте доступ до геолокації в налаштуваннях', isError: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final here = LatLng(pos.latitude, pos.longitude);
      if (!isInsideRegion(here, _g.polygons)) {
        if (mounted) showToast(context, 'Ви поза своєю областю (${_g.name})');
        return;
      }
      _mapController.move(here, 14);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося визначити місцезнаходження', isError: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onAddPickPressed() {
    // Майстер створення тук-тука — Фаза 3 (B3.0/B3.1, Signed Upload URL).
    showToast(context, 'Створення знахідки — скоро');
  }

  @override
  Widget build(BuildContext context) {
    // Ліси всієї області — з телефону; мережа лише раз на добу (офлайн-карта).
    final forests = ref.watch(regionForestsProvider(_g.slug));
    final load = forests.valueOrNull;
    final zones = load?.zones ?? const <ForestZone>[];
    final offline = load?.offline ?? false;
    final loading = forests.isLoading || (load != null && !load.complete);
    final bounds = LatLngBounds(_g.bounds.southWest, _g.bounds.northEast);

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
              const RichAttributionWidget(
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
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'add_pick',
                  onPressed: _onAddPickPressed,
                  backgroundColor: AppTheme.darkGreen,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Тук-тук'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'whole_region',
                  tooltip: 'Вся область',
                  onPressed: _showWholeRegion,
                  backgroundColor: AppTheme.backgroundColor,
                  foregroundColor: AppTheme.darkGreen,
                  child: const Icon(Icons.zoom_out_map_rounded),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  onPressed: _locating ? null : _onMyLocationPressed,
                  backgroundColor: AppTheme.darkGreen,
                  foregroundColor: Colors.white,
                  child: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),
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
