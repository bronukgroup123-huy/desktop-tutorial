import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/weather_scene.dart' show Mascot;
import 'package:flutter_client/features/catalog/catalog_description.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/catalog/oblast_map.dart';
import 'package:flutter_client/features/forecast/identify_view.dart' show PartGlyph;

/// Сторінка-стаття виду в довіднику (рішення PO 2026-11-16): той самий книжковий текст —
/// дослівно, — але з подачею: «Головне» вгорі (статус, небезпека, ключова ознака), паспорт
/// зі схемами частин гриба, двійники поруч, кольорові попередження, порада від маскота,
/// плитки «де і коли», карта областей, рецепти кроками з підсвіченим часом.

/// Роль розділу — визначає лише подачу.
enum ArticleKind {
  intro,
  status,
  danger,
  risks,
  passport,
  twins,
  confusions,
  where,
  worms,
  culinary,
  recipes,
  memo,
  why,
  fact,
  law,
  taxonomy,
  action,
  plain,
}

ArticleKind articleKind(DescSection s) {
  final t = s.title ?? '';
  switch (s.emoji) {
    case null:
      return switch (t) {
        '' => ArticleKind.intro,
        'Чи може ви зламати закон?' => ArticleKind.law,
        'Чим цікавий?' => ArticleKind.fact,
        'Таксономія' => ArticleKind.taxonomy,
        'Що робити, якщо ви його знайшли?' => ArticleKind.action,
        _ => ArticleKind.plain,
      };
    case '🍄':
      return ArticleKind.intro;
    case '✅':
      return ArticleKind.status;
    case '⚠️':
      if (t.startsWith('Обережно, двійники')) return ArticleKind.twins;
      if (t.startsWith('З ким можна сплутати')) return ArticleKind.confusions;
      if (t.startsWith('Головні ризики')) return ArticleKind.risks;
      if (t.startsWith('Статус:')) return ArticleKind.status;
      return ArticleKind.danger;
    case '🔍':
      return ArticleKind.passport;
    case '🗺️':
      return ArticleKind.where;
    case '🪱':
      return ArticleKind.worms;
    case '🍳':
      return ArticleKind.culinary;
    case '🍽️':
      return ArticleKind.recipes;
    case '📋':
      return ArticleKind.memo;
    case '🧪':
      return ArticleKind.why;
    case '💡':
      return ArticleKind.fact;
  }
  return ArticleKind.plain;
}

/// Що піднімається в «Головне» (рядки переносяться, не дублюються).
class ArticleSummary {
  String? status;
  final List<({String title, List<String> lines})> dangers = [];
  final List<String> facts = [];
  String? keyFeature;
  DescSection? law;
}

/// Розібрати опис: «Головне» і решта розділів у книжковому порядку.
({ArticleSummary summary, List<(ArticleKind, DescSection)> body}) buildArticle(CatalogSpecies sp) {
  final summary = ArticleSummary();
  final body = <(ArticleKind, DescSection)>[];
  for (final s in descSections(sp.description)) {
    var kind = articleKind(s);
    switch (kind) {
      case ArticleKind.status when summary.status == null:
        summary.status = s.title;
        kind = ArticleKind.intro; // абзаци під статусом — звичайний вступ
      case ArticleKind.danger:
        summary.dangers.add((title: s.title ?? '', lines: s.lines));
        continue;
      case ArticleKind.law:
        summary.law = s;
        continue;
      case ArticleKind.intro:
        // Вступ без емодзі (отруйні, Червона книга): «Бейдж», «Небезпека», «Природоохоронний статус» — у «Головне».
        final rest = <String>[];
        for (final line in s.lines) {
          final t = line.trim();
          final kv = descKv.firstMatch(t);
          final key = kv?.group(1);
          if (t == sp.name.trim()) continue; // назва — вже в шапці сторінки
          if (key == 'Бейдж' || key == 'Природоохоронний статус') {
            summary.status ??= t;
          } else if (key == 'Симптоми' || key == 'Небезпека') {
            summary.facts.add(t);
          } else {
            rest.add(line);
          }
        }
        s.lines
          ..clear()
          ..addAll(rest);
      case ArticleKind.passport:
        final i = s.lines.indexWhere((l) => l.trim().startsWith('Ключова ознака:'));
        if (i >= 0) summary.keyFeature = s.lines.removeAt(i).trim();
      default:
    }
    if (kind == ArticleKind.intro && s.lines.every((l) => l.trim().isEmpty)) continue;
    body.add((kind, s));
  }
  return (summary: summary, body: body);
}

