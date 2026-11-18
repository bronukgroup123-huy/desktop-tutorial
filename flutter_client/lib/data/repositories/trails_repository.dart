import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../features/safety/hike/trails.dart';
import '../local/local_store.dart';
import '../models/region.dart';
import 'basemap_repository.dart' show BasemapMeta;

/// Де лежить мережа стежок області, якщо сервер ще не віддає посилання (старий кеш).
const kTrailsBase = 'https://github.com/bronukgroup123-huy/desktop-tutorial/releases/download/trails-data';

RegionForestFiles trailsFilesFor(RegionGeometry g) =>
    g.trails ?? RegionForestFiles(metaUrl: '$kTrailsBase/trails-${g.slug}.json', dataUrl: '$kTrailsBase/trails-${g.slug}.bin.gz');

/// Мережа доріг і стежок області (ADR-022 §22.7) — один файл, качається разом з офлайн-картою,
/// лежить у файлах застосунку; маршрут «Додому» прокладається з нього без інтернету.
class TrailsRepository {
  TrailsRepository(this._store, {required Dio files, required Future<Directory> Function() directory})
      : _files = files,
        _directory = directory;

  final LocalStore _store;
  final Dio _files;
  final Future<Directory> Function() _directory;

  static String metaKey(String slug) => 'trails_$slug.meta';

  Future<File> _fileFor(String slug) async => File('${(await _directory()).path}/trails-$slug.bin.gz');

  /// Чи є мережа на телефоні.
  Future<BasemapMeta?> localMeta(String slug) async {
    final stored = await _store.read(metaKey(slug));
    if (stored == null) return null;
    try {
      final meta = BasemapMeta.fromJson(stored.data);
      final file = await _fileFor(slug);
      if (!await file.exists() || await file.length() != meta.bytes) return null;
      return meta;
    } on FormatException {
      return null;
    }
  }

  /// Прочитати мережу з телефону (в окремому ізоляті — файл великий). `null` — ще немає.
  Future<TrailGraph?> load(String slug) async {
    if (await localMeta(slug) == null) return null;
    final path = (await _fileFor(slug)).path;
    return Isolate.run(() => TrailGraph.parse(Uint8List.fromList(gzip.decode(File(path).readAsBytesSync()))));
  }

  /// Завантажити (або оновити) мережу області. `false` — для області ще немає файлу.
  Future<bool> download(String slug, RegionForestFiles files) async {
    final BasemapMeta meta;
    try {
      final res = await _files.get<String>(files.metaUrl, options: Options(responseType: ResponseType.plain));
      meta = BasemapMeta.fromJson(jsonDecode(res.data ?? ''));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
    if (meta.slug != slug) throw const FormatException('Файл стежок іншої області');
    final current = await localMeta(slug);
    if (current?.version == meta.version) return true;
    final file = await _fileFor(slug);
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await _files.download(files.dataUrl, part.path, options: Options(receiveTimeout: const Duration(minutes: 5)));
    final bytes = await part.readAsBytes();
    if (bytes.length != meta.bytes || sha256.convert(bytes).toString() != meta.sha256) {
      await part.delete();
      throw const FormatException('Файл стежок пошкоджено під час завантаження. Спробуйте ще раз.');
    }
    await part.rename(file.path);
    await _store.write(metaKey(slug), meta.toJson());
    await for (final e in file.parent.list()) {
      if (e is File && e.path != file.path && e.path.endsWith('.bin.gz')) await e.delete();
    }
    await _store.deleteByPrefix('trails_', except: metaKey(slug));
    debugPrint('[trails] $slug: saved ${meta.version} (${bytes.length} bytes)');
    return true;
  }
}
