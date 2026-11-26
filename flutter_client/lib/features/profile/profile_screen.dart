import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/auth_errors.dart';
import 'package:flutter_client/core/supabase_config.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/profile_hero.dart';
import 'package:flutter_client/features/learn/learn_screen.dart';
import 'package:flutter_client/features/profile/settings_screen.dart';
import 'package:flutter_client/features/profile/trophies_view.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';
import 'package:flutter_client/core/ui.dart';

/// Вкладка «Профіль» (ADR-021 §21.2.1; вигляд — PO 2026-11-21): шапка в стилі аватарів
/// (аватар, ім'я, @нік, рівень, прогрес), вітрина трофеїв, подарунки, друзі й кнопка
/// «Налаштування» (дані без інтернету, область, акаунт). У гостя — «Створіть профіль».
/// Автори й ліцензії фото — на картці виду в Довіднику.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _openSettings(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    final guest = me == null || me.isGuest;
    return Scaffold(
      appBar: AppBar(
        title: Text('Профіль', style: AppTheme.appBarTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('profile-settings-icon'),
            tooltip: 'Налаштування',
            icon: const Icon(Icons.settings_rounded, color: AppTheme.darkGreen),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('profile-list'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (guest) const _GuestCard() else _Header(me: me),
          if (!guest) ...[
            const SizedBox(height: 16),
            const _TrophiesCard(),
            const SizedBox(height: 12),
            const _GiftsCard(),
            const SectionTitle('Друзі'),
            const _FriendsTile(),
          ],
          const SectionTitle('Ще'),
          AppTile(
            key: const ValueKey('profile-learn'),
            leading: const BrandIcon('learn'),
            title: 'Навчання',
            subtitle: 'Тести знань: бали, рівень «Грибознавець», сертифікат',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LearnScreen())),
          ),
          const SizedBox(height: 8),
          AppTile(
            key: const ValueKey('profile-settings'),
            leading: const BrandIcon('settings'),
            title: 'Налаштування',
            subtitle: guest ? 'Дані без інтернету, область' : 'Дані без інтернету, область, акаунт',
            onTap: () => _openSettings(context),
          ),
        ],
      ),
    );
  }
}

/// Шапка профілю в стилі аватарів (PO 2026-11-21): аватар 208, тло й світло — за рівнем (як
/// рамки аватарів); компактна — ім'я, @нік, рівень, знахідки й бали, прогрес.
class _Header extends ConsumerWidget {
  const _Header({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = me.level;
    final p = heroPalette(level?.id);
    return ProfileHeroBackground(
      key: const ValueKey('profile-header'),
      levelId: level?.id,
      glowCenterY: 0.32,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Дотик по аватару — вибір готового аватара.
            Center(
              child: GestureDetector(
                key: const ValueKey('profile-avatar'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AvatarPickerScreen())),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(avatar: me.avatar, size: 208),
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.darkGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.accent, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6)],
                        ),
                        child: const Icon(Icons.edit_rounded, size: 15, color: heroCream),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              me.name ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppTheme.serif, fontSize: 20, fontWeight: FontWeight.bold, color: heroCream, shadows: const [Shadow(color: Colors.black54, blurRadius: 6)]),
            ),
            if (me.handle != null)
              Text('@${me.handle}', key: const ValueKey('profile-handle'), textAlign: TextAlign.center, style: TextStyle(color: heroCream.withValues(alpha: 0.75), fontSize: 13)),
            const SizedBox(height: 8),
            // Рівень, підтверджені знахідки й бали — одним рядком.
            Wrap(
              key: const ValueKey('profile-stats'),
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                if (level != null) LevelBadge(key: const ValueKey('profile-level'), levelId: level.id, label: level.label),
                HeroStat(icon: Icons.verified_rounded, value: '${me.totalVerifiedPicks}', label: _plural(me.totalVerifiedPicks, 'знахідка', 'знахідки', 'знахідок'), accent: p.accent),
                HeroStat(icon: Icons.star_rounded, value: '${me.rating}', label: _plural(me.rating, 'бал', 'бали', 'балів'), accent: p.accent),
              ],
            ),
            if (level != null) ...[
              const SizedBox(height: 10),
              HeroProgress(value: level.progress(me.rating), label: level.progressLabel, accent: p.accent),
            ],
          ],
        ),
      ),
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

/// Вітрина трофеїв-медальйонів (ADR-021 §21.2.2, §21.10): рахує сервер; дотик — за що й скільки.
class _TrophiesCard extends StatelessWidget {
  const _TrophiesCard();

  @override
  Widget build(BuildContext context) => const TrophyShowcase(
        key: ValueKey('profile-trophies'),
        child: TrophiesSection(onDark: true),
      );
}

/// Подарунки від друзів — B9.6 (поки «скоро»).
class _GiftsCard extends StatelessWidget {
  const _GiftsCard();

  @override
  Widget build(BuildContext context) => AppTile(
        key: const ValueKey('profile-gifts'),
        leading: const BrandIcon('gift'),
        title: 'Подарунки',
        subtitle: 'Тут будуть подарунки від друзів',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.darkGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.darkGreen.withValues(alpha: 0.2)),
          ),
          child: const Text('скоро', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
        ),
      );
}

/// «Друзі» — скільки друзів і нових запитів (із сервера); без інтернету — просто вхід.
class _FriendsTile extends ConsumerWidget {
  const _FriendsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(friendsProvider).valueOrNull;
    final subtitle = f == null
        ? 'Пошук за @ніком, запити в друзі'
        : [
            if (f.incoming.isNotEmpty) 'Нових запитів: ${f.incoming.length}',
            f.friends.isEmpty ? 'Знайдіть друзів за @ніком' : 'Друзів: ${f.friends.length}',
          ].join(' · ');
    return AppTile(
      key: const ValueKey('profile-friends'),
      leading: const BrandIcon('friends'),
      title: 'Друзі',
      subtitle: subtitle,
      badge: f?.incoming.length,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
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
    return ProfileHeroBackground(
      key: const ValueKey('profile-guest'),
      glowCenterY: 0.2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Перший «Мандрівник» — яким буде аватар після входу.
          const Center(child: UserAvatar(avatar: Avatar(), size: 160)),
          const SizedBox(height: 8),
          Text('Створіть профіль', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.serif, fontSize: 20, fontWeight: FontWeight.bold, color: heroCream)),
          const SizedBox(height: 10),
          for (final t in const [
            'Ім\'я, нік і свій грибний аватар — 40 героїв за рівнями',
            'Друзі й Наглядач у поході',
            'Рейтинг, рівні, трофеї й публічні точки',
            'Ваші точки й ділянки збережуться',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: heroGold),
                const SizedBox(width: 8),
                Expanded(child: Text(t, style: const TextStyle(color: heroCream))),
              ]),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('profile-google'),
            onPressed: () => _google(context, ref),
            icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
            label: const Text('Увійти через Google'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentOrange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('profile-apple'),
            onPressed: () => showToast(context, 'Вхід через Apple — скоро'),
            icon: const Icon(Icons.apple_rounded),
            label: const Text('Увійти через Apple'),
            style: OutlinedButton.styleFrom(foregroundColor: heroCream, side: BorderSide(color: heroCream.withValues(alpha: 0.6))),
          ),
        ],
        ),
      ),
    );
  }
}

