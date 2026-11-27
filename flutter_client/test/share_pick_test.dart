// B9.4b: поділитися приватною точкою з другом (ADR-021 §21.5).
// Кнопку «Поділитися з другом» показує лише сервер; вибір друзів; список «Бачать N друзів» з «Прибрати»;
// у друга — «Від @нік», точне місце, лише «Відкрити в Google Картах»; екран «Точки від друзів».
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/picks_repository.dart';
import 'package:flutter_client/features/picks/pick_card_sheet.dart';
import 'package:flutter_client/features/picks/shared_picks_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'profile_test.dart' show FakeMe, registered;

const pickId = '99999999-9999-4999-8999-999999999999';
const petro = '22222222-2222-4222-8222-222222222222';
const iryna = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> friend(String id, String handle) => {
      'id': id,
      'handle': handle,
      'name': null,
      'avatar': {'kind': 'preset', 'id': 'tracker_03'},
      'level': {'id': 'tracker', 'label': 'Слідопит'},
      'relation': 'friends',
      'relation_label': null,
      'actions': const [],
    };

Map<String, dynamic> ownCard({List<Map<String, dynamic>> sharedWith = const []}) => {
      'id': pickId,
      'lat': 50.45,
      'lng': 30.52,
      'is_exact': true,
      'is_mine': true,
      'visibility': 'private',
      'species_id': 'boletus_edulis',
      'name_label': 'Білий гриб',
      'status_label': 'Приватна точка',
      'marker_color': '#8e24aa',
      'description': null,
      'date_label': '10 листопада 2026 р.',
      'photo_url': null,
      'disclaimer_label': null,
      'shared_from_label': null,
      'actions': ['open_in_maps', 'share', 'make_public', 'edit_description', 'delete'],
      'shared_with': sharedWith,
      'shared_with_label': sharedWith.isEmpty ? null : 'Бачать ${sharedWith.length} друг',
    };