/// Колір статусу — за їстівністю виду.
Color statusColor(CatalogSpecies s) => switch (s.edibility) {
      _ when s.redListed => const Color(0xffb7791f),
      'deadly_poisonous' => const Color(0xff8e1b1b),
      'poisonous' => const Color(0xffc62828),
      'conditionally_edible' => const Color(0xffd9822b),
      'inedible' => const Color(0xff6b7a70),
      'edible' => const Color(0xff2e7d32),
      _ => const Color(0xff6b7a70),
    };

IconData statusIcon(CatalogSpecies s) => switch (s.edibility) {
      _ when s.redListed => Icons.menu_book_rounded,
      'deadly_poisonous' || 'poisonous' => Icons.dangerous_rounded,
      'conditionally_edible' => Icons.local_fire_department_rounded,
      'inedible' => Icons.no_food_rounded,
      'edible' => Icons.check_circle_rounded,
      _ => Icons.help_outline_rounded,
    };

class CatalogArticle extends StatelessWidget {
  const CatalogArticle({super.key, required this.species});

  final CatalogSpecies species;

  @override
  Widget build(BuildContext context) {
    if (species.description.trim().isEmpty) {
      return Text('Опису ще немає.', style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.6)));
    }
    final a = buildArticle(species);
    var mapShown = false;
    final children = <Widget>[_Summary(species: species, summary: a.summary)];
    for (final (kind, s) in a.body) {
      final w = switch (kind) {
        ArticleKind.intro => _Plain(section: s, headed: false),
        ArticleKind.status => _Callout.status(species, s),
        ArticleKind.risks => _Callout(
            color: const Color(0xffb7791f),
            icon: Icons.warning_amber_rounded,
            title: s.title,
            child: DescBlocks(lines: s.lines),
          ),
        ArticleKind.passport => _Passport(section: s),
        ArticleKind.twins => _Twins(species: species, section: s),
        ArticleKind.confusions => _Confusions(section: s),
        ArticleKind.where => _Where(section: s),
        ArticleKind.worms => _Tips(section: s),
        ArticleKind.culinary => _Accordion(section: s, child: DescBlocks(lines: s.lines, time: true)),
        ArticleKind.recipes => _Accordion(section: s, child: _Recipes(lines: s.lines)),
        ArticleKind.memo => _Memo(section: s),
        ArticleKind.why => _Callout(
            color: const Color(0xffc62828),
            icon: Icons.science_outlined,
            title: s.title,
            child: DescBlocks(lines: s.lines),
          ),
        ArticleKind.fact => _MascotTip(title: s.title, lines: s.lines),
        ArticleKind.taxonomy => _Taxonomy(section: s),
        ArticleKind.action => _Callout(
            color: const Color(0xff2e7d32),
            icon: Icons.photo_camera_outlined,
            title: s.title,
            child: DescBlocks(lines: s.lines),
          ),
        ArticleKind.danger || ArticleKind.law || ArticleKind.plain => _Plain(section: s),
      };
      children.add(w);
      // Карта областей — після розділу «де росте».
      if (!mapShown && (kind == ArticleKind.where || s.title == 'Де росте?') && species.zones.isNotEmpty) {
        children.add(OblastMap(zones: species.zones));
        mapShown = true;
      }
    }
    if (!mapShown && species.zones.isNotEmpty) {
      children.add(const _Heading(icon: Icons.map_outlined, title: 'Поширення в Україні'));
      children.add(OblastMap(zones: species.zones));
    }
    return Column(
        key: const ValueKey('catalog-description'), crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

// ─── Заголовки й рамки ──────────────────────────────────────────────────────

class _Heading extends StatelessWidget {
  const _Heading({this.emoji, this.icon, required this.title});

  final String? emoji;
  final IconData? icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 18))
            else if (icon != null)
              Icon(icon, size: 20, color: AppTheme.darkGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style:
                      GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
            ),
          ],
        ),
      );
}

const _redBookIcons = {
  'Короткий опис': Icons.notes_rounded,
  'Як виглядає?': Icons.visibility_outlined,
  'Де росте?': Icons.park_outlined,
  'Чому він такий рідкісний?': Icons.trending_down_rounded,
};

