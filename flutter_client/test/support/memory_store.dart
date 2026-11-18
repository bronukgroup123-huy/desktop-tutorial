import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_client/data/local/local_store.dart';

/// Сховище в пам'яті (без файлів) — для тестів.
class MemoryStore extends LocalStore {
  MemoryStore() : super(Directory.systemTemp);

  final Map<String, Object?> data = {};

  @override
  Future<StoredEntry?> read(String key) async => data.containsKey(key) ? StoredEntry(data: data[key], savedAt: DateTime(2026)) : null;

  @override
  Future<void> write(String key, Object? value, {String? etag, DateTime? savedAt}) async => data[key] = value;

  @override
  Future<Uint8List?> readBytes(String key) async => null;
}
