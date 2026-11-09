/// Результат із офлайн-кешем.
class OfflineResult<T> {
  const OfflineResult({required this.value, required this.savedAt, required this.offline});

  final T value;

  /// Коли дані отримано із сервера.
  final DateTime savedAt;

  /// `true` — сервер недоступний, показано збережену копію.
  final bool offline;
}
