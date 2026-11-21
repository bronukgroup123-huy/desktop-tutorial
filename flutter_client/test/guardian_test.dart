import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/guardian.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/guardian_repository.dart';
import 'package:flutter_client/features/safety/guardian/guardian_card.dart';
import 'package:flutter_client/features/safety/guardian/guardian_session.dart';
import 'package:flutter_client/features/safety/guardian/watched_hikes.dart';
import 'package:flutter_client/features/safety/hike/hike_card.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'profile_test.dart' show FakeMe, registered;
import 'safety_hike_test.dart' show FakeHikeDevice, walk;
import 'safety_test.dart' show FakeDevice, frames;
import 'support/memory_store.dart';

const petro = '22222222-2222-4222-8222-222222222222';
const olena = '11111111-1111-4111-8111-111111111111';
const hikeId = '99999999-9999-4999-8999-999999999999';
const avatar = {'kind': 'custom', 'sticker': 'kind', 'hat': null, 'item': null, 'fx': null};

Map<String, dynamic> person(String id, String handle, {String? status}) => {
      'id': id,
      'handle': handle,
      'name': handle,
      'avatar': avatar,
      'status': status,
      'status_label': status == 'accepted' ? 'Наглядач' : null,
      'actions': [
        {'id': 'remove', 'label': 'Прибрати з Наглядачів', 'style': 'secondary'},
      ],
    };

Map<String, dynamic> ownerHike({bool ask = false}) => {
      'id': hikeId,
      'status': ask ? 'check' : 'active',
      'status_label': ask ? 'Питаємо «Все добре?»' : 'У поході',
      'detail_label': ask ? 'Час повернення настав. Без відповіді за 15 хв сповістимо Наглядача' : 'Повернення до 17:00',
      'ask_ok': ask,
      'expected_return': '2026-11-20T15:00:00Z',
      'guardians': [person(petro, 'Петро')],
      'actions': ask
          ? [
              {'id': 'ok', 'label': 'Так, все добре', 'style': 'primary'},
              {'id': 'extend', 'label': 'Продовжити на годину', 'style': 'secondary'},
              {'id': 'finish', 'label': 'Я вдома', 'style': 'secondary'},
            ]
          : [
              {'id': 'extend', 'label': 'Продовжити на годину', 'style': 'secondary'},
              {'id': 'finish', 'label': 'Я вдома', 'style': 'primary'},
            ],
    };

