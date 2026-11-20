import '../api/api_client.dart';
import '../models/guardian.dart';

/// Наглядач (`/v1-guardian`, ADR-022): згода друга, похід, трек, «Все добре?», SOS.
class GuardianRepository {
  GuardianRepository(this._api);

  final ApiClient _api;

  Future<GuardianOverview> overview() async => GuardianOverview.fromJson(await _api.get('/v1-guardian') as Map<String, dynamic>);

  Future<HikeDetail> hike(String id, {DateTime? since}) async {
    final data = await _api.get('/v1-guardian', query: {
      'hike': id,
      if (since != null) 'since': since.toUtc().toIso8601String(),
    }) as Map<String, dynamic>;
    return HikeDetail.fromJson(data['hike'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async => await _api.post('/v1-guardian', body: body) as Map<String, dynamic>;

  /// invite | accept_invite | decline_invite | remove | resign → текст для підказки.
  Future<String?> person(String action, String userId) async => (await _post({'action': action, 'user_id': userId}))['done_label'] as String?;

  Future<OwnerHike> start({
    required List<({double lat, double lng, String label})> route,
    required DateTime expectedReturn,
    required List<String> guardianIds,
    required String clientId,
  }) async {
    final data = await _post({
      'action': 'start',
      'route': [for (final p in route) {'lat': p.lat, 'lng': p.lng, 'label': p.label}],
      'expected_return': expectedReturn.toUtc().toIso8601String(),
      'guardian_ids': guardianIds,
      'client_id': clientId,
    });
    return OwnerHike.fromJson(data['hike'] as Map<String, dynamic>);
  }

  /// Точки треку й батарея; відповідь — актуальний стан походу (чи питати «Все добре?»).
  Future<OwnerHike> track(String hikeId, List<({double lat, double lng, DateTime t, double acc})> points, {int? battery}) async {
    final data = await _post({
      'action': 'track',
      'hike_id': hikeId,
      'points': [for (final p in points) {'lat': p.lat, 'lng': p.lng, 't': p.t.toUtc().toIso8601String(), 'acc': p.acc}],
      if (battery != null) 'battery': battery,
    });
    return OwnerHike.fromJson(data['hike'] as Map<String, dynamic>);
  }

  /// ok | extend | sos | sos_cancel | finish. Після finish — `hike: null`.
  Future<({OwnerHike? hike, String? done})> hikeAction(String action, String hikeId) async {
    final data = await _post({'action': action, 'hike_id': hikeId});
    final h = data['hike'];
    return (hike: h == null ? null : OwnerHike.fromJson(h as Map<String, dynamic>), done: data['done_label'] as String?);
  }

  Future<String> telegramLink() async => (await _post({'action': 'telegram_link'}))['url'] as String;

  Future<void> telegramUnlink() => _post({'action': 'telegram_unlink'});
}
