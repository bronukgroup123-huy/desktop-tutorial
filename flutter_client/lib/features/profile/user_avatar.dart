import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/me.dart';

/// Аватар користувача (ADR-021 §21.7, PO 2026-11-21): готова картинка з рамкою рівня
/// `assets/avatars/<id>.webp` (без фону; роги й корона виступають за коло — не обрізаємо).
/// Якщо картинки в застосунку немає (новіша за реліз) — перший «Мандрівник», а без нього —
/// силует грибника в колі.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.avatar, this.size = 72});

  final Avatar avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
    Widget image(String asset, ImageErrorWidgetBuilder onError) =>
        Image.asset(asset, width: size, height: size, fit: BoxFit.contain, cacheWidth: cache, errorBuilder: onError);
    return SizedBox(
      width: size,
      height: size,
      child: image(
        avatar.asset,
        (_, __, ___) => avatar.id == Avatar.defaultId ? _Placeholder(size) : image(const Avatar().asset, (_, __, ___) => _Placeholder(size)),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.size);

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('avatar-placeholder'),
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.16),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xffeef4e6),
          border: Border.all(color: AppTheme.darkGreen.withValues(alpha: 0.25), width: 1.5),
        ),
        child: SvgPicture.asset('assets/icons/ic_profile.svg', fit: BoxFit.contain),
      );
}
