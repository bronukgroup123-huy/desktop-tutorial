import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:flutter_client/core/app_theme.dart';

/// Спільні будівельні блоки інтерфейсу (UI-004): однакові картки, плитки й заголовки розділів на всіх
/// вкладках. Екран не малює власну «картку» чи «плитку» — бере ці.

/// Біла картка: радіус [AppTheme.radiusCard], без тіні; з [onTap] — натискається.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.color = AppTheme.surface});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// Фірмова іконка плитки (`assets/icons/tile/<name>.svg`) — у стилі іконок вкладок: кремове коло, дві зелені,
/// помаранчевий акцент. Для плиток, що є «обличчям» розділу (профіль, налаштування).
class BrandIcon extends StatelessWidget {
  const BrandIcon(this.name, {super.key, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/icons/tile/$name.svg', width: size, height: size, excludeFromSemantics: true);
}

/// Іконка плитки: у м'якому зеленому колі (небезпечна дія — у червоному).
class TileIcon extends StatelessWidget {
  const TileIcon(this.icon, {super.key, this.danger = false, this.size = 40});

  final IconData icon;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: danger ? AppTheme.tintDanger : AppTheme.tint,
        ),
        child: Icon(icon, size: size * 0.55, color: danger ? AppTheme.errorRed : AppTheme.darkGreen),
      );
}

/// Рядок-кнопка: іконка, назва, підпис, лічильник, стрілка — однаковий на всіх вкладках.
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
    this.danger = false,
    this.trailing,
    this.badge,
  });

  final IconData? icon;

  /// Власна іконка замість [icon] (аватар, кольоровий значок).
  final Widget? leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  /// Замість стрілки (перемикач, значок стану).
  final Widget? trailing;

  /// Число в кружечку (нові запити тощо).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final ink = danger ? AppTheme.errorRed : AppTheme.darkGreen;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        children: [
          leading ?? (icon == null ? const SizedBox.shrink() : TileIcon(icon!, danger: danger)),
          if (leading != null || icon != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  ),
              ],
            ),
          ),
          if (badge != null && badge! > 0)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.accentOrange, borderRadius: BorderRadius.circular(10)),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          trailing ?? (onTap == null ? const SizedBox.shrink() : const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

/// Заголовок розділу всередині екрана: Merriweather 17, жирний ([AppTheme.sectionTitle]).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(2, 20, 2, 8)});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppTheme.sectionTitle)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
