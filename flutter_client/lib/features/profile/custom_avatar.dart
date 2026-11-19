import 'package:flutter/material.dart';

import 'package:flutter_client/features/profile/sticker_painter.dart';

/// Аватар-наліпка (ADR-021 §21.7): персонаж + капелюх, річ, ефект — статичний малюнок.
/// Каталог і замки — з сервера; тут лише як намалювати кожен id. Невідомий id (додали на
/// сервері, а застосунок старий): персонаж — «Добряк», деталь — не малюється.
typedef AvatarParts = Map<String, String?>;

const kDefaultAvatarParts = <String, String?>{'sticker': 'kind', 'hat': null, 'item': null, 'fx': null};

const _cream = Color(0xfff4ead6);

/// Персонажі-наліпки: форма, колір, емоція, поза. Порядок і замки — у серверному каталозі.
const kStickers = <String, StickerSpec>{
  // Безкоштовні.
  'kind': StickerSpec(body: SBody.round, cap: SCap.dome, capColor: Color(0xffa0673a), eyes: SEyes.normal, mouth: SMouth.smile, arms: SArms.down, fx: {SFx.blush}),
  'laugh': StickerSpec(body: SBody.round, cap: SCap.dome, capColor: Color(0xff8a5a32), eyes: SEyes.happy, mouth: SMouth.laugh, arms: SArms.wave, fx: {SFx.blush}),
  'wow': StickerSpec(body: SBody.chanterelle, cap: SCap.funnel, capColor: Color(0xfff5a623), bodyColor: Color(0xfff7c25a), eyes: SEyes.scared, mouth: SMouth.o, arms: SArms.cheeks, fx: {SFx.blush}),
  'cool': StickerSpec(body: SBody.potato, cap: SCap.dome, capColor: Color(0xff6b4226), eyes: SEyes.shades, mouth: SMouth.smirk, arms: SArms.hips, fx: {SFx.sparkle}),
  'love': StickerSpec(body: SBody.tall, cap: SCap.cone, capColor: Color(0xff7fae4e), eyes: SEyes.hearts, mouth: SMouth.smile, arms: SArms.cheeks, fx: {SFx.hearts, SFx.blush}, tilt: 0.08),
  'sleepy': StickerSpec(body: SBody.puff, cap: SCap.none, capColor: Color(0xffefe6d2), eyes: SEyes.sleepy, mouth: SMouth.o, arms: SArms.down, fx: {SFx.zzz, SFx.blush}, tilt: 0.1),
  'tease': StickerSpec(body: SBody.round, cap: SCap.flat, capColor: Color(0xffe8798f), eyes: SEyes.wink, mouth: SMouth.tongue, arms: SArms.wave, fx: {SFx.blush}),
  'sly': StickerSpec(body: SBody.potato, cap: SCap.flat, capColor: Color(0xff9c4f2a), eyes: SEyes.sly, mouth: SMouth.smirk, arms: SArms.hips),
  'dizzy': StickerSpec(body: SBody.tall, cap: SCap.spotted, capColor: Color(0xffe0352b), eyes: SEyes.spiral, mouth: SMouth.wavy, arms: SArms.out, tilt: -0.12),
  'scared': StickerSpec(body: SBody.potato, cap: SCap.spotted, capColor: Color(0xffd8432f), eyes: SEyes.scared, mouth: SMouth.wavy, arms: SArms.head, fx: {SFx.sweat}),
  'grumpy': StickerSpec(body: SBody.cluster, cap: SCap.flat, capColor: Color(0xffc9893d), eyes: SEyes.angry, mouth: SMouth.shout, arms: SArms.up, fx: {SFx.vein}, side: [(SEyes.squeeze, SMouth.shout), (SEyes.scared, SMouth.o)]),
  'cry': StickerSpec(body: SBody.tall, cap: SCap.morel, capColor: Color(0xffa0784e), eyes: SEyes.crying, mouth: SMouth.frown, arms: SArms.down, fx: {SFx.tears}),
  'hello': StickerSpec(body: SBody.tall, cap: SCap.parasol, capColor: Color(0xffd9b98f), eyes: SEyes.happy, mouth: SMouth.smile, arms: SArms.wave, fx: {SFx.blush}),
  'shy': StickerSpec(body: SBody.tall, cap: SCap.bell, capColor: Color(0xffece6dc), eyes: SEyes.happy, mouth: SMouth.smile, arms: SArms.cheeks, fx: {SFx.blush}, tilt: -0.08),
  // За рівень.
  'excited': StickerSpec(body: SBody.round, cap: SCap.dome, capColor: Color(0xffe07b24), eyes: SEyes.stars, mouth: SMouth.laugh, arms: SArms.up, fx: {SFx.sparkle, SFx.blush}),
  'friends': StickerSpec(body: SBody.cluster, cap: SCap.flat, capColor: Color(0xffd9a04e), eyes: SEyes.happy, mouth: SMouth.laugh, arms: SArms.wave, fx: {SFx.blush}),
  'sage': StickerSpec(body: SBody.potato, cap: SCap.bell, capColor: Color(0xffb8ad9c), eyes: SEyes.sleepy, mouth: SMouth.smile, arms: SArms.hips, fx: {SFx.blush}),
  'strong': StickerSpec(body: SBody.potato, cap: SCap.flat, capColor: Color(0xff7a3b1f), eyes: SEyes.angry, mouth: SMouth.laugh, arms: SArms.up, fx: {SFx.sparkle}),
  'fashion': StickerSpec(body: SBody.tall, cap: SCap.parasol, capColor: Color(0xffe8a0b4), eyes: SEyes.wink, mouth: SMouth.smile, arms: SArms.hips, fx: {SFx.blush, SFx.sparkle}, pattern: CapPattern.polka),
  'brave': StickerSpec(body: SBody.round, cap: SCap.spotted, capColor: Color(0xffc62828), eyes: SEyes.angry, mouth: SMouth.smirk, arms: SArms.hips, fx: {SFx.sparkle}),
  'golden': StickerSpec(body: SBody.round, cap: SCap.dome, capColor: Color(0xffe0a43a), bodyColor: _cream, eyes: SEyes.happy, mouth: SMouth.laugh, arms: SArms.up, fx: {SFx.sparkle, SFx.blush}, pattern: CapPattern.gold, glow: Color(0xffffd54f)),
  'giant': StickerSpec(body: SBody.potato, cap: SCap.dome, capColor: Color(0xff5d3a1a), eyes: SEyes.normal, mouth: SMouth.laugh, arms: SArms.out, fx: {SFx.blush}),
  // Pro.
  'cosmic': StickerSpec(body: SBody.round, cap: SCap.dome, capColor: Color(0xff283593), bodyColor: Color(0xffe8e4f7), eyes: SEyes.stars, mouth: SMouth.o, arms: SArms.up, fx: {SFx.sparkle}, pattern: CapPattern.stars),
  'firefly': StickerSpec(body: SBody.tall, cap: SCap.cone, capColor: Color(0xff26c6da), bodyColor: Color(0xffe0f7fa), eyes: SEyes.happy, mouth: SMouth.smile, arms: SArms.cheeks, fx: {SFx.blush}, glow: Color(0xff80deea)),
  'frost': StickerSpec(body: SBody.potato, cap: SCap.flat, capColor: Color(0xff64b5f6), bodyColor: Color(0xffe3f2fd), eyes: SEyes.squeeze, mouth: SMouth.wavy, arms: SArms.out, fx: {SFx.blush}, pattern: CapPattern.snow),
  'rainbow': StickerSpec(body: SBody.round, cap: SCap.dome, capColor: Color(0xffab47bc), eyes: SEyes.happy, mouth: SMouth.laugh, arms: SArms.wave, fx: {SFx.sparkle, SFx.blush}, pattern: CapPattern.stripes),
  'sorceress': StickerSpec(body: SBody.tall, cap: SCap.dome, capColor: Color(0xff7e57c2), eyes: SEyes.wink, mouth: SMouth.smile, arms: SArms.cheeks, fx: {SFx.sparkle, SFx.blush}, pattern: CapPattern.polka),
  'nightcap': StickerSpec(body: SBody.tall, cap: SCap.spotted, capColor: Color(0xff4a2a6b), eyes: SEyes.sly, mouth: SMouth.smirk, arms: SArms.hips, spotColor: Color(0xffccff90), glow: Color(0xffb2ff59)),
};

class CustomAvatarPainter extends StickerPainter {
  CustomAvatarPainter(AvatarParts parts)
      : super(
          kStickers[parts['sticker']] ?? kStickers['kind']!,
          StickerExtras(hat: parts['hat'], item: parts['item'], fx: parts['fx']),
        );
}
