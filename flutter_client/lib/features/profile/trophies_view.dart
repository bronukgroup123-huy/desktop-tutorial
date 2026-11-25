import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/models/trophies.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/profile/profile_hero.dart';

/// Медальйон-трофей: картинка з `assets/trophies`; ще не отримано — блідий, сірий, із замочком.
class TrophyBadge extends StatelessWidget {
  const TrophyBadge({super.key, required this.id, required this.earned, this.size = 62, this.large = false});

  final String id;
  final bool earned;
  final double size;
  final bool large;

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      'assets/trophies/${large ? 'large' : 'small'}/$id.webp',
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xffe4e6e1)),
        child: Icon(Icons.emoji_events_rounded, size: size * 0.4, color: const Color(0xffa7aca2)),
      ),
    );
    if (earned) return img;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Opacity(opacity: 0.55, child: ColorFiltered(colorFilter: _grey, child: img)),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(size * 0.05),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.lock_rounded, size: size * 0.2, color: const Color(0xff8d928a)),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Трофеї» у профілі: ряд медальйонів (отримані — згори), «N з 24», дотик — за що й скільки.
class TrophiesSection extends ConsumerWidget {
  const TrophiesSection({super.key, this.onDark = false});

  /// На темній вітрині профілю — світлі підписи й сяйво за отриманими.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trophiesProvider);
    // Щойно отримані — підказкою (раз).
    ref.listen(trophiesProvider, (prev, next) {
      final labels = next.valueOrNull?.newLabels ?? const [];
      if (labels.isNotEmpty && prev?.valueOrNull?.newLabels != labels) showToast(context, labels.join('\n'));
    });
    final data = async.valueOrNull;
    final ink = onDark ? AppTheme.backgroundColor : AppTheme.darkGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onDark) ...[
              const Icon(Icons.emoji_events_rounded, size: 20, color: Color(0xFFF9C66B)),
              const SizedBox(width: 6),
            ],
            Text('Трофеї', style: TextStyle(fontWeight: FontWeight.w800, fontSize: onDark ? 15.5 : 14, color: ink, shadows: onDark ? _woodShadow : null)),
            const Spacer(),
            if (data != null)
              Text('${data.earnedCount} з ${data.total}',
                  key: const ValueKey('profile-trophies-count'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: onDark ? const Color(0xFFF9C66B) : AppTheme.darkGreen.withValues(alpha: 0.7))),
          ],
        ),
        const SizedBox(height: 10),
        if (data == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              async.isLoading ? 'Завантажуємо трофеї…' : 'Трофеї покажемо, щойно з\'явиться інтернет',
              style: TextStyle(fontSize: 12.5, color: ink.withValues(alpha: 0.6)),
            ),
          )
        else
          TrophyShelfRow(
            key: const ValueKey('profile-trophies-list'),
            onDark: onDark,
            items: [
              for (final t in data.trophies)
                (id: t.id, title: t.title, earned: t.earned, progressLabel: t.progressLabel, onTap: () => showTrophySheet(context, t)),
            ],
          ),
      ],
    );
  }
}

const _woodShadow = [Shadow(color: Color(0xAA2B180A), blurRadius: 4, offset: Offset(0, 1))];

typedef TrophyShelfItem = ({String id, String title, bool earned, String? progressLabel, VoidCallback? onTap});

/// Ряд медальйонів. На дубовій поличці ([onDark]) медальйони стоять на полиці, отримані
/// сяють, підписи — світлі з тінню; інакше — просто ряд.
class TrophyShelfRow extends StatelessWidget {
  const TrophyShelfRow({super.key, required this.items, this.onDark = false});

  final List<TrophyShelfItem> items;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? AppTheme.backgroundColor : AppTheme.darkGreen;
    const badge = 64.0;
    final list = ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, i) {
        final t = items[i];
        return InkWell(
          key: ValueKey('trophy-${t.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: t.onTap,
          child: SizedBox(
            width: 72,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: onDark && t.earned
                      ? BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFF9C66B).withValues(alpha: 0.5), blurRadius: 16)])
                      : const BoxDecoration(),
                  child: TrophyBadge(id: t.id, earned: t.earned, size: badge),
                ),
                SizedBox(height: onDark ? 20 : 4), // на поличці підпис — під дошкою
                Text(t.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.15,
                      fontWeight: t.earned ? FontWeight.w700 : FontWeight.w500,
                      color: ink.withValues(alpha: t.earned ? 0.95 : 0.7),
                      shadows: onDark ? _woodShadow : null,
                    )),
                if (!t.earned && t.progressLabel != null)
                  Text(t.progressLabel!,
                      style: TextStyle(fontSize: 10.5, color: onDark ? const Color(0xFFFFD98A) : AppTheme.warning, fontWeight: FontWeight.w700, shadows: onDark ? _woodShadow : null)),
              ],
            ),
          ),
        );
      },
    );
    // Звичайно 112 / 128 px; з великим шрифтом ряд росте під дворядковий підпис і прогрес (UI-001c).
    final scaler = MediaQuery.textScalerOf(context);
    final progress = items.any((t) => !t.earned && t.progressLabel != null) ? scaler.scale(10.5) * 1.25 : 0.0;
    final needed = badge + (onDark ? 20 : 4) + scaler.scale(11) * 1.15 * 2 + progress + 4;
    if (!onDark) return SizedBox(height: math.max(112, needed), child: list);
    // Полиця на всю ширину; медальйони стоять на її верхній грані.
    return SizedBox(
      height: math.max(128, needed),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(left: -12, right: -12, top: badge - 6, child: OakShelfPlank()),
          list,
        ],
      ),
    );
  }
}

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Картка трофея: великий медальйон, метал, за що й скільки, прогрес або дата отримання.
Future<void> showTrophySheet(BuildContext context, Trophy t) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          key: const ValueKey('trophy-sheet'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrophyBadge(id: t.id, earned: t.earned, size: 200, large: true),
              const SizedBox(height: 14),
              Text(t.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
              const SizedBox(height: 2),
              Text(t.tierLabel, style: TextStyle(fontWeight: FontWeight.w700, color: _tierColor(t.tier))),
              const SizedBox(height: 12),
              Text(t.howLabel, key: const ValueKey('trophy-how'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.35)),
              const SizedBox(height: 14),
              if (t.earned && t.earnedAt != null)
                Text('Отримано ${_date(t.earnedAt!)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w700))
              else if (t.soon)
                Text('Скоро — з\'явиться разом із новою функцією', style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.6)))
              else if (t.progressLabel != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: t.progress,
                    minHeight: 8,
                    color: AppTheme.accentOrange,
                    backgroundColor: AppTheme.accentOrange.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 6),
                Text(t.progressLabel!, key: const ValueKey('trophy-progress'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.warning)),
              ] else
                Text('Ще не отримано', style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );

Color _tierColor(String tier) => switch (tier) {
      'gold' => const Color(0xffb7860b),
      'silver' => const Color(0xff7d878e),
      _ => const Color(0xff9c5a2b),
    };
