import '../api/api_client.dart';
import '../models/me.dart';

/// Профіль і онбординг (`/v1-me`). Рішення «який екран далі» приймає сервер.
class MeRepository {
  MeRepository(this._api);

  final ApiClient _api;

  Future<Me> fetchMe() async =>
      Me.fromJson(await _api.get('/v1-me') as Map<String, dynamic>);

  /// Спільний крок онбордингу: область + згода з EULA/Privacy (план v8.2 §3.7).
  /// [termsVersion] — `onboarding.terms_version` з останньої відповіді `GET /v1-me`.
  Future<Me> completeOnboarding({
    required String regionSlug,
    required String termsVersion,
  }) =>
      _patch({'home_region_slug': regionSlug, 'accept_terms_version': termsVersion});

  /// Зміна області після онбордингу (ADR-016). Дозвіл — у `me.regionChange.allowed`;
  /// інакше сервер відповість `403 region_change_not_allowed`.
  Future<Me> changeRegion(String regionSlug) => _patch({'home_region_slug': regionSlug});

  Future<Me> updateName(String name) => _patch({'name': name});

  Future<Me> _patch(Map<String, Object> body) async =>
      Me.fromJson(await _api.patch('/v1-me', body: body) as Map<String, dynamic>);
}
