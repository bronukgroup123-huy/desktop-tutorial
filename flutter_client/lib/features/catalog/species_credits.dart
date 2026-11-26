import 'package:flutter/material.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/catalog.dart';

/// Автори й ліцензії фото виду (рішення PO 2026-11-17): КОЖЕН автор із файлу ліцензії — свій
/// рядок з ліцензією та посиланнями на його фото; і джерело статусу Червоної книги.
/// Текст можна виділити й скопіювати (посилання).
class SpeciesCredits extends StatelessWidget {
  const SpeciesCredits({super.key, required this.species, this.color});

  final CatalogSpecies species;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textMuted;
    final small = TextStyle(fontSize: 11, color: c, height: 1.35);
    return Column(
      key: const ValueKey('catalog-photo-credit'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (species.credits.isNotEmpty)
          Text(species.credits.length == 1 ? 'Фото' : 'Фото (${species.credits.length} автори)',
              style: small.copyWith(fontWeight: FontWeight.w700)),
        for (final (i, credit) in species.credits.indexed)
          Padding(
            key: ValueKey('photo-credit-$i'),
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(creditText(credit), style: small),
          ),
        if (species.redBookSource case final src?) ...[
          const SizedBox(height: 8),
          Text('Червона книга — джерело', style: small.copyWith(fontWeight: FontWeight.w700)),
          Padding(
            key: const ValueKey('red-book-source'),
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText([src.text, if (src.url != null) src.url!].where((x) => x.isNotEmpty).join('\n'), style: small),
          ),
        ],
      ],
    );
  }
}

/// «Алена Ручка, iNaturalist · CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)
/// https://www.inaturalist.org/photos/161474921»
String creditText(PhotoCredit c) => [
      [
        c.author,
        if (c.license != null) '${c.license}${c.licenseUrl == null ? '' : ' (${c.licenseUrl})'}',
      ].join(' · '),
      ...c.sources,
    ].join('\n');
