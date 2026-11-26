import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/trip_feedback.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/analysis_repository.dart';
import 'package:flutter_client/features/feedback/trip_feedback_sheet.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'safety_test.dart' show frames;

/// B3.11 «Знайшли?» після «Я вдома» (ADR-014): питаємо лише коли сервер каже `ask`, відповідь — одним дотиком.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const trip = (lat: 50.45, lng: 30.52, day: '2026-11-26');
  final prompt = {
    'ask': true,
    'title': 'Знайшли гриби?',
    'subtitle': 'Біля ділянки «Біля Броників»',
    'explain_label': 'Чим чесніша відповідь, тим точніший прогноз — передусім для вас.',
    'answers': [
      {'id': 'found', 'label': 'Так, знайшли'},
      {'id': 'not_found', 'label': 'Ні, не знайшли'},
    ],
    'skip_label': 'Не зараз',
    'points_label': '+2 бали за чесну відповідь — раз на добу',
    'accuracy_label': 'Прогноз для вас збувся 3 з 4 разів',
  };

  late List<String> requests;
  late List<Object?> bodies;

  Widget app(FakeResponse Function(String method) respond) {
    requests = [];
    bodies = [];
    final (api, _) = makeClient((r) {
      requests.add('${r.method} ${r.path}');
      bodies.add(r.data);
      return respond(r.method);
    });
    final repo = AnalysisRepository(api);
    return ProviderScope(
      overrides: [analysisRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('ask'),
                onPressed: () => askTripFeedback(Navigator.of(ctx), repo, trip),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  test('Похід → середина треку й день старту; без треку — не питаємо', () {
    final t = DateTime(2026, 11, 26, 8);
    final hike = HikeState(startedAt: t, track: [
      (lat: 50.40, lng: 30.50, t: t, acc: 5.0),
      (lat: 50.42, lng: 30.54, t: t, acc: 5.0),
    ]);
    expect(tripSummary(hike), (lat: 50.41, lng: 30.52, day: '2026-11-26'));
    expect(tripSummary(const HikeState()), isNull);
  });

  testWidgets('Сервер каже «питати»: пояснення, «Так» → відповідь, бали й «прогноз для вас збувся»', (tester) async {
    await tester.pumpWidget(app((m) => m == 'GET'
        ? FakeResponse(200, {'data': prompt})
        : const FakeResponse(200, {
            'data': {
              'message_label': 'Дякуємо! Записали: знайшли',
              'points': 'pending',
              'points_label': '+2 бали — через добу, після перевірки',
              'accuracy_label': 'Прогноз для вас збувся 4 з 5 разів',
            },
          })));
    await tester.tap(find.byKey(const ValueKey('ask')));
    await frames(tester);
    expect(find.byKey(const ValueKey('trip-feedback-sheet')), findsOneWidget);
    expect(find.text('Знайшли гриби?'), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-explain')), findsOneWidget);
    expect(find.text('Прогноз для вас збувся 3 з 4 разів'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feedback-found')));
    await frames(tester);
    expect(requests, ['GET /v1-analysis/feedback', 'POST /v1-analysis/feedback']);
    final body = bodies.last is String ? jsonDecode(bodies.last as String) : bodies.last;
    expect(body, {'lat': 50.45, 'lng': 30.52, 'day': '2026-11-26', 'answer': 'found'});
    expect(find.text('Дякуємо! Записали: знайшли'), findsOneWidget);
    expect(find.text('+2 бали — через добу, після перевірки'), findsOneWidget);
    expect(find.text('Прогноз для вас збувся 4 з 5 разів'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feedback-done')));
    await frames(tester);
    expect(find.byKey(const ValueKey('trip-feedback-sheet')), findsNothing);
  });

  testWidgets('Сервер каже «не питати» або немає мережі — аркуша немає, нічого не ламається', (tester) async {
    await tester.pumpWidget(app((_) => const FakeResponse(200, {'data': {'ask': false, 'accuracy_label': null}})));
    await tester.tap(find.byKey(const ValueKey('ask')));
    await frames(tester);
    expect(find.byKey(const ValueKey('trip-feedback-sheet')), findsNothing);

    await tester.pumpWidget(app((_) => const FakeResponse.offline()));
    await tester.tap(find.byKey(const ValueKey('ask')));
    await frames(tester);
    expect(find.byKey(const ValueKey('trip-feedback-sheet')), findsNothing);
  });

  testWidgets('Відмова сервера — його текст в аркуші; «Не зараз» закриває без відповіді', (tester) async {
    await tester.pumpWidget(app((m) => m == 'GET'
        ? FakeResponse(200, {'data': prompt})
        : const FakeResponse(409, {'error': 'already_answered', 'message': 'Ви вже відповіли про цей похід. Дякуємо!'})));
    await tester.tap(find.byKey(const ValueKey('ask')));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('feedback-not_found')));
    await frames(tester);
    expect(find.text('Ви вже відповіли про цей похід. Дякуємо!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feedback-skip')));
    await frames(tester);
    expect(find.byKey(const ValueKey('trip-feedback-sheet')), findsNothing);
  });

  test('Моделі: порожні поля — безпечні значення', () {
    final p = TripFeedbackPrompt.fromJson(const {'ask': true});
    expect([p.ask, p.answers, p.skipLabel], [true, isEmpty, 'Не зараз']);
    expect(TripFeedbackResult.fromJson(const {}).points, 'none');
  });
}
