import '../api/api_client.dart';
import '../models/friends.dart';

/// Друзі (`/v1-friends`, ADR-021 §21.1). Ліміти, стани й кнопки — на сервері.
class FriendsRepository {
  FriendsRepository(this._api);

  final ApiClient _api;

  Future<FriendsOverview> overview() async =>
      FriendsOverview.fromJson(await _api.get('/v1-friends') as Map<String, dynamic>);

  /// Пошук за початком @ніка; коротко — порожньо з підказкою.
  Future<({List<FriendCard> results, String? hint})> search(String query) async {
    final data = await _api.get('/v1-friends', query: {'q': query}) as Map<String, dynamic>;
    return (
      results: [for (final e in (data['results'] as List? ?? const []).cast<Map<String, dynamic>>()) FriendCard.fromJson(e)],
      hint: data['hint_label'] as String?,
    );
  }

  Future<FriendProfile> profile(String idOrHandle) async {
    final data = await _api.get('/v1-friends', query: {'user': idOrHandle}) as Map<String, dynamic>;
    return FriendProfile.fromJson(data['profile'] as Map<String, dynamic>);
  }

  /// Дія над користувачем; відповідь — новий стан картки і текст для підказки.
  Future<({FriendCard user, String? done})> act(String action, String userId, {String? reason, String? comment, bool block = false}) async {
    final data = await _api.post('/v1-friends', body: {
      'action': action,
      'user_id': userId,
      if (reason != null) 'reason': reason,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      if (action == 'report' && block) 'block': true,
    }) as Map<String, dynamic>;
    return (user: FriendCard.fromJson(data['user'] as Map<String, dynamic>), done: data['done_label'] as String?);
  }

  /// Пристрій для push «запит у друзі», «прийнято» (і тривог Наглядача).
  Future<void> registerPush(String token, String platform) =>
      _api.put('/v1-friends/push', body: {'token': token, 'platform': platform});
}