class _Plain extends StatelessWidget {
  const _Plain({required this.section, this.headed = true});

  final DescSection section;
  final bool headed;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (headed && section.title != null)
            _Heading(emoji: section.emoji, icon: _redBookIcons[section.title], title: section.title!),
          DescBlocks(lines: section.lines),
        ],
      );
}

/// Кольорова плашка: статус, ризики, «чому небезпечний», «що робити».
class _Callout extends StatelessWidget {
  const _Callout({required this.color, required this.icon, this.title, required this.child, this.strong = false});

  factory _Callout.status(CatalogSpecies sp, DescSection s) => _Callout(
        color: statusColor(sp),
        icon: statusIcon(sp),
        title: s.title,
        strong: true,
        child: DescBlocks(lines: s.lines),
      );

  final Color color;
  final IconData icon;
  final String? title;
  final Widget child;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title!,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: strong ? color : AppTheme.darkGreen, height: 1.3)),
                  ),
                ],
              ),
            child,
          ],
        ),
      );
}

// ─── «Головне» ──────────────────────────────────────────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({required this.species, required this.summary});

  final CatalogSpecies species;
  final ArticleSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final color = statusColor(species);
    final rows = <Widget>[
      if (s.status != null)
        Container(
          key: const ValueKey('article-status'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(statusIcon(species), color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(kvSpan(s.status!, const TextStyle(color: Colors.white, fontSize: 14, height: 1.3))),
              ),
            ],
          ),
        ),
      for (final f in s.facts)
        _SummaryLine(
          icon: f.startsWith('Симптоми') ? Icons.schedule_rounded : Icons.report_rounded,
          color: const Color(0xffc62828),
          child: Text.rich(kvSpan(f, kDescText)),
        ),
      for (final (i, d) in s.dangers.indexed)
        Container(
          key: ValueKey('article-danger-$i'),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xffc62828).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xffc62828).withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_rounded, color: Color(0xffc62828), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff8e1b1b), height: 1.3)),
                    if (d.lines.any((l) => l.trim().isNotEmpty)) DescBlocks(lines: d.lines),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (s.law != null)
        _Callout(
          color: const Color(0xffb7791f),
          icon: Icons.gavel_rounded,
          title: s.law!.title,
          child: DescBlocks(lines: s.law!.lines),
        ),
      if (s.keyFeature != null)
        _SummaryLine(
          key: const ValueKey('article-key-feature'),
          icon: Icons.star_rounded,
          color: AppTheme.accentOrange,
          child: Text.rich(kvSpan(s.keyFeature!, kDescText)),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('article-summary'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({super.key, required this.icon, required this.color, required this.child});

  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      );
}

// ─── Паспорт: схема частини гриба біля кожної ознаки ────────────────────────

/// Схема для ознаки «Шапка: …» → (частина, вид низу шапки) або значок.
({String? part, String? kind, IconData? icon}) passportGlyph(String key) {
  final k = key.toLowerCase();
  String? under() => k.contains('трубоч')
      ? 'tubes'
      : k.contains('склад')
          ? 'folds'
          : (k.contains('шип') || k.contains('голк'))
              ? 'spines'
              : 'gills';
  if (k.startsWith('низ шапки') ||
      k.contains('пластин') ||
      k.contains('трубоч') ||
      k.contains('гіменофор') ||
      k.contains('шип') ||
      k.contains('склад')) {
    return (part: 'underside', kind: under(), icon: null);
  }
  if (k.startsWith('шапка') || k.startsWith('капелюх') || k.startsWith('капелюш')) {
    return (part: 'cap', kind: null, icon: null);
  }
  if (k.startsWith('ніжка')) return (part: 'stem', kind: null, icon: null);
  if (k.startsWith('кільце')) return (part: 'ring', kind: null, icon: null);
  if (k.startsWith("м'якоть") || k.startsWith('м’якоть') || k.startsWith('мякоть')) {
    return (part: 'flesh', kind: null, icon: null);
  }
  if (k.contains('спор')) return (part: null, kind: null, icon: Icons.grain_rounded);
  if (k.startsWith('запах')) return (part: null, kind: null, icon: Icons.air_rounded);
  if (k.startsWith('смак')) return (part: null, kind: null, icon: Icons.restaurant_rounded);
  if (k.contains('місце') || k.contains('росте')) return (part: null, kind: null, icon: Icons.place_outlined);
  return (part: null, kind: null, icon: Icons.info_outline_rounded);
}

