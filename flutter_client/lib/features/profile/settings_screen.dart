import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_offline.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/profile_hero.dart';
import 'package:flutter_client/features/profile/profile_setup_screen.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart' show trailGraphProvider;

/// «Налаштування» з профілю (PO 2026-11-21): дані без інтернету, область, акаунт (ім'я й нік,
/// аватар, вийти, видалити). У гостя — лише дані без інтернету й область.
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
          const ProfileSectionTitle('Дані без інтернету'),
          const _OfflineGroup(),
          const ProfileSectionTitle('Область'),
          ParchmentTile(
            key: const ValueKey('profile-region'),
            icon: Icons.place_rounded,
            title: me?.homeRegion?.name ?? 'Область не вибрано',
            subtitle: me?.regionChange.reasonLabel ?? '',
          ),
          if (!guest) ...[
            const ProfileSectionTitle('Акаунт'),
            ParchmentTile(
              key: const ValueKey('settings-identity'),
              icon: Icons.badge_rounded,
              title: 'Ім\'я й нік',
              subtitle: [me.name ?? '', if (me.handle != null) '@${me.handle}'].where((x) => x.isNotEmpty).join(' · '),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditIdentityScreen())),
            ),
            const SizedBox(height: 8),
            ParchmentTile(
              key: const ValueKey('settings-avatar'),
              icon: Icons.face_retouching_natural_rounded,
              title: 'Аватар',
              subtitle: 'Готові аватари за рівнями',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AvatarPickerScreen())),
            ),
            const SizedBox(height: 8),
            ParchmentTile(
              key: const ValueKey('profile-sign-out'),
              icon: Icons.logout_rounded,
              title: 'Вийти',
              onTap: () {
                Navigator.of(context).pop();
                ref.read(authRepositoryProvider).signOut();
              },
            ),
            const SizedBox(height: 8),
            ParchmentTile(
              key: const ValueKey('profile-delete'),
              icon: Icons.delete_forever_rounded,
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
        ParchmentTile(
          key: const ValueKey('profile-offline'),
          icon: ready == 4 ? Icons.offline_pin_rounded : Icons.cloud_download_rounded,
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
          icon: Icons.map_rounded,
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
          icon: Icons.alt_route_rounded,
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
          icon: Icons.photo_library_rounded,
          title: 'Фото довідника',
          status: photos.complete ? mb(photos.savedBytes) : (photos.saved > 0 ? '${photos.saved} з ${photos.total} · ${mb(photos.savedBytes)}' : 'Не завантажено'),
          ready: photos.complete,
          onGet: () => context.go('/recognize'),
          onDelete: photos.saved == 0 ? null : () => remove('фото довідника', () => ref.read(catalogOfflineProvider.notifier).deleteAll()),
        ),
        _DataRow(
          key: const ValueKey('data-ai'),
          icon: Icons.psychology_rounded,
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
  const _DataRow({super.key, required this.icon, required this.title, required this.status, required this.ready, required this.onGet, this.onDelete});

  final IconData icon;
  final String title;
  final String status;
  final bool ready;
  final VoidCallback onGet;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ParchmentCard(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          radius: 14,
          child: Row(
              children: [
                Icon(icon, color: AppTheme.darkGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                      Row(children: [
                        Icon(ready ? Icons.check_circle_rounded : Icons.cloud_download_outlined, size: 14, color: ready ? AppTheme.success : AppTheme.warning),
                        const SizedBox(width: 4),
                        Flexible(child: Text(status, style: TextStyle(fontSize: 12.5, color: AppTheme.darkGreen.withValues(alpha: 0.75)))),
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

