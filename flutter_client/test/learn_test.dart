// B3.10c: «Навчання» — модулі з сервера, вибір «на бали / тренування», три типи питань, розбір, скарга (ADR-023).
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client/data/models/quiz.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/quiz_repository.dart';
import 'package:flutter_client/features/learn/learn_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'safety_test.dart' show frames;

Map<String, dynamic> mod(String id, int pos, String status, {String? next, int? best}) => {
      'id': id, 'position': pos, 'title': 'Модуль $id', 'summary': 'Про $id', 'points': 10, 'status': status,
      'best_percent': best, 'next_scored_at': next, 'questions_per_attempt': 3, 'pass_percent': 80,
    };

Map<String, dynamic> overview({String appStatus = 'open', String? next, String? guest}) => {
      'modules': [mod('app', 1, appStatus, next: next, best: appStatus == 'passed' ? 90 : null), mod('forest', 2, 'locked'), mod('weather', 3, 'soon')],
      'passed_count': appStatus == 'passed' ? 1 : 0,
      'total': 7,
      'certified_at': null,
      'disclaimer_label': 'Тест навчає, але не дає дозволу їсти знайдені гриби',
      'guest_label': guest,
    };

const attempt = {
  'attempt_id': '11111111-2222-4333-8444-555555555555',
  'practice': false,
  'questions': [
    {'id': 'app_q1', 'kind': 'single', 'prompt': 'Одна відповідь?', 'options': [{'id': 'a', 'text': 'Так'}, {'id': 'b', 'text': 'Ні'}]},
    {'id': 'app_q2', 'kind': 'multi', 'prompt': 'Усі правильні?', 'options': [{'id': 'a', 'text': 'Перше'}, {'id': 'b', 'text': 'Друге'}, {'id': 'c', 'text': 'Третє'}]},
    {'id': 'app_q3', 'kind': 'order', 'prompt': 'Порядок?', 'options': [{'id': 'x', 'text': 'Крок X'}, {'id': 'y', 'text': 'Крок Y'}]},
  ],
};

