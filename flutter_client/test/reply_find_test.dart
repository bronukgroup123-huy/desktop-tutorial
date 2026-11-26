// B3.8b: «Я теж знайшов тут» — відповідь знахідкою на чужу публічну точку (ADR-019 §19.5).
// Кнопку показує лише сервер; форма — той самий вид, лише публічна; на сервер іде ознака підміни місця.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/picks_repository.dart';
import 'package:flutter_client/features/picks/new_pick_screen.dart';
import 'package:flutter_client/features/picks/pick_card_sheet.dart';
import 'package:flutter_client/features/recognize/recognizer.dart' show recognizerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'data/fake_adapter.dart';
import 'profile_test.dart' show FakeMe, registered;

const pickId = '99999999-9999-4999-8999-999999999999';

Map<String, dynamic> foreignCard({List<String> actions = const [], String? confirmed, bool byMe = false, String? twin}) => {
      'id': pickId,
      'lat': 50.45,
      'lng': 30.52,
      'is_exact': false,
      'is_mine': false,
      'visibility': 'public',
      'species_id': 'boletus_edulis',
      'name_label': 'Білий гриб',
      'status_label': 'Перевіряється',
      'marker_color': '#9e9e9e',
      'description': null,
      'date_label': '10 листопада 2026 р.',
      'captured_at': null,
      'photo_url': null,
      'disclaimer_label': 'Фото користувача — не порада їсти гриб',
      'actions': actions,
      'confirmed_label': confirmed,
      'confirmed_by_me': byMe,
      'twin_warning_label': twin,
    };

/// Репозиторій, що запам'ятовує, яку точку створюють, і відповідає як сервер.
class _CapturingRepo extends PicksRepository {
  _CapturingRepo(super.api, this.reply) : super(uploads: Dio());
  final Map<String, dynamic> reply;
  NewPick? created;

