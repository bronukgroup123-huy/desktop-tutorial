import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Межі фото тук-тука — ті самі, що на сервері (bucket `mushroom-photos`, B3.0).
abstract final class PickPhotoRules {
  static const int maxBytes = 5 * 1024 * 1024;

  /// Менше — майже напевно порожній або обрізаний файл.
  static const int minBytes = 1024;
}

/// Результат перевірки фото: тип за вмістом файлу або зрозуміла помилка.
class PickPhotoCheck {
  const PickPhotoCheck.ok(this.contentType, this.sizeBytes) : error = null;
  const PickPhotoCheck.fail(this.error)
      : contentType = null,
        sizeBytes = 0;

  /// `image/jpeg` | `image/png` | `image/webp` — за «магічними байтами», не за розширенням.
  final String? contentType;
  final int sizeBytes;
  final String? error;

  bool get isOk => error == null;
}

/// Формат за першими байтами файлу (як `detectImageFormat` на сервері).
String? detectImageContentType(Uint8List head) {
  if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) return 'image/jpeg';
  if (head.length >= 8 &&
      head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47 &&
      head[4] == 0x0D && head[5] == 0x0A && head[6] == 0x1A && head[7] == 0x0A) {
    return 'image/png';
  }
  if (head.length >= 12 &&
      head[0] == 0x52 && head[1] == 0x49 && head[2] == 0x46 && head[3] == 0x46 && // RIFF
      head[8] == 0x57 && head[9] == 0x45 && head[10] == 0x42 && head[11] == 0x50) { // WEBP
    return 'image/webp';
  }
  return null;
}

/// Чиста перевірка: розмір і формат. Повідомлення — для користувача.
PickPhotoCheck checkPickPhoto({required int sizeBytes, required Uint8List head}) {
  if (sizeBytes < PickPhotoRules.minBytes) {
    return const PickPhotoCheck.fail('Фото не збереглося або пошкоджене. Перезніміть, будь ласка.');
  }
  if (sizeBytes > PickPhotoRules.maxBytes) {
    final mb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return PickPhotoCheck.fail('Фото завелике ($mb МБ, можна до 5 МБ). Перезніміть, будь ласка.');
  }
  final type = detectImageContentType(head);
  if (type == null) {
    return const PickPhotoCheck.fail('Непідтримуваний формат фото. Потрібне JPEG, PNG або WebP — перезніміть.');
  }
  return PickPhotoCheck.ok(type, sizeBytes);
}

/// Перевіряє знімок із камери: файл є, читається, розмір і формат допустимі.
Future<PickPhotoCheck> validatePickPhoto(XFile? photo) async {
  if (photo == null) return const PickPhotoCheck.fail('Для тук-тука потрібне фото гриба.');
  try {
    final size = await photo.length();
    final head = BytesBuilder(copy: false);
    await for (final chunk in photo.openRead(0, size < 12 ? size : 12)) {
      head.add(chunk);
    }
    return checkPickPhoto(sizeBytes: size, head: head.toBytes());
  } catch (_) {
    return const PickPhotoCheck.fail('Не вдалося прочитати фото. Перезніміть, будь ласка.');
  }
}