Map<String, dynamic> friendsCard() => {
      ...ownCard(),
      'is_mine': false,
      'shared_from_label': 'Від @Олена',
      'actions': ['open_in_maps'],
      'shared_with': null,
      'shared_with_label': null,
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Моделі: поширена точка, з ким поділилися, список «Точки від друзів»', () {
    final shared = PickCard.fromJson(friendsCard());
    expect([shared.pick.isShared, shared.pick.sharedFromLabel], [true, 'Від @Олена']);
    final own = PickCard.fromJson(ownCard(sharedWith: [{'user_id': petro, 'handle': 'Петро', 'avatar': null}]));
    expect(own.sharedWith.single.label, '@Петро');
    expect(own.sharedWithLabel, 'Бачать 1 друг');
    expect(PickCard.fromJson(ownCard()).sharedWith, isEmpty);
    final list = SharedPick.fromJson({
      'id': pickId, 'lat': 50.45, 'lng': 30.52, 'is_exact': true, 'species_id': null,
      'name_label': 'Білий гриб', 'shared_from_label': 'Від @Олена', 'date_label': '20 листопада 2026 р.',
    });
    expect([list.nameLabel, list.sharedFromLabel, list.dateLabel], ['Білий гриб', 'Від @Олена', '20 листопада 2026 р.']);
  });

  group('Картка', () {
    late FakeAdapter adapter;
    late Map<String, dynamic> card;

    Widget app() {
      final (api, a) = makeClient((r) {
        if (r.method == 'POST' && r.path.endsWith('/shares')) {
          card = ownCard(sharedWith: [{'user_id': petro, 'handle': 'Петро', 'avatar': null}]);
          return const FakeResponse(200, {'data': {'shared': 1, 'recipients': 1, 'label': 'Бачать 1 друг'}});
        }
        if (r.method == 'DELETE') {
          card = ownCard();
          return const FakeResponse(200, {'data': {'revoked': 1}});
        }
        return FakeResponse(200, {'data': card});
      });
      adapter = a;
      return ProviderScope(
        overrides: [
          picksRepositoryProvider.overrideWithValue(PicksRepository(api, uploads: Dio())),
          meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
          friendsProvider.overrideWith((ref) async => FriendsOverview(friends: [
                FriendCard.fromJson(friend(petro, 'Петро')),
                FriendCard.fromJson(friend(iryna, 'Ірина')),
              ])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => TextButton(onPressed: () => showPickCard(context, pickId), child: const Text('open'))),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('своя приватна: «Поділитися з другом» → вибір друга → на сервер id друга; далі «Прибрати»', (tester) async {
      card = ownCard();
      await tester.pumpWidget(app());
      await open(tester);
      expect(find.byKey(const ValueKey('pick-shared-with')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('pick-share')));
      await tester.tap(find.byKey(const ValueKey('pick-share')));
      await settle(tester);
      // без вибору кнопка неактивна
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('pick-share-send'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('pick-share-friend-$petro')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pick-share-send')));
      await settle(tester);
      final post = adapter.requests.firstWhere((r) => r.method == 'POST');
      expect(post.path, endsWith('/v1-picks/$pickId/shares'));
      final body = (post.data is String ? jsonDecode(post.data as String) : post.data) as Map<String, dynamic>;
      expect(body['friend_ids'], [petro]);
      // картка оновилась: хто бачить — і кнопка «Прибрати»
      expect(find.byKey(const ValueKey('pick-shared-with')), findsOneWidget);
      expect(find.text('@Петро'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('pick-share-revoke-$petro')));
      await tester.tap(find.byKey(const ValueKey('pick-share-revoke-$petro')));
      await settle(tester);
      final del = adapter.requests.lastWhere((r) => r.method == 'DELETE');
      expect(del.path, endsWith('/v1-picks/$pickId/shares/$petro'));
      expect(find.byKey(const ValueKey('pick-shared-with')), findsNothing);
    });

    testWidgets('у виборі немає тих, хто вже бачить точку; якщо бачать усі — підказка', (tester) async {
      card = ownCard(sharedWith: [
        {'user_id': petro, 'handle': 'Петро', 'avatar': null},
        {'user_id': iryna, 'handle': 'Ірина', 'avatar': null},
      ]);
      await tester.pumpWidget(app());
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('pick-share')));
      await tester.tap(find.byKey(const ValueKey('pick-share')));
      await settle(tester);
      expect(find.byKey(const ValueKey('pick-share-no-friends')), findsOneWidget);
      expect(find.text('Цю точку вже бачать усі ваші друзі.'), findsOneWidget);
    });

    testWidgets('точка від друга: «Від @нік», точне місце, лише «Відкрити в Google Картах»', (tester) async {
      card = friendsCard();
      await tester.pumpWidget(app());
      await open(tester);
      expect(find.byKey(const ValueKey('pick-shared-from')), findsOneWidget);
      expect(find.textContaining('Від @Олена. Друг поділився з вами точним місцем'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-open-in-maps')), findsOneWidget);
      for (final k in ['pick-share', 'pick-make-public', 'pick-edit-description', 'pick-delete']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
    });
  });

  testWidgets('«Точки від друзів»: список із сервера; порожній — підказка', (tester) async {
    var picks = <Map<String, dynamic>>[
      {
        'id': pickId, 'lat': 50.45, 'lng': 30.52, 'is_exact': true, 'species_id': 'boletus_edulis',
        'name_label': 'Білий гриб', 'shared_from_label': 'Від @Олена', 'date_label': '20 листопада 2026 р.',
      },
    ];
    final (api, _) = makeClient((r) => FakeResponse(200, {'data': {'picks': picks}}));
    Widget app() => ProviderScope(
          overrides: [picksRepositoryProvider.overrideWithValue(PicksRepository(api, uploads: Dio()))],
          child: const MaterialApp(home: SharedPicksScreen()),
        );
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Білий гриб'), findsOneWidget);
    expect(find.text('Від @Олена · 20 листопада 2026 р.'), findsOneWidget);
    picks = [];
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('shared-picks-empty')), findsOneWidget);
  });
}
