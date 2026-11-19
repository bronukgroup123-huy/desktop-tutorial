import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/supabase_config.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/core/auth_errors.dart';
import 'package:flutter_client/features/catalog/catalog_offline.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/profile_setup_screen.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart' show trailGraphProvider;

/// Вкладка «Профіль» (ADR-021 §21.2.1): шапка (аватар, ім'я, @нік, рівень), мій сезон, дані без
/// інтернету, налаштування, акаунт (вийти, видалити). У гостя — «Увійти через Google / Apple» і що
/// дає акаунт. Автори й ліцензії фото — на картці виду в Довіднику.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    final guest = me == null || me.isGuest;
    return Scaffold(
      appBar: AppBar(
        title: Text('Профіль', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        key: const ValueKey('profile-list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (guest) const _GuestCard() else _Header(me: me),
          if (!guest) ...[
            const _Section('Мій сезон'),
            _SeasonCard(me: me),
            const _Section('Друзі'),
            const _Tile(
              key: ValueKey('profile-friends'),
              icon: Icons.group_rounded,
              title: 'Друзі й Наглядач',
              subtitle: 'Скоро: пошук за ніком, запити в друзі, Наглядач у поході',
            ),
          ],
          const _Section('Дані без інтернету'),
          const _OfflineData(),
          const _Section('Налаштування'),
          _Tile(
            key: const ValueKey('profile-region'),
            icon: Icons.place_rounded,
            title: me?.homeRegion?.name ?? 'Область не вибрано',
            subtitle: me?.regionChange.reasonLabel ?? '',
          ),
          if (!guest) ...[
            const _Section('Акаунт'),
            _Tile(
              key: const ValueKey('profile-sign-out'),
              icon: Icons.logout_rounded,
              title: 'Вийти',
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
            const SizedBox(height: 8),
            _Tile(
              key: const ValueKey('profile-delete'),
              icon: Icons.delete_forever_rounded,
              title: 'Видалити акаунт',
              subtitle: 'Назавжди: профіль, точки, ділянки, рейтинг',
              danger: true,
              onTap: () => _confirmDelete(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
            style: FilledButton.styleFrom(backgroundColor: const Color(0xffc62828)),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(meProvider.notifier).deleteAccount();
    } catch (_) {
      if (context.mounted) showToast(context, 'Не вдалося видалити акаунт. Перевірте інтернет і спробуйте ще раз.', isError: true);
    }
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = me.level;
    return Container(
      key: const ValueKey('profile-header'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                key: const ValueKey('profile-avatar'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AvatarPickerScreen())),
                child: Stack(
                  children: [
                    UserAvatar(avatar: me.avatar, size: 76),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: AppTheme.darkGreen, shape: BoxShape.circle),
                        child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me.name ?? '', style: GoogleFonts.merriweather(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
                    if (me.handle != null) Text('@${me.handle}', key: const ValueKey('profile-handle'), style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.7))),
                    if (level != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(level.label, key: const ValueKey('profile-level'), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xffb45309))),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('profile-edit'),
                tooltip: 'Змінити ім\'я й нік',
                icon: const Icon(Icons.edit_note_rounded, color: AppTheme.darkGreen),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditIdentityScreen())),
              ),
            ],
          ),
          if (level != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: level.progress(me.rating),
                minHeight: 8,
                color: const Color(0xffd97706),
                backgroundColor: const Color(0xffd97706).withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 6),
            Text(level.progressLabel, style: TextStyle(fontSize: 12.5, color: AppTheme.darkGreen.withValues(alpha: 0.75))),
          ],
        ],
      ),
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.darkGreen)),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.7))),
            ],
          ),
        );
    return Container(
      key: const ValueKey('profile-season'),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [stat('${me.totalVerifiedPicks}', 'підтверджених\nзнахідок'), stat('${me.rating}', 'балів\nрейтингу')]),
    );
  }
}

/// Гість: що дає акаунт і вхід через Google / Apple (дані гостя переносяться).
class _GuestCard extends ConsumerWidget {
  const _GuestCard();

  Future<void> _google(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authRepositoryProvider).linkGoogle(redirectTo: kIsWeb ? Uri.base.origin : SupabaseConfig.authRedirectUrl);
    } catch (e) {
      if (context.mounted) showToast(context, authErrorMessage(e, action: 'увійти через Google'), isError: true);
    }
  }

  /// Google уже має свій акаунт: прив'язати до гостя не можна — увійти в той акаунт.
  Future<void> _offerExisting(BuildContext context, WidgetRef ref) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('google-taken'),
        title: const Text('Цей Google уже має профіль'),
        content: const Text(
          'З цим Google-акаунтом ви вже входили раніше. Увійти в той профіль?\n\n'
          'Точки й ділянки, збережені зараз у гостьовому режимі, туди не перенесуться.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Скасувати')),
          FilledButton(key: const ValueKey('google-taken-signin'), onPressed: () => Navigator.of(c).pop(true), child: const Text('Увійти в нього')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle(redirectTo: kIsWeb ? Uri.base.origin : SupabaseConfig.authRedirectUrl);
    } catch (e) {
      if (context.mounted) showToast(context, authErrorMessage(e, action: 'увійти через Google'), isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Повернення зі сторінки Google з помилкою приходить у потік стану входу — показати її,
    // а не мовчки лишитися гостем.
    ref.listen(authStateProvider, (_, next) {
      final e = next.error;
      if (e == null || !context.mounted) return;
      if (isIdentityTaken(e)) {
        _offerExisting(context, ref);
      } else {
        showToast(context, authErrorMessage(e, action: 'увійти через Google'), isError: true);
      }
    });
    return Container(
      key: const ValueKey('profile-guest'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Створіть профіль', style: GoogleFonts.merriweather(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
          const SizedBox(height: 8),
          for (final t in const [
            'Ім\'я, нік і свій грибний аватар',
            'Друзі й Наглядач у поході',
            'Рейтинг, рівні й публічні точки',
            'Ваші точки й ділянки збережуться',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xff2e7d32)),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
              ]),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('profile-google'),
            onPressed: () => _google(context, ref),
            icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
            label: const Text('Увійти через Google'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('profile-apple'),
            onPressed: () => showToast(context, 'Вхід через Apple — скоро'),
            icon: const Icon(Icons.apple_rounded),
            label: const Text('Увійти через Apple'),
          ),
        ],
      ),
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
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
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
                        Icon(ready ? Icons.check_circle_rounded : Icons.cloud_download_outlined, size: 14, color: ready ? const Color(0xff2e7d32) : const Color(0xffb45309)),
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
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(title, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.danger = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xffc62828) : AppTheme.darkGreen;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
        trailing: onTap == null ? null : Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.6)),
        onTap: onTap,
      ),
    );
  }
}
