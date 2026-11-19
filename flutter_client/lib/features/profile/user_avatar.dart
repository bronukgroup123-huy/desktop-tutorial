import 'package:flutter/material.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/features/catalog/mushroom_character.dart';

/// 20 стандартних аватарів (ADR-021 §21.7) — гриби-персонажі Топ-20 довідника, статичні.
/// Номер аватара на сервері: 1…20 у цьому порядку.
final List<String> kStandardAvatarSpecies = kCharacterLooks.keys.toList(growable: false);

/// Емоція стандартного аватара — щоб гриби різнилися не лише формою.
Face _faceFor(int id) => switch (id % 4) {
      0 => const Face(eyes: Eyes.happy, mouth: Mouth.grin, blush: true),
      1 => const Face(),
      2 => const Face(eyes: Eyes.wink, mouth: Mouth.grin),
      _ => const Face(eyes: Eyes.wide, mouth: Mouth.o, brows: 1),
    };

/// Аватар користувача в колі.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.avatar, this.size = 72, this.selected = false});

  final Avatar avatar;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final id = avatar.id.clamp(1, kStandardAvatarSpecies.length);
    final look = kCharacterLooks[kStandardAvatarSpecies[id - 1]]!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xffeef4e6),
        border: Border.all(color: selected ? const Color(0xffd97706) : AppTheme.darkGreen.withValues(alpha: 0.25), width: selected ? 3 : 1.5),
      ),
      alignment: Alignment.center,
      child: MushroomCharacter(look: look, face: _faceFor(id), size: size * 0.82),
    );
  }
}
