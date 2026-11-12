/// Помилка API у єдиному форматі бекенду: `{ "error": "code", "message"?: "текст UA" }`.
///
/// Клієнт не вигадує тексти для бізнес-помилок — показує `message` із сервера
/// (Thin Client). Власні тексти — лише для мережевих збоїв, коли сервер не відповів.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    this.statusCode,
    this.serverMessage,
    this.retryAfter,
  });

  /// Машинний код (`outside_home_region`, `registration_required`, …) або `network_error`.
  final String code;

  /// HTTP-статус; `null`, якщо відповіді не було (немає мережі, тайм-аут).
  final int? statusCode;

  /// Людський текст із сервера (може бути відсутнім).
  final String? serverMessage;

  /// Для `429 rate_limited` — через скільки секунд можна повторити.
  final int? retryAfter;

  static const String networkError = 'network_error';
  static const String invalidPhoto = 'invalid_photo';
  static const String invalidResponse = 'invalid_response';
  static const String uploadFailed = 'upload_failed';

  bool get isUnauthorized => statusCode == 401;
  bool get isNetworkError => code == networkError;
  bool get isRegistrationRequired => code == 'registration_required';
  bool get isRateLimited => statusCode == 429;

  /// Текст для Toast/SnackBar.
  String get userMessage {
    if (serverMessage != null && serverMessage!.isNotEmpty) return serverMessage!;
    switch (code) {
      case networkError:
        return 'Немає зв\'язку з сервером. Перевірте інтернет і спробуйте ще раз.';
      case invalidResponse:
        return 'Сервер повернув неочікувану відповідь. Спробуйте пізніше.';
      case uploadFailed:
        return 'Не вдалося завантажити фото. Спробуйте ще раз.';
      case invalidPhoto:
        return 'Фото не підходить: потрібне JPEG, PNG або WebP до 5 МБ. Перезніміть, будь ласка.';
      default:
        return 'Щось пішло не так. Спробуйте ще раз.';
    }
  }

  @override
  String toString() => 'ApiException($statusCode $code${serverMessage != null ? ': $serverMessage' : ''})';
}
