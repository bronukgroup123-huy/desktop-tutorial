import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/region_data.dart';
import 'package:flutter_client/presentation/providers/forest_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  String _currentRegionName = 'Київська область';
  bool _isLoadingLocation = false;
  int _currentRegionId = 10;
  List<LatLng> _kyivOblastOuterRing = [];
  bool _maskLoaded = false;

  static const LatLng _kyivCenter = LatLng(50.4501, 30.5234);

  @override
  void initState() {
    super.initState();
    _loadRegionInfo();
    _loadKyivOblastMask();
  }

  Future<void> _loadRegionInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final regionIdString = prefs.getString(regionKey);
      debugPrint('--- РЕГІОН: Зчитано ID: $regionIdString');

      // ukraineRegions uses string IDs like 'kyiv', 'zhytomyr', etc.
      final region = ukraineRegions.firstWhere(
        (r) => r.id == regionIdString,
        orElse: () => const Region(id: 'kyiv', name: 'Київська область'),
      );

      // For test: if regionIdString is empty, force Kyiv
      final effectiveRegionName = (regionIdString == null || regionIdString.isEmpty)
          ? 'Київська область'
          : region.name;

      // Extract numeric ID for API calls (index in list + 1, or use a mapping)
      final regionIndex = ukraineRegions.indexWhere((r) => r.id == regionIdString);
      final effectiveRegionId = regionIndex >= 0 ? regionIndex + 1 : 10; // 10 = Kyiv (index 9 + 1)

      if (mounted) {
        setState(() {
          _currentRegionName = effectiveRegionName;
          _currentRegionId = effectiveRegionId;
        });
      }
      debugPrint('--- РЕГІОН: Встановлено: $_currentRegionName (ID: $_currentRegionId)');
    } catch (e) {
      debugPrint('--- РЕГІОН: Помилка: $e');
    }
  }

  Future<void> _loadKyivOblastMask() async {
    try {
      final String geojsonString = await rootBundle.loadString('assets/data/kyiv_oblast.geojson');
      final Map<String, dynamic> geojson = json.decode(geojsonString);

      // Parse MultiPolygon/Polygon coordinates
      final features = geojson['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) {
        debugPrint('--- МАСКА: Файл порожній або не знайдено (features пусті)');
        return;
      }

      for (final feature in features) {
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final type = geometry['type'] as String?;
        final coordinates = geometry['coordinates'] as List<dynamic>?;

        if (coordinates == null || coordinates.isEmpty) continue;

        if (type == 'Polygon') {
          // Polygon: coordinates[0] = outer ring, coordinates[1+] = holes
          final outerRing = coordinates[0] as List<dynamic>;
          _kyivOblastOuterRing = outerRing.map((coord) {
            final c = coord as List<dynamic>;
            return LatLng(c[1] as double, c[0] as double); // GeoJSON is [lon, lat]
          }).toList();
        } else if (type == 'MultiPolygon') {
          // MultiPolygon: coordinates[0] = first polygon, coordinates[0][0] = outer ring
          final firstPolygon = coordinates[0] as List<dynamic>;
          final outerRing = firstPolygon[0] as List<dynamic>;
          _kyivOblastOuterRing = outerRing.map((coord) {
            final c = coord as List<dynamic>;
            return LatLng(c[1] as double, c[0] as double);
          }).toList();
        }
      }

      debugPrint('--- МАСКА: Завантажено точок: ${_kyivOblastOuterRing.length}');

      if (_kyivOblastOuterRing.isEmpty) {
        debugPrint('--- МАСКА: Файл порожній або не знайдено');
        return;
      }

      // IMPORTANT: For flutter_map Polygon with holePointsList, the outer ring (world)
      // should be clockwise, and the hole (Kyiv oblast) should be counter-clockwise
      // or vice versa. We'll reverse to ensure correct winding order.
      _kyivOblastOuterRing = _kyivOblastOuterRing.reversed.toList();

      if (mounted) {
        setState(() {
          _maskLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('--- МАСКА: Помилка завантаження: $e');
    }
  }

  // Helper to create world polygon with hole for the region mask
  Polygon _buildRegionMaskPolygon() {
    // World bounds (clockwise)
    final worldOuterRing = [
      const LatLng(-85, -180),
      const LatLng(-85, 180),
      const LatLng(85, 180),
      const LatLng(85, -180),
      const LatLng(-85, -180),
    ];

    return Polygon(
      points: worldOuterRing,
      holePointsList: [_kyivOblastOuterRing],
      color: Colors.black.withValues(alpha: 0.5),
      borderColor: Colors.transparent,
      borderStrokeWidth: 0,
      isDotted: false,
    );
  }

  Future<void> _onMyLocationPressed() async {
    setState(() => _isLoadingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Дозвіл на геолокацію відхилено');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Геолокація вимкнена в налаштуваннях');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        _mapController.move(LatLng(position.latitude, position.longitude), 14.0);
        _showSnackBar('Місцезнаходження знайдено');
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        _showSnackBar('Помилка отримання місцезнаходження');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  void _onAddMarkerPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Створення нової знахідки в розробці',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.darkGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.darkGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final polygonsAsync = ref.watch(forestPolygonsProviderProvider(_currentRegionId));
    final zonesAsync = ref.watch(forestZonesNotifierProvider(_currentRegionId));

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Stack(
        children: [
          _buildMap(polygonsAsync),
          _buildTopHeader(),
          _buildActionButtons(),
          zonesAsync.when(
            loading: () => _buildLoadingIndicator(),
            error: (e, st) => _buildErrorIndicator(e.toString()),
            data: (_) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(AsyncValue<List<Polygon>> polygonsAsync) {
    final maskPolygon = _maskLoaded ? _buildRegionMaskPolygon() : null;
    final maskLayer = maskPolygon != null ? PolygonLayer(polygons: [maskPolygon]) : null;

    return polygonsAsync.when(
      data: (polygons) => FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _kyivCenter,
          initialZoom: 10.0,
          minZoom: 3.0,
          maxZoom: 18.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.mushroomradar.mushroom_radar_client',
            maxZoom: 19,
          ),
          if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
          if (maskLayer != null) maskLayer,
        ],
      ),
      loading: () => FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _kyivCenter,
          initialZoom: 10.0,
          minZoom: 3.0,
          maxZoom: 18.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.mushroomradar.mushroom_radar_client',
            maxZoom: 19,
          ),
          if (maskLayer != null) maskLayer,
        ],
      ),
      error: (e, st) => FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _kyivCenter,
          initialZoom: 10.0,
          minZoom: 3.0,
          maxZoom: 18.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.mushroomradar.mushroom_radar_client',
            maxZoom: 19,
          ),
          if (maskLayer != null) maskLayer,
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.darkGreen.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Завантаження лісів...',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.darkGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorIndicator(String error) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'Помилка завантаження: $error',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.darkGreen.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forest_rounded,
              size: 20,
              color: AppTheme.darkGreen,
            ),
            const SizedBox(width: 8),
            Text(
              _currentRegionName,
              style: GoogleFonts.merriweather(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Positioned(
      bottom: 24,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _onAddMarkerPressed,
            backgroundColor: AppTheme.darkGreen,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded, size: 24),
            label: Text(
              'Тук-тук',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            heroTag: 'add_marker',
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            onPressed: _isLoadingLocation ? null : _onMyLocationPressed,
            backgroundColor: AppTheme.darkGreen,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            heroTag: 'my_location',
            child: _isLoadingLocation
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.my_location_rounded, size: 22),
          ),
        ],
      ),
    );
  }
}