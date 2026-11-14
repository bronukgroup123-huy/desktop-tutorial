import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_client/features/map/basemap_style.dart' show glyphFontStack;

/// Діапазони гліфів шрифту, вкладені в застосунок: латиниця, розширена латиниця,
/// кирилиця, розділові знаки («—», лапки). Інших діапазонів у назвах України майже немає.
const glyphRanges = ['0-255', '256-511', '1024-1279', '8192-8447'];

/// Гліфи шрифту для підписів офлайн карти — на диск (один раз).
///
/// MapLibre Native читає гліфи сам, лише з файлів або мережі — не з ресурсів Flutter. Тому
/// при першому відкритті карти копіюємо їх у файли застосунку; повертає теку для `glyphs`
/// у стилі (`<тека>/{fontstack}/{range}.pbf`).
Future<String> ensureOfflineGlyphs({Future<Directory> Function()? directory}) async {
  final base = await (directory ?? getApplicationSupportDirectory)();
  final root = Directory('${base.path}/map_glyphs');
  final fontDir = Directory('${root.path}/$glyphFontStack');
  await fontDir.create(recursive: true);
  for (final range in glyphRanges) {
    final file = File('${fontDir.path}/$range.pbf');
    final data = await rootBundle.load('assets/map/glyphs/noto_sans_regular/$range.pbf');
    if (await file.exists() && await file.length() == data.lengthInBytes) continue;
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  }
  return root.path;
}
