import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_client/features/recognize/recognizer.dart';

/// Історія розпізнавань — лише на телефоні (фото нікуди не відправляються, ADR-006 / ADR-009):
/// мініатюра першого кадру, час і кандидати. Не більше [kHistoryMax] записів.
const kHistoryMax = 30;

class HistoryEntry {
  const HistoryEntry({required this.id, required this.at, required this.thumb, required this.recognition});

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        at: DateTime.parse(j['at'] as String),
        thumb: j['thumb'] as String,
        recognition: Recognition(
          notMushroom: j['not_mushroom'] == true,
          candidates: [
            for (final c in (j['candidates'] as List).cast<Map<String, dynamic>>())
              Candidate(
                label: RecognitionLabel.fromJson((c['label'] as Map).cast<String, dynamic>()),
                likelihood: Likelihood.values.byName(c['likelihood'] as String),
              ),
          ],
        ),
      );

  final String id;
  final DateTime at;

  /// Ім'я файлу мініатюри в теці історії.
  final String thumb;
  final Recognition recognition;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'thumb': thumb,
        'not_mushroom': recognition.notMushroom,
        'candidates': [
          for (final c in recognition.candidates) {'label': c.label.toJson(), 'likelihood': c.likelihood.name},
        ],
      };
}

class RecognitionHistory {
  RecognitionHistory._();

  /// Тека історії (у тестах підміняється).
  static Future<Directory?> Function() directory = () async {
    try {
      return Directory('${(await getApplicationSupportDirectory()).path}/recognitions');
    } catch (_) {
      return null;
    }
  };

  static Future<List<HistoryEntry>> load() async {
    final dir = await directory();
    final f = dir == null ? null : File('${dir.path}/index.json');
    if (f == null || !await f.exists()) return [];
    try {
      return [for (final j in (jsonDecode(await f.readAsString()) as List).cast<Map<String, dynamic>>()) HistoryEntry.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  /// Додати результат (найновіший — першим); зайві старі записи й мініатюри — видалити.
  static Future<HistoryEntry?> add(Recognition r, Uint8List photo, {DateTime? now}) async {
    final dir = await directory();
    if (dir == null) return null;
    await dir.create(recursive: true);
    final at = now ?? DateTime.now();
    final id = at.microsecondsSinceEpoch.toString();
    final thumb = '$id.jpg';
    try {
      await File('${dir.path}/$thumb').writeAsBytes(await compute(_thumbnail, photo));
    } catch (_) {
      return null;
    }
    final entry = HistoryEntry(id: id, at: at, thumb: thumb, recognition: r);
    final all = [entry, ...await load()];
    for (final old in all.skip(kHistoryMax)) {
      final f = File('${dir.path}/${old.thumb}');
      if (await f.exists()) await f.delete();
    }
    await File('${dir.path}/index.json').writeAsString(jsonEncode([for (final e in all.take(kHistoryMax)) e.toJson()]));
    return entry;
  }

  static Future<void> clear() async {
    final dir = await directory();
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<File?> thumbFile(HistoryEntry e) async {
    final dir = await directory();
    return dir == null ? null : File('${dir.path}/${e.thumb}');
  }
}

/// Мініатюра 320 px (JPEG) — історії вистачає, повні фото не зберігаємо.
Uint8List _thumbnail(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('фото');
  final im = img.bakeOrientation(decoded);
  final small = im.width >= im.height ? img.copyResize(im, width: 320) : img.copyResize(im, height: 320);
  return Uint8List.fromList(img.encodeJpg(small, quality: 80));
}

final recognitionHistoryProvider = FutureProvider<List<HistoryEntry>>((ref) => RecognitionHistory.load());
