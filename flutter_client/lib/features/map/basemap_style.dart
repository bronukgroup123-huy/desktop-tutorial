// ignore_for_file: implementation_imports — стандартний стиль бібліотеки не експортується,
// а нам потрібні українські підписи.
import 'package:vector_tile_renderer/src/themes/light_theme.dart' show lightThemeData;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show Theme, ThemeReader;

/// Стиль векторної карти області (ADR-020): схема OpenMapTiles, на основі OSM Bright
/// (© OpenMapTiles, BSD / CC-BY 4.0).
///
/// У стандартному стилі назви міст і сіл — англійською (`name_en`: «Lviv»). У нас — назва з
/// OpenStreetMap (`name`), в Україні це українська назва («Львів»).
final Theme basemapTheme = ThemeReader().read(ukrainianLabels(lightThemeData()));

/// Усі підписи стилю — з поля `name` (місцева назва) замість `name_en` / `name:latin`.
Map<String, dynamic> ukrainianLabels(Map<String, dynamic> style) {
  Object? fix(Object? v) => switch (v) {
        String s => s.replaceAll('{name_en}', '{name}').replaceAll('{name:latin}', '{name}'),
        Map m => <String, dynamic>{for (final e in m.entries) e.key as String: fix(e.value)},
        List l => <dynamic>[for (final e in l) fix(e)],
        _ => v,
      };
  return fix(style) as Map<String, dynamic>;
}
