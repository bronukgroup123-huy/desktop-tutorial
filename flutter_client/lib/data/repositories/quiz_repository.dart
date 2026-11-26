import '../api/api_client.dart';
import '../models/quiz.dart';

/// Тести знань (`/v1-quiz`, ADR-023). Перевірка, бали й сертифікат — лише на сервері.
class QuizRepository {
  QuizRepository(this._api);

  final ApiClient _api;

  Future<QuizOverview> overview() async => QuizOverview.fromJson(await _api.get('/v1-quiz') as Map<String, dynamic>);

  /// Почати спробу: [practice] — тренування без балів (гостю — лише так).
  Future<QuizAttempt> start(String moduleId, {bool practice = false}) async => QuizAttempt.fromJson(
        await _api.post('/v1-quiz/attempts', body: {'module_id': moduleId, 'practice': practice}) as Map<String, dynamic>,
      );

  /// Здати: { питання: [варіанти] } (для «порядку» — у вибраному порядку).
  Future<QuizResult> submit(String attemptId, Map<String, List<String>> answers) async => QuizResult.fromJson(
        await _api.post('/v1-quiz/attempts/$attemptId/submit', body: {'answers': answers}) as Map<String, dynamic>,
      );

  /// «Помилка в питанні».
  Future<void> report(String questionId, {String? comment}) async {
    await _api.post('/v1-quiz/questions/$questionId/report', body: {'comment': comment});
  }
}
