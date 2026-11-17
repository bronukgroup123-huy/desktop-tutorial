import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'package:flutter_client/features/recognize/ai_model.dart';

/// Розпізнавання на телефоні (ADR-006): кодувальник зображень BioCLIP 2 (ONNX) перетворює фото на
/// вектор, а схожість із заздалегідь порахованими відбитками видів дає кандидатів. Фото нікуди не
/// відправляються. Користувачу — рівні («Найімовірніше / Можливо / Менш імовірно»), без відсотків.

/// Вид (або «не гриб») з labels.json.
class RecognitionLabel {
  const RecognitionLabel({required this.id, required this.latin, required this.name, required this.edibility, this.redListed = false, this.hasPhoto = false});

  factory RecognitionLabel.fromJson(Map<String, dynamic> j) => RecognitionLabel(
        id: j['id'] as String,
        latin: (j['latin'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        edibility: (j['edibility'] as String?) ?? '',
        redListed: j['red_listed'] == true,
        hasPhoto: j['has_photo'] == true,
      );

  final String id, latin, name, edibility;
  final bool redListed, hasPhoto;

  bool get notMushroom => id == 'not_mushroom';
  bool get poisonous => edibility == 'poisonous' || edibility == 'deadly_poisonous';

  Map<String, dynamic> toJson() => {'id': id, 'latin': latin, 'name': name, 'edibility': edibility, 'red_listed': redListed, 'has_photo': hasPhoto};
}

enum Likelihood {
  likely('Найімовірніше'),
  possible('Можливо'),
  unlikely('Менш імовірно');

  const Likelihood(this.label);
  final String label;
}

class Candidate {
  const Candidate({required this.label, required this.likelihood});

  final RecognitionLabel label;
  final Likelihood likelihood;
}

/// Результат: «не гриб» або до трьох кандидатів рівнями.
class Recognition {
  const Recognition({required this.notMushroom, required this.candidates});

  final bool notMushroom;
  final List<Candidate> candidates;

  /// Серед схожих є отруйний — червона плашка зверху (ADR-006, «безпека першою»).
  RecognitionLabel? get dangerous => notMushroom ? null : candidates.where((c) => c.label.poisonous).map((c) => c.label).firstOrNull;
}

/// Відбитки видів: float16 (N×D) → Float32List.
Float32List decodeF16(Uint8List bytes) {
  final half = bytes.buffer.asUint16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
  final out = Float32List(half.length);
  for (var i = 0; i < half.length; i++) {
    final h = half[i];
    final sign = (h & 0x8000) != 0 ? -1.0 : 1.0;
    final exp = (h >> 10) & 0x1f;
    final frac = h & 0x3ff;
    out[i] = exp == 0
        ? sign * math.pow(2, -14) * (frac / 1024)
        : exp == 31
            ? (frac == 0 ? sign * double.infinity : double.nan)
            : sign * math.pow(2, exp - 15) * (1 + frac / 1024);
  }
  return out;
}

/// Підготовка фото — як при збірці моделі (open_clip): поворот за EXIF, коротша сторона → [size]
/// (бікубічно), центральний квадрат, нормалізація; NCHW float32.
Float32List preprocessImage(Uint8List bytes, int size, List<double> mean, List<double> std) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Не вдалося прочитати фото');
  final im = img.bakeOrientation(decoded);
  final scale = size / math.min(im.width, im.height);
  final resized = img.copyResize(im,
      width: math.max(size, (im.width * scale).round()),
      height: math.max(size, (im.height * scale).round()),
      interpolation: img.Interpolation.cubic);
  final crop = img.copyCrop(resized, x: (resized.width - size) ~/ 2, y: (resized.height - size) ~/ 2, width: size, height: size);
  final out = Float32List(3 * size * size);
  final plane = size * size;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = crop.getPixel(x, y);
      final i = y * size + x;
      out[i] = (p.r / 255 - mean[0]) / std[0];
      out[plane + i] = (p.g / 255 - mean[1]) / std[1];
      out[2 * plane + i] = (p.b / 255 - mean[2]) / std[2];
    }
  }
  return out;
}

