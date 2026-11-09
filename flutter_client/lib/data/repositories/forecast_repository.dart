import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../local/local_store.dart';
import '../local/offline_result.dart';
import '../models/forecast.dart';

/// Прогноз для точки в межах Home Region (`POST /v1-forecast`).
///
/// Кожен успішний прогноз зберігається на телефоні: без інтернету показуємо
/// останній відомий прогноз для цієї точки з датою («Дані від …»).
class ForecastRepository {
  ForecastRepository(this._api, this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ApiClient _api;
  final LocalStore _store;
  final DateTime Function() _now;

  static const Duration keepFor = Duration(days: 7);

  /// Ключ точки: ~100 м (3 знаки) — повторний тап поруч знаходить збережене.
  static String keyFor(double lat, double lng) =>
      'forecast_${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}';

  Future<OfflineResult<Forecast>> fetchForecast({
    required double lat,
    required double lng,
    required DateTime date,
    String? forestType,
  }) async {
    final key = keyFor(lat, lng);
    try {
      final data = await _api.post('/v1-forecast', body: {
        'lat': lat,
        'lng': lng,
        'date': _ymd(date),
        if (forestType != null) 'forestType': forestType,
      });
      final now = _now();
      await _store.write(key, data, savedAt: now);
      await _store.pruneOlderThan('forecast_', keepFor, now: now);
      return OfflineResult(value: Forecast.fromJson(data as Map<String, dynamic>), savedAt: now, offline: false);
    } on ApiException catch (e) {
      if (e.isNetworkError) {
        final cached = await _store.read(key);
        if (cached != null) {
          return OfflineResult(
            value: Forecast.fromJson(cached.data as Map<String, dynamic>),
            savedAt: cached.savedAt,
            offline: true,
          );
        }
      }
      rethrow;
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
