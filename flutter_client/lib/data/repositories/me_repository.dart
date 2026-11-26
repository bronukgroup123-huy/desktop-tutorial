import 'dart:convert';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../local/local_store.dart';
import '../models/me.dart';
import '../models/avatars.dart';
import '../models/trophies.dart';

/// Профіль і онбординг (`/v1-me`). Рішення «який екран далі» приймає сервер.
///
/// Остання відповідь сервера зберігається на телефоні (разом з UUID користувача):
/// без інтернету застосунок відкривається з нею — гість не застрягає на заставці.
class MeRepository {
  MeRepository(this._api, {LocalStore? store, String? Function()? userId})
      : _store = store,
        _userId = userId;

  final ApiClient _api;
  final LocalStore? _store;
  final String? Function()? _userId;

  static const cacheKey = 'me_profile';

  /// Профіль із сервера (і зберегти на телефоні).
  Future<Me> fetchMe() async => _save(await _api.get('/v1-me'));

  /// Збережений профіль цього ж користувача; `null` — немає або належить іншому.
  Future<Me?> cached() async {
    final uid = _userId?.call();
    if (_store == null || uid == null) return null;
    final entry = await _store.read(cacheKey);
    final data = entry?.data;
    if (data is! Map || data['user_id'] != uid || data['me'] is! Map) return null;
    try {
      return Me.fromJson(Map<String, dynamic>.from(data['me'] as Map));
    } catch (_) {
      await _store.delete(cacheKey); // формат змінився — візьмемо з сервера
      return null;
    }
  }

  /// З сервера, а без інтернету — збережений профіль (якщо є).
  Future<Me> fetchMeOrCached() async {
    try {
      return await fetchMe();
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      return await cached() ?? (throw e);
    }
  }

  /// Забути збережений профіль (вихід з акаунта).
  Future<void> clearCache() async => _store?.delete(cacheKey);

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

  /// Ім'я й нік (ADR-021 §21.2.1). 409 handle_taken / handle_change_too_soon — у [ApiException].
  Future<Me> updateIdentity({required String name, required String handle}) => _patch({'name': name, 'handle': handle});

  /// Трофеї-медальйони: сервер перераховує, записує нові й віддає каталог (за що й скільки).
  Future<TrophiesOverview> trophies() async =>
      TrophiesOverview.fromJson(await _api.get('/v1-me', query: {'trophies': '1'}) as Map<String, dynamic>);

  /// Чи вільний нік — підказка під полем вводу.
  /// Готові аватари за рівнями із замками (ADR-021 §21.7).
  Future<AvatarChoices> avatars() async =>
      AvatarChoices.fromJson(await _api.get('/v1-me', query: {'avatars': '1'}) as Map<String, dynamic>);

  /// Вибрати готовий аватар; закритий — `403 avatar_locked` із причиною.
  Future<Me> setAvatar(String id) => _patch({'avatar': {'kind': 'preset', 'id': id}});

  Future<({bool available, String? reason})> checkHandle(String handle) async {
    final data = await _api.get('/v1-me', query: {'check_handle': handle}) as Map<String, dynamic>;
    return (available: data['available'] == true, reason: data['reason'] as String?);
  }

  /// Усі свої дані з сервера одним JSON-файлом (GDPR, B6.1): ім'я файлу й вміст з відступами,
  /// щоб людина могла відкрити й прочитати.
  Future<({String fileName, String content})> exportData() async {
    final data = await _api.get('/v1-me', query: {'export': '1'}) as Map<String, dynamic>;
    return (
      fileName: data['file_name'] as String? ?? 'hrybnyi-radar-dani.json',
      content: const JsonEncoder.withIndent('  ').convert(data['export']),
    );
  }

  /// Видалити акаунт назавжди (вимога Google Play).
  Future<void> deleteAccount() async {
    await _api.delete('/v1-me');
    await clearCache();
  }

  Future<Me> _patch(Map<String, Object> body) async => _save(await _api.patch('/v1-me', body: body));

  Future<Me> _save(Object? raw) async {
    final json = raw as Map<String, dynamic>;
    final me = Me.fromJson(json);
    final uid = _userId?.call();
    if (_store != null && uid != null) {
      try {
        await _store.write(cacheKey, {'user_id': uid, 'me': json});
      } catch (_) {
        // не вдалося записати — працюємо без збереженої копії
      }
    }
    return me;
  }
}
