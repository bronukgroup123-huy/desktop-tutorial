import 'package:flutter_client/data/models/forest_zone.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> feature(String id, String? type, {String? source, int? area, String? label}) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [[28.0, 50.0], [28.1, 50.0], [28.1, 50.1], [28.0, 50.0]],
        ],
      },
      'properties': {
        'id': id,
        'forest_type': type,
        'type_label': label ?? (type ?? 'Ліс (тип невідомий)'),
        'type_color': '#81c784',
        if (area != null) 'area_m2': area,
        if (area != null) 'area_label': '≈ ${area / 10000} га',
        if (source != null) 'type_source': source,
        'type_source_label': switch (source) {
          'osm_species' => 'Порода вказана в OpenStreetMap',
          'osm_leaf_type' => 'У OpenStreetMap вказано лише хвойний / листяний',
          'osm_name' => 'Визначено за назвою урочища — може бути неточно',
          'satellite' => 'Визначено за супутниковими знімками (Sentinel-2) — без породи',
          _ => 'Порода в OpenStreetMap не вказана',
        },
      },
    };

ForestZone zone(String id, String? type, {String? source, int? area}) =>
    ForestZone.fromFeature(feature(id, type, source: source, area: area));

void main() {
  test('ForestZone: площа і джерело типу з файлу лісів; старі дані — без них', () {
    final z = zone('w1', 'pine', source: 'osm_species', area: 4000);
    expect([z.areaM2, z.areaLabel, z.typeSource, z.typeSourceLabel],
        [4000, '≈ 0.4 га', 'osm_species', 'Порода вказана в OpenStreetMap']);
    final old = ForestZone.fromFeature({
      'type': 'Feature',
      'geometry': null,
      'properties': {'id': 1, 'forest_type': 'oak', 'type_label': 'Дубовий ліс', 'type_color': '#4caf50'},
    });
    expect([old.areaM2, old.areaLabel, old.typeSourceLabel], [null, null, null]);
  });

  group('Визначник лісу: який контур показати, коли вони перекриваються', () {
    test('порода з OSM важливіша за загальний «ліс без типу»', () {
      final hits = [zone('big', null, area: 5000000), zone('pine', 'pine', source: 'osm_species', area: 300000)];
      expect(pickForestAt(hits).id, 'pine');
    });

    test('порода важливіша за «мішаний» з leaf_type, навіть якщо мішаний — менший', () {
      final hits = [
        zone('mixed', 'mixed', source: 'osm_leaf_type', area: 10000),
        zone('oak', 'oak', source: 'osm_species', area: 900000),
      ];
      expect(pickForestAt(hits).id, 'oak');
    });

    test('дані з OSM надійніші за назву урочища', () {
      final hits = [
        zone('byName', 'birch', source: 'osm_name', area: 5000),
        zone('leaf', 'coniferous', source: 'osm_leaf_type', area: 800000),
      ];
      expect(pickForestAt(hits).id, 'leaf');
    });

    test('супутник: важливіший за «ліс без типу», поступається даним OSM і породі з назви', () {
      final sat = zone('sat', 'coniferous', source: 'satellite', area: 50000);
      expect(pickForestAt([zone('big', null, area: 5000000), sat]).id, 'sat');
      expect(pickForestAt([sat, zone('leaf', 'deciduous', source: 'osm_leaf_type', area: 900000)]).id, 'leaf');
      expect(pickForestAt([sat, zone('byName', 'pine', source: 'osm_name', area: 900000)]).id, 'byName');
      expect(sat.typeSourceLabel, 'Визначено за супутниковими знімками (Sentinel-2) — без породи');
    });

    test('однаково надійні — менший (локальніший) контур', () {
      final hits = [
        zone('pineBig', 'pine', source: 'osm_species', area: 2000000),
        zone('birchSmall', 'birch', source: 'osm_species', area: 20000),
      ];
      expect(pickForestAt(hits).id, 'birchSmall');
    });

    test('один контур — він і є', () {
      expect(pickForestAt([zone('only', null)]).id, 'only');
    });
  });
}
