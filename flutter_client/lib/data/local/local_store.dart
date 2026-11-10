import 'dart:convert';
import 'dart:io';

/// Запис у локальному сховищі: дані + коли збережено + ETag сервера.
class StoredEntry {
  const StoredEntry({required this.data, required this.savedAt, this.etag});

  final Object? data;
  final DateTime savedAt;
  final String? etag;
}

/// Просте файлове сховище JSON на телефоні (офлайн-режим).
///
/// Один ключ — один файл `<dir>/<key>.json`. Використовується для лісів і кордону
/// області (завантажуються один раз) та останніх прогнозів.
class LocalStore {
  LocalStore(this.dir);

  final Directory dir;

  static final _safeKey = RegExp(r'^[a-z0-9_.:-]+$');

  File _file(String key) {
    if (!_safeKey.hasMatch(key)) throw ArgumentError.value(key, 'key');
    return File('${dir.path}/$key.json');
  }

  Future<StoredEntry?> read(String key) async {
    final f = _file(key);
    if (!await f.exists()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return StoredEntry(
        data: json['data'],
        savedAt: DateTime.parse(json['saved_at'] as String),
        etag: json['etag'] as String?,
      );
    } catch (_) {
      await f.delete(); // пошкоджений файл — просто перезавантажимо
      return null;
    }
  }

  Future<void> write(String key, Object? data, {String? etag, DateTime? savedAt}) async {
    await dir.create(recursive: true);
    final tmp = File('${_file(key).path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'saved_at': (savedAt ?? DateTime.now()).toIso8601String(),
      'etag': etag,
      'data': data,
    }));
    await tmp.rename(_file(key).path); // атомарний запис
  }

  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  /// Видаляє всі ключі з префіксом, крім [except] (стара область після зміни Home Region).
  /// [keepPrefix] — не видаляти ключі, що починаються з нього (плитки поточної області).
  Future<void> deleteByPrefix(String prefix, {String? except, String? keepPrefix}) async {
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File &&
          name.startsWith(prefix) &&
          name.endsWith('.json') &&
          name != '$except.json' &&
          (keepPrefix == null || !name.startsWith(keepPrefix))) {
        await e.delete();
      }
    }
  }

  /// Видаляє ключі з префіксом, збережені раніше за [maxAge] (старі прогнози).
  Future<void> pruneOlderThan(String prefix, Duration maxAge, {DateTime? now}) async {
    if (!await dir.exists()) return;
    final limit = (now ?? DateTime.now()).subtract(maxAge);
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.startsWith(prefix) && name.endsWith('.json')) {
        if ((await e.lastModified()).isBefore(limit)) await e.delete();
      }
    }
  }
}
