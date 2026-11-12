import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../local/local_store.dart';
import '../models/analysis.dart';

/// Машинний прогноз — аналіз ділянки (`/v1-analysis`, ADR-015).
///
/// Ділянку не пересувають (ADR-015 §15.4): її створюють у вільний слот
/// ([createArea]), повторно аналізують ([analyzeArea]) або видаляють ([deleteArea]).
/// Які розміри доступні, чи можна створити ще одну і скільки аналізів лишилось —
/// вирішує сервер; клієнт лише показує.
class AnalysisRepository {
  AnalysisRepository(this._api, [this._store]);

  final ApiClient _api;

  /// Офлайн-копія ділянок і їхніх останніх результатів (вкладка «Прогноз» без мережі).
  final LocalStore? _store;

  static String cacheKey(String userId) => 'analysis_overview_$userId';

  /// Ділянки й доступи. Без інтернету — збережена копія з [AnalysisOverview.offlineSince].
  Future<AnalysisOverview> fetchOverview({String? userId}) async {
    final key = userId == null ? null : cacheKey(userId);
    try {
      final data = await _api.get('/v1-analysis') as Map<String, dynamic>;
      final overview = AnalysisOverview.fromJson(data);
      if (key != null) await _store?.write(key, data);
      return overview;
    } on ApiException catch (e) {
      if (!e.isNetworkError || key == null) rethrow;
      final cached = await _store?.read(key);
      if (cached?.data is! Map<String, dynamic>) rethrow;
      return AnalysisOverview.fromJson(cached!.data as Map<String, dynamic>, offlineSince: cached.savedAt);
    }
  }

  /// Нова ділянка [sizeKm]×[sizeKm] км з центром у [center] + перший аналіз.
  /// [forest] — ліс у квадраті з полігонів на карті (сервер має не всі області).
  /// Вільного місця немає → `409 area_limit_reached` з поясненням.
  Future<AnalysisResult> createArea({
    required LatLng center,
    required int sizeKm,
    Map<String, dynamic>? forest,
  }) async =>
      AnalysisResult.fromJson(await _api.post('/v1-analysis', body: {
        'lat': center.latitude,
        'lng': center.longitude,
        'size_km': sizeKm,
        if (forest != null) 'forest': forest,
      }) as Map<String, dynamic>);

  /// Повторний аналіз збереженої ділянки (той самий центр і розмір).
  Future<AnalysisResult> analyzeArea(String areaId, {Map<String, dynamic>? forest}) async =>
      AnalysisResult.fromJson(await _api.post('/v1-analysis', body: {
        'area_id': areaId,
        if (forest != null) 'forest': forest,
      }) as Map<String, dynamic>);

  Future<void> deleteArea(String areaId) async {
    await _api.delete('/v1-analysis/areas/$areaId');
  }
}