  @override
  Future<CreatedPick> createPick(NewPick pick, PickPhoto photo) async {
    created = pick;
    return CreatedPick.fromJson(reply);
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Моделі: картка з підтвердженнями; відповідь сервера про зарахування', () {
    final c = PickCard.fromJson(foreignCard(confirmed: 'Підтвердили 2 грибники', byMe: true, twin: 'Двійник'));
    expect([c.confirmedLabel, c.confirmedByMe, c.twinWarningLabel], ['Підтвердили 2 грибники', true, 'Двійник']);
    final created = CreatedPick.fromJson({
      'id': 'x', 'visibility': 'public', 'status_label': 'Перевіряється', 'marker_color': '#9e9e9e',
      'confirmation': {'counted': true, 'label': 'Дякуємо! Ви підтвердили точку своєю знахідкою'},
    });
    expect([created.confirmationCounted, created.confirmationLabel], [true, 'Дякуємо! Ви підтвердили точку своєю знахідкою']);
    expect(CreatedPick.fromJson({'id': 'x', 'visibility': 'private', 'status_label': 's', 'marker_color': '#000000'}).confirmationLabel, isNull);
  });

  group('Картка чужої точки', () {
    late int cardLoads;
    late List<ReplyTarget> started;

    Widget app(Map<String, dynamic> card, {bool saved = true}) {
      cardLoads = 0;
      started = [];
      final (api, _) = makeClient((r) {
        cardLoads++;
        return FakeResponse(200, {'data': card});
      });
      return ProviderScope(
        overrides: [
          picksRepositoryProvider.overrideWithValue(PicksRepository(api, uploads: Dio())),
          meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
          replyFindStarterProvider.overrideWithValue((context, target) async {
            started.add(target);
            return saved;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => TextButton(onPressed: () => showPickCard(context, pickId), child: const Text('open'))),
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('open'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('сервер не дозволив — кнопки немає; підтвердження й двійник — підписи з сервера', (tester) async {
      await tester.pumpWidget(app(foreignCard(confirmed: 'Підтвердили 2 грибники', byMe: true, twin: 'Схожий на отруйного двійника')));
      await open(tester);
      expect(find.byKey(const ValueKey('pick-reply-found')), findsNothing);
      expect(find.text('Підтвердили 2 грибники. Серед них — ви'), findsOneWidget);
      expect(find.text('Схожий на отруйного двійника'), findsOneWidget);
    });

    testWidgets('сервер дозволив — «Я теж знайшов тут»: та сама точка й вид; після збереження картка оновлюється', (tester) async {
      await tester.pumpWidget(app(foreignCard(actions: ['reply_found'])));
      await open(tester);
      final loadsBefore = cardLoads;
      await tester.tap(find.byKey(const ValueKey('pick-reply-found')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(started.single.pickId, pickId);
      expect([started.single.species.id, started.single.species.nameLabel], ['boletus_edulis', 'Білий гриб']);
      expect(cardLoads, greaterThan(loadsBefore)); // картку перечитано: «Підтвердили N» з сервера
    });
  });

  group('Форма відповіді знахідкою', () {
    late _CapturingRepo repo;

    Future<void> pumpForm(WidgetTester tester, {bool? mocked = false, Map<String, dynamic>? reply}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('reply');
      // справжній заголовок JPEG — форма перевіряє тип фото за вмістом
      final photo = File('${dir.path}/p.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(2048, 0), 0xFF, 0xD9]);
      final (api, _) = makeClient((r) => const FakeResponse(200, {'data': {}}));
      repo = _CapturingRepo(api, reply ??
          {
            'id': 'new', 'visibility': 'public', 'status_label': 'Перевіряється', 'marker_color': '#9e9e9e',
            'confirmation': {'counted': true, 'label': 'Дякуємо! Ви підтвердили точку своєю знахідкою'},
          });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
          recognizerProvider.overrideWith((ref) async => null),
          picksRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NewPickScreen(
                    photo: XFile(photo.path),
                    point: const LatLng(50.4501, 30.5234),
                    capturedAt: DateTime(2026, 11, 26, 10),
                    locationMocked: mocked,
                    replyTo: (pickId: pickId, species: const PickSpecies(id: 'boletus_edulis', nameLabel: 'Білий гриб', latinLabel: null)),
                  ),
                )),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Підтвердити знахідкою'));
      await tester.tap(find.text('Підтвердити знахідкою'));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('вид зафіксований, вибору видимості немає, правила підтвердження видно', (tester) async {
      await pumpForm(tester);
      expect(find.text('Я теж знайшов тут'), findsOneWidget);
      expect(find.text('Білий гриб'), findsOneWidget);
      expect(find.byType(SegmentedButton<PickVisibility>), findsNothing);
      expect(find.byKey(const ValueKey('pick-reply-rules')), findsOneWidget);
      await tester.tap(find.text('Білий гриб'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BottomSheet), findsNothing); // вид не змінити
    });

    testWidgets('збереження: публічна, reply_to, той самий вид, ознака місця — і текст сервера про зарахування', (tester) async {
      await pumpForm(tester);
      await save(tester);
      final p = repo.created!;
      expect([p.replyTo, p.visibility, p.speciesId, p.locationMocked], [pickId, PickVisibility.public, 'boletus_edulis', false]);
      expect(find.text('Дякуємо! Ви підтвердили точку своєю знахідкою'), findsOneWidget);
    });

    testWidgets('місце підмінене — передаємо як є; сервер пояснює, чому не зараховано', (tester) async {
      await pumpForm(tester, mocked: true, reply: {
        'id': 'new', 'visibility': 'public', 'status_label': 'Перевіряється', 'marker_color': '#9e9e9e',
        'confirmation': {'counted': false, 'label': 'Телефон повідомив, що місце підмінене програмою — знахідку збережено, але точку не підтверджено'},
      });
      await save(tester);
      expect(repo.created!.locationMocked, isTrue);
      expect(find.text('Телефон повідомив, що місце підмінене програмою — знахідку збережено, але точку не підтверджено'), findsOneWidget);
    });
  });
}