class _Passport extends StatelessWidget {
  const _Passport({required this.section});

  final DescSection section;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final rest = <String>[];
    void flush() {
      if (rest.isNotEmpty) rows.add(DescBlocks(lines: List.of(rest)));
      rest.clear();
    }

    for (final line in section.lines) {
      final m = descKv.firstMatch(line.trim());
      if (m == null || line.contains('\t')) {
        rest.add(line);
        continue;
      }
      flush();
      final g = passportGlyph(m.group(1)!);
      rows.add(Container(
        key: ValueKey('passport-${m.group(1)}'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xfff4f1e8), borderRadius: BorderRadius.circular(10)),
              child: g.part != null
                  ? PartGlyph(part: g.part!, kind: g.kind)
                  : Icon(g.icon, color: const Color(0xff8b5a2b), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.group(1)!, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                  Text.rich(inlineSpans(m.group(2)!, kDescText)),
                ],
              ),
            ),
          ],
        ),
      ));
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_Heading(emoji: section.emoji, title: section.title ?? ''), ...rows],
    );
  }
}

// ─── Двійники поруч ─────────────────────────────────────────────────────────

/// Вид довідника за назвою з таблиці («Гірчак (жовчний гриб)», «Галерина облямована»).
CatalogSpecies? findByName(Catalog? c, String text) {
  if (c == null) return null;
  final t = text.toLowerCase().replaceAll(RegExp(r'\s*\(.*'), '').trim();
  if (t.isEmpty) return null;
  final latin = RegExp(r'\(([A-Z][a-z]+ [a-z]+)').firstMatch(text)?.group(1)?.toLowerCase();
  for (final s in c.species) {
    if (s.name.toLowerCase() == t || (latin != null && s.latin.toLowerCase() == latin)) return s;
  }
  return null;
}

/// ✅ / ❌ на початку клітинки — значком (текст після нього — дослівно).
Widget markCell(String text, TextStyle style) {
  final t = text.trim();
  IconData? icon;
  Color? color;
  var rest = t;
  if (t.startsWith('✅')) {
    icon = Icons.check_circle_rounded;
    color = const Color(0xff2e7d32);
    rest = t.substring(1).trim();
  } else if (t.startsWith('❌')) {
    icon = Icons.cancel_rounded;
    color = const Color(0xffc62828);
    rest = t.substring(1).trim();
  }
  final txt = Text.rich(inlineSpans(rest, style));
  if (icon == null) return txt;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.only(top: 1, right: 4), child: Icon(icon, size: 16, color: color)),
      Expanded(child: txt),
    ],
  );
}

class _Twins extends ConsumerWidget {
  const _Twins({required this.species, required this.section});

