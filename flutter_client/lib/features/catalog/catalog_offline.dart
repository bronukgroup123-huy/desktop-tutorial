import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';

/// Середній розмір архіву виду — для оцінки, поки manifest.json недоступний (немає мережі).
const _avgBundleBytes = 540 * 1024;
const _thumbsBundle = 'thumbs.tar';

/// Стан «Фото без інтернету».
class CatalogOfflineState {
  const CatalogOfflineState({
    this.checked = false,
    this.total = 0,
    this.saved = 0,
    this.thumbsSaved = false,
    this.downloading = false,
    this.done = 0,
    this.planned = 0,
    this.bytesDone = 0,
    this.bytesPlanned = 0,
    this.bytesExact = false,
    this.savedBytes = 0,
    this.error,
  });

  /// Стан телефону вже перевірено.
  final bool checked;

  /// Видів у довіднику / з усіма фото на телефоні.
  final int total;
  final int saved;
  final bool thumbsSaved;

  final bool downloading;

  /// Архівів завантажено / заплановано в поточному завантаженні.
  final int done;
  final int planned;
  final int bytesDone;

  /// Скільки займе решта (за manifest.json, інакше — оцінка).
  final int bytesPlanned;
  final bool bytesExact;

  /// Скільки займають уже збережені фото.
  final int savedBytes;
  final String? error;

  bool get complete => checked && total > 0 && saved >= total && thumbsSaved;
  int get missing => total - saved;

