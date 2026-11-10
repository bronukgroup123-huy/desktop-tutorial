import 'package:flutter/foundation.dart' show debugPrint;
import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../local/local_store.dart';
import '../models/forest_zone.dart';
import '../models/geo.dart';

/// Плитка сітки, на яку ділиться область для завантаження лісів.
class ForestTile {
  const ForestTile(this.row, this.col);

  final int row;
  final int col;

  static const double sizeDeg = 0.5;

  GeoBounds get bounds => GeoBounds(
        southWest: LatLng(row * sizeDeg, col * sizeDeg),
        northEast: LatLng((row + 1) * sizeDeg, (col + 1) * sizeDeg),
      );

  String key(String slug) => 'forests_${slug}_${row}_$col';

  /// Плитки сітки 0.5°, що перекривають межі області (стабільні між запусками).
  static List<ForestTile> cover(GeoBounds b) {
    final r0 = (b.southWest.latitude / sizeDeg).floor();
    final r1 = (b.northEast.latitude / sizeDeg).ceil() - 1;
    final c0 = (b.southWest.longitude / sizeDeg).floor();
    final c1 = (b.northEast.longitude / sizeDeg).ceil() - 1;
    return [
      for (var r = r0; r <= r1; r++)
        for (var c = c0; c <= c1; c++) ForestTile(r, c),
    ];
  }
}

/// Стан завантаження лісів області (для поступового показу на карті).
class ForestLoad {
  const ForestLoad({
    required this.zones,
    required this.done,
    required this.total,
    required this.failed,
    required this.offline,
  });

  final List<ForestZone> zones;
  final int done;
  final int total;

  /// Плитки, які не вдалося завантажити і яких немає на телефоні.
  final int failed;

  /// Хоч одна плитка взята з телефону через відсутність мережі.
  final bool offline;

  bool get complete => done >= total;
}

/// Полігони лісів — сервер віддає ТІЛЬКИ Home Region користувача (ADR-015 §15.2).
///
/// Офлайн-карта: область ділиться на плитки 0.5°; кожна плитка завантажується
/// один раз і зберігається на телефоні, далі — з телефону. Раз на добу плитка
/// тихо перевіряється на сервері (ETag → 304 без тіла).
///
/// Чому плитки, а не один запит на всю область: у лісистих областях (Житомирська,
/// Рівненська) повна область — це тисячі полігонів і десятки МБ JSON, такий
/// запит на мобільному інтернеті впирається в тайм-аут, і на карті не з'являється
/// нічого. Плитки малі, вантажаться паралельно і показуються поступово.
class ForestZonesRepository {
  ForestZonesRepository(this._api, this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ApiClient _api;
  final LocalStore _store;
  final DateTime Function() _now;

  static const Duration refreshAfter = Duration(hours: 24);

  /// Масштаб, під який сервер спрощує геометрію (≈ 20 м — непомітно на карті).
  static const int downloadZoom = 11;
  static const int maxFeaturesPerTile = 10000;
  static const int parallel = 4;

  /// Ліси всієї області, плитка за плиткою. Кожен елемент потоку — усі ліси,
  /// що вже є (без дублів: полігон на межі плиток приходить двічі).
  Stream<ForestLoad> loadRegion(String slug, GeoBounds regionBounds, {bool forceRefresh = false}) async* {
    final tiles = ForestTile.cover(regionBounds);
    // Плитки іншої області більше не потрібні (ADR-016).
    await _store.deleteByPrefix('forests_', keepPrefix: 'forests_${slug}_');

    final byId = <String, ForestZone>{};
    var done = 0;
    var failed = 0;
    var offline = false;
    final pending = <ForestTile>[];

    ForestLoad snapshot() => ForestLoad(
          zones: List.unmodifiable(byId.values),
          done: done,
          total: tiles.length,
          failed: failed,
          offline: offline,
        );

    // 1. Свіжі плитки з телефону — миттєво, без мережі.
    for (final t in tiles) {
      final cached = await _store.read(t.key(slug));
      if (cached != null && !forceRefresh && _now().difference(cached.savedAt) < refreshAfter) {
        _addAll(byId, cached.data);
        done++;
      } else {
        pending.add(t);
      }
    }
    debugPrint('[forests] $slug: ${tiles.length} tiles, ${tiles.length - pending.length} from phone, '
        '${pending.length} to download');
    yield snapshot();

    // 2. Решта — з мережі, по кілька паралельно.
    for (var i = 0; i < pending.length; i += parallel) {
      final batch = pending.skip(i).take(parallel);
      final results = await Future.wait(batch.map((t) => _loadTile(slug, t)));
      for (final r in results) {
        done++;
        if (r.data != null) _addAll(byId, r.data);
        if (r.offline) offline = true;
        if (r.failed) failed++;
      }
      yield snapshot();
    }
    debugPrint('[forests] $slug: done, ${byId.length} forests, failed tiles: $failed, offline: $offline');
  }

  Future<({Object? data, bool offline, bool failed})> _loadTile(String slug, ForestTile t) async {
    final cached = await _store.read(t.key(slug));
    try {
      final res = await _api.getConditional(
        '/v1-forest-zones',
        query: {'bbox': t.bounds.toQuery(), 'z': downloadZoom, 'limit': maxFeaturesPerTile},
        etag: cached?.etag,
      );
      final now = _now();
      if (res.notModified && cached != null) {
        await _store.write(t.key(slug), cached.data, etag: cached.etag, savedAt: now);
        debugPrint('[forests] tile ${t.row}_${t.col}: not modified');
        return (data: cached.data, offline: false, failed: false);
      }
      await _store.write(t.key(slug), res.data, etag: res.etag, savedAt: now);
      final n = ((res.data as Map<String, dynamic>)['features'] as List?)?.length ?? 0;
      debugPrint('[forests] tile ${t.row}_${t.col}: $n features');
      return (data: res.data, offline: false, failed: false);
    } on ApiException catch (e) {
      debugPrint('[forests] tile ${t.row}_${t.col}: ${e.code} (HTTP ${e.statusCode}) ${e.serverMessage ?? ''}');
      if (cached != null) return (data: cached.data, offline: e.isNetworkError, failed: false);
      return (data: null, offline: e.isNetworkError, failed: true);
    } on FormatException catch (e) {
      debugPrint('[forests] tile ${t.row}_${t.col}: bad data — $e');
      return (data: cached?.data, offline: false, failed: cached == null);
    }
  }

  static void _addAll(Map<String, ForestZone> byId, Object? data) {
    for (final z in ForestZone.listFromFeatureCollection(data as Map<String, dynamic>)) {
      byId[z.id] = z;
    }
  }

  /// Ліси для ділянки карти (без кешу).
  Future<List<ForestZone>> fetchForestZones({GeoBounds? bounds, int? zoom, int? limit}) async {
    final data = await _api.get('/v1-forest-zones', query: {
      if (bounds != null) 'bbox': bounds.toQuery(),
      if (zoom != null) 'z': zoom,
      if (limit != null) 'limit': limit,
    });
    return ForestZone.listFromFeatureCollection(data as Map<String, dynamic>);
  }
}
