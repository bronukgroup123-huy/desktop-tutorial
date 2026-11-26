import 'json.dart';

/// Тести знань (`/v1-quiz`, ADR-023). Усі тексти й рішення — із сервера; клієнт лише показує.
enum QuizModuleStatus {
  /// Модуль ще готується.
  soon,

  /// Спершу пройдіть попередній.
  locked,
  open,
  passed;

  static QuizModuleStatus parse(String? s) =>
      QuizModuleStatus.values.firstWhere((v) => v.name == s, orElse: () => QuizModuleStatus.soon);
}

class QuizModule {
  const QuizModule({
    required this.id,
    required this.position,
    required this.title,
    required this.summary,
    required this.points,
    required this.status,
    this.bestPercent,
    this.nextScoredAt,
    this.questionsPerAttempt = 10,
    this.passPercent = 80,
  });

  factory QuizModule.fromJson(Map<String, dynamic> j) => QuizModule(
        id: req<String>(j, 'id'),
        position: (j['position'] as num?)?.toInt() ?? 0,
        title: req<String>(j, 'title'),
        summary: opt<String>(j, 'summary') ?? '',
        points: (j['points'] as num?)?.toInt() ?? 0,
        status: QuizModuleStatus.parse(opt<String>(j, 'status')),
        bestPercent: (j['best_percent'] as num?)?.toInt(),
        nextScoredAt: DateTime.tryParse(opt<String>(j, 'next_scored_at') ?? '')?.toLocal(),
        questionsPerAttempt: (j['questions_per_attempt'] as num?)?.toInt() ?? 10,
        passPercent: (j['pass_percent'] as num?)?.toInt() ?? 80,
      );

  final String id;
  final int position;
  final String title;
  final String summary;
  final int points;
  final QuizModuleStatus status;
  final int? bestPercent;

  /// Наступна спроба на бали — не раніше (після невдалої); `null` — можна зараз.
  final DateTime? nextScoredAt;
  final int questionsPerAttempt;
  final int passPercent;
}

class QuizOverview {
  const QuizOverview({
    required this.modules,
    required this.passedCount,
    required this.total,
    this.certifiedAt,
    this.disclaimerLabel,
    this.guestLabel,
  });

  factory QuizOverview.fromJson(Map<String, dynamic> j) => QuizOverview(
        modules: [for (final m in (j['modules'] as List? ?? const []).whereType<Map<String, dynamic>>()) QuizModule.fromJson(m)],
        passedCount: (j['passed_count'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        certifiedAt: DateTime.tryParse(opt<String>(j, 'certified_at') ?? '')?.toLocal(),
        disclaimerLabel: opt<String>(j, 'disclaimer_label'),
        guestLabel: opt<String>(j, 'guest_label'),
      );

  final List<QuizModule> modules;
  final int passedCount;
  final int total;
  final DateTime? certifiedAt;
  final String? disclaimerLabel;

  /// Гостю — пояснення, що бали й сертифікат після входу.
  final String? guestLabel;
}

/// Тип питання: одна відповідь / усі правильні / порядок.
enum QuizKind {
  single,
  multi,
  order;

  static QuizKind parse(String? s) => QuizKind.values.firstWhere((v) => v.name == s, orElse: () => QuizKind.single);
}

typedef QuizOption = ({String id, String text});

List<QuizOption> _options(dynamic raw) => [
      for (final o in (raw as List? ?? const []).whereType<Map<String, dynamic>>())
        (id: o['id'] as String? ?? '', text: o['text'] as String? ?? ''),
    ];

class QuizQuestion {
  const QuizQuestion({required this.id, required this.kind, required this.prompt, required this.options});

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        id: req<String>(j, 'id'),
        kind: QuizKind.parse(opt<String>(j, 'kind')),
        prompt: req<String>(j, 'prompt'),
        options: _options(j['options']),
      );

  final String id;
  final QuizKind kind;
  final String prompt;
  final List<QuizOption> options;
}

/// Спроба: питання без правильних відповідей.
class QuizAttempt {
  const QuizAttempt({required this.id, required this.practice, required this.questions});

  factory QuizAttempt.fromJson(Map<String, dynamic> j) => QuizAttempt(
        id: req<String>(j, 'attempt_id'),
        practice: j['practice'] == true,
        questions: [for (final q in (j['questions'] as List? ?? const []).whereType<Map<String, dynamic>>()) QuizQuestion.fromJson(q)],
      );

  final String id;
  final bool practice;
  final List<QuizQuestion> questions;
}

/// Розбір одного питання після спроби.
class QuizReviewItem {
  const QuizReviewItem({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.options,
    required this.chosen,
    required this.correct,
    required this.isCorrect,
    required this.critical,
    required this.explanation,
    required this.source,
  });

  factory QuizReviewItem.fromJson(Map<String, dynamic> j) => QuizReviewItem(
        id: req<String>(j, 'id'),
        kind: QuizKind.parse(opt<String>(j, 'kind')),
        prompt: opt<String>(j, 'prompt') ?? '',
        options: _options(j['options']),
        chosen: [for (final c in (j['chosen'] as List? ?? const [])) '$c'],
        correct: [for (final c in (j['correct'] as List? ?? const [])) '$c'],
        isCorrect: j['is_correct'] == true,
        critical: j['critical'] == true,
        explanation: opt<String>(j, 'explanation') ?? '',
        source: opt<String>(j, 'source') ?? '',
      );

  final String id;
  final QuizKind kind;
  final String prompt;
  final List<QuizOption> options;
  final List<String> chosen;
  final List<String> correct;
  final bool isCorrect;
  final bool critical;
  final String explanation;
  final String source;

  String textOf(String optionId) => options.firstWhere((o) => o.id == optionId, orElse: () => (id: optionId, text: optionId)).text;
}

class QuizResult {
  const QuizResult({
    required this.correct,
    required this.total,
    required this.percent,
    required this.passed,
    required this.criticalFailed,
    required this.pointsAwarded,
    required this.certifiedNow,
    required this.resultLabel,
    required this.review,
    required this.practice,
  });

  factory QuizResult.fromJson(Map<String, dynamic> j) => QuizResult(
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        percent: (j['percent'] as num?)?.toInt() ?? 0,
        passed: j['passed'] == true,
        criticalFailed: j['critical_failed'] == true,
        pointsAwarded: (j['points_awarded'] as num?)?.toInt() ?? 0,
        certifiedNow: j['certified_now'] == true,
        resultLabel: opt<String>(j, 'result_label') ?? '',
        review: [for (final r in (j['review'] as List? ?? const []).whereType<Map<String, dynamic>>()) QuizReviewItem.fromJson(r)],
        practice: j['practice'] == true,
      );

  final int correct;
  final int total;
  final int percent;
  final bool passed;
  final bool criticalFailed;
  final int pointsAwarded;
  final bool certifiedNow;
  final String resultLabel;
  final List<QuizReviewItem> review;
  final bool practice;
}
