import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;

/// Фото довідника: з телефону (якщо вже переглядали) або з релізу «catalog-data» — і
/// зберігається на телефоні, щоб наступного разу працювало без інтернету.
class CatalogPhotoCache {
  CatalogPhotoCache._();

  static final Map<String, Future<Uint8List?>> _memory = {};

  /// Завантаження з мережі (у тестах підміняється).
  @visibleForTesting
  static Future<Uint8List?> Function(String url) fetcher = _download;

  /// Тека на телефоні (у тестах підміняється).
  @visibleForTesting
  static Future<Directory?> Function() directory = _defaultDir;

  static Future<Directory?> _defaultDir() async {
    try {
      return Directory('${(await getApplicationSupportDirectory()).path}/catalog_photos');
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _download(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final b = BytesBuilder(copy: false);
      await for (final chunk in res) {
        b.add(chunk);
      }
      return b.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<Uint8List?> get(String name) => _memory.putIfAbsent(name, () => _load(name));

  static Future<Uint8List?> _load(String name) async {
    final dir = await directory();
    final file = dir == null ? null : File('${dir.path}/$name');
    if (file != null && await file.exists()) return file.readAsBytes();
    final bytes = await fetcher('$kCatalogPhotosBase/$name');
    if (bytes == null) {
      _memory.remove(name); // наступного разу спробувати ще
      return null;
    }
    if (file != null) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {}
    }
    return bytes;
  }

  @visibleForTesting
  static void clear() => _memory.clear();
}

/// Фото виду; немає (офлайн і ще не переглядали) — стікер гриба на світлому тлі.
class CatalogPhoto extends StatelessWidget {
  const CatalogPhoto({super.key, required this.name, required this.speciesId, this.fit = BoxFit.cover});

  final String? name;
  final String speciesId;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xfff1ece0),
      alignment: Alignment.center,
      child: SpeciesIcon(type: speciesId, fallbackColor: const Color(0xff8d6e63), size: 44),
    );
    if (name == null) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: CatalogPhotoCache.get(name!),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return placeholder;
        return Image.memory(bytes, fit: fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => placeholder);
      },
    );
  }
}
