import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/features/map/basemap_style.dart';

void main() {
  test('карта області: підписи з назви OpenStreetMap (українською), а не англійською', () {
    final style = jsonEncode(ukrainianLabels({
      'layers': [
        {'id': 'place_city', 'layout': {'text-field': '{name_en}'}},
        {'id': 'road_label', 'layout': {'text-field': '{name}'}},
        {'id': 'x', 'layout': {'text-field': '{name:latin}\n{name:nonlatin}'}},
      ],
    }));
    expect(style.contains('name_en'), isFalse);
    expect(style.contains('name:latin'), isFalse);
    expect(style.contains('{name}'), isTrue);
    // справжній стиль читається без помилок
    expect(basemapTheme.layers, isNotEmpty);
  });
}
