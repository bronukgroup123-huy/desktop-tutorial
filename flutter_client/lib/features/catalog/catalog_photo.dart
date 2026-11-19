import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/features/catalog/catalog_motion.dart' show reduceMotion;
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;

/// Фото довідника: з телефону (якщо вже переглядали) або з релізу «catalog-photos» — і
/// зберігається на телефоні, щоб наступного разу працювало без інтернету.
///
/// У релізі фото лежать архівами tar (GitHub обмежує кількість файлів, що викладаються):
/// `<id>.tar` — фото виду, `thumbs.tar` — мініатюри всіх видів для списку. Перше звернення до
/// будь-якого фото архіву завантажує його цілком і розпаковує на телефон.
class CatalogPhotoCache {
  CatalogPhotoCache._();

  static final Map<String, Future<Uint8List?>> _memory = {};
  static final Map<String, Future<Map<String, Uint8List>?>> _bundles = {};

  /// Архів, у якому лежить фото.
  static String bundleOf(String name) =>
      name.endsWith('-t.webp') ? 'thumbs.tar' : '${name.replaceFirst(RegExp(r'-\d+\.webp$'), '')}.tar';

  /// Розпакувати tar (ustar): ім'я файлу → вміст.
  static Map<String, Uint8List> untar(Uint8List b) {
    final out = <String, Uint8List>{};
    String field(int off, int len) {
      final raw = b.sublist(off, off + len);
      final end = raw.indexOf(0);
      return String.fromCharCodes(end < 0 ? raw : raw.sublist(0, end)).trim();
    }

    var off = 0;
    while (off + 512 <= b.length) {
      if (b[off] == 0) break; // кінець архіву — порожні блоки
      final name = field(off, 100);
      final size = int.tryParse(field(off + 124, 12), radix: 8) ?? 0;
      final type = b[off + 156];
      off += 512;
      if (off + size > b.length) break; // обірваний архів
      if ((type == 0x30 || type == 0) && name.isNotEmpty) {
        out[name.split('/').last] = Uint8List.fromList(b.sublist(off, off + size));
      }
      off += (size + 511) ~/ 512 * 512;
    }
    return out;
  }

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

  /// Уже завантажені за цей сеанс — показуються одразу, без проміжного кадру з заглушкою.
  static final Map<String, Uint8List> _ready = {};

  static Uint8List? peek(String name) => _ready[name];

  static Future<Uint8List?> get(String name) => _memory.putIfAbsent(
        name,
        () => _load(name).then((b) {
          if (b != null) _ready[name] = b;
          return b;
        }),
      );

  static Future<Uint8List?> _load(String name) async {
    final dir = await directory();
    final file = dir == null ? null : File('${dir.path}/$name');
    if (file != null && await file.exists()) return file.readAsBytes();
    final bundle = bundleOf(name);
    final files = await _bundles.putIfAbsent(bundle, () => _fetchBundle(bundle, dir));
    // Збережено на телефоні — далі фото читаються звідти, архів у пам'яті не тримаємо
    // (запити, що вже чекають, отримають фото з цього ж результату).
    if (files == null || dir != null) _bundles.remove(bundle);
    final bytes = files?[name];
    if (bytes == null) _memory.remove(name); // наступного разу спробувати ще
    return bytes;
  }

  /// Завантажити архів і розпакувати на телефон.
  static Future<Map<String, Uint8List>?> _fetchBundle(String bundle, Directory? dir) async {
    final raw = await fetcher('$kCatalogPhotosBase/$bundle');
    if (raw == null) return null;
    final files = untar(raw);
    if (files.isEmpty) return null;
    if (dir != null) {
      try {
        await dir.create(recursive: true);
        for (final e in files.entries) {
          // Спершу тимчасовий файл: обірване збереження не лишить «битого» фото.
          final tmp = File('${dir.path}/${e.key}.part');
          await tmp.writeAsBytes(e.value, flush: true);
          await tmp.rename('${dir.path}/${e.key}');
        }
      } catch (_) {}
    }
    return files;
  }

  // ─── «Фото без інтернету»: увесь довідник на телефон ───────────────────────

  /// Завантажити й зберегти на телефоні архів (`<id>.tar`, `thumbs.tar`); `false` — не вдалося.
  static Future<bool> downloadBundle(String bundle) async {
    final dir = await directory();
    if (dir == null) return false;
    final files = await _fetchBundle(bundle, dir);
    return files != null && files.keys.every((n) => File('${dir.path}/$n').existsSync());
  }

