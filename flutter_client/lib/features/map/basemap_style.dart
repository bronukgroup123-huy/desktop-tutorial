import 'package:vector_tile_renderer/vector_tile_renderer.dart' show Theme, ThemeReader;

/// Стиль офлайн карти області (ADR-020) — власний, компактний, під грибника.
///
/// Чому не стандартний OSM Bright: у ньому десятки шарів (тунелі, POI, будівлі, стрілки
/// одностороннього руху) — це гальмувало малювання; назви міст були англійською, а підписи
/// річок і сіл з'являлися на будь-якому масштабі й захаращували карту.
///
/// * Ліси OSM у підкладці не малюються — їх показує наш шар лісів із типами (ADR-015 §15.5).
/// * Усі підписи в одному форматі: той самий шрифт, темний текст з білою обвідкою; річки —
///   тим самим шрифтом, лише синім. Назва — українська (`name:uk`), інакше `name`.
/// * Підписи з'являються за масштабом: міста — з z6, селища — з z9, села — з z11,
///   хутори — з z13; річки — з z11, струмки й канали — з z14; вулиці — з z14.
///
/// Дані: © OpenStreetMap contributors (ODbL); схема OpenMapTiles.
final Theme basemapTheme = ThemeReader().read(basemapStyle());

const _source = 'openmaptiles';
const _font = ['Roboto Regular'];
const _textColor = '#2f3a33';
const _waterText = '#3a6f96';
const _halo = '#ffffff';

/// Назва українською; якщо її немає — назва з OpenStreetMap.
const List<Object> _name = [
  'coalesce',
  ['get', 'name:uk'],
  ['get', 'name'],
];

List<Object> _zoomSize(num z1, num s1, num z2, num s2) => [
      'interpolate',
      ['linear'],
      ['zoom'],
      z1,
      s1,
      z2,
      s2,
    ];

Map<String, dynamic> _line(
  String id,
  String layer,
  List<Object> filter, {
  required num minzoom,
  required String color,
  required List<Object> width,
  List<num>? dash,
}) =>
    {
      'id': id,
      'type': 'line',
      'source': _source,
      'source-layer': layer,
      'minzoom': minzoom,
      'filter': filter,
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': color,
        'line-width': width,
        if (dash != null) 'line-dasharray': dash,
      },
    };

Map<String, dynamic> _label(
  String id,
  String layer,
  List<Object> filter, {
  required num minzoom,
  required List<Object> size,
  String color = _textColor,
  bool alongLine = false,
}) =>
    {
      'id': id,
      'type': 'symbol',
      'source': _source,
      'source-layer': layer,
      'minzoom': minzoom,
      'filter': filter,
      'layout': {
        'text-field': _name,
        'text-font': _font,
        'text-size': size,
        if (alongLine) 'symbol-placement': 'line',
        if (!alongLine) 'text-max-width': 8,
      },
      'paint': {'text-color': color, 'text-halo-color': _halo, 'text-halo-width': 1.4},
    };

