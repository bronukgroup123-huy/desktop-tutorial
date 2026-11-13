import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../local/local_store.dart';
import '../models/region.dart';

/// Опис файлу карти області (`basemap-<slug>.json`, генерує GitHub Action «Basemap»).
class BasemapMeta {
  const BasemapMeta({required this.slug, required this.version, required this.bytes, required this.sha256});

  factory BasemapMeta.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('basemap meta: expected object');
    final slug = raw['slug'], version = raw['version'], bytes = raw['bytes'], sha = raw['sha256'];
    if (slug is! String || version is! String || bytes is! int || sha is! String || bytes <= 0) {
      throw const FormatException('basemap meta: bad fields');
    }
    return BasemapMeta(slug: slug, version: version, bytes: bytes, sha256: sha);
  }

  final String slug;
  final String version;
  final int bytes;
  final String sha256;

  /// «≈ 48 МБ»
  String get sizeLabel => '≈ ${(bytes / (1024 * 1024)).ceil()} МБ';

  Map<String, dynamic> toJson() => {'slug': slug, 'version': version, 'bytes': bytes, 'sha256': sha256};
}

/// Карта області, що вже лежить на телефоні.
class LocalBasemap {
  const LocalBasemap({required this.path, required this.meta});

  final String path;
  final BasemapMeta meta;
}

/// Карта-підкладка області для роботи без інтернету (пілот, рішення PO 2026-11-13).
///
/// Один файл PMTiles на область: качається ОДИН раз (розмір і sha256 перевіряються),
/// лежить у файлах застосунку (не в кеші — Android його не стирає) і далі карта
/// малюється з нього без запитів до серверів плиток. Карта іншої області видаляється.
class BasemapRepository {
  BasemapRepository(this._store, {required Dio files, required Future<Directory> Function() directory})
      : _files = files,
        _directory = directory;

  final LocalStore _store;

  /// Окремий Dio без токенів Supabase — файли лежать на GitHub.
  final Dio _files;
  final Future<Directory> Function() _directory;

  static String metaKey(String slug) => 'basemap_$slug.meta';

  Future<File> _fileFor(String slug) async {
    final dir = await _directory();
    return File('${dir.path}/basemap-$slug.pmtiles');
  }

  /// Карта області на телефоні; `null` — ще не завантажена (або файл пошкоджено).
  Future<LocalBasemap?> local(String slug) async {
    final stored = await _store.read(metaKey(slug));
    if (stored == null) return null;
    try {
      final meta = BasemapMeta.fromJson(stored.data);
      final file = await _fileFor(slug);
      if (!await file.exists() || await file.length() != meta.bytes) return null;
      return LocalBasemap(path: file.path, meta: meta);
    } on FormatException {
      return null;
    }
  }

  /// Опис карти на сервері; `null` — карти для області ще немає (404).
  Future<BasemapMeta?> remote(RegionForestFiles files) async {
    try {
      final res = await _files.get<List<int>>(files.metaUrl, options: Options(responseType: ResponseType.bytes));
      return BasemapMeta.fromJson(jsonDecode(utf8.decode(res.data ?? const [])));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Завантажити карту області. Потік — частка завантаженого (0…1); останнє значення —
  /// 1.0, коли файл перевірено й збережено. Помилка — виняток у потоці.
  Stream<double> download(String slug, RegionForestFiles files) async* {
    final meta = await remote(files);
    if (meta == null || meta.slug != slug) throw const FormatException('Для цієї області карти ще немає');
    final file = await _fileFor(slug);
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');

    final progress = StreamController<double>();
    Object? failure;
    StackTrace? failureStack;
    final done = _files
        .download(
          files.dataUrl,
          part.path,
          onReceiveProgress: (got, total) {
            final t = total > 0 ? total : meta.bytes;
            if (!progress.isClosed) progress.add((got / t).clamp(0.0, 0.99));
          },
          options: Options(receiveTimeout: const Duration(minutes: 10)),
        )
        .then<void>((_) {}, onError: (Object e, StackTrace s) {
          failure = e;
          failureStack = s;
        }).whenComplete(progress.close);
    yield* progress.stream;
    await done;
    if (failure != null) {
      if (await part.exists()) await part.delete();
      Error.throwWithStackTrace(failure!, failureStack!);
    }

    final length = await part.length();
    final digest = await _sha256Of(part.path);
    if (length != meta.bytes || digest != meta.sha256) {
      await part.delete();
      throw const FormatException('Файл карти пошкоджено під час завантаження. Спробуйте ще раз.');
    }
    await part.rename(file.path);
    await _store.write(metaKey(slug), meta.toJson());
    // Карта іншої області більше не потрібна (ADR-016: одна Home Region).
    await for (final e in file.parent.list()) {
      if (e is File && e.path != file.path && e.path.endsWith('.pmtiles')) await e.delete();
    }
    await _store.deleteByPrefix('basemap_', except: metaKey(slug));
    debugPrint('[basemap] $slug: saved ${meta.version} ($length bytes)');
    yield 1.0;
  }

  /// Видалити карту області з телефону.
  Future<void> delete(String slug) async {
    await _store.delete(metaKey(slug));
    final file = await _fileFor(slug);
    if (await file.exists()) await file.delete();
  }
}

/// sha256 файлу в окремому ізоляті (файл карти — десятки МБ). Окрема функція: замикання
/// для ізолята не повинно захоплювати незавершені Future з методу, що її викликає.
Future<String> _sha256Of(String path) =>
    Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());
