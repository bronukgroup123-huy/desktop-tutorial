import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;
import 'package:flutter_client/features/catalog/catalog_browser.dart' show EdibilityBadge;
import 'package:flutter_client/features/catalog/catalog_article.dart';
import 'package:flutter_client/features/catalog/catalog_forecast_link.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';

/// Значок дерева / лісу: хвойні — 🌲, листяні — 🌳, мішаний — обидва.
String treeEmoji(String t) => switch (t) {
      'pine' || 'spruce' || 'larch' || 'coniferous' => '🌲',
      'mixed' || 'any' => '🌲🌳',
      _ => '🌳',
    };

const _monthsShort = ['Січ', 'Лют', 'Бер', 'Кві', 'Тра', 'Чер', 'Лип', 'Сер', 'Вер', 'Жов', 'Лис', 'Гру'];

/// Сторінка виду в довіднику (`/catalog/<id>`): фото, назва, значки, сезон і книжковий опис —
/// як сторінка виду у веб-довіднику.
class CatalogDetailScreen extends ConsumerWidget {
  const CatalogDetailScreen({super.key, required this.speciesId});

  final String speciesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Missing(text: 'Не вдалося відкрити довідник'),
        data: (c) {
          final s = c.byId(speciesId);
          if (s == null) return const _Missing(text: 'Цього гриба ще немає в довіднику');
          return _Detail(species: s);
        },
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          children: [
            const Align(alignment: Alignment.centerLeft, child: BackButton()),
            Expanded(child: Center(child: Text(text, style: const TextStyle(color: AppTheme.darkGreen)))),
          ],
        ),
      );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.species});

  final CatalogSpecies species;

  @override
  Widget build(BuildContext context) {
    final s = species;
    final badge = edibilityBadge(s);
    final dim = AppTheme.darkGreen.withValues(alpha: 0.65);
    return CustomScrollView(
      key: ValueKey('catalog-detail-${s.id}'),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 320,
          backgroundColor: AppTheme.backgroundColor,
          foregroundColor: AppTheme.darkGreen,
          automaticallyImplyLeading: false,
          // Кнопка «назад» на білому колі — видно і на фото.
          leading: Navigator.of(context).canPop()
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: const CircleBorder(),
                    child: const BackButton(),
                  ),
                )
              : null,
          // Назва — лише коли фото згорнулось (поверх фото вона не читається).
          flexibleSpace: LayoutBuilder(builder: (context, c) {
            final collapsed = c.maxHeight <= MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
            return Stack(fit: StackFit.expand, children: [
              Offstage(offstage: collapsed, child: _Gallery(species: s)),
              if (collapsed)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 64, right: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.merriweather(color: AppTheme.darkGreen, fontSize: 17)),
                    ),
                  ),
                ),
            ]);
          }),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          sliver: SliverList.list(children: [
            Row(
              children: [
                SpeciesIcon(type: s.id, fallbackColor: const Color(0xff8d6e63), size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
                      if (s.latin.isNotEmpty)
                        Text(s.latin, style: TextStyle(fontStyle: FontStyle.italic, color: dim)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                EdibilityBadge(label: badge.label, color: Color(badge.color)),
                if (s.redListed)
                  _Tag(text: s.rarity.isEmpty ? '📕 Червона книга' : '📕 Червона книга · ${s.rarity}', color: const Color(0xffb7791f)),
                if (s.inSeason(DateTime.now().month))
                  const _Tag(key: ValueKey('catalog-in-season'), text: '🍂 Зараз сезон', color: Color(0xff2e7d32)),
                if (s.top20) const _Tag(text: '⭐ Топ-20', color: Color(0xff7b4fb5)),
                if (s.popular) const _Tag(text: '🍲 Популярний', color: Color(0xff2f6fb3)),
              ],
            ),
            if (s.months.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SeasonStrip(months: s.months.toSet(), peak: s.peakMonths.toSet()),
            ],
            if (s.tree.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                key: const ValueKey('catalog-trees'),
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in s.tree)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Text('${treeEmoji(t)} ${kTreeLabels[t] ?? t}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.darkGreen)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            CatalogForecastLink(speciesId: s.id),
            const SizedBox(height: 8),
            CatalogArticle(species: s),
            if (s.photoAuthor != null) ...[
              const SizedBox(height: 18),
              Text(
                'Фото: ${s.photoAuthor}${s.photoLicense == null ? '' : ' · ${s.photoLicense}'}',
                key: const ValueKey('catalog-photo-credit'),
                style: TextStyle(fontSize: 11, color: dim),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      );
}

/// 12 місяців: сезон і пік плодоношення.
class _SeasonStrip extends StatelessWidget {
  const _SeasonStrip({required this.months, required this.peak});

  final Set<int> months;
  final Set<int> peak;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('catalog-season'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Сезон плодоношення', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var m = 1; m <= 12; m++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: peak.contains(m)
                          ? AppTheme.darkGreen
                          : months.contains(m)
                              ? const Color(0xff8fbf8f)
                              : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      child: Text(
                        _monthsShort[m - 1],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: peak.contains(m) ? Colors.white : AppTheme.darkGreen.withValues(alpha: months.contains(m) ? 1 : 0.4),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (peak.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: AppTheme.darkGreen, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 4),
                Text('пік', style: TextStyle(fontSize: 11, color: AppTheme.darkGreen.withValues(alpha: 0.7))),
                const SizedBox(width: 10),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xff8fbf8f), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 4),
                Text('трапляється', style: TextStyle(fontSize: 11, color: AppTheme.darkGreen.withValues(alpha: 0.7))),
              ],
            ),
          ],
        ],
      );
}

/// Гортання фото з крапками; дотик — на весь екран з масштабуванням.
class _Gallery extends StatefulWidget {
  const _Gallery({required this.species});

  final CatalogSpecies species;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.species;
    if (s.photos.isEmpty) return CatalogPhoto(name: null, speciesId: s.id);
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          key: const ValueKey('catalog-gallery'),
          itemCount: s.photos.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => _FullscreenPhotos(species: s, initial: i),
            )),
            child: CatalogPhoto(name: s.photos[i], speciesId: s.id),
          ),
        ),
        if (s.photos.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < s.photos.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 16 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: i == _page ? 0.95 : 0.6),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FullscreenPhotos extends StatelessWidget {
  const _FullscreenPhotos({required this.species, required this.initial});

  final CatalogSpecies species;
  final int initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(species.name)),
        body: PageView.builder(
          controller: PageController(initialPage: initial),
          itemCount: species.photos.length,
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 4,
            child: Center(child: CatalogPhoto(name: species.photos[i], speciesId: species.id, fit: BoxFit.contain)),
          ),
        ),
      );
}
