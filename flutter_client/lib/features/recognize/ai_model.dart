import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';


/// ШІ-розпізнавач (ADR-006): модель BioCLIP 2 (ONNX int8) і відбитки видів лежать у релізі «ai-model»
/// (.github/workflows/ai-model.yml); застосунок завантажує їх на телефон — як офлайн-карту й фото
/// довідника — і далі розпізнає без інтернету.
const kAiModelBase = 'https://github.com/bronukgroup123-huy/desktop-tutorial/releases/download/ai-model';

class AiModelFile {
  const AiModelFile({required this.name, required this.size, required this.sha256});

  final String name;
  final int size;
  final String sha256;
}

/// Маніфест моделі (manifest.json у релізі).
class AiModelManifest {
  const AiModelManifest({
    required this.version,
    required this.files,
    required this.imageSize,
    required this.mean,
    required this.std,
    required this.species,
    this.logitScale = 100,
  });

  factory AiModelManifest.fromJson(Map<String, dynamic> j) => AiModelManifest(
        version: j['version'] as String,
        files: [
          for (final e in (j['files'] as Map<String, dynamic>).entries)
            AiModelFile(
              name: e.key,
              size: ((e.value as Map)['size'] as num).toInt(),
              sha256: (e.value as Map)['sha256'] as String,
            ),
        ],
        imageSize: (j['image_size'] as num?)?.toInt() ?? 224,
        mean: [for (final v in (j['mean'] as List? ?? const [])) (v as num).toDouble()],
        std: [for (final v in (j['std'] as List? ?? const [])) (v as num).toDouble()],
        species: (j['species'] as num?)?.toInt() ?? 0,
        logitScale: (j['logit_scale'] as num?)?.toDouble() ?? 100,
      );

  final String version;
  final List<AiModelFile> files;
  final int imageSize;
  final List<double> mean, std;
  final int species;

  /// «Температура» схожості (CLIP) — для рівнів кандидатів.
  final double logitScale;

  int get totalBytes => files.fold(0, (a, f) => a + f.size);
}

/// Доступ до мережі й теки моделі (у тестах підміняється).
class AiModelIo {
  AiModelIo._();

  /// Тека моделі на телефоні (у тестах підміняється).
  static Future<Directory?> Function() directory = () async {
    try {
      return Directory('${(await getApplicationSupportDirectory()).path}/ai_model');
    } catch (_) {
      return null;
    }
  };

  /// Маленький файл цілком (manifest.json); немає мережі / ще немає релізу — `null`.
  @visibleForTesting
  static Future<List<int>?> Function(String url) fetch = _fetch;

  /// Великий файл потоком, з місця [from] (докачування після обриву): кожен шматок — у [onChunk].
  @visibleForTesting
  static Future<bool> Function(String url, int from, Future<void> Function(List<int> chunk) onChunk, bool Function() cancelled)
      stream = _stream;

