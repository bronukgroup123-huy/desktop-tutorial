import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Ширина декодування фото, яке показується з [BoxFit.cover] у рамці [box] (PERF-001).
///
/// Без неї фото з камери розкодовується в повному розмірі (кадр 1280×720 — 3,7 МБ пам'яті,
/// навіть у мініатюрі 58×58). Ширина така, щоб і короткий бік кадру 16:9 у будь-якій орієнтації
/// покривав рамку на екрані з цією щільністю пікселів — без розмиття; більшим за оригінал
/// фото не стає (Flutter не збільшує при декодуванні).
int coverDecodeWidth(Size box, double devicePixelRatio) =>
    (devicePixelRatio * math.max(box.width, box.height * 16 / 9)).ceil();

/// [image] з декодуванням під рамку [box] — для `Image(image: …, fit: BoxFit.cover)`.
ImageProvider coverDecoded(ImageProvider image, Size box, BuildContext context) =>
    ResizeImage(image, width: coverDecodeWidth(box, MediaQuery.devicePixelRatioOf(context)));
