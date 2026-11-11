import 'dart:math';

/// UUID v4 (випадковий). Використовується як `client_id` тук-тука — ключ
/// ідемпотентності: повтор запиту з тим самим id не створює дубль (ADR-002).
String uuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // версія 4
  b[8] = (b[8] & 0x3f) | 0x80; // варіант RFC 4122
  String hex(int from, int to) =>
      b.sublist(from, to).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
