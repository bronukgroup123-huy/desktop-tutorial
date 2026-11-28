import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

const mapBackdropAsset = 'assets/textures/forest_map_backdrop.svg';
const mapBackdropPattern = 'app_backdrop_pattern';
const mapBackdropLayer = 'app_backdrop_image';
const mapBackdropRasterSize = 512;
const mapBackdropPixelRatio = 1.0;

/// Малює компактний повторюваний офлайн-патерн для простору поза областю.
///
/// MapLibre повторює fill-pattern на всій масці, тому фон не має прямокутного
/// краю й не відкриває великі розтягнуті фрагменти під час панорамування.
Future<Uint8List> buildMapBackdropPattern() async {
  final size = mapBackdropRasterSize.toDouble();

  final picture = await vg.loadPicture(const SvgAssetLoader(mapBackdropAsset), null);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(size / picture.size.width, size / picture.size.height);
  canvas.drawPicture(picture.picture);

  final rendered = recorder.endRecording();
  final image = await rendered.toImage(mapBackdropRasterSize, mapBackdropRasterSize);
  rendered.dispose();
  picture.picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Map backdrop could not be encoded');

  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}