Map<String, dynamic> watched({bool alarm = true}) => {
      'hike_id': hikeId,
      'owner': person(olena, 'Олена_лісова'),
      'status': alarm ? 'sos' : 'active',
      'status_label': alarm ? 'SOS' : 'У поході',
      'detail_label': alarm ? 'Натиснуто SOS' : 'Повернення до 17:00',
      'alarm': alarm,
      'battery_label': 'Батарея 64 %',
      'last_signal_label': 'Останній сигнал 4 хв тому',
      'no_signal': false,
      'gps_issue_label': null,
      'last': {'lat': 50.41234, 'lng': 28.61234, 'accuracy': 12, 'at': '2026-11-20T09:55:00Z'},
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => HikeController.now = DateTime.now);

  test('Розбір: огляд Наглядача, мій похід із «Все добре?», картка з текстом для 112', () {
    final o = GuardianOverview.fromJson({
      'guardians': [person(petro, 'Петро', status: 'accepted'), person(olena, 'Олена', status: 'pending')],
      'invites': [],
      'watching': [],
      'hike': ownerHike(ask: true),
      'watched': [watched()],
      'limits': {'max_guardians_per_hike': 1, 'label': '1 Наглядач у поході · до 3 — у Pro'},
      'telegram': {'available': true, 'linked': false},
    });
    expect(o.acceptedGuardians.map((g) => g.handle), ['Петро']);
    expect(o.hike!.askOk, isTrue);
    expect(o.hike!.actions.first.id, 'ok');
    expect(o.watched.single.alarm, isTrue);
    expect(o.watched.single.last!.lat, 50.41234);
    expect(o.telegramAvailable, isTrue);

    final d = HikeDetail.fromJson({
      ...watched(),
      'route': [{'lat': 50.4, 'lng': 28.6, 'label': 'Машина'}],
      'track': [{'lat': 50.41, 'lng': 28.61, 'accuracy': 9, 'low_accuracy': false, 't': '2026-11-20T09:00:00Z'}],
      'rescue': {'coords_label': '50.41234, 28.61234', 'at_label': 'Останнє місце о 11:55', 'sms_text': 'Потрібна допомога…'},
      'server_time': '2026-11-20T10:00:00Z',
    });
    expect(d.route.single.label, 'Машина');
    expect(d.rescueCoords, '50.41234, 28.61234');
    final more = d.withMore(HikeDetail.fromJson({
      ...watched(),
      'track': [{'lat': 50.42, 'lng': 28.62, 'low_accuracy': true, 't': '2026-11-20T09:01:00Z'}],
    }));
    expect(more.track.length, 2);
  });

  group('Похід із Наглядачем', () {
    late FakeHikeDevice device;
    late List<Map<String, dynamic>> posted;
    late bool askOk;

    Widget app(Widget home) {
      // Пристрій — у зоні тесту (інакше скасування потоку GPS завершиться поза fake-часом).
      device = FakeHikeDevice();
      posted = [];
      askOk = false;
      final (api, _) = makeClient((RequestOptions r) {
        if (r.method == 'POST') {
          final body = (r.data is String ? jsonDecode(r.data as String) : r.data) as Map<String, dynamic>;
          posted.add(body);
          if (body['action'] == 'finish') return const FakeResponse(200, {'data': {'hike': null, 'done_label': 'Гарного відпочинку!'}});
          if (body['action'] == 'ok') {
            askOk = false;
            return FakeResponse(200, {'data': {'hike': ownerHike(), 'done_label': 'Добре! Спитаємо ще раз о 17:30'}});
          }
          return FakeResponse(200, {'data': {'hike': ownerHike(ask: askOk), 'accepted': 0}});
        }
        return FakeResponse(200, {
          'data': {
            'guardians': [person(petro, 'Петро', status: 'accepted')],
            'invites': [],
            'watching': [],
            'hike': null,
            'watched': [],
            'limits': {'max_guardians_per_hike': 1, 'label': '1 Наглядач у поході · до 3 — у Pro'},
            'telegram': {'available': false, 'linked': false},
          },
        });
      });
      return ProviderScope(
        overrides: [
          hikeDeviceProvider.overrideWithValue(device),
          safetyDeviceProvider.overrideWithValue(FakeDevice()),
          localStoreProvider.overrideWithValue(MemoryStore()),
          meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
          guardianRepositoryProvider.overrideWithValue(GuardianRepository(api)),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: home))),
      );
    }

    testWidgets('«Почати похід» → «Йду в ліс»: час повернення й Наглядач → сесія на сервері, трек іде Наглядачу', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      HikeController.now = () => DateTime(2026, 11, 20, 10);
      await tester.pumpWidget(app(const HikeCard()));
      await frames(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(HikeCard)));
      c.read(hikeProvider.notifier).addPoint(50.4, 28.6, label: 'Машина');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('hike-start')));
      await frames(tester);
      expect(find.byKey(const ValueKey('guardian-start-sheet')), findsOneWidget);
      expect(find.text('@Петро'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('return-1'))); // +4 год
      await tester.tap(find.byKey(const ValueKey('start-with-guardian')));
      await frames(tester);

      final start = posted.firstWhere((b) => b['action'] == 'start');
      expect(start['guardian_ids'], [petro]);
      expect(start['checklist_done'], false); // чек-лист сьогодні не пройдено
      expect((start['route'] as List).single, {'lat': 50.4, 'lng': 28.6, 'label': 'Машина'});
      expect(DateTime.parse(start['expected_return'] as String), DateTime(2026, 11, 20, 14).toUtc());
      expect(find.textContaining('Наглядач @Петро'), findsOneWidget);

      // Трек — лише нові точки, з батареєю.
      c.read(hikeProvider.notifier)
        ..debugPosition(walk(0, 0))
        ..debugPosition(walk(300, 5));
      c.read(guardianSessionProvider.notifier).sync();
      await frames(tester);
      final tracks = posted.where((b) => b['action'] == 'track').toList();
      expect((tracks.last['points'] as List).length, 2);
      expect(tracks.last['battery'], 80);
      c.read(guardianSessionProvider.notifier).sync();
      await frames(tester);
      expect((posted.where((b) => b['action'] == 'track').last['points'] as List), isEmpty);

      // Настав час повернення — «Все добре?» з кнопками із сервера.
      askOk = true;
      c.read(guardianSessionProvider.notifier).sync();
      await frames(tester);
      await tester.pump();
      expect(find.byKey(const ValueKey('hike-ask-ok')), findsOneWidget);
      expect(find.text('Все добре?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hike-guardian-ok')));
      await frames(tester);
      expect(posted.last['action'], 'ok');
      expect(find.byKey(const ValueKey('hike-ask-ok')), findsNothing);

      // «Я вдома» — і Наглядачу (трек на сервері видаляється).
      await tester.ensureVisible(find.byKey(const ValueKey('hike-finish')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hike-finish')));
      await frames(tester);
      expect(find.byKey(const ValueKey('hike-finish-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hike-finish-confirm')));
      await frames(tester);
      // Зупинка запису треку завершується поза fake-часом тесту — даємо їй мить реального часу.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await frames(tester);
      expect(posted.last, {'action': 'finish', 'hike_id': hikeId, 'used_home_nav': false});
      expect(c.read(guardianSessionProvider).active, isFalse);
    });

    testWidgets('«Без Наглядача» — похід лише на телефоні, на сервер нічого', (tester) async {
      await tester.pumpWidget(app(const HikeCard()));
      await frames(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(HikeCard)));
      c.read(hikeProvider.notifier).addPoint(50.4, 28.6);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hike-start')));
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('start-without-guardian')));
      await frames(tester);
      expect(c.read(hikeProvider).active, isTrue);
      expect(posted, isEmpty);
      expect(c.read(guardianSessionProvider).active, isFalse);
    });
  });

  testWidgets('Наглядач: тривожний похід друга згори; картка — координати для 112, дзвінок і SMS', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final detail = HikeDetail.fromJson({
      ...watched(),
      'route': [{'lat': 50.4, 'lng': 28.6, 'label': 'Машина'}],
      'track': [],
      'rescue': {'coords_label': '50.41234, 28.61234', 'at_label': 'Останнє місце о 11:55', 'sms_text': 'Потрібна допомога: грибник…'},
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
        guardianProvider.overrideWith((ref) async => GuardianOverview.fromJson({
              'guardians': [],
              'invites': [
                {...person(petro, 'Петро'), 'label': '@Петро просить вас бути Наглядачем', 'actions': [
                  {'id': 'accept_invite', 'label': 'Так, буду', 'style': 'primary'},
                  {'id': 'decline_invite', 'label': 'Ні', 'style': 'secondary'},
                ]},
              ],
              'watching': [person(olena, 'Олена_лісова')],
              'watched': [watched()],
              'limits': {'max_guardians_per_hike': 1},
              'telegram': {'available': false, 'linked': false},
            })),
        watchedHikesProvider.overrideWith((ref) => Stream.value([detail])),
      ],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GuardianCard()))),
    ));
    await frames(tester);
    expect(find.text('@Олена_лісова · SOS'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-accept_invite')), findsOneWidget);
    expect(find.textContaining('Ви Наглядач для: @Олена_лісова'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('watched-$hikeId')));
    await frames(tester);
    expect(find.byKey(const ValueKey('watched-status')), findsOneWidget);
    expect(find.text('50.41234, 28.61234'), findsOneWidget);
    expect(find.byKey(const ValueKey('watched-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('watched-sms')), findsOneWidget);
    expect(find.byKey(const ValueKey('watched-show-map')), findsOneWidget);
  });

  testWidgets('Гість: Наглядач — після входу', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [meProvider.overrideWith(() => FakeMe(Me.fromJson({...registered(), 'is_guest': true})))],
      child: const MaterialApp(home: Scaffold(body: GuardianCard())),
    ));
    await frames(tester);
    expect(find.byKey(const ValueKey('guardian-guest')), findsOneWidget);
  });
}
