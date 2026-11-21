import 'json.dart';
import 'me.dart';

/// Кнопка дії над користувачем — назва, вигляд і питання перед дією приходять із сервера
/// (Thin Client: клієнт не тримає таблиці переходів «запит → друзі → блок»).
class FriendActionButton {
  const FriendActionButton({required this.id, required this.label, required this.style, this.confirmLabel});

  factory FriendActionButton.fromJson(Map<String, dynamic> json) => FriendActionButton(
        id: req<String>(json, 'id'),
        label: req<String>(json, 'label'),
        style: opt<String>(json, 'style') ?? 'secondary',
        confirmLabel: opt<String>(json, 'confirm_label'),
      );

  /// request | accept | decline | cancel | remove | block | unblock | report
  final String id;
  final String label;

  /// primary | secondary — кнопки; menu | danger — у меню «⋮».
  final String style;
  final String? confirmLabel;

  bool get inMenu => style == 'menu' || style == 'danger';
}

/// Користувач у списку друзів, запитах, пошуку (ADR-021 §21.1). Без координат, телефону, email.
class FriendCard {
  const FriendCard({
    required this.id,
    required this.handle,
    this.name,
    required this.avatar,
    required this.levelLabel,
    this.levelId,
    required this.relation,
    this.relationLabel,
    this.actions = const [],
  });

  factory FriendCard.fromJson(Map<String, dynamic> json) => FriendCard(
        id: req<String>(json, 'id'),
        handle: opt<String>(json, 'handle') ?? '',
        name: opt<String>(json, 'name'),
        avatar: Avatar.fromJson(req<Map<String, dynamic>>(json, 'avatar')),
        levelLabel: (opt<Map<String, dynamic>>(json, 'level') ?? const {})['label'] as String? ?? '',
        levelId: (opt<Map<String, dynamic>>(json, 'level') ?? const {})['id'] as String?,
        relation: opt<String>(json, 'relation') ?? 'none',
        relationLabel: opt<String>(json, 'relation_label'),
        actions: [
          for (final a in (opt<List<dynamic>>(json, 'actions') ?? const []).cast<Map<String, dynamic>>()) FriendActionButton.fromJson(a),
        ],
      );

  final String id;
  final String handle;
  final String? name;
  final Avatar avatar;
  final String levelLabel;

  /// traveler … master — для кольору шапки й значка рівня.
  final String? levelId;

  /// none | outgoing | incoming | friends | blocked
  final String relation;
  final String? relationLabel;
  final List<FriendActionButton> actions;

  List<FriendActionButton> get buttons => actions.where((a) => !a.inMenu).toList();
  List<FriendActionButton> get menu => actions.where((a) => a.inMenu).toList();
}

/// `GET /v1-friends`: друзі, запити, заблоковані.
class FriendsOverview {
  const FriendsOverview({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.blocked = const [],
    this.limitLabel,
  });

  factory FriendsOverview.fromJson(Map<String, dynamic> json) {
    List<FriendCard> list(String k) =>
        [for (final e in (opt<List<dynamic>>(json, k) ?? const []).cast<Map<String, dynamic>>()) FriendCard.fromJson(e)];
    return FriendsOverview(
      friends: list('friends'),
      incoming: list('incoming'),
      outgoing: list('outgoing'),
      blocked: list('blocked'),
      limitLabel: (opt<Map<String, dynamic>>(json, 'limits') ?? const {})['label'] as String?,
    );
  }

  final List<FriendCard> friends;
  final List<FriendCard> incoming;
  final List<FriendCard> outgoing;
  final List<FriendCard> blocked;
  final String? limitLabel;
}

/// Публічний профіль (§21.2; PO 2026-11-21): аватар із ніком, ім'ям і рівнем, трофеї й
/// подарунки — більше нічого (бали, прогрес і друзі — лише власнику).
class FriendProfile {
  const FriendProfile({required this.card, required this.isMe, this.trophies = const []});

  factory FriendProfile.fromJson(Map<String, dynamic> json) => FriendProfile(
        card: FriendCard.fromJson(json),
        isMe: opt<bool>(json, 'is_me') ?? false,
        trophies: [
          for (final t in (opt<List<dynamic>>(json, 'trophies') ?? const []).cast<Map<String, dynamic>>())
            (id: t['id'] as String, title: t['title'] as String? ?? ''),
        ],
      );

  final FriendCard card;
  final bool isMe;

  /// Отримані трофеї (id картинки, назва) — найновіші перші.
  final List<({String id, String title})> trophies;
}

/// Причини скарги — ті самі коди, що й на сервері.
const kReportReasons = <(String, String)>[
  ('spam', 'Спам або реклама'),
  ('abuse', 'Образи чи погрози'),
  ('impersonation', 'Видає себе за іншого'),
  ('inappropriate', 'Непристойний нік чи аватар'),
  ('other', 'Інше'),
];
