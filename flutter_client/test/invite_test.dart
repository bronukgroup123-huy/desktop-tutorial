// B9.5b: запрошення в застосунок (ADR-021 §21.4).
// Код із Play Install Referrer — один раз після входу, без інтернету — повторити пізніше;
// екран «Запросити друга»: код, QR, «Поділитися», бонуси — з сервера.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/friends_repository.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_client/features/friends/invite_screen.dart';
import 'package:flutter_client/features/friends/referral.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'data/fake_adapter.dart';
import 'profile_test.dart' show FakeMe, registered;

const shareUrl = 'https://play.google.com/store/apps/details?id=ua.mushroomradar.app&referrer=ref%3DABCD2345';

Map<String, dynamic> inviteJson({int left = 5}) => {
      'code': 'ABCD2345',
      'share_url': shareUrl,
      'share_text': 'Шукаю гриби з «Грибним Радаром». Встанови за цим посиланням — і ми одразу станемо друзями: $shareUrl',
      'invited': 2,
      'rewarded': 1,
      'bonuses_left': left,
      'label': '+10 балів вам обом, коли друг пройде перший похід. Лишилось бонусів: $left з 5',
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Код із рядка Install Referrer: ref=…, закодований, серед інших параметрів; без коду — нічого', () {
    expect(referralCodeFromReferrer('ref=ABCD2345'), 'ABCD2345');
    expect(referralCodeFromReferrer('ref%3Dabcd2345'), 'ABCD2345');
    expect(referralCodeFromReferrer('utm_source=share&ref=QWER7890'), 'QWER7890');
    expect(referralCodeFromReferrer(' ref = ZXCV5678 '), 'ZXCV5678');
    expect(referralCodeFromReferrer('utm_source=google-play&utm_medium=organic'), isNull, reason: 'звичайне встановлення');
    expect(referralCodeFromReferrer('ref=AB'), isNull);
    expect(referralCodeFromReferrer('ref=ABC<script>'), isNull);
    expect(referralCodeFromReferrer('ref=%E0%A4%A'), isNull, reason: 'зламане кодування — не падаємо');
    expect(referralCodeFromReferrer(''), isNull);
    expect(referralCodeFromReferrer(null), isNull);
  });

  test('Модель «Мій код запрошення»', () {
    final i = MyInvite.fromJson(inviteJson(left: 3));
    expect([i.code, i.shareUrl, i.invited, i.rewarded, i.bonusesLeft], ['ABCD2345', shareUrl, 2, 1, 3]);
    expect(i.label, contains('3 з 5'));
    expect(i.shareText, endsWith(shareUrl));
  });

  group('Активувати код після встановлення', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mr_referral_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<({String? label, List<Map<String, dynamic>> sent, LocalStore store})> run(
      WidgetTester tester, {
      required String? referrer,
      FakeResponse Function()? respond,
      LocalStore? store,
    }) async {
      final sent = <Map<String, dynamic>>[];
      final (api, _) = makeClient((RequestOptions r) {
        if (r.method == 'PATCH' && r.path.endsWith('/v1-me')) {
          sent.add(jsonDecode(jsonEncode(r.data)) as Map<String, dynamic>);
          return respond?.call() ??
              FakeResponse(200, {
                'data': {
                  ...registered(),
                  'referral': {'applied': true, 'label': 'Запрошення від @Олена прийнято: ви друзі'},
                },
              });
        }
        return const FakeResponse(404, {'error': {'code': 'not_found', 'message': 'ні'}});
      });
      final s = store ?? LocalStore(dir);
      late WidgetRef captured;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(s),
          meRepositoryProvider.overrideWithValue(MeRepository(api)),
          meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
          installReferrerProvider.overrideWithValue(() async => referrer),
        ],
        child: MaterialApp(home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        })),
      ));
      final label = await tester.runAsync(() => redeemInstallReferral(captured));
      return (label: label, sent: sent, store: s);
    }

    testWidgets('за посиланням: код іде на сервер один раз, підказка — з сервера', (tester) async {
      final first = await run(tester, referrer: 'ref=abcd2345');
      expect(first.sent, [{'referral_code': 'ABCD2345'}]);
      expect(first.label, 'Запрошення від @Олена прийнято: ви друзі');
      final again = await run(tester, referrer: 'ref=abcd2345', store: first.store);
      expect(again.sent, isEmpty, reason: 'вже перевірено — більше не надсилаємо');
      expect(again.label, isNull);
    });

    testWidgets('звичайне встановлення: нічого не надсилаємо і більше не перевіряємо', (tester) async {
      final r = await run(tester, referrer: 'utm_source=google-play&utm_medium=organic');
      expect([r.sent, r.label], [isEmpty, isNull]);
      expect(await tester.runAsync(() => r.store.read(referralCheckedKey)), isNotNull);
    });

    testWidgets('без інтернету: не позначаємо — спробуємо при наступному запуску', (tester) async {
      final r = await run(tester, referrer: 'ref=ABCD2345', respond: () => const FakeResponse.offline());
      expect(r.label, isNull);
      expect(await tester.runAsync(() => r.store.read(referralCheckedKey)), isNull);
      final retry = await run(tester, referrer: 'ref=ABCD2345', store: r.store);
      expect(retry.sent, [{'referral_code': 'ABCD2345'}]);
    });

    testWidgets('код не підійшов: показуємо підказку сервера, але більше не надсилаємо', (tester) async {
      final r = await run(tester, referrer: 'ref=ZZZZZZZZ', respond: () => FakeResponse(200, {
            'data': {...registered(), 'referral': {'applied': false, 'label': 'Код запрошення не знайдено'}},
          }));
      expect(r.label, 'Код запрошення не знайдено');
      final again = await run(tester, referrer: 'ref=ZZZZZZZZ', store: r.store);
      expect(again.sent, isEmpty);
    });
  });

  testWidgets('Екран «Запросити друга»: код, QR із посиланням у Google Play, бонуси, копіювання', (tester) async {
    final (api, adapter) = makeClient((RequestOptions r) => r.path.endsWith('/v1-friends/invite')
        ? FakeResponse(200, {'data': inviteJson()})
        : const FakeResponse(404, {'error': {'code': 'not_found', 'message': 'ні'}}));
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        friendsRepositoryProvider.overrideWithValue(FriendsRepository(api)),
        meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
      ],
      child: const MaterialApp(home: InviteScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(adapter.requests.map((r) => r.path), everyElement(endsWith('/v1-friends/invite')));
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(tester.widget<QrImageView>(find.byKey(const ValueKey('invite-qr'))), isNotNull);
    expect(find.textContaining('Лишилось бонусів: 5 з 5'), findsOneWidget);
    expect(find.text('Запрошено: 2 · бонусів отримано: 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-share')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('invite-copy')));
    await tester.tap(find.byKey(const ValueKey('invite-copy')));
    await tester.pump();
    expect(copied, [shareUrl]);
    expect(find.text('Посилання скопійовано'), findsOneWidget);
  });

  testWidgets('Екран «Запросити друга»: помилка сервера — текст і «Повторити»', (tester) async {
    final (api, _) = makeClient((_) => const FakeResponse(503, {'error': {'code': 'code_unavailable', 'message': 'Спробуйте пізніше'}}));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        friendsRepositoryProvider.overrideWithValue(FriendsRepository(api)),
        meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
      ],
      child: const MaterialApp(home: InviteScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('invite-error')), findsOneWidget);
    expect(find.text('Повторити'), findsOneWidget);
  });
}
