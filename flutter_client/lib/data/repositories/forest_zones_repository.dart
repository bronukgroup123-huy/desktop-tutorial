import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../local/local_store.dart';
import '../models/forest_lod.dart';
import '../models/forest_zone.dart';
import '../models/geo.dart';
import '../models/region.dart';

/// Плитка сітки, на яку ділиться область для завантаження лісів.
class ForestTile {
  const ForestTile(this.row, this.col);

  final int row;
  final int col;

  static const double sizeDeg = 0.5;

  GeoBounds get bounds => GeoBounds(
        southWest: LatLng(row * sizeDeg, col * sizeDeg),
        northEast: LatLng((row + 1) * sizeDeg, (col + 1) * sizeDeg),
      );

  /// Версія кешу: v2 — після виправлення порожніх відповідей сервера
  /// (region_id = NULL у forest_zones). Старі порожні плитки на телефоні
  /// ігноруються і видаляються, ліси завантажуються заново.
  static const String cacheVersion = 'v2';

  static String prefix(String slug) => 'forests_${cacheVersion}_${slug}_';

  String key(String slug) => '${prefix(slug)}${row}_$col';

  /// Плитки сітки 0.5°, що перекривають межі області (стабільні між запусками).
  static List<ForestTile> cover(GeoBounds b) {
    final r0 = (b.southWest.latitude / sizeDeg).floor();
    final r1 = (b.northEast.latitude / sizeDeg).ceil() - 1;
    final c0 = (b.southWest.longitude / sizeDeg).floor();
    final c1 = (b.northEast.longitude / sizeDeg).ceil() - 1;
    return [
      for (var r = r0; r <= r1; r++)
        for (var c = c0; c <= c1; c++) ForestTile(r, c),
    ];
  }
}

/// Стан завантаження лісів області (для поступового показу на карті).
class ForestLoad {
  const ForestLoad({
    required this.zones,
    required this.done,
    required this.total,
    required this.failed,
    required this.offline,
    this.lod,
  });

  final List<ForestZone> zones;

  /// Ліси, підготовлені для карти (рівні деталізації, індекс для тапу). Для повного файлу
  /// будується в ізоляті разом із розбором; для запасних плиток — `null` (карта збудує сама).
  final ForestLod? lod;
  final int done;
  final int total;

  /// Плитки, які не вдалося завантажити і яких немає на телефоні.
  final int failed;

  /// Хоч одна плитка взята з телефону через відсутність мережі.
  final bool offline;

  bool get complete => done >= total;
}

/// Опис файлу лісів області (`forests-<slug>.json`, генерує GitHub Action).
class ForestFileMeta {
  const ForestFileMeta({required this.slug, required this.version, required this.bytes, required this.sha256});

  factory ForestFileMeta.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) throw const FormatException('forest meta: not an object');
    final slug = json['slug'], version = json['version'], bytes = json['bytes'], sha = json['sha256'];
    if (slug is! String || version is! String || bytes is! int || sha is! String || bytes <= 0) {
      throw const FormatException('forest meta: missing fields');
    }
    return ForestFileMeta(slug: slug, version: version, bytes: bytes, sha256: sha.toLowerCase());
  }

  final String slug;
  final String version;
  final int bytes;
  final String sha256;

  Map<String, dynamic> toJson() => {'slug': slug, 'version': version, 'bytes': bytes, 'sha256': sha256};
}

/// Полігони лісів — ТІЛЬКИ Home Region користувача (ADR-015 §15.2).
///
/// Основний шлях — один файл лісів області (GeoJSON.gz із GitHub Releases,
/// згенерований з OpenStreetMap). Він завантажується один раз і зберігається на
/// телефоні; раз на добу перевіряється маленький опис (`version`) — файл
/// перекачується лише коли вийшла нова версія. Без інтернету — файл з телефону.
///
/// Запасний шлях (файлу для області ще немає) — плитки з `v1-forest-zones`:
/// область ділиться на плитки 0.5°; кожна плитка завантажується
/// один раз і зберігається на телефоні, далі — з телефону. Раз на добу плитка
/// тихо перевіряється на сервері (ETag → 304 без тіла).
///
/// Чому плитки, а не один запит на всю область: у лісистих областях (Житомирська,
/// Рівненська) повна область — це тисячі полігонів і десятки МБ JSON, такий
/// запит на мобільному інтернеті впирається в тайм-аут, і на карті не з'являється
/// нічого. Плитки малі, вантажаться паралельно і показуються поступово.
class ForestZonesRepository {
  ForestZonesRepository(this._api, this._store, {Dio? files, DateTime Function()? now})
      : _files = files ?? Dio(),
        _now = now ?? DateTime.now;