  final CatalogSpecies species;
  final DescSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final lines = section.lines;
    final start = lines.indexWhere((l) => l.contains('\t'));
    var end = start;
    while (end >= 0 && end < lines.length && lines[end].contains('\t')) {
      end++;
    }
    final rows = start < 0
        ? <List<String>>[]
        : [for (final l in lines.sublist(start, end)) l.split(RegExp(r'\t+')).map((c) => c.trim()).toList()];
    final ok = rows.length > 1 && rows.first.length == 3 && rows.every((r) => r.length <= 3);
    final children = <Widget>[_Heading(emoji: section.emoji, title: section.title ?? '')];
    if (!ok) {
      children.add(DescBlocks(lines: lines));
    } else {
      if (start > 0) children.add(DescBlocks(lines: lines.sublist(0, start)));
      final head = rows.first;
      final twin = findByName(catalog, head[2]);
      Widget side(String name, CatalogSpecies? sp, {required bool ours}) {
        final color = ours ? const Color(0xff2e7d32) : const Color(0xffc62828);
        final card = Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 40, height: 40, child: CatalogPhoto(name: sp?.thumb, speciesId: sp?.id ?? '')),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color, height: 1.2)),
              ),
              if (!ours && sp != null) Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        );
        if (ours || sp == null) return card;
        return InkWell(
          key: ValueKey('twin-link-${sp.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/catalog/${sp.id}'),
          child: card,
        );
      }

      // Підпис першого стовпця («Ознака») — над рядками порівняння.
      if (head[0].isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(head[0], style: TextStyle(fontSize: 11, color: AppTheme.darkGreen.withValues(alpha: 0.55))),
        ));
      }
      children.add(Padding(
        key: const ValueKey('article-twins'),
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: side(head[1], species, ours: true)),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                child: Text('vs', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen))),
            Expanded(child: side(head[2], twin, ours: false)),
          ],
        ),
      ));
      const cellStyle = TextStyle(color: AppTheme.darkGreen, fontSize: 13, height: 1.3);
      for (final r in rows.skip(1)) {
        children.add(Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r[0],
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.darkGreen.withValues(alpha: 0.65))),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: markCell(r.length > 1 ? r[1] : '', cellStyle)),
                  Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: const Color(0xffe3dccb)),
                  Expanded(child: markCell(r.length > 2 ? r[2] : '', cellStyle)),
                ],
              ),
            ],
          ),
        ));
      }
      final after = lines.sublist(end);
      final note = after.indexWhere((l) => l.trim().startsWith('Важливо:'));
      if (note >= 0) {
        if (note > 0) children.add(DescBlocks(lines: after.sublist(0, note)));
        children.add(_Callout(
          color: const Color(0xffb7791f),
          icon: Icons.priority_high_rounded,
          child: DescBlocks(lines: [after[note]]),
        ));
        children.add(DescBlocks(lines: after.sublist(note + 1)));
      } else {
        children.add(DescBlocks(lines: after));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// «З ким можна сплутати» (отруйні): «B40 Рядовка майська (Calocybe gambosa)» + ознаки — картками.
class _Confusions extends ConsumerWidget {
  const _Confusions({required this.section});

  final DescSection section;

  static final _head = RegExp(r'^([A-Z]\d+)\s+(.+)$');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final groups = <({String code, String name, List<String> lines})>[];
    final before = <String>[];
    for (final line in section.lines) {
      final m = _head.firstMatch(line.trim());
      if (m != null) {
        groups.add((code: m.group(1)!, name: m.group(2)!, lines: <String>[]));
      } else if (groups.isEmpty) {
        before.add(line);
      } else if (line.trim().isNotEmpty) {
        groups.last.lines.add(line.trim());
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(emoji: section.emoji, title: section.title ?? ''),
        if (before.isNotEmpty) DescBlocks(lines: before),
        for (final g in groups)
          Builder(builder: (context) {
            final sp = findByName(catalog, g.name);
            final card = Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        SizedBox(width: 48, height: 48, child: CatalogPhoto(name: sp?.thumb, speciesId: sp?.id ?? '')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: '${g.code} ',
                              style: TextStyle(fontSize: 11, color: AppTheme.darkGreen.withValues(alpha: 0.5))),
                          TextSpan(
                              text: g.name,
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                        ])),
                        for (final l in g.lines) DescBullet(child: Text.rich(inlineSpans(l, kDescText))),
                      ],
                    ),
                  ),
                  if (sp != null) const Icon(Icons.chevron_right_rounded, color: AppTheme.darkGreen),
                ],
              ),
            );
            if (sp == null) return card;
            return InkWell(onTap: () => context.push('/catalog/${sp.id}'), child: card);
          }),
      ],
    );
  }
}

// ─── «Де, коли і як шукати» — плитки ────────────────────────────────────────

/// «🌲 Де росте?» → (емодзі, ключ): емодзі — усе до першої літери.
final _leadingEmoji = RegExp(r'^([^\p{L}\p{N}\s]+)\s*(.+)$', unicode: true);

class _Where extends StatelessWidget {
  const _Where({required this.section});

