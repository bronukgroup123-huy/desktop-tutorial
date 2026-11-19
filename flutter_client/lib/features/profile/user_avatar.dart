import 'package:flutter/material.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/features/profile/custom_avatar.dart';
import 'package:flutter_client/features/profile/sticker_image.dart';

/// Аватар користувача — грибна наліпка (ADR-021 §21.7) у колі. Сервер завжди віддає наліпку;
/// інше (старий застосунок / невідоме) — «Добряк».
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.avatar, this.size = 72, this.selected = false, this.dimmed = false});

  final Avatar avatar;
  final double size;
  final bool selected;

  /// Закрита деталь — бліда (без шару прозорості: так дешевше при прокрутці).
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final parts = avatar.isCustom ? avatar.parts : kDefaultAvatarParts;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dimmed ? const Color(0xfff6f8f2) : const Color(0xffeef4e6),
        border: Border.all(color: selected ? const Color(0xffd97706) : AppTheme.darkGreen.withValues(alpha: 0.25), width: selected ? 3 : 1.5),
      ),
      alignment: Alignment.center,
      child: StickerImage(parts, size: size * 0.9, opacity: dimmed ? 0.35 : 1),
    );
  }
}
