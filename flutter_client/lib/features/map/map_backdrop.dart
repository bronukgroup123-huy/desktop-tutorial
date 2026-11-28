import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

const mapBackdropAsset = 'assets/textures/forest_map_backdrop.png';
const mapBackdropPattern = 'app_backdrop_pattern';
const mapBackdropLayer = 'app_backdrop_image';
const mapBackdropRasterSize = 512;
const mapBackdropPixelRatio = 1.0;

/// Завантажує компактний повторюваний офлайн-патерн для простору поза областю.
///
/// MapLibre повторює fill-pattern на всій масці, тому фон не має прямокутного
/// краю й не відкриває великі розтягнуті фрагменти під час панорамування.
Future<Uint8List> buildMapBackdropPattern() async {
  final data = await rootBundle.load(mapBackdropAsset);
  if (data.lengthInBytes == 0) throw StateError('Map backdrop is empty');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