  final DescSection section;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[_Heading(emoji: section.emoji, title: section.title ?? '')];
    final rest = <String>[];
    var header = true;
    for (final line in section.lines) {
      if (!line.contains('\t')) {
        rest.add(line);
        continue;
      }
      final cells = line.split(RegExp(r'\t+')).map((c) => c.trim()).toList();
      if (header && cells.length == 2 && !_leadingEmoji.hasMatch(cells[0])) {
        header = false; // «Параметр | Опис…» — шапка таблиці, плитки її не потребують
        continue;
      }
      header = false;
      if (cells.length != 2) {
        rest.add(line);
        continue;
      }
      if (rest.isNotEmpty) {
        children.add(DescBlocks(lines: List.of(rest)));
        rest.clear();
      }
      final m = _leadingEmoji.firstMatch(cells[0]);
      final emoji = m?.group(1);
      final key = m?.group(2) ?? cells[0];
      if (key.startsWith('Порада')) {
        children.add(_MascotTip(title: key, lines: [cells[1]]));
        continue;
      }
      children.add(Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 30, child: Text(emoji ?? '•', style: const TextStyle(fontSize: 20))),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(key, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                  Text.rich(inlineSpans(cells[1], kDescText)),
                ],
              ),
            ),
          ],
        ),
      ));
    }
    if (rest.isNotEmpty) children.add(DescBlocks(lines: rest));
    return Column(
        key: const ValueKey('article-where'), crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

// ─── Поради картками (тест на червивість) ───────────────────────────────────

class _Tips extends StatelessWidget {
  const _Tips({required this.section});

  final DescSection section;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[_Heading(emoji: section.emoji, title: section.title ?? '')];
    final rest = <String>[];
    var n = 0;
    for (final line in section.lines) {
      final m = descKv.firstMatch(line.trim());
      if (m == null || line.contains('\t')) {
        rest.add(line);
        continue;
      }
      if (rest.isNotEmpty) {
        children.add(DescBlocks(lines: List.of(rest)));
        rest.clear();
      }
      n++;
      children.add(_Step(n: n, title: m.group(1)!, text: m.group(2)!));
    }
    if (rest.isNotEmpty) children.add(DescBlocks(lines: rest));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, this.title, required this.text, this.time = false});

  final int n;
  final String? title;
  final String text;
  final bool time;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: AppTheme.darkGreen,
              child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                  Text.rich(inlineSpans(text, kDescText, time: time)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─── Кулінарія: згорнуто; рецепти — кроками ─────────────────────────────────

class _Accordion extends StatelessWidget {
  const _Accordion({required this.section, required this.child});

  final DescSection section;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(top: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('desc-acc-${section.title}'),
            leading: Text(section.emoji ?? '', style: const TextStyle(fontSize: 20)),
            title: Text(section.title ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [child],
          ),
        ),
      );
}

/// Рецепт з опису: «1. 🧄 Назва», «Інгредієнти:» (список), «Приготування:» (кроки), «Порада: …».
class Recipe {
  Recipe(this.title);

  final String title;
  String ingredientsLabel = 'Інгредієнти:';
  String stepsLabel = 'Приготування:';
  final List<String> intro = [];
  final List<String> ingredients = [];
  final List<String> steps = [];
  final List<String> notes = [];
}

final _recipeTitle = RegExp(r'^\d+\.\s+(.+)$');

/// Проміжний підпис усередині рецепта («Для маринаду на 1 літр води:») — окремим рядком, без номера.
bool isRecipeLabel(String s) => s.endsWith(':') && s.length < 45;

/// Розділ рецептів: вступ до першого рецепта («Знайдено перевірені рецепти…») і рецепти.
/// Немає нумерованих рецептів — `recipes` порожній (розділ показується як текст).
({List<String> preface, List<Recipe> recipes}) parseRecipeSection(List<String> lines) {
  final preface = <String>[];
  final out = <Recipe>[];
  var mode = 0; // 0 — вступ, 1 — інгредієнти, 2 — кроки
  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    final t = _recipeTitle.firstMatch(l);
    if (t != null) {
      out.add(Recipe(t.group(1)!));
      mode = 0;
      continue;
    }
    if (out.isEmpty) {
      preface.add(l);
      continue;
    }
    final r = out.last;
    if (l.startsWith('Інгредієнти') && l.length < 45) {
      mode = 1;
      r.ingredientsLabel = l; // підпис — дослівно з книги
    } else if (l.startsWith('Приготування') && l.length < 45) {
      mode = 2;
      r.stepsLabel = l;
    } else if (l.startsWith('Порада:')) {
      r.notes.add(l);
    } else if (mode == 1) {
      r.ingredients.add(l.replaceFirst(descBullet, ''));
    } else if (mode == 2) {
      r.steps.add(l.replaceFirst(descBullet, ''));
    } else {
      r.intro.add(l);
    }
  }
  return (preface: preface, recipes: out);
}

List<Recipe> parseRecipes(List<String> lines) => parseRecipeSection(lines).recipes;

