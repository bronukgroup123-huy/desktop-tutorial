import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../local/local_store.dart';
import '../models/region.dart';

enum GeometryDetail { low, medium, high }

/// Довідник областей і їхні кордони.
class RegionsRepository {
  RegionsRepository(this._api, this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ApiClient _api;
  final LocalStore _store;
  final DateTime Function() _now;
  final Map<String, RegionGeometry> _memory = {};

  /// Кордони змінюються вкрай рідко — перевіряємо раз на тиждень.
  static const Duration refreshAfter = Duration(days: 7);

  /// Список областей для онбордингу (`GET /regions`, публічний; потрібен інтернет).
  Future<List<RegionSummary>> fetchRegions() async {
    final data = await _api.get('/regions') as List<dynamic>;
    return data
        .map((e) => RegionSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Кордон області (`GET /v1-regions/{slug}/geometry`): пам'ять → телефон → мережа.
  /// Без інтернету — збережена копія.
  Future<RegionGeometry> fetchGeometry(
    String slug, {
    GeometryDetail detail = GeometryDetail.medium,
  }) async {
    final key = 'geometry_${slug}_${detail.name}';
    final inMemory = _memory[key];
    if (inMemory != null) return inMemory;

    final cached = await _store.read(key);
    if (cached != null && _now().difference(cached.savedAt) < refreshAfter) {
      return _memory[key] = RegionGeometry.fromJson(cached.data as Map<String, dynamic>);
    }
    try {
      final data = await _api.get(
        '/v1-regions/${Uri.encodeComponent(slug)}/geometry',
        query: {'detail': detail.name},
      );
      await _store.write(key, data);
      await _store.deleteByPrefix('geometry_', except: key);
      return _memory[key] = RegionGeometry.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.isNetworkError && cached != null) {
        return _memory[key] = RegionGeometry.fromJson(cached.data as Map<String, dynamic>);
      }
      rethrow;
    }
  }
}
