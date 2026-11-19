import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_client/features/profile/custom_avatar.dart';

/// Наліпка як готова картинка. Малюнок наліпки важкий (тіні з розмиттям, градієнти), і без
/// кешу телефон перемальовує його в кожному кадрі прокрутки — сітка аватарів гальмує.
/// Тут кожна наліпка малюється один раз у потрібному розмірі й далі лише показується.
class StickerImage extends StatelessWidget {
  const StickerImage(this.parts, {super.key, required this.size, this.opacity = 1});

  final AvatarParts parts;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(16, 1024);
    final image = StickerCache.instance.image(parts, px);
    return RawImage(
      // RawImage забирає картинку собі й звільняє її — віддаємо копію, оригінал лишається в кеші.
      image: image.clone(),
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      opacity: opacity == 1 ? null : AlwaysStoppedAnimation(opacity),
    );
  }
}

/// Готові картинки наліпок (останні ~200: сітка персонажів і деталей у кількох розмірах).
class StickerCache {
  StickerCache._();
  static final instance = StickerCache._();

  static const _max = 200;
  final _images = <String, ui.Image>{}; // зберігає порядок додавання

  ui.Image image(AvatarParts parts, int px) {
    final key = '${parts['sticker']}|${parts['hat']}|${parts['item']}|${parts['fx']}|$px';
    final hit = _images.remove(key);
    if (hit != null) return _images[key] = hit; // свіжіше — в кінець черги
    final recorder = ui.PictureRecorder();
    CustomAvatarPainter(parts).paint(Canvas(recorder), Size(px.toDouble(), px.toDouble()));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(px, px);
    picture.dispose();
    _images[key] = image;
    while (_images.length > _max) {
      _images.remove(_images.keys.first)!.dispose();
    }
    return image;
  }
}
