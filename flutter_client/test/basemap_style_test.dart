import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/features/map/basemap_style.dart';

void main() {
  final layers = (basemapStyle()['layers'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> layer(String id) => layers.firstWhere((l) => l['id'] == id);

  test('офлайн карта: стиль читається рендерером', () {
    expect(basemapTheme.layers.length, layers.length);
  });

  test('підписи: українська назва (name:uk, інакше name), один шрифт і оформлення', () {
    final labels = layers.where((l) => l['type'] == 'symbol').toList();
    expect(labels, isNotEmpty);
    expect(jsonEncode(basemapStyle()).contains('name_en'), isFalse);
    for (final l in labels) {
      final layout = l['layout'] as Map;
      expect(layout['text-field'], [
        'coalesce',
        ['get', 'name:uk'],
        ['get', 'name'],
      ]);
      expect(layout['text-font'], ['Roboto Regular']);
      expect((l['paint'] as Map)['text-halo-color'], '#ffffff');
    }
  });

  test('підписи з\'являються за масштабом: міста раніше за села, річки — з z11, струмки й вулиці — з z14', () {
    expect(layer('label_city')['minzoom'], 6);
    expect(layer('label_town')['minzoom'], 9);
    expect(layer('label_village')['minzoom'], 11);
    expect(layer('label_hamlet')['minzoom'], 13);
    expect(layer('label_river')['minzoom'], 11);
    expect(layer('label_stream')['minzoom'], 14);
    expect(layer('label_road')['minzoom'], 14);
  });

  test('ліси OSM у підкладці не малюються — їх показує наш шар лісів із типами', () {
    expect(layers.where((l) => jsonEncode(l['filter'] ?? []).contains('wood')), isEmpty);
  });
}
