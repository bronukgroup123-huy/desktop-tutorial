import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_offline.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/profile_setup_screen.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart' show trailGraphProvider;
import 'package:flutter_client/core/ui.dart';

/// «Налаштування» з профілю (PO 2026-11-21): дані без інтернету, область, мої дані (експорт), акаунт
/// (ім'я й нік, аватар, вийти, видалити). У гостя — дані без інтернету, область і експорт.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    final guest = me == null || me.isGuest;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Налаштування', style: AppTheme.appBarTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        key: const ValueKey('settings-list'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionTitle('Дані без інтернету'),
          const _OfflineGroup(),
          const SectionTitle('Область'),
          AppTile(
            key: const ValueKey('profile-region'),
            leading: const BrandIcon('region'),
            title: me?.homeRegion?.name ?? 'Область не вибрано',
            subtitle: me?.regionChange.reasonLabel ?? '',
          ),
          const SectionTitle('Мої дані'),
          const _ExportTile(),
          if (!guest) ...[
            const SectionTitle('Акаунт'),
            AppTile(
              key: const ValueKey('settings-identity'),
              leading: const BrandIcon('id_card'),
              title: 'Ім\'я й нік',
              subtitle: [me.name ?? '', if (me.handle != null) '@${me.handle}'].where((x) => x.isNotEmpty).join(' · '),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditIdentityScreen())),
            ),
            const SizedBox(height: 8),
            AppTile(
              key: const ValueKey('settings-avatar'),
              leading: const BrandIcon('avatar'),
              title: 'Аватар',
              subtitle: 'Готові аватари за рівнями',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AvatarPickerScreen())),
            ),
            const SizedBox(height: 8),
            AppTile(
              key: const ValueKey('profile-sign-out'),
              leading: const BrandIcon('logout'),
              title: 'Вийти',
              onTap: () {
                Navigator.of(context).pop();
                ref.read(authRepositoryProvider).signOut();
              },
            ),
            const SizedBox(height: 8),
            AppTile(
              key: const ValueKey('profile-delete'),
              leading: const BrandIcon('delete'),
              title: 'Видалити акаунт',
              subtitle: 'Назавжди: профіль, точки, ділянки, рейтинг',
              danger: true,
              onTap: () async {
                if (await _confirmDelete(context, ref) && context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Як віддати файл експорту людині: зберегти в тимчасову папку й відкрити «Поділитися» (Файли, Диск,
/// пошта). Провайдер — щоб тести не відкривали системне вікно.
final exportSharerProvider = Provider<Future<void> Function(String fileName, String content)>((ref) => (name, content) async {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(content, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Мої дані з Грибного Радара',
      ));
    });

/// «Завантажити мої дані» (GDPR, B6.1): усе, що сервер зберігає про людину, — одним файлом.
class _ExportTile extends ConsumerStatefulWidget {
  const _ExportTile();

  @override
  ConsumerState<_ExportTile> createState() => _ExportTileState();
}

class _ExportTileState extends ConsumerState<_ExportTile> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(meRepositoryProvider).exportData();
      await ref.read(exportSharerProvider)(file.fileName, file.content);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося підготувати файл. Спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppTile(
        key: const ValueKey('settings-export'),
        leading: const BrandIcon('export'),
        title: 'Завантажити мої дані',
        subtitle: _busy ? 'Готуємо файл…' : 'Профіль, точки, ділянки, походи — одним файлом',
        trailing: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
            : null,
        onTap: _busy ? null : _export,
      );
}

Future<bool> _confirmDelete(BuildContext context, WidgetRef ref) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('delete-confirm'),
      title: const Text('Видалити акаунт назавжди?'),
      content: const Text(
        'Буде видалено профіль, нік, приватні й публічні точки, ділянки, рейтинг і рівень. '
        'Відновити це неможливо.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Скасувати')),
        FilledButton(
          key: const ValueKey('delete-yes'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('Видалити'),
        ),
      ],
    ),
  );
  if (yes != true) return false;
  try {
    await ref.read(meProvider.notifier).deleteAccount();
    return true;
  } catch (_) {
    if (context.mounted) showToast(context, 'Не вдалося видалити акаунт. Перевірте інтернет і спробуйте ще раз.', isError: true);
    return false;
  }
}

/// «Офлайн дані» — кнопка з підсумком (скільки з чотирьох уже на телефоні й скільки місця);
/// натиснули — розгортається список: карта, стежки, фото довідника, ШІ.
class _OfflineGroup extends ConsumerStatefulWidget {
  const _OfflineGroup();

  @override
  ConsumerState<_OfflineGroup> createState() => _OfflineGroupState();
}