  final ApiClient _api;
  final LocalStore _store;

  /// Окремий Dio без токенів Supabase — файли лежать на GitHub, туди JWT не шлемо.
  final Dio _files;
  final DateTime Function() _now;

  static String fileMetaKey(String slug) => 'forestsfile_$slug.meta';
  static String fileDataKey(String slug) => 'forestsfile_$slug.data';

  static const Duration refreshAfter = Duration(hours: 24);

  /// Масштаб, під який сервер спрощує геометрію (≈ 20 м — непомітно на карті).
  static const int downloadZoom = 11;
  static const int maxFeaturesPerTile = 10000;
  static const int parallel = 4;

  /// Ліси всієї області, плитка за плиткою. Кожен елемент потоку — усі ліси,
  /// що вже є (без дублів: полігон на межі плиток приходить двічі).
  Stream<ForestLoad> loadRegion(
    String slug,
    GeoBounds regionBounds, {
    RegionForestFiles? files,
    bool forceRefresh = false,
  }) async* {
    if (files != null) {
      final fromFile = await _loadFile(slug, files, forceRefresh: forceRefresh);
      if (fromFile != null) {
        yield fromFile;
        return;
      }
    }
    yield* _loadTiles(slug, regionBounds, forceRefresh: forceRefresh);
  }

  /// Ліси з файлу області; `null` — файлу немає (ще не згенерований) і на
  /// телефоні його теж немає → запасний шлях плитками.
  Future<ForestLoad?> _loadFile(String slug, RegionForestFiles files, {required bool forceRefresh}) async {
    // Файл іншої області більше не потрібен (ADR-016).
    await _store.deleteByPrefix('forestsfile_', keepPrefix: 'forestsfile_$slug.');

    final stored = await _store.read(fileMetaKey(slug));
    ForestFileMeta? storedMeta;
    Uint8List? storedBytes;
    if (stored != null) {
      try {
        storedMeta = ForestFileMeta.fromJson(stored.data);
        storedBytes = await _store.readBytes(fileDataKey(slug));
      } on FormatException {
        storedMeta = null;
      }
    }
    final haveLocal = storedMeta != null && storedBytes != null;

    Future<ForestLoad?> fromLocal({required bool offline}) async {
      if (!haveLocal) return null;
      final parsed = await _parseFile(storedBytes!);
      if (parsed == null) {
        await _store.delete(fileMetaKey(slug));
        await _store.delete(fileDataKey(slug));
        return null;
      }
      debugPrint('[forests] $slug: ${parsed.zones.length} forests from phone (file ${storedMeta!.version})');
      return ForestLoad(zones: parsed.zones, lod: parsed.lod, done: 1, total: 1, failed: 0, offline: offline);
    }

    if (haveLocal && !forceRefresh && _now().difference(stored!.savedAt) < refreshAfter) {
      final local = await fromLocal(offline: false);
      if (local != null) return local;
    }

    try {
      final meta = ForestFileMeta.fromJson(jsonDecode(utf8.decode(await _download(files.metaUrl))));
      if (meta.slug != slug) throw const FormatException('forest meta: wrong region');

      if (haveLocal && storedMeta.version == meta.version) {
        await _store.write(fileMetaKey(slug), storedMeta.toJson(), savedAt: _now());
        final local = await fromLocal(offline: false);
        if (local != null) return local;
      }

      debugPrint('[forests] $slug: downloading file ${meta.version} (${meta.bytes} bytes)');
      final bytes = await _download(files.dataUrl);
      if (bytes.length != meta.bytes || sha256.convert(bytes).toString() != meta.sha256) {
        throw const FormatException('forest file: size or checksum mismatch');
      }
      final parsed = await _parseFile(bytes);
      if (parsed == null) throw const FormatException('forest file: cannot parse');

      await _store.writeBytes(fileDataKey(slug), bytes);
      await _store.write(fileMetaKey(slug), meta.toJson(), savedAt: _now());
      // Плитки з v1-forest-zones більше не потрібні — є повний файл.
      await _store.deleteByPrefix('forests_');
      debugPrint('[forests] $slug: ${parsed.zones.length} forests from file ${meta.version}');
      return ForestLoad(zones: parsed.zones, lod: parsed.lod, done: 1, total: 1, failed: 0, offline: false);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint('[forests] $slug: file unavailable (${status ?? e.type.name})');
      return fromLocal(offline: status == null);
    } on FormatException catch (e) {
      debugPrint('[forests] $slug: bad file — $e');
      return fromLocal(offline: false);
    }
  }