  /// Імена фото, що вже лежать на телефоні.
  static Future<Set<String>> savedNames() async {
    final dir = await directory();
    if (dir == null || !await dir.exists()) return {};
    return {
      await for (final f in dir.list())
        if (f is File && f.path.endsWith('.webp')) f.uri.pathSegments.last,
    };
  }

  /// Скільки займають збережені фото.
  static Future<int> savedBytes() async {
    final dir = await directory();
    if (dir == null || !await dir.exists()) return 0;
    var total = 0;
    await for (final f in dir.list()) {
      // Тимчасові «.part» пропускаємо; фото могло щойно зникнути (перейменування, видалення).
      if (f is! File || !f.path.endsWith('.webp')) continue;
      try {
        total += await f.length();
      } on FileSystemException {
        continue;
      }
    }
    return total;
  }

  /// Розміри архівів у релізі (manifest.json); немає мережі / старий реліз — `null`.
  static Future<Map<String, int>?> manifest() async {
    final raw = await fetcher('$kCatalogPhotosBase/manifest.json');
    if (raw == null) return null;
    try {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      return {for (final e in (j['bundles'] as Map<String, dynamic>).entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return null;
    }
  }

  /// Видалити всі збережені фото (звільнити місце).
  static Future<void> deleteAll() async {
    _memory.clear();
    _bundles.clear();
    _ready.clear();
    final dir = await directory();
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  }

  @visibleForTesting
  static void clear() {
    _memory.clear();
    _bundles.clear();
    _ready.clear();
  }
}

/// Фото виду; немає (офлайн і ще не переглядали) — стікер гриба на світлому тлі.
///
/// Картка є одразу; нове фото один раз плавно проявляється поверх стікера (рішення PO 2026-11-16).
/// Уже завантажене за сеанс (зокрема при гортанні назад) — одразу, без анімації й без блимання.
class CatalogPhoto extends StatefulWidget {
  const CatalogPhoto({super.key, required this.name, required this.speciesId, this.fit = BoxFit.cover, this.whole = false, this.inset = EdgeInsets.zero});

  final String? name;
  final String speciesId;
  final BoxFit fit;

  /// Гриб цілим (без обрізки): фото вписане повністю, а місце довкола заповнює те саме фото,
  /// збільшене й розмите — без порожніх смуг. [inset] — відступ для цілого фото (статус-бар).
  final bool whole;
  final EdgeInsets inset;

  @override
  State<CatalogPhoto> createState() => _CatalogPhotoState();
}

class _CatalogPhotoState extends State<CatalogPhoto> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() {}); // заглушка більше не потрібна
    });
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CatalogPhoto old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) _resolve();
  }

  void _resolve() {
    final name = widget.name;
    _bytes = null;
    if (name == null) return;
    final ready = CatalogPhotoCache.peek(name);
    if (ready != null) {
      _bytes = ready;
      _fade.value = 1;
      return;
    }
    _fade.value = 0;
    CatalogPhotoCache.get(name).then((b) {
      if (!mounted || widget.name != name || b == null) return;
      setState(() => _bytes = b);
      if (reduceMotion(context)) {
        _fade.value = 1;
      } else {
        _fade.forward();
      }
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      key: const ValueKey('photo-placeholder'),
      color: const Color(0xfff1ece0),
      alignment: Alignment.center,
      child: SpeciesIcon(type: widget.speciesId, fallbackColor: const Color(0xff8d6e63), size: 44),
    );
    final bytes = _bytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bytes == null || !_fade.isCompleted) placeholder,
        if (bytes != null)
          FadeTransition(
            key: const ValueKey('photo-image'),
            opacity: _fade,
            child: widget.whole
                ? Stack(fit: StackFit.expand, children: [
                    ClipRect(
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.mirror),
                        child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    ),
                    const ColoredBox(color: Color(0x33000000)),
                    Padding(
                      padding: widget.inset,
                      // Center дає вільні межі — фото бере свій розмір із пропорціями, тож кути й тінь — по фото.
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 6))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(bytes,
                                key: const ValueKey('photo-whole'), fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, __, ___) => placeholder),
                          ),
                        ),
                      ),
                    ),
                  ])
                : Image.memory(bytes, fit: widget.fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => placeholder),
          ),
      ],
    );
  }
}
