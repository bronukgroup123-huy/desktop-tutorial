import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../local/local_store.dart';
import '../local/offline_result.dart';
import '../models/forest_zone.dart';
import '../models/geo.dart';

/// Полігони лісів — сервер віддає ТІЛЬКИ Home Region користувача (ADR-015 §15.2).
///
/// Офлайн-карта: ліси всієї області завантажуються один раз і зберігаються на
/// телефоні. Далі карта працює з локальної копії (і без інтернету); раз на добу
/// застосунок тихо перевіряє на сервері, чи дані змінились (ETag → 304 без тіла).
class ForestZonesRepository {
  ForestZonesRepository(this._api, this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ApiClient _api;
  final LocalStore _store;
  final DateTime Function() _now;

  static const Duration refreshAfter = Duration(hours: 24);

  /// Масштаб, під який сервер спрощує геометрію для повного завантаження області.
  static const int fullRegionZoom = 11;
  static const int maxFeatures = 10000;

  static String _key(String slug) => 'forests_$slug';

  /// Ліси всієї області: з телефону, а з мережі — лише перший раз, раз на добу
  /// або на вимогу ([forceRefresh]).
  Future<OfflineResult<List<ForestZone>>> regionForests(String slug, {bool forceRefresh = false}) async {
    final cached = await _store.read(_key(slug));
    final fresh = cached != null && _now().difference(cached.savedAt) < refreshAfter;
    if (cached != null && fresh && !forceRefresh) {
      return OfflineResult(value: _parse(cached.data), savedAt: cached.savedAt, offline: false);
    }

    try {
      final res = await _api.getConditional(
        '/v1-forest-zones',
        query: {'z': fullRegionZoom, 'limit': maxFeatures},
        etag: cached?.etag,
      );
      final now = _now();
      if (res.notModified && cached != null) {
        await _store.write(_key(slug), cached.data, etag: cached.etag, savedAt: now);
        return OfflineResult(value: _parse(cached.data), savedAt: now, offline: false);
      }
      await _store.write(_key(slug), res.data, etag: res.etag, savedAt: now);
      // Стара область більше не потрібна (ADR-016: при зміні області — видаляємо).
      await _store.deleteByPrefix('forests_', except: _key(slug));
      return OfflineResult(value: _parse(res.data), savedAt: now, offline: false);
    } on ApiException catch (e) {
      if (e.isNetworkError && cached != null) {
        return OfflineResult(value: _parse(cached.data), savedAt: cached.savedAt, offline: true);
      }
      rethrow;
    }
  }

  /// Ліси для ділянки карти (без кешу).
  Future<List<ForestZone>> fetchForestZones({GeoBounds? bounds, int? zoom, int? limit}) async {
    final data = await _api.get('/v1-forest-zones', query: {
      if (bounds != null) 'bbox': bounds.toQuery(),
      if (zoom != null) 'z': zoom,
      if (limit != null) 'limit': limit,
    });
    return _parse(data);
  }

  static List<ForestZone> _parse(Object? data) =>
      ForestZone.listFromFeatureCollection(data as Map<String, dynamic>);
}
