import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/geo.dart';

const mapBackdropAsset = 'assets/textures/forest_map_backdrop.svg';
const mapBackdropSource = 'app_backdrop_image_source';
const mapBackdropLayer = 'app_backdrop_image';
const mapBackdropRasterSize = 768;

/// Готовий растр декоративної карти та географічні кути для MapLibre.
typedef MapBackdropImage = ({Uint8List png, GeoBounds extent});

({double x, double y}) _mercator(LatLng point) {
  final latitude = point.latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return (
    x: (point.longitude + 180) / 360,
    y: (1 - math.log(math.tan(latitude) + 1 / math.cos(latitude)) / math.pi) / 2,
  );
}

LatLng _unmercator(double x, double y) {
  final n = math.pi - 2 * math.pi * y;
  return LatLng(
    180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n))),
    x * 360 - 180,
  );
}

/// Малює гарантовано видимий офлайн-фон і вирізає з нього точний контур області.
///
/// Розширення на 65% покриває поля стартового огляду навіть у портреті. Усі
/// перетворення виконуються у Web Mercator, тому прозорий виріз збігається з
/// геометрією MapLibre, а не лише приблизно з широтою/довготою.
Future<MapBackdropImage> buildMapBackdropImage({
  required GeoBounds bounds,
  required List<GeoPolygon> region,
}) async {
  final southWest = _mercator(bounds.southWest);
  final northEast = _mercator(bounds.northEast);
  final width = northEast.x - southWest.x;
  final height = southWest.y - northEast.y;
  final west = southWest.x - width * 0.65;
  final east = northEast.x + width * 0.65;
  final north = northEast.y - height * 0.65;
  final south = southWest.y + height * 0.65;
  final size = mapBackdropRasterSize.toDouble();

  ui.Offset offsetOf(LatLng point) {
    final projected = _mercator(point);
    return ui.Offset(
      (projected.x - west) / (east - west) * size,
      (projected.y - north) / (south - north) * size,
    );
  }

  final picture = await vg.loadPicture(const SvgAssetLoader(mapBackdropAsset), null);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final surface = ui.Rect.fromLTWH(0, 0, size, size);
  canvas.saveLayer(surface, ui.Paint());
  canvas.save();
  canvas.scale(size / picture.size.width, size / picture.size.height);
  canvas.drawPicture(picture.picture);
  canvas.restore();

  final cutout = ui.Path()..fillType = ui.PathFillType.evenOdd;
  for (final polygon in region) {
    cutout.addPolygon([for (final point in polygon.outer) offsetOf(point)], true);
    for (final hole in polygon.holes) {
      cutout.addPolygon([for (final point in hole) offsetOf(point)], true);
    }
  }
  canvas.drawPath(
    cutout,
    ui.Paint()
      ..blendMode = ui.BlendMode.clear
      ..style = ui.PaintingStyle.fill,
  );
  canvas.restore();

  final rendered = recorder.endRecording();
  final image = await rendered.toImage(mapBackdropRasterSize, mapBackdropRasterSize);
  rendered.dispose();
  picture.picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Map backdrop could not be encoded');

  return (
    png: bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    extent: GeoBounds(
      southWest: _unmercator(west, south),
      northEast: _unmercator(east, north),
    ),
  );
}
