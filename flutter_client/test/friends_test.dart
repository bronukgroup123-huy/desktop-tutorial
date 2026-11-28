import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/friends_repository.dart';
import 'package:flutter_client/features/friends/friend_profile_screen.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/friends/invite_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'data/fake_adapter.dart';
import 'safety_test.dart' show frames;

const petroId = '22222222-2222-4222-8222-222222222222';
const irynaId = '44444444-4444-4444-8444-444444444444';

Map<String, dynamic> card(String id, String handle, String relation, List<Map<String, dynamic>> actions, {String? label}) => {
      'id': id,
      'handle': handle,
      'name': handle,
      'avatar': {'kind': 'preset', 'id': 'tracker_03'},
      'level': {'id': 'tracker', 'label': 'Слідопит'},
      'relation': relation,
      'relation_label': label,
      'actions': actions,
    };

Map<String, dynamic> act(String id, String label, String style, [String? confirm]) =>
    {'id': id, 'label': label, 'style': style, 'confirm_label': confirm};

final report = act('report', 'Поскаржитися', 'menu');
final block = act('block', 'Заблокувати', 'danger', 'Заблокувати @Петро?');

void main() {
  test('FriendCard: кнопки й меню розділено за style із сервера', () {
    final c = FriendCard.fromJson(card(irynaId, 'Ірина', 'incoming', [act('accept', 'Прийняти', 'primary'), act('decline', 'Відхилити', 'secondary'), report, block]));
    expect(c.buttons.map((a) => a.id), ['accept', 'decline']);
    expect(c.menu.map((a) => a.id), ['report', 'block']);
    expect(c.avatar.asset, 'assets/avatars/tracker_03.webp');
  });

  late FakeAdapter adapter;
  late List<Map<String, dynamic>> posted;

  Widget app(Widget home) {
    posted = [];
    final (api, a) = makeClient((r) {
      if (r.method == 'PUT') return const FakeResponse(200, {'data': {'registered': true}});
      if (r.method == 'POST') {
        final body = (r.data is String ? jsonDecode(r.data as String) : r.data) as Map<String, dynamic>;
        posted.add(body);
        final relation = body['action'] == 'accept' ? 'friends' : body['action'] == 'request' ? 'outgoing' : 'none';
        return FakeResponse(200, {
          'data': {
            'user': card(body['user_id'] as String, body['user_id'] == petroId ? 'Петро' : 'Ірина', relation,
                relation == 'outgoing' ? [act('cancel', 'Скасувати запит', 'secondary'), report, block] : [act('remove', 'Видалити з друзів', 'menu', 'Видалити?'), report, block],
                label: relation == 'outgoing' ? 'Запит надіслано' : null),
            'done_label': relation == 'friends' ? 'Тепер ви друзі' : 'Запит надіслано',
          },
        });
      }
      final q = r.queryParameters;
      if (q['q'] != null) {
        return FakeResponse(200, {
          'data': {
            'results': [card(petroId, 'Петро', 'none', [act('request', 'Додати в друзі', 'primary'), report, block])],
            'hint_label': null,
          },
        });
      }
      if (q['user'] != null) {
        return FakeResponse(200, {
          'data': {
            'profile': {
              ...card(petroId, 'Петро', 'friends', [act('remove', 'Видалити з друзів', 'menu', 'Видалити @Петро з друзів?'), report, block], label: 'У друзях'),
              'is_me': false,
              'trophies': [{'id': 'first_find', 'title': 'Перша знахідка', 'earned_at': '2026-09-10T08:00:00Z'}],
            },
          },
        });
      }
      return FakeResponse(200, {
        'data': {
          'friends': [card(petroId, 'Петро', 'friends', [act('remove', 'Видалити з друзів', 'menu', 'Видалити?'), report, block], label: 'У друзях')],
          'incoming': [card(irynaId, 'Ірина', 'incoming', [act('accept', 'Прийняти', 'primary'), act('decline', 'Відхилити', 'secondary'), report, block], label: 'Хоче додати вас у друзі')],
          'outgoing': [],
          'blocked': [],
          'counts': {'friends': 1, 'incoming': 1},
          'limits': {'max_friends': 200, 'label': 'До 200 друзів'},
        },
      });
    });
    adapter = a;
    return ProviderScope(
      overrides: [
        friendsRepositoryProvider.overrideWithValue(FriendsRepository(api)),
        friendsProvider.overrideWith((ref) => ref.watch(friendsRepositoryProvider).overview()),
      ],
      child: MaterialApp(home: home),
    );
  }

  testWidgets('Друзі: запити згори, «Прийняти» — дія на сервер і список оновлюється', (tester) async {
    await tester.pumpWidget(app(const FriendsScreen()));
    await frames(tester);
    expect(find.text('Запити в друзі · 1'), findsOneWidget);
    expect(find.text('@Ірина'), findsOneWidget);
    expect(find.text('Хоче додати вас у друзі'), findsOneWidget);
    expect(find.text('Мої друзі · 1'), findsOneWidget);
    expect(find.text('@Петро'), findsOneWidget);

    final before = adapter.requests.where((r) => r.method == 'GET').length;
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('friend-$irynaId')), matching: find.byKey(const ValueKey('friend-action-accept'))));
    await frames(tester);
    expect(posted.single, {'action': 'accept', 'user_id': irynaId});
    expect(find.text('Тепер ви друзі'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'GET').length, greaterThan(before)); // перечитали список
  });

  testWidgets('Друзі: «Запросити друга» відкриває екран коду запрошення', (tester) async {
    await tester.pumpWidget(app(const FriendsScreen()));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('friends-invite')));
    await tester.pumpAndSettle();
    expect(find.byType(InviteScreen), findsOneWidget);
    expect(find.text('Запросити друга'), findsWidgets);
  });

  testWidgets('Друзі: пошук за ніком → «Додати в друзі» → «Запит надіслано»', (tester) async {
    await tester.pumpWidget(app(const FriendsScreen()));
    await frames(tester);
    await tester.enterText(find.byKey(const ValueKey('friends-search')), '@пет');
    await tester.pump(const Duration(milliseconds: 400));
    await frames(tester);
    final search = adapter.requests.lastWhere((r) => r.queryParameters['q'] != null);
    expect(search.queryParameters['q'], '@пет');
    expect(find.text('Пошук: @пет'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('friend-action-request')));
    await frames(tester);
    expect(posted.single['action'], 'request');
    expect(find.text('Запит надіслано'), findsWidgets);
    expect(find.byKey(const ValueKey('friend-action-cancel')), findsOneWidget);
  });

  testWidgets('Профіль друга: лише аватар із рівнем, трофеї й подарунки — без балів і друзів; «Видалити з друзів» — після підтвердження', (tester) async {
    await tester.pumpWidget(app(const FriendProfileScreen(userId: petroId)));
    await frames(tester);
    expect(find.text('@Петро'), findsWidgets);
    expect(find.text('Слідопит'), findsOneWidget);
    expect(find.text('У друзях'), findsOneWidget);
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('trophy-first_find')), 200, scrollable: scroll);
    expect(find.byKey(const ValueKey('friend-trophies')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('friend-gifts')), 200, scrollable: scroll);
    expect(find.textContaining('бал'), findsNothing);
    expect(find.textContaining(RegExp(r'\d+ друз')), findsNothing);
    await tester.scrollUntilVisible(find.text('У друзях'), -200, scrollable: scroll);

    await tester.tap(find.byKey(const ValueKey('profile-menu')));
    await frames(tester);
    await tester.tap(find.text('Видалити з друзів'));
    await frames(tester);
    expect(find.text('Видалити @Петро з друзів?'), findsOneWidget);
    await tester.tap(find.text('Скасувати'));
    await frames(tester);
    expect(posted, isEmpty);
  });

  testWidgets('Скарга: без причини не надіслати; з причиною — report + block', (tester) async {
    await tester.pumpWidget(app(const FriendProfileScreen(userId: petroId)));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('profile-menu')));
    await frames(tester);
    await tester.tap(find.text('Поскаржитися'));
    await frames(tester);
    final send = find.byKey(const ValueKey('report-send'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('report-spam')));
    await tester.pump();
    await tester.tap(send);
    await frames(tester);
    expect(posted.single['action'], 'report');
    expect(posted.single['reason'], 'spam');
    expect(posted.single['block'], true);
  });
}