final result = {
  'correct': 2, 'total': 3, 'percent': 66, 'pass_percent': 80, 'passed': false, 'critical_failed': false,
  'points_awarded': 0, 'certified_now': false, 'practice': false,
  'result_label': 'Не зараховано: 2 з 3 (66 %), потрібно 80 %. Наступна спроба на бали — через добу',
  'review': [
    {'id': 'app_q1', 'kind': 'single', 'prompt': 'Одна відповідь?', 'options': [{'id': 'a', 'text': 'Так'}, {'id': 'b', 'text': 'Ні'}],
     'chosen': ['a'], 'correct': ['b'], 'is_correct': false, 'critical': false, 'explanation': 'Бо ні.', 'source': 'ADR-014'},
  ],
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late List<RequestOptions> sent;

  Widget app(Map<String, dynamic> ov) {
    final (api, adapter) = makeClient((r) {
      if (r.method == 'GET') return FakeResponse(200, {'data': ov});
      if (r.path.endsWith('/attempts')) {
        final b = (r.data is String ? jsonDecode(r.data as String) : r.data) as Map<String, dynamic>;
        return FakeResponse(200, {'data': {...attempt, 'practice': b['practice'] == true}});
      }
      if (r.path.endsWith('/submit')) return FakeResponse(200, {'data': result});
      return const FakeResponse(200, {'data': {'reported': true}});
    });
    sent = adapter.requests;
    return ProviderScope(
      overrides: [quizRepositoryProvider.overrideWithValue(QuizRepository(api))],
      child: const MaterialApp(home: LearnScreen()),
    );
  }

  Map<String, dynamic> bodyOf(RequestOptions r) => (r.data is String ? jsonDecode(r.data as String) : r.data) as Map<String, dynamic>;

  Future<void> big(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  test('Моделі: статуси, невідомий статус — «готується»', () {
    final o = QuizOverview.fromJson(overview());
    expect(o.modules.map((m) => m.status), [QuizModuleStatus.open, QuizModuleStatus.locked, QuizModuleStatus.soon]);
    expect(QuizModuleStatus.parse('щось'), QuizModuleStatus.soon);
    final a = QuizAttempt.fromJson(attempt);
    expect(a.questions.map((q) => q.kind), [QuizKind.single, QuizKind.multi, QuizKind.order]);
    final r = QuizResult.fromJson(result);
    expect([r.passed, r.review.single.textOf('b')], [false, 'Ні']);
  });

  testWidgets('Модулі: прогрес, відкритий / закритий / готується; закритий не відкривається', (tester) async {
    await big(tester);
    await tester.pumpWidget(app(overview()));
    await frames(tester);
    expect(find.text('Пройдено 0 з 7'), findsOneWidget);
    expect(find.text('Спершу пройдіть попередній модуль'), findsOneWidget);
    expect(find.text('Готується'), findsOneWidget);
    expect(find.text('Тест навчає, але не дає дозволу їсти знайдені гриби'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('learn-module-forest')));
    await frames(tester);
    expect(find.byKey(const ValueKey('learn-start-practice')), findsNothing);
  });

  testWidgets('На бали: три типи питань → здача з відповідями → підсумок сервера, розбір, скарга', (tester) async {
    await big(tester);
    await tester.pumpWidget(app(overview()));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('learn-module-app')));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('learn-start-scored')));
    await frames(tester);
    expect(bodyOf(sent.firstWhere((r) => r.path.endsWith('/attempts'))), {'module_id': 'app', 'practice': false});

    // 1: одна відповідь — «Далі» неактивна, доки нічого не вибрано
    expect(find.text('Одна відповідь?'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('quiz-next'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('quiz-option-app_q1-a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quiz-next')));
    await tester.pump();
    // 2: усі правильні — дві відповіді
    await tester.tap(find.byKey(const ValueKey('quiz-option-app_q2-a')));
    await tester.tap(find.byKey(const ValueKey('quiz-option-app_q2-c')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quiz-next')));
    await tester.pump();
    // 3: порядок — як показано; «Здати»
    expect(find.text('Перетягніть у правильному порядку'), findsOneWidget);
    expect(find.text('Здати'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quiz-next')));
    await frames(tester);

    final submit = sent.firstWhere((r) => r.path.endsWith('/submit'));
    expect(submit.path, '/v1-quiz/attempts/11111111-2222-4333-8444-555555555555/submit');
    expect(bodyOf(submit), {'answers': {'app_q1': ['a'], 'app_q2': ['a', 'c'], 'app_q3': ['x', 'y']}});
    expect(find.byKey(const ValueKey('quiz-result-label')), findsOneWidget);
    expect(find.textContaining('Не зараховано: 2 з 3'), findsOneWidget);
    expect(find.text('Ваша відповідь: Так'), findsOneWidget);
    expect(find.text('Правильно: Ні'), findsOneWidget);
    expect(find.text('Бо ні.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quiz-report-app_q1')));
    await frames(tester);
    await tester.enterText(find.byKey(const ValueKey('quiz-report-comment')), 'Неточне формулювання');
    await tester.tap(find.byKey(const ValueKey('quiz-report-send')));
    await frames(tester);
    final rep = sent.firstWhere((r) => r.path.endsWith('/report'));
    expect([rep.path, bodyOf(rep)], ['/v1-quiz/questions/app_q1/report', {'comment': 'Неточне формулювання'}]);
    expect(find.text('Дякуємо! Перевіримо це питання'), findsOneWidget);
  });

  testWidgets('Пауза після невдалої спроби — лише тренування з поясненням; гість — лише тренування', (tester) async {
    await big(tester);
    final later = DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String();
    await tester.pumpWidget(app(overview(next: later)));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('learn-module-app')));
    await frames(tester);
    expect(find.byKey(const ValueKey('learn-start-scored')), findsNothing);
    expect(find.byKey(const ValueKey('learn-wait')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('learn-start-practice')));
    await frames(tester);
    expect(bodyOf(sent.firstWhere((r) => r.path.endsWith('/attempts'))), {'module_id': 'app', 'practice': true});
    expect(find.text('Тренування'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(overview(guest: 'Бали за тести — після входу')));
    await frames(tester);
    expect(find.byKey(const ValueKey('learn-guest')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('learn-module-app')));
    await frames(tester);
    expect(find.byKey(const ValueKey('learn-start-scored')), findsNothing);
    expect(find.byKey(const ValueKey('learn-start-practice')), findsOneWidget);
  });
}
