/// Невеликі хелпери для безпечного розбору JSON із сервера.
/// Помилка формату → [FormatException] з назвою поля (легко діагностувати).
library;

T req<T>(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is T) return v;
  throw FormatException('Field "$key": expected $T, got ${v.runtimeType}');
}

T? opt<T>(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is T) return v;
  throw FormatException('Field "$key": expected $T?, got ${v.runtimeType}');
}

double toDouble(Object? v, String field) {
  if (v is num) return v.toDouble();
  throw FormatException('Field "$field": expected number, got ${v.runtimeType}');
}

List<String> stringList(Map<String, dynamic> json, String key) =>
    (opt<List<dynamic>>(json, key) ?? const []).map((e) => e.toString()).toList();
