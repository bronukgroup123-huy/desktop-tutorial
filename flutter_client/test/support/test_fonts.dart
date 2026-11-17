import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Для тестів зі справжнім очікуванням (`runAsync`): google_fonts встигає дочитати маніфест
/// і падає, бо Merriweather/Inter не в assets. Підкладаємо їх (байти Roboto з Flutter SDK)
/// у маніфест тестових ресурсів, решту ресурсів віддаємо як є.
void useBundledTestFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final font = File('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  final bytes = font.existsSync() ? font.readAsBytesSync() : Uint8List(0);
  const assets = 'build/unit_test_assets';
  final codec = const StandardMessageCodec();
  final manifest = Map<Object?, Object?>.of(
    codec.decodeMessage(ByteData.sublistView(File('$assets/AssetManifest.bin').readAsBytesSync())) as Map<Object?, Object?>,
  );
  const weights = ['Thin', 'ExtraLight', 'Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black'];
  final fonts = <String>{
    for (final family in ['Merriweather', 'Inter'])
      for (final w in weights) ...['test_fonts/$family-$w.ttf', 'test_fonts/$family-${w == 'Regular' ? '' : w}Italic.ttf'],
  };
  for (final f in fonts) {
    manifest[f] = [
      {'asset': f},
    ];
  }
  final manifestBytes = codec.encodeMessage(manifest)!;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
    final key = Uri.decodeFull(utf8.decode(message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes)));
    if (key == 'AssetManifest.bin') return manifestBytes;
    if (fonts.contains(key)) return ByteData.sublistView(bytes);
    final file = File('$assets/$key');
    return file.existsSync() ? ByteData.sublistView(file.readAsBytesSync()) : null;
  });
}