  Future<Uint8List> _download(String url) async {
    final res = await _files.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    final data = res.data;
    if (data == null) throw const FormatException('empty response');
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  /// gzip → JSON → ліси + підготовка для карти, в окремому ізоляті (файл області —
  /// мегабайти; на головному потоці це підвисання інтерфейсу).
  static Future<({List<ForestZone> zones, ForestLod lod})?> _parseFile(Uint8List gz) => Isolate.run(() {
        try {
          final json = jsonDecode(utf8.decode(gzip.decode(gz)));
          final zones = ForestZone.listFromFeatureCollection(json as Map<String, dynamic>);
          return (zones: zones, lod: buildForestLod(zones));
        } catch (_) {
          return null;
        }
      });

  Stream<ForestLoad> _loadTiles(String slug, GeoBounds regionBounds, {required bool forceRefresh}) async* {
    final tiles = ForestTile.cover(regionBounds);
    // Плитки іншої області та старих версій кешу більше не потрібні (ADR-016).
    await _store.deleteByPrefix('forests_', keepPrefix: ForestTile.prefix(slug));

    final byId = <String, ForestZone>{};
    var done = 0;
    var failed = 0;
    var offline = false;
    final pending = <ForestTile>[];

    ForestLoad snapshot() => ForestLoad(
          zones: List.unmodifiable(byId.values),
          done: done,
          total: tiles.length,
          failed: failed,
          offline: offline,
        );

    // 1. Свіжі плитки з телефону — миттєво, без мережі.
    for (final t in tiles) {
      final cached = await _store.read(t.key(slug));
      if (cached != null && !forceRefresh && _now().difference(cached.savedAt) < refreshAfter) {
        _addAll(byId, cached.data);
        done++;
      } else {
        pending.add(t);
      }
    }
    debugPrint('[forests] $slug: ${tiles.length} tiles, ${tiles.length - pending.length} from phone, '
        '${pending.length} to download');
    yield snapshot();

    // 2. Решта — з мережі, по кілька паралельно.
    for (var i = 0; i < pending.length; i += parallel) {
      final batch = pending.skip(i).take(parallel);
      final results = await Future.wait(batch.map((t) => _loadTile(slug, t)));
      for (final r in results) {
        done++;
        if (r.data != null) _addAll(byId, r.data);
        if (r.offline) offline = true;
        if (r.failed) failed++;
      }
      yield snapshot();
    }
    debugPrint('[forests] $slug: done, ${byId.length} forests, failed tiles: $failed, offline: $offline');
  }

  Future<({Object? data, bool offline, bool failed})> _loadTile(String slug, ForestTile t) async {
    final cached = await _store.read(t.key(slug));
    try {
      final res = await _api.getConditional(
        '/v1-forest-zones',
        query: {'bbox': t.bounds.toQuery(), 'z': downloadZoom, 'limit': maxFeaturesPerTile},
        etag: cached?.etag,
      );
      final now = _now();
      if (res.notModified && cached != null) {
        await _store.write(t.key(slug), cached.data, etag: cached.etag, savedAt: now);
        debugPrint('[forests] tile ${t.row}_${t.col}: not modified');
        return (data: cached.data, offline: false, failed: false);
      }
      await _store.write(t.key(slug), res.data, etag: res.etag, savedAt: now);
      final n = ((res.data as Map<String, dynamic>)['features'] as List?)?.length ?? 0;
      debugPrint('[forests] tile ${t.row}_${t.col}: $n features');
      return (data: res.data, offline: false, failed: false);
    } on ApiException catch (e) {
      debugPrint('[forests] tile ${t.row}_${t.col}: ${e.code} (HTTP ${e.statusCode}) ${e.serverMessage ?? ''}');
      if (cached != null) return (data: cached.data, offline: e.isNetworkError, failed: false);
      return (data: null, offline: e.isNetworkError, failed: true);
    } on FormatException catch (e) {
      debugPrint('[forests] tile ${t.row}_${t.col}: bad data — $e');
      return (data: cached?.data, offline: false, failed: cached == null);
    }
  }

  static void _addAll(Map<String, ForestZone> byId, Object? data) {
    for (final z in ForestZone.listFromFeatureCollection(data as Map<String, dynamic>)) {
      byId[z.id] = z;
    }
  }

  /// Ліси для ділянки карти (без кешу).
  Future<List<ForestZone>> fetchForestZones({GeoBounds? bounds, int? zoom, int? limit}) async {
    final data = await _api.get('/v1-forest-zones', query: {
      if (bounds != null) 'bbox': bounds.toQuery(),
      if (zoom != null) 'z': zoom,
      if (limit != null) 'limit': limit,
    });
    return ForestZone.listFromFeatureCollection(data as Map<String, dynamic>);
  }
}