  static Future<List<int>?> _fetch(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) return null;
      final b = BytesBuilder(copy: false);
      await for (final c in res) {
        b.add(c);
      }
      return b.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<bool> _stream(String url, int from, Future<void> Function(List<int>) onChunk, bool Function() cancelled) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      if (from > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      final res = await req.close();
      if (res.statusCode != 200 && res.statusCode != 206) return false;
      if (from > 0 && res.statusCode == 200) return false; // сервер не вміє докачувати — почати знову
      await for (final c in res) {
        if (cancelled()) return false;
        await onChunk(c);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

/// Стан ШІ-розпізнавача на телефоні.
class AiModelState {
  const AiModelState({
    this.checked = false,
    this.installed,
    this.remote,
    this.downloading = false,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.error,
  });

  final bool checked;

  /// Встановлена (перевірена sha256) версія; `null` — моделі на телефоні немає.
  final AiModelManifest? installed;

  /// Що лежить у релізі; `null` — без мережі або моделі ще немає.
  final AiModelManifest? remote;
  final bool downloading;
  final int bytesDone, bytesTotal;
  final String? error;

  bool get ready => installed != null;
  bool get updateAvailable => installed != null && remote != null && remote!.version != installed!.version;

  AiModelState copyWith({
    bool? checked,
    AiModelManifest? installed,
    bool clearInstalled = false,
    AiModelManifest? remote,
    bool? downloading,
    int? bytesDone,
    int? bytesTotal,
    String? error,
    bool clearError = false,
  }) =>
      AiModelState(
        checked: checked ?? this.checked,
        installed: clearInstalled ? null : (installed ?? this.installed),
        remote: remote ?? this.remote,
        downloading: downloading ?? this.downloading,
        bytesDone: bytesDone ?? this.bytesDone,
        bytesTotal: bytesTotal ?? this.bytesTotal,
        error: clearError ? null : (error ?? this.error),
      );
}

Future<String> _sha256Of(String path) => Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());

class AiModelController extends Notifier<AiModelState> {
  bool _cancel = false;

  @override
  AiModelState build() {
    Future.microtask(refresh);
    return const AiModelState();
  }

  Future<AiModelManifest?> _local() async {
    final dir = await AiModelIo.directory();
    final f = dir == null ? null : File('${dir.path}/manifest.json');
    if (f == null || !await f.exists()) return null;
    try {
      final m = AiModelManifest.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      for (final file in m.files) {
        final p = File('${dir!.path}/${file.name}');
        if (!await p.exists() || await p.length() != file.size) return null;
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<AiModelManifest?> _remote() async {
    final raw = await AiModelIo.fetch('$kAiModelBase/manifest.json');
    if (raw == null) return null;
    try {
      return AiModelManifest.fromJson(jsonDecode(utf8.decode(raw)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    try {
      final local = await _local();
      state = state.copyWith(checked: true, installed: local, clearInstalled: local == null);
      final remote = await _remote();
      if (remote != null) state = state.copyWith(remote: remote);
    } catch (_) {
      state = state.copyWith(checked: true);
    }
  }

  /// Завантажити (або оновити) модель: докачування після обриву, перевірка sha256 кожного файлу.
  Future<void> start() async {
    if (state.downloading) return;
    _cancel = false;
    final remote = state.remote ?? await _remote();
    final dir = await AiModelIo.directory();
    if (remote == null || dir == null) {
      state = state.copyWith(error: 'Не вдалося отримати модель — перевірте інтернет.');
      return;
    }
    await dir.create(recursive: true);
    // Що вже є (і правильне) — не качаємо вдруге.
    final todo = <AiModelFile>[];
    var done = 0;
    for (final f in remote.files) {
      final p = File('${dir.path}/${f.name}');
      if (await p.exists() && await p.length() == f.size && await _sha256Of(p.path) == f.sha256) {
        done += f.size;
      } else {
        todo.add(f);
      }
    }
    state = state.copyWith(remote: remote, downloading: true, bytesDone: done, bytesTotal: remote.totalBytes, clearError: true);
    String? error;
    for (final f in todo) {
      final part = File('${dir.path}/${f.name}.part');
      var have = await part.exists() ? await part.length() : 0;
      if (have > f.size) {
        await part.delete();
        have = 0;
      }
      done += have;
      final sink = part.openWrite(mode: FileMode.append);
      var ok = false;
      try {
        ok = have == f.size ||
            await AiModelIo.stream('$kAiModelBase/${f.name}', have, (chunk) async {
              sink.add(chunk);
              done += chunk.length;
              state = state.copyWith(bytesDone: done);
            }, () => _cancel);
      } finally {
        await sink.close();
      }
      if (_cancel) break;
      if (!ok) {
        error = 'Завантаження перервалось — натисніть «Продовжити», докачається з того ж місця.';
        break;
      }
      if (await part.length() != f.size || await _sha256Of(part.path) != f.sha256) {
        await part.delete(); // пошкоджений — наступного разу заново
        error = 'Файл моделі пошкоджено під час завантаження — спробуйте ще раз.';
        break;
      }
      await part.rename('${dir.path}/${f.name}');
    }
    if (!_cancel && error == null) {
      await File('${dir.path}/manifest.json').writeAsString(jsonEncode(_manifestJson(remote)));
    }
    state = state.copyWith(downloading: false, error: error);
    await refresh();
  }

  void stop() => _cancel = true;

  Future<void> deleteModel() async {
    _cancel = true;
    final dir = await AiModelIo.directory();
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
    state = state.copyWith(clearInstalled: true, downloading: false, bytesDone: 0, clearError: true);
  }

  static Map<String, dynamic> _manifestJson(AiModelManifest m) => {
        'version': m.version,
        'image_size': m.imageSize,
        'mean': m.mean,
        'std': m.std,
        'species': m.species,
        'logit_scale': m.logitScale,
        'files': {for (final f in m.files) f.name: {'size': f.size, 'sha256': f.sha256}},
      };
}

final aiModelProvider = NotifierProvider<AiModelController, AiModelState>(AiModelController.new);
