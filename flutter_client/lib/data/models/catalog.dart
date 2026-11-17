import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/services.dart' show rootBundle;

/// Де лежать фото довідника (реліз «catalog-photos», .github/workflows/catalog.yml).
const kCatalogPhotosBase = 'https://github.com/bronukgroup123-huy/desktop-tutorial/releases/download/catalog-photos';

/// Вид у довіднику (як у веб-довіднику: web-guardian/public/landing.html).
class CatalogSpecies {
  const CatalogSpecies({
    required this.id,
    required this.name,
    required this.latin,
    required this.edibility,
    required this.redListed,
    this.rarity = '',
    required this.top20,
    required this.popular,
    required this.months,
    required this.peakMonths,
    required this.tree,
    required this.season,
    required this.photos,
    required this.description,
    this.credits = const [],
    this.redBookSource,
    this.zones = const [],
  });

  factory CatalogSpecies.fromJson(Map<String, dynamic> j) => CatalogSpecies(
        id: j['id'] as String,
        name: j['name'] as String,
        latin: (j['latin'] as String?) ?? '',
        edibility: (j['edibility'] as String?) ?? '',
        redListed: j['red_listed'] == true,
        rarity: (j['rarity'] as String?) ?? '',
        top20: j['top20'] == true,
        popular: j['popular'] == true,
        months: [for (final m in (j['months'] as List? ?? const [])) (m as num).toInt()],
        peakMonths: [for (final m in (j['peak_months'] as List? ?? const [])) (m as num).toInt()],
        tree: [for (final t in (j['tree'] as List? ?? const [])) t as String],
        season: [for (final t in (j['season'] as List? ?? const [])) t as String],
        photos: [for (final p in (j['photos'] as List? ?? const [])) p as String],
        description: (j['description'] as String?) ?? '',
        credits: [
          for (final c in (j['credits'] as List? ?? const []).cast<Map<String, dynamic>>()) PhotoCredit.fromJson(c),
        ],
        redBookSource: switch (j['red_book_source']) {
          final Map<String, dynamic> r when r['text'] != null || r['url'] != null =>
            (text: (r['text'] as String?) ?? '', url: r['url'] as String?),
          _ => null,
        },
        zones: [for (final z in (j['zones'] as List? ?? const [])) z as String],
      );

  final String id;
  final String name;
  final String latin;

  /// `edible | conditionally_edible | inedible | poisonous | deadly_poisonous`
  final String edibility;
  final bool redListed;

  /// Для Червоної книги: «Рідкісний вид», «Вразливий вид»…
  final String rarity;
  final bool top20;
  final bool popular;
  final List<int> months;
  final List<int> peakMonths;

  /// Дерева / тип лісу: `pine`, `birch`, `deciduous`…
  final List<String> tree;

  /// `spring | summer | autumn | winter`
  final List<String> season;

  /// Імена фото в релізі: `<id>-<n>.webp`.
  final List<String> photos;

  /// Книжковий опис (розділи з емодзі-заголовками, таблиці через табуляцію).
  final String description;

  /// Автори фото з ліцензіями (CC BY — підпис обов'язковий): КОЖЕН автор із файлу ліцензії
  /// папки виду. Порожньо — фото з колекції проєкту без окремої ліцензії.
  final List<PhotoCredit> credits;

  /// Джерело статусу Червоної книги (бібліографія й посилання).
  final ({String text, String? url})? redBookSource;

  /// Області, де вид поширений (`zhytomyrska`…) — карта на сторінці виду; порожньо — невідомо.
  final List<String> zones;

  /// Сезон плодоношення показуємо лише не для отруйних (рішення PO 2026-11-16): отруйний гриб
  /// не «збирають у сезон».
  bool get showsSeason => !poisonous;

  /// Місяць [month] (1–12) — у сезоні цього виду (отруйні — ніколи).
  bool inSeason(int month) => showsSeason && months.contains(month);

  /// Сезони за місяцями плодоношення (точніше, ніж атрибут каталогу: у зимового опенька там
  /// помилково всі чотири сезони); місяців немає — з атрибута. Отруйні — без сезону.
  List<String> get seasons {
    if (!showsSeason) return const [];
    if (months.isEmpty) return season;
    return [
      for (final e in const {'spring': [3, 4, 5], 'summer': [6, 7, 8], 'autumn': [9, 10, 11], 'winter': [12, 1, 2]}.entries)
        if (e.value.any(months.contains)) e.key,
    ];
  }

  bool get poisonous => edibility == 'poisonous' || edibility == 'deadly_poisonous';

  /// Мініатюра першого фото для списку.
  String? get thumb => photos.isEmpty ? null : '$id-0-t.webp';
}

/// Довідник: вбудований у застосунок (assets/catalog/catalog.json.gz) — працює без інтернету.
/// Автор фото й ліцензія: «Paula Nimigean, iNaturalist» · CC BY 4.0 · посилання на фото.
class PhotoCredit {
  const PhotoCredit({required this.author, this.license, this.licenseUrl, this.sources = const []});

  factory PhotoCredit.fromJson(Map<String, dynamic> j) => PhotoCredit(
        author: (j['author'] as String?) ?? '',
        license: j['type'] as String?,
        licenseUrl: j['url'] as String?,
        sources: [for (final u in (j['sources'] as List? ?? const [])) u as String],
      );

  final String author;

  /// «CC BY 4.0»
  final String? license;

  /// https://creativecommons.org/licenses/by/4.0/
  final String? licenseUrl;

  /// Сторінки фото автора (iNaturalist).
  final List<String> sources;
}

class Catalog {
  const Catalog(this.species);

  final List<CatalogSpecies> species;

  CatalogSpecies? byId(String id) {
    for (final s in species) {
      if (s.id == id) return s;
    }
    return null;
  }

  static Catalog parse(List<int> gz) {
    final json = jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
    return Catalog([
      for (final s in (json['species'] as List).cast<Map<String, dynamic>>()) CatalogSpecies.fromJson(s),
    ]);
  }

  static Future<Catalog> load() async {
    final data = await rootBundle.load('assets/catalog/catalog.json.gz');
    return parse(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }
}

/// Підпис і колір значка їстівності (як у веб-довіднику).
({String label, int color}) edibilityBadge(CatalogSpecies s) {
  if (s.redListed) return (label: 'Червонокнижний', color: 0xffb7791f);
  return switch (s.edibility) {
    'deadly_poisonous' => (label: 'Смертельно отруйний', color: 0xff8e1b1b),
    'poisonous' => (label: 'Отруйний', color: 0xffc62828),
    'conditionally_edible' => (label: 'Умовно їстівний', color: 0xffd9822b),
    'inedible' => (label: 'Неїстівний', color: 0xff6b7a70),
    'edible' => (label: 'Їстівний', color: 0xff2e7d32),
    _ => (label: 'Уточнюється', color: 0xff6b7a70),
  };
}

const kTreeLabels = {
  'pine': 'Сосна', 'spruce': 'Ялина', 'larch': 'Модрина', 'oak': 'Дуб', 'birch': 'Береза',
  'aspen': 'Осика', 'poplar': 'Тополя', 'willow': 'Верба', 'alder': 'Вільха', 'hornbeam': 'Граб',
  'beech': 'Бук', 'elm': "В'яз", 'hazel': 'Ліщина', 'mixed': 'Мішаний ліс', 'deciduous': 'Листяний ліс',
  'coniferous': 'Хвойний ліс', 'any': 'Будь-який ліс',
};

const kSeasonLabels = {'spring': 'Весна', 'summer': 'Літо', 'autumn': 'Осінь', 'winter': 'Зима'};