  CatalogOfflineState copyWith({
    bool? checked,
    int? total,
    int? saved,
    bool? thumbsSaved,
    bool? downloading,
    int? done,
    int? planned,
    int? bytesDone,
    int? bytesPlanned,
    bool? bytesExact,
    int? savedBytes,
    String? error,
    bool clearError = false,
  }) =>
      CatalogOfflineState(
        checked: checked ?? this.checked,
        total: total ?? this.total,
        saved: saved ?? this.saved,
        thumbsSaved: thumbsSaved ?? this.thumbsSaved,
        downloading: downloading ?? this.downloading,
        done: done ?? this.done,
        planned: planned ?? this.planned,
        bytesDone: bytesDone ?? this.bytesDone,
        bytesPlanned: bytesPlanned ?? this.bytesPlanned,
        bytesExact: bytesExact ?? this.bytesExact,
        savedBytes: savedBytes ?? this.savedBytes,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Завантаження всіх фото довідника на телефон — щоб у лісі без зв'язку відкривався будь-який
/// гриб, а не лише вже переглянуті. Працює, поки застосунок відкритий (і при переході між
/// вкладками); зупинене чи обірване — продовжується з того ж місця.
class CatalogOfflineController extends Notifier<CatalogOfflineState> {
  bool _cancel = false;
  Map<String, int>? _sizes;

  @override
  CatalogOfflineState build() {
    Future.microtask(refresh);
    return const CatalogOfflineState();
  }

  /// Яких архівів ще бракує на телефоні.
  static List<String> missingBundles(Catalog c, Set<String> saved) => [
        if (c.species.any((s) => s.thumb != null && !saved.contains(s.thumb))) _thumbsBundle,
        for (final s in c.species)
          if (s.photos.any((p) => !saved.contains(p))) '${s.id}.tar',
      ];

  int _bytes(List<String> bundles) => bundles.fold(
      0, (a, b) => a + (_sizes?[b] ?? (b == _thumbsBundle ? 3300 * 1024 : _avgBundleBytes)));

  Future<void>? _refreshing;

  /// Перевірити, що вже на телефоні. Виклики виконуються по черзі: паралельні перевірки
  /// (під час відкриття і після завантаження) не перезаписують одна одну застарілим станом.
  Future<void> refresh() {
    // Перевірка не кидає помилок: це лише показ стану (файли можуть змінюватись під час неї).
    final next = (_refreshing ?? Future<void>.value()).then((_) => _refresh()).catchError((Object _) {});
    _refreshing = next;
    return next.whenComplete(() {
      if (identical(_refreshing, next)) _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    final Catalog c;
    try {
      c = await ref.read(catalogProvider.future);
    } catch (_) {
      return;
    }
    final saved = await CatalogPhotoCache.savedNames();
    final savedBytes = await CatalogPhotoCache.savedBytes();
    final missing = missingBundles(c, saved);
    // Стан — лише після всіх очікувань (інакше записали б значення, прочитані до них).
    state = state.copyWith(
      checked: true,
      total: c.species.length,
      saved: c.species.where((s) => s.photos.every(saved.contains)).length,
      thumbsSaved: c.species.every((s) => s.thumb == null || saved.contains(s.thumb)),
      bytesPlanned: _bytes(missing),
      bytesExact: _sizes != null,
      savedBytes: savedBytes,
    );
    // Точний розмір — з manifest.json (одним малим запитом, якщо є мережа).
    if (_sizes == null && missing.isNotEmpty && !state.downloading) {
      final sizes = await CatalogPhotoCache.manifest();
      if (sizes != null) {
        _sizes = sizes;
        state = state.copyWith(bytesPlanned: _bytes(missing), bytesExact: true);
      }
    }
  }

  Future<void> start() async {
    if (state.downloading) return;
    _cancel = false;
    // Не перетинатися з перевіркою, що ще йде (під час відкриття довідника).
    await _refreshing;
    final c = await ref.read(catalogProvider.future);
    _sizes ??= await CatalogPhotoCache.manifest();
    final queue = missingBundles(c, await CatalogPhotoCache.savedNames());
    state = state.copyWith(
      downloading: true,
      done: 0,
      planned: queue.length,
      bytesDone: 0,
      bytesPlanned: _bytes(queue),
      bytesExact: _sizes != null,
      clearError: true,
    );
    var failed = false;
    // Три архіви паралельно — швидше, ніж по одному, і не перевантажує мережу.
    Future<void> worker() async {
      while (!_cancel && !failed && queue.isNotEmpty) {
        final bundle = queue.removeAt(0);
        if (await CatalogPhotoCache.downloadBundle(bundle)) {
          state = state.copyWith(done: state.done + 1, bytesDone: state.bytesDone + _bytes([bundle]));
        } else {
          failed = true;
        }
      }
    }

    await Future.wait([worker(), worker(), worker()]);
    state = state.copyWith(
      downloading: false,
      error: failed ? 'Не вдалося завантажити — перевірте інтернет і натисніть «Продовжити».' : null,
    );
    await refresh();
  }

  void stop() => _cancel = true;

  Future<void> deleteAll() async {
    _cancel = true;
    await CatalogPhotoCache.deleteAll();
    state = state.copyWith(downloading: false, clearError: true);
    await refresh();
  }
}

final catalogOfflineProvider =
    NotifierProvider<CatalogOfflineController, CatalogOfflineState>(CatalogOfflineController.new);

String _mb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 10 ? '${mb.round()} МБ' : '${mb.toStringAsFixed(1)} МБ';
}

/// Картка вгорі довідника: «Фото без інтернету» — розмір, «Завантажити», прогрес, «Зупинити»,
/// після завантаження — тихий рядок «Усі фото на телефоні» з «Видалити».
class CatalogOfflineCard extends ConsumerWidget {
  const CatalogOfflineCard({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, String size) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити фото довідника?'),
        content: Text('Звільнить близько $size. Описи лишаться, а фото знову завантажуватимуться з інтернету.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
          TextButton(
            key: const ValueKey('offline-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(catalogOfflineProvider.notifier).deleteAll();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(catalogOfflineProvider);
    final ctrl = ref.read(catalogOfflineProvider.notifier);
    final muted = AppTheme.darkGreen.withValues(alpha: 0.7);
    if (!s.checked) return const SizedBox.shrink();

    if (s.complete && !s.downloading) {
      return Padding(
        key: const ValueKey('offline-complete'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            const Icon(Icons.offline_pin_rounded, size: 18, color: Color(0xff2e7d32)),
            const SizedBox(width: 6),
            Expanded(child: Text('Усі фото збережено — довідник працює без інтернету', style: TextStyle(fontSize: 12, color: muted))),
            TextButton(
              key: const ValueKey('offline-delete'),
              onPressed: () => _confirmDelete(context, ref, _mb(s.savedBytes)),
              style: TextButton.styleFrom(foregroundColor: muted, visualDensity: VisualDensity.compact),
              child: const Text('Видалити'),
            ),
          ],
        ),
      );
    }

    final String title;
    final String subtitle;
    if (s.downloading) {
      title = 'Завантаження фото…';
      subtitle = s.planned == 0
          ? 'Готуємо…'
          : '${s.done} з ${s.planned} · ${_mb(s.bytesDone)} з ${s.bytesExact ? '' : '≈'}${_mb(s.bytesPlanned)}';
    } else {
      title = 'Фото без інтернету';
      final size = '${s.bytesExact ? '' : '≈'}${_mb(s.bytesPlanned)}';
      subtitle = s.saved == 0
          ? 'Збережіть фото всіх грибів на телефон, щоб дивитися довідник у лісі без зв\'язку · $size'
          : 'Збережено ${s.saved} з ${s.total} видів. Решта · $size';
    }
    return Container(
      key: const ValueKey('offline-card'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(s.downloading ? Icons.downloading_rounded : Icons.cloud_download_outlined, color: AppTheme.darkGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                    Text(subtitle, key: const ValueKey('offline-subtitle'), style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              if (s.downloading) ...[
                const SizedBox(width: 6),
                TextButton(key: const ValueKey('offline-stop'), onPressed: ctrl.stop, child: const Text('Зупинити')),
              ],
            ],
          ),
          if (s.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: s.planned == 0 ? null : s.done / s.planned,
              color: AppTheme.darkGreen,
              backgroundColor: const Color(0xffe7e1d1),
              borderRadius: BorderRadius.circular(4),
            ),
          ] else ...[
            if (s.error != null) ...[
              const SizedBox(height: 6),
              Text(s.error!, key: const ValueKey('offline-error'), style: const TextStyle(fontSize: 12, color: AppTheme.errorRed)),
            ],
            const SizedBox(height: 6),
            Text('Краще через Wi‑Fi. Не закривайте застосунок до кінця завантаження.',
                style: TextStyle(fontSize: 11, color: muted)),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('offline-download'),
                onPressed: ctrl.start,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(s.saved == 0 && s.error == null ? 'Завантажити' : 'Продовжити'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
