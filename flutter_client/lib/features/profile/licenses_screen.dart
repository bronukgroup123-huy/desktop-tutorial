import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/species_credits.dart';

/// Дані, фото й програми інших авторів, якими користується застосунок, з їхніми ліцензіями.
/// Фото довідника — кожен автор кожного виду (з файлів ліцензій у папках фото); решта — сталі
/// джерела (карта, межі областей, шрифт, погода, ґрунти, ШІ).
const kDataSources = <({String title, String text})>[
  (
    title: 'Карта, ліси й дороги',
    text: '© учасники OpenStreetMap. Дані доступні за ліцензією Open Database License (ODbL) — '
        'openstreetmap.org/copyright. Витяг для областей — Geofabrik (download.geofabrik.de).',
  ),
  (
    title: 'Межі областей',
    text: 'Natural Earth (naturalearthdata.com) — суспільне надбання (public domain).',
  ),
  (
    title: 'Шрифт підписів карти',
    text: 'Noto Sans — © 2012 Google Inc., SIL Open Font License 1.1 (openfontlicense.org). '
        'Гліфи — openmaptiles/fonts.',
  ),
  (
    title: 'Погода й висота місцевості',
    text: 'Open-Meteo.com — дані за ліцензією CC BY 4.0 (creativecommons.org/licenses/by/4.0/).',
  ),
  (
    title: 'Ґрунти',
    text: 'SoilGrids, ISRIC — World Soil Information, CC BY 4.0 (creativecommons.org/licenses/by/4.0/).',
  ),
  (
    title: 'ШІ-розпізнавання',
    text: 'BioCLIP 2 (Imageomics Institute, huggingface.co/imageomics/bioclip-2) — ліцензія MIT. '
        'Модель працює лише на телефоні.',
  ),
];

class LicensesScreen extends ConsumerWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final withCredits = [...?catalog?.species.where((s) => s.credits.isNotEmpty)]..sort((a, b) => a.name.compareTo(b.name));
    final authors = withCredits.fold<int>(0, (n, s) => n + s.credits.length);
    final redSources = <String, String?>{
      for (final s in catalog?.species ?? const []) if (s.redBookSource case final r?) r.text: r.url,
    };
    final dim = AppTheme.darkGreen.withValues(alpha: 0.7);
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
          child: Text(t, style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
        );
    return Scaffold(
      appBar: AppBar(title: Text('Джерела та ліцензії', style: GoogleFonts.merriweather(color: AppTheme.darkGreen))),
      body: ListView(
        key: const ValueKey('licenses-list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          header('Дані'),
          for (final d in kDataSources)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                  SelectableText(d.text, style: TextStyle(fontSize: 13, color: dim)),
                ],
              ),
            ),
          header('Фото довідника'),
          Text(
            'Фото інших авторів (видів — ${withCredits.length}, авторів — $authors): ліцензія — біля кожного '
            'автора (CC BY 4.0 — з обов\'язковим підписом; CC0 і суспільне надбання — без обмежень). '
            'Решта фото — з колекції проєкту.',
            key: const ValueKey('licenses-photos-summary'),
            style: TextStyle(fontSize: 13, color: dim),
          ),
          for (final s in withCredits)
            Padding(
              key: ValueKey('licenses-species-${s.id}'),
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s.name} · ${s.latin}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                  for (final c in s.credits)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: SelectableText(creditText(c), style: TextStyle(fontSize: 12, color: dim, height: 1.35)),
                    ),
                ],
              ),
            ),
          if (redSources.isNotEmpty) ...[
            header('Червона книга'),
            for (final e in redSources.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText([e.key, if (e.value != null) e.value!].join('\n'), style: TextStyle(fontSize: 12, color: dim)),
              ),
          ],
          header('Програмні бібліотеки'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('licenses-packages'),
              onPressed: () => showLicensePage(context: context, applicationName: 'Грибний Радар'),
              icon: const Icon(Icons.code_rounded),
              label: const Text('Ліцензії бібліотек'),
            ),
          ),
        ],
      ),
    );
  }
}
