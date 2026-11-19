import 'package:flutter/material.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/features/profile/custom_avatar.dart';

/// Аватар користувача — грибна наліпка (ADR-021 §21.7) у колі. Сервер завжди віддає наліпку;
/// інше (старий застосунок / невідоме) — «Добряк».
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.avatar, this.size = 72, this.selected = false});

  final Avatar avatar;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final parts = avatar.isCustom ? avatar.parts : kDefaultAvatarParts;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xffeef4e6),
        border: Border.all(color: selected ? const Color(0xffd97706) : AppTheme.darkGreen.withValues(alpha: 0.25), width: selected ? 3 : 1.5),
      ),
      alignment: Alignment.center,
      child: SizedBox(width: size * 0.9, height: size * 0.9, child: CustomPaint(painter: CustomAvatarPainter(parts))),
    );
  }
}