/// Стиль у форматі Mapbox GL Style (підмножина, яку підтримує vector_tile_renderer).
Map<String, dynamic> basemapStyle() => {
      'version': 8,
      'name': 'mushroom-radar-offline',
      'sources': {
        _source: {'type': 'vector'},
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#f3f1ec'},
        },
        // ─── Площі ───────────────────────────────────────────────────────────
        {
          'id': 'landcover_fields',
          'type': 'fill',
          'source': _source,
          'source-layer': 'landcover',
          'filter': ['in', 'class', 'farmland', 'grass'],
          'paint': {'fill-color': '#eef0e2'},
        },
        {
          'id': 'landcover_wetland',
          'type': 'fill',
          'source': _source,
          'source-layer': 'landcover',
          'minzoom': 9,
          'filter': ['==', 'class', 'wetland'],
          'paint': {'fill-color': '#e2ebe3'},
        },
        {
          'id': 'landuse_residential',
          'type': 'fill',
          'source': _source,
          'source-layer': 'landuse',
          'minzoom': 8,
          'filter': ['in', 'class', 'residential', 'suburb', 'neighbourhood', 'commercial', 'industrial'],
          'paint': {'fill-color': '#e7e3dd'},
        },
        {
          'id': 'water',
          'type': 'fill',
          'source': _source,
          'source-layer': 'water',
          'paint': {'fill-color': '#a9cbe0'},
        },
        // ─── Річки ───────────────────────────────────────────────────────────
        _line('waterway_river', 'waterway', ['==', 'class', 'river'],
            minzoom: 8, color: '#8fbbd8', width: _zoomSize(8, 0.8, 14, 2.4)),
        _line(
            'waterway_other',
            'waterway',
            ['in', 'class', 'stream', 'canal', 'drain', 'ditch'],
            minzoom: 12,
            color: '#a3c7df',
            width: _zoomSize(12, 0.5, 14, 1.0)),
        // ─── Дороги ──────────────────────────────────────────────────────────
        _line('rail', 'transportation', ['==', 'class', 'rail'],
            minzoom: 10, color: '#b6b0a8', width: _zoomSize(10, 0.6, 14, 1.2)),
        _line('road_track', 'transportation', ['in', 'class', 'track', 'path'],
            minzoom: 13, color: '#a88f73', width: _zoomSize(13, 0.6, 15, 1.2), dash: [2, 1.5]),
        _line('road_minor', 'transportation', ['in', 'class', 'minor', 'service'],
            minzoom: 12, color: '#d6cfc4', width: _zoomSize(12, 0.6, 15, 2.5)),
        _line('road_secondary', 'transportation', ['in', 'class', 'secondary', 'tertiary'],
            minzoom: 9, color: '#f3dca3', width: _zoomSize(9, 0.7, 15, 3.5)),
        _line('road_primary', 'transportation', ['==', 'class', 'primary'],
            minzoom: 7, color: '#efc57c', width: _zoomSize(7, 0.8, 15, 4)),
        _line('road_trunk', 'transportation', ['in', 'class', 'motorway', 'trunk'],
            minzoom: 5, color: '#e9a95e', width: _zoomSize(5, 0.8, 15, 4.5)),
        // ─── Кордон країни ───────────────────────────────────────────────────
        _line('boundary_country', 'boundary', ['==', 'admin_level', 2],
            minzoom: 0, color: '#8a8a8a', width: _zoomSize(5, 1, 12, 2), dash: [3, 2]),
        // ─── Підписи (усі — одного формату) ──────────────────────────────────
        _label('label_road', 'transportation_name', ['has', 'name'],
            minzoom: 14, size: _zoomSize(14, 10, 17, 12), alongLine: true),
        _label('label_river', 'waterway', ['==', 'class', 'river'],
            minzoom: 11, size: _zoomSize(11, 10.5, 15, 12.5), color: _waterText, alongLine: true),
        _label('label_stream', 'waterway', ['!=', 'class', 'river'],
            minzoom: 14, size: _zoomSize(14, 10, 17, 11.5), color: _waterText, alongLine: true),
        _label('label_lake', 'water_name', ['has', 'name'],
            minzoom: 12, size: _zoomSize(12, 10.5, 16, 12.5), color: _waterText),
        _label(
            'label_hamlet',
            'place',
            ['in', 'class', 'hamlet', 'isolated_dwelling', 'locality', 'suburb', 'neighbourhood', 'quarter'],
            minzoom: 13,
            size: _zoomSize(13, 10.5, 16, 12.5)),
        _label('label_village', 'place', ['==', 'class', 'village'],
            minzoom: 11, size: _zoomSize(11, 11, 15, 13.5)),
        _label('label_town', 'place', ['==', 'class', 'town'],
            minzoom: 9, size: _zoomSize(9, 12, 14, 15)),
        _label('label_city', 'place', ['==', 'class', 'city'],
            minzoom: 6, size: _zoomSize(6, 13, 12, 17)),
      ],
    };
