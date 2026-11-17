import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart' show EdibilityBadge;
import 'package:flutter_client/features/catalog/catalog_article.dart';
import 'package:flutter_client/features/catalog/catalog_forecast_link.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/catalog/catalog_motion.dart' show reduceMotion, seg;
import 'package:flutter_client/features/catalog/mushroom_character.dart' show hasCharacter;
import 'package:flutter_client/features/catalog/mushroom_scenes.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;

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
  const CatalogDetailScreen({super.key, required this.speciesId, this.focus});

  final String speciesId;

  /// `twins` — одразу прокрутити до «Обережно, двійники» (з результату розпізнавання «Як відрізнити»).
  final String? focus;

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
          final detail = _Detail(species: s);
          return focus == 'twins' ? _FocusTwins(child: detail) : detail;
        },
      ),
    );
  }
}

/// Відкрито з «Як відрізнити» (результат розпізнавання) — прокрутити до розділу двійників.
class _FocusTwins extends StatefulWidget {
  const _FocusTwins({required this.child});

  final Widget child;

  @override
  State<_FocusTwins> createState() => _FocusTwinsState();
}

class _FocusTwinsState extends State<_FocusTwins> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scroll());
  }

  void _scroll() {
    if (!mounted) return;
    Element? target;
    void visit(Element e) {
      if (target != null) return;
      if (e.widget.key == const ValueKey('article-twins-section')) {
        target = e;
        return;
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    if (target != null) {
      Scrollable.ensureVisible(target!, alignment: 0.05, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
            _Header(species: s),
            // Отруйним сезон плодоношення не показуємо (рішення PO 2026-11-16).
            if (s.showsSeason && s.months.isNotEmpty) ...[
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

/// Шапка: значок, назва, латина й плашки. Для Топ-20 праворуч — віконце з грибом-персонажем:
/// стоїть, кліпає; затиснути значок чи віконце — коло сценок, сценка грає тут же.
class _Header extends StatefulWidget {
  const _Header({required this.species});

  final CatalogSpecies species;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final _slot = GlobalKey<CharacterSlotState>();

  @override
  Widget build(BuildContext context) {
    final s = widget.species;
    final badge = edibilityBadge(s);
    final dim = AppTheme.darkGreen.withValues(alpha: 0.65);
    final playful = hasCharacter(s.id);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (playful)
              PlayfulSpeciesIcon(speciesId: s.id, onPick: (scene) => _slot.currentState?.play(scene))
            else
              SpeciesIcon(type: s.id, fallbackColor: const Color(0xff8d6e63), size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
                  if (s.latin.isNotEmpty) Text(s.latin, style: TextStyle(fontStyle: FontStyle.italic, color: dim)),
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
      ],
    );
    if (!playful) return info;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: info),
        const SizedBox(width: 8),
        CharacterSlot(key: _slot, speciesId: s.id),
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
/// 12 місяців: сезон і пік плодоношення. Під час появи вздовж місяців пробігає листочок —
/// клітинки сезону загоряються слідом, місяці піку на мить «спалахують» (календар гортається).
class _SeasonStrip extends StatefulWidget {
  const _SeasonStrip({required this.months, required this.peak});

  final Set<int> months;
  final Set<int> peak;

  @override
  State<_SeasonStrip> createState() => _SeasonStripState();
}

class _SeasonStripState extends State<_SeasonStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final months = widget.months, peak = widget.peak;
    return Column(
      key: const ValueKey('catalog-season'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Сезон плодоношення', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final run = seg(t, 0, 0.7); // листочок біжить січень → грудень
            return LayoutBuilder(builder: (context, box) {
              final cell = box.maxWidth / 12;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    children: [
                      for (var m = 1; m <= 12; m++)
                        Builder(builder: (context) {
                          final lit = seg(run * 12, m - 1.0, m - 0.2); // загоряється, коли листочок поруч
                          final glow = peak.contains(m) ? math.sin(math.pi * seg(t, 0.72, 0.95)) : 0.0;
                          final target = peak.contains(m)
                              ? AppTheme.darkGreen
                              : months.contains(m)
                                  ? const Color(0xff8fbf8f)
                                  : Colors.white;
                          final on = months.contains(m) || peak.contains(m);
                          return Expanded(
                            child: Transform.scale(
                              scale: 1 + 0.12 * glow + (on ? 0.08 * math.sin(math.pi * lit) : 0),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: Color.lerp(Colors.white, target, on ? lit : 1),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: glow > 0
                                      ? [BoxShadow(color: const Color(0xff7cc47f).withValues(alpha: 0.7 * glow), blurRadius: 10 * glow)]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: FittedBox(
                                  child: Text(
                                    _monthsShort[m - 1],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color.lerp(
                                        AppTheme.darkGreen.withValues(alpha: on ? 1 : 0.4),
                                        peak.contains(m) ? Colors.white : AppTheme.darkGreen,
                                        peak.contains(m) ? lit : 0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                  // Листочок, що пробігає над місяцями.
                  if (run > 0 && run < 1)
                    Positioned(
                      left: cell * 12 * run - 9,
                      top: -14 - 6 * math.sin(run * math.pi * 12).abs(),
                      child: Transform.rotate(
                        angle: run * math.pi * 6,
                        child: const Text('🍂', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                ],
              );
            });
          },
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
