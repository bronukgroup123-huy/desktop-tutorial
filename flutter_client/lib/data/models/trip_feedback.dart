/// «Знайшли?» після походу (`/v1-analysis/feedback`, B3.11, ADR-014). Усі тексти — з сервера.
class TripFeedbackPrompt {
  const TripFeedbackPrompt({
    required this.ask,
    this.title = '',
    this.subtitle = '',
    this.explainLabel = '',
    this.answers = const [],
    this.skipLabel = 'Не зараз',
    this.pointsLabel,
    this.accuracyLabel,
  });

  /// Чи питати: сервер знайшов зв'язок походу з прогнозом ділянки чи Наглядачем і ще не питав.
  final bool ask;
  final String title;
  final String subtitle;

  /// Навіщо чесна відповідь (ADR-014 §14.1).
  final String explainLabel;
  final List<({String id, String label})> answers;
  final String skipLabel;
  final String? pointsLabel;

  /// «Прогноз для вас збувся N з M разів».
  final String? accuracyLabel;

  factory TripFeedbackPrompt.fromJson(Map<String, dynamic> j) => TripFeedbackPrompt(
        ask: j['ask'] == true,
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        explainLabel: j['explain_label'] as String? ?? '',
        answers: [
          for (final a in (j['answers'] as List? ?? const []).whereType<Map<String, dynamic>>())
            (id: a['id'] as String? ?? '', label: a['label'] as String? ?? ''),
        ],
        skipLabel: j['skip_label'] as String? ?? 'Не зараз',
        pointsLabel: j['points_label'] as String?,
        accuracyLabel: j['accuracy_label'] as String?,
      );
}

/// Відповідь прийнято: подяка, що з балами, точність прогнозу для людини.
class TripFeedbackResult {
  const TripFeedbackResult({required this.messageLabel, required this.points, this.pointsLabel, this.accuracyLabel});

  final String messageLabel;

  /// `pending` — бали нарахують через добу; `none` — без балів (причина в [pointsLabel]).
  final String points;
  final String? pointsLabel;
  final String? accuracyLabel;

  factory TripFeedbackResult.fromJson(Map<String, dynamic> j) => TripFeedbackResult(
        messageLabel: j['message_label'] as String? ?? 'Дякуємо!',
        points: j['points'] as String? ?? 'none',
        pointsLabel: j['points_label'] as String?,
        accuracyLabel: j['accuracy_label'] as String?,
      );
}

/// Похід для відгуку: середина треку й день (місце сервер лише перевіряє, не зберігає).
typedef TripSummary = ({double lat, double lng, String day});
