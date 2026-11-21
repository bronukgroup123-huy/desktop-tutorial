import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/me.dart';

/// Аватар користувача у колі (ADR-021 §21.7, PO 2026-11-21): готова картинка
/// `assets/avatars/<id>.webp`; поки її немає (`default` чи новіший за застосунок) — силует
/// грибника, як на вкладці «Профіль». Конструктора більше немає.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.avatar, this.size = 72});

  final Avatar avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Padding(
      padding: EdgeInsets.all(size * 0.16),
      child: SvgPicture.asset('assets/icons/ic_profile.svg', key: const ValueKey('avatar-placeholder'), fit: BoxFit.contain),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xffeef4e6),
        border: Border.all(color: AppTheme.darkGreen.withValues(alpha: 0.25), width: 1.5),
      ),
      child: avatar.isDefault
          ? placeholder
          : Image.asset(
              'assets/avatars/${avatar.id}.webp',
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