class _Recipes extends StatelessWidget {
  const _Recipes({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final parsed = parseRecipeSection(lines);
    final recipes = parsed.recipes;
    if (recipes.isEmpty) return DescBlocks(lines: lines, time: true);
    return Column(
      key: const ValueKey('article-recipes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parsed.preface.isNotEmpty) DescBlocks(lines: parsed.preface, time: true),
        for (final r in recipes)
          Container(
            margin: const EdgeInsets.only(top: 10),
            child: Material(
              color: const Color(0xfffaf7ef),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                  childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.intro.isNotEmpty) DescBlocks(lines: r.intro, time: true),
                    if (r.ingredients.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text(r.ingredientsLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final i in r.ingredients)
                            if (isRecipeLabel(i))
                              SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(i,
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                                ),
                              )
                            else
                              Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xffe3dccb)),
                              ),
                              child: Text(i, style: const TextStyle(fontSize: 12, color: AppTheme.darkGreen)),
                            ),
                        ],
                      ),
                    ],
                    if (r.steps.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(r.stepsLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                      ),
                      ..._stepWidgets(r.steps),
                    ],
                    for (final n in r.notes) _MascotTip(lines: [n]),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Кроки рецепта з номерами; проміжні підписи («Для соусу:») — без номера.
List<Widget> _stepWidgets(List<String> steps) {
  final out = <Widget>[];
  var n = 0;
  for (final st in steps) {
    if (isRecipeLabel(st)) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(st, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
      ));
    } else {
      out.add(_Step(n: ++n, text: st, time: true));
    }
  }
  return out;
}

// ─── Пам'ятка: питання — відповідь ──────────────────────────────────────────

class _Memo extends StatelessWidget {
  const _Memo({required this.section});

  final DescSection section;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final l in section.lines)
        if (l.contains('\t')) l.split(RegExp(r'\t+')).map((c) => c.trim()).toList(),
    ];
    final qa = rows.isNotEmpty && rows.every((r) => r.length == 2);
    final rest = [
      for (final l in section.lines)
        if (!l.contains('\t')) l
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(emoji: section.emoji, title: section.title ?? ''),
        if (!qa)
          DescBlocks(lines: section.lines)
        else ...[
          for (final r in (DescTable.hasHeader(rows) ? rows.skip(1) : rows))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.help_outline_rounded, size: 20, color: AppTheme.accentOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r[0], style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                        const SizedBox(height: 2),
                        markCell(r[1], kDescText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (rest.any((l) => l.trim().isNotEmpty)) DescBlocks(lines: rest),
        ],
      ],
    );
  }
}

// ─── Таксономія — компактно ─────────────────────────────────────────────────

class _Taxonomy extends StatelessWidget {
  const _Taxonomy({required this.section});

  final DescSection section;

  @override
  Widget build(BuildContext context) {
    final kv = [
      for (final l in section.lines)
        if (descKv.hasMatch(l.trim())) descKv.firstMatch(l.trim())!
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(icon: Icons.account_tree_outlined, title: section.title ?? ''),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in kv)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${m.group(1)}: ',
                      style: TextStyle(fontSize: 11, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
                  TextSpan(
                      text: m.group(2),
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.darkGreen)),
                ])),
              ),
          ],
        ),
        DescBlocks(lines: [
          for (final l in section.lines)
            if (!descKv.hasMatch(l.trim())) l
        ]),
      ],
    );
  }
}

// ─── Порада / цікавий факт — від маскота ────────────────────────────────────

class _MascotTip extends StatelessWidget {
  const _MascotTip({this.title, required this.lines});

  final String? title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('article-mascot'),
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Mascot(size: 52),
            const SizedBox(width: 4),
            Expanded(
              child: CustomPaint(
                painter: _BubblePainter(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff6b4a12))),
                      DescBlocks(lines: lines),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Хмаринка-репліка з «хвостиком» до маскота зліва внизу.
class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tail = 8.0;
    final r =
        RRect.fromRectAndRadius(Rect.fromLTWH(tail, 0, size.width - tail, size.height), const Radius.circular(14));
    final path = Path()
      ..addRRect(r)
      ..moveTo(tail, size.height - 22)
      ..lineTo(0, size.height - 8)
      ..lineTo(tail + 10, size.height - 12)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xfffff4d6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
