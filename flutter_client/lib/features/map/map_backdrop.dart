import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/features/map/region_camera.dart';

/// Невеликі декоративні гриби для приглушеної карти поза Home Region.
///
/// Це не точки знахідок: вони не інтерактивні, не мають координат користувачів і
/// показуються лише на стартовому масштабі. Прозорі WEBP вже входять до каталогу
/// застосунку, тому фон повністю працює офлайн.
const mapBackdropMushroomAssets = <String>[
  'assets/species/small/boletus_edulis.webp',
  'assets/species/small/cantharellus_cibarius.webp',
  'assets/species/small/amanita_muscaria.webp',
  'assets/species/small/armillaria_mellea.webp',
  'assets/species/small/morchella_esculenta.webp',
  'assets/species/small/leccinum_scabrum.webp',
];

String mapBackdropMushroomIcon(int index) => 'backdrop-mushroom-$index';

/// Розміщує декор у вільних кутах bbox, але ніколи всередині області.
///
/// Першими йдуть точки всередині bbox, щоб гриби залишалися видимими на
/// стартовому огляді. Точки трохи поза bbox — лише запасний варіант для областей,
/// контур яких заповнює майже весь прямокутник.
Map<String, dynamic> mapBackdropMushroomsGeoJson({
  required GeoBounds bounds,
  required List<GeoPolygon> region,
}) {
  final west = bounds.southWest.longitude;
  final south = bounds.southWest.latitude;
  final east = bounds.northEast.longitude;
  final north = bounds.northEast.latitude;
  final width = east - west;
  final height = north - south;

  LatLng at(double x, double y) => LatLng(south + height * y, west + width * x);

  final candidates = <LatLng>[
    at(0.08, 0.90),
    at(0.88, 0.91),
    at(0.04, 0.62),
    at(0.96, 0.57),
    at(0.17, 0.13),
    at(0.81, 0.08),
    at(0.20, 0.83),
    at(0.76, 0.84),
    at(0.11, 0.36),
    at(0.90, 0.31),
    at(0.32, 0.06),
    at(0.66, 0.05),
    at(-0.025, 0.78),
    at(1.025, 0.72),
    at(-0.025, 0.28),
    at(1.025, 0.24),
    at(0.28, 1.015),
    at(0.72, -0.015),
  ];
  final points = candidates
      .where((point) => !isInsideRegion(point, region))
      .take(mapBackdropMushroomAssets.length);

  return {
    'type': 'FeatureCollection',
    'features': [
      for (final (index, point) in points.indexed)
        {
          'type': 'Feature',
          'properties': {'icon': mapBackdropMushroomIcon(index)},
          'geometry': {
            'type': 'Point',
            'coordinates': [point.longitude, point.latitude],
          },
        },
    ],
  };
}