/// Кандидати за векторами фото: середній вектор кількох кадрів (шапка, ніжка, зріз), схожість з
/// відбитками, softmax. Імовірність «не гриб» — сума класів «не гриб».
Recognition rankSpecies(List<Float32List> photos, Float32List text, List<RecognitionLabel> labels, {double logitScale = 100}) {
  final dim = photos.first.length;
  final mean = Float32List(dim);
  for (final e in photos) {
    for (var d = 0; d < dim; d++) {
      mean[d] += e[d];
    }
  }
  var norm = 0.0;
  for (final v in mean) {
    norm += v * v;
  }
  norm = math.sqrt(norm);
  final n = labels.length;
  final logits = List<double>.filled(n, 0);
  for (var k = 0; k < n; k++) {
    var s = 0.0;
    for (var d = 0; d < dim; d++) {
      s += text[k * dim + d] * mean[d];
    }
    logits[k] = logitScale * s / (norm == 0 ? 1 : norm);
  }
  final maxL = logits.reduce(math.max);
  final exps = [for (final l in logits) math.exp(l - maxL)];
  final sum = exps.reduce((a, b) => a + b);
  final probs = [for (final e in exps) e / sum];
  var notMushroom = 0.0;
  final species = <(int, double)>[];
  for (var k = 0; k < n; k++) {
    if (labels[k].notMushroom) {
      notMushroom += probs[k];
    } else {
      species.add((k, probs[k]));
    }
  }
  species.sort((a, b) => b.$2.compareTo(a.$2));
  if (notMushroom > 0.5 || (species.isNotEmpty && notMushroom > species.first.$2 * 2)) {
    return const Recognition(notMushroom: true, candidates: []);
  }
  final top = species.take(3).toList();
  return Recognition(
    notMushroom: false,
    candidates: [
      for (final (i, (k, p)) in top.indexed)
        Candidate(
          label: labels[k],
          likelihood: i == 0
              ? (p >= 0.45 ? Likelihood.likely : Likelihood.possible)
              : (p >= 0.12 ? Likelihood.possible : Likelihood.unlikely),
        ),
    ],
  );
}

/// Перетворення фото на вектор (у тестах — підміна без нативного рушія).
abstract class ImageEmbedder {
  Future<Float32List> embed(Float32List input, int size);
  void dispose();
}

class OrtEmbedder implements ImageEmbedder {
  OrtEmbedder(File model) {
    OrtEnv.instance.init();
    _session = OrtSession.fromFile(model, OrtSessionOptions());
  }

  late final OrtSession _session;

  @override
  Future<Float32List> embed(Float32List input, int size) async {
    final tensor = OrtValueTensor.createTensorWithDataList(input, [1, 3, size, size]);
    final runOptions = OrtRunOptions();
    try {
      final outputs = await (_session.runAsync(runOptions, {'image': tensor}) ?? Future.value(_session.run(runOptions, {'image': tensor})));
      final value = outputs.first!.value as List;
      final row = (value.first as List).cast<num>();
      for (final o in outputs) {
        o?.release();
      }
      return Float32List.fromList([for (final v in row) v.toDouble()]);
    } finally {
      tensor.release();
      runOptions.release();
    }
  }

  @override
  void dispose() => _session.release();
}

/// Розпізнавач: модель і відбитки з теки ai_model на телефоні.
class AiRecognizer {
  AiRecognizer({required this.manifest, required this.labels, required this.text, required this.embedder});

  final AiModelManifest manifest;
  final List<RecognitionLabel> labels;
  final Float32List text;
  final ImageEmbedder embedder;

  @visibleForTesting
  static ImageEmbedder Function(File model) embedderFactory = OrtEmbedder.new;

  static Future<AiRecognizer> open(Directory dir, AiModelManifest manifest) async {
    final labels = [
      for (final j in (jsonDecode(await File('${dir.path}/labels.json').readAsString()) as List).cast<Map<String, dynamic>>())
        RecognitionLabel.fromJson(j),
    ];
    final text = decodeF16(await File('${dir.path}/species_text.f16').readAsBytes());
    return AiRecognizer(
      manifest: manifest,
      labels: labels,
      text: text,
      embedder: embedderFactory(File('${dir.path}/bioclip2_vision_int8.onnx')),
    );
  }

  /// Кілька кадрів одного гриба (шапка · ніжка · зріз) → кандидати.
  Future<Recognition> recognize(List<Uint8List> photos) async {
    final m = manifest;
    final vectors = <Float32List>[];
    for (final p in photos) {
      final input = await compute(_prep, (p, m.imageSize, m.mean, m.std));
      vectors.add(await embedder.embed(input, m.imageSize));
    }
    return rankSpecies(vectors, text, labels, logitScale: m.logitScale);
  }

  void dispose() => embedder.dispose();
}

Float32List _prep((Uint8List, int, List<double>, List<double>) a) => preprocessImage(a.$1, a.$2, a.$3, a.$4);

/// Розпізнавач, коли модель на телефоні; немає — `null`. Відкривається один раз (модель — сотні МБ).
final recognizerProvider = FutureProvider<AiRecognizer?>((ref) async {
  final installed = ref.watch(aiModelProvider.select((s) => s.installed));
  if (installed == null) return null;
  final dir = await AiModelIo.directory();
  if (dir == null) return null;
  final r = await AiRecognizer.open(dir, installed);
  ref.onDispose(r.dispose);
  return r;
});