class _OfflineGroupState extends ConsumerState<_OfflineGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final slug = ref.watch(meProvider.select((m) => m.valueOrNull?.homeRegion?.slug));
    final map = slug == null ? null : ref.watch(localBasemapProvider(slug)).valueOrNull;
    final trails = slug == null ? null : ref.watch(_trailsMetaProvider(slug)).valueOrNull;
    final photos = ref.watch(catalogOfflineProvider);
    final ai = ref.watch(aiModelProvider);
    final ready = [map != null, trails != null, photos.complete, ai.ready].where((x) => x).length;
    final bytes = (map?.meta.bytes ?? 0) + (trails ?? 0) + photos.savedBytes + (ai.installed?.totalBytes ?? 0);
    final summary = '$ready з 4 на телефоні${bytes > 0 ? ' · ${_OfflineData.mb(bytes)}' : ''}';
    return Column(
      children: [
        AppTile(
          key: const ValueKey('profile-offline'),
          leading: BrandIcon(ready == 4 ? 'offline_ready' : 'offline'),
          title: 'Офлайн дані',
          subtitle: summary,
          trailing: AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more_rounded, color: AppTheme.darkGreen),
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open ? const Padding(padding: EdgeInsets.only(top: 8), child: _OfflineData()) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Що лежить на телефоні для роботи без інтернету — з розміром; оновити / видалити.
class _OfflineData extends ConsumerWidget {
  const _OfflineData();

  static String mb(int bytes) {
    final v = bytes / (1024 * 1024);
    return v >= 10 ? '${v.round()} МБ' : '${v.toStringAsFixed(1).replaceAll('.', ',')} МБ';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = ref.watch(meProvider.select((m) => m.valueOrNull?.homeRegion?.slug));
    final map = slug == null ? null : ref.watch(localBasemapProvider(slug)).valueOrNull;
    final trails = slug == null ? null : ref.watch(_trailsMetaProvider(slug)).valueOrNull;
    final photos = ref.watch(catalogOfflineProvider);
    final ai = ref.watch(aiModelProvider);

    Future<void> remove(String what, Future<void> Function() action) async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Видалити $what з телефону?'),
          content: const Text('Без інтернету цього не буде, доки не завантажите знову.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Скасувати')),
            FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Видалити')),
          ],
        ),
      );
      if (yes == true) await action();
    }

    return Column(
      children: [
        _DataRow(
          key: const ValueKey('data-map'),
          brand: 'map',
          title: 'Офлайн карта області',
          status: map == null ? 'Не завантажено' : mb(map.meta.bytes),
          ready: map != null,
          onGet: () => context.go('/map'),
          onDelete: map == null || slug == null
              ? null
              : () => remove('офлайн-карту', () async {
                    await ref.read(basemapRepositoryProvider).delete(slug);
                    ref.invalidate(localBasemapProvider(slug));
                  }),
        ),
        _DataRow(
          key: const ValueKey('data-trails'),
          brand: 'route',
          title: 'Стежки для «Додому»',
          status: trails == null ? 'Завантажуються разом з картою' : mb(trails),
          ready: trails != null,
          onGet: () => context.go('/map'),
          onDelete: trails == null || slug == null
              ? null
              : () => remove('стежки', () async {
                    await ref.read(trailsRepositoryProvider).delete(slug);
                    ref.invalidate(_trailsMetaProvider(slug));
                    ref.invalidate(trailGraphProvider(slug));
                  }),
        ),
        _DataRow(
          key: const ValueKey('data-photos'),
          brand: 'photos',
          title: 'Фото довідника',
          status: photos.complete ? mb(photos.savedBytes) : (photos.saved > 0 ? '${photos.saved} з ${photos.total} · ${mb(photos.savedBytes)}' : 'Не завантажено'),
          ready: photos.complete,
          onGet: () => context.go('/recognize'),
          onDelete: photos.saved == 0 ? null : () => remove('фото довідника', () => ref.read(catalogOfflineProvider.notifier).deleteAll()),
        ),
        _DataRow(
          key: const ValueKey('data-ai'),
          brand: 'ai',
          title: 'ШІ-розпізнавання',
          status: ai.installed == null ? 'Не завантажено' : mb(ai.installed!.totalBytes),
          ready: ai.ready,
          onGet: () => context.go('/recognize'),
          onDelete: ai.installed == null ? null : () => remove('модель ШІ', () => ref.read(aiModelProvider.notifier).deleteModel()),
        ),
      ],
    );
  }
}

/// Розмір файлу стежок області на телефоні; `null` — немає.
final _trailsMetaProvider = FutureProvider.autoDispose.family<int?, String>(
  (ref, slug) async => (await ref.watch(trailsRepositoryProvider).localMeta(slug))?.bytes,
);

class _DataRow extends StatelessWidget {
  const _DataRow({super.key, required this.brand, required this.title, required this.status, required this.ready, required this.onGet, this.onDelete});

  /// Фірмова іконка (assets/icons/tile/).
  final String brand;
  final String title;
  final String status;
  final bool ready;
  final VoidCallback onGet;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
              children: [
                BrandIcon(brand, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                      Row(children: [
                        Icon(ready ? Icons.check_circle_rounded : Icons.cloud_download_outlined, size: 14, color: ready ? AppTheme.success : AppTheme.warning),
                        const SizedBox(width: 4),
                        Flexible(child: Text(status, style: TextStyle(fontSize: 13, color: AppTheme.textMuted))),
                      ]),
                    ],
                  ),
                ),
                if (!ready) TextButton(onPressed: onGet, child: const Text('Завантажити')),
                if (onDelete != null) IconButton(tooltip: 'Видалити з телефону', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
              ],
            ),
        ),
      );
}

