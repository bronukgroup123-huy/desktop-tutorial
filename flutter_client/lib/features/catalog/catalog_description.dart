import 'package:flutter/material.dart';

import 'package:flutter_client/core/app_theme.dart';

/// Розбір книжкового опису виду на розділи і базові блоки тексту (абзаци, списки,
/// «Ключ: значення», таблиці). Текст показується дослівно — змінюється лише подача
/// (рішення PO 2026-11-16: «без зміни тексту і сенсу, лише візуальна частина»).

const kDescHeadings = ['🍄', '✅', '🔍', '⚠️', '🗺️', '🪱', '🍳', '🍽️', '📋', '🧪', '📍', '💡'];

/// Підзаголовки описів Червоної книги (рядки без емодзі, однакові в усіх описах).
const kRedBookHeadings = [
  'Чи може ви зламати закон?',
  'Короткий опис',
  'Чим цікавий?',
  'Таксономія',
  'Як виглядає?',
  'Де росте?',
  'Чому він такий рідкісний?',
  'Що робити, якщо ви його знайшли?',
];

/// Розділ опису: емодзі-заголовок (`emoji`) або підзаголовок Червоної книги (`emoji == null`,
/// `title` задано); вступ без заголовка — обидва `null`.
class DescSection {
  DescSection({this.emoji, this.title, List<String>? lines}) : lines = lines ?? [];

  final String? emoji;
  final String? title;
  final List<String> lines;
}

({String emoji, String title})? descHeading(String line) {
  if (line.contains('\t')) return null;
  final t = line.trim();
  for (final e in kDescHeadings) {
    if (t.startsWith('$e ') || t.startsWith('$e ')) return (emoji: e, title: t.substring(e.length).trim());
  }
  return null;
}

List<DescSection> descSections(String raw) {
  final out = <DescSection>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final h = descHeading(line);
    if (h != null) {
      out.add(DescSection(emoji: h.emoji, title: h.title));
    } else if (kRedBookHeadings.contains(line.trim())) {
      out.add(DescSection(title: line.trim()));
    } else if (out.isEmpty) {
      out.add(DescSection(lines: [line]));
    } else {
      out.last.lines.add(line);
    }
  }
  return out;
}

final descBullet = RegExp(r'^\s*[-•*]\s+');
final descKv = RegExp(r'^([^:\n]{1,45}):\s*(.+)$');

/// Час приготування в тексті («15–20 хвилин», «1 год») — підсвічується значком.
final descTime = RegExp(r'(\d+(?:[,.]\d+)?(?:\s*[–-]\s*\d+)?\s*(?:хвилин[иу]?|хв\.?|годин[иу]?|год\.?))');

/// Рядок із **жирним** (і, за потреби, підсвіченим часом) → TextSpan. Текст не змінюється.
TextSpan inlineSpans(String s, TextStyle base, {bool time = false}) {
  final spans = <InlineSpan>[];
  void plain(String part) {
    if (!time) {
      spans.add(TextSpan(text: part));
      return;
    }
    var i = 0;
    for (final m in descTime.allMatches(part)) {
      if (m.start > i) spans.add(TextSpan(text: part.substring(i, m.start)));
      spans.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.timer_outlined, size: 14, color: AppTheme.accentOrange)),
      ));
      spans.add(TextSpan(text: m.group(0), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xffa35a00))));
      i = m.end;
    }
    if (i < part.length) spans.add(TextSpan(text: part.substring(i)));
  }

  final re = RegExp(r'\*\*([^*]+)\*\*');
  var i = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > i) plain(s.substring(i, m.start));
    spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
    i = m.end;
  }
  if (i < s.length) plain(s.substring(i));
  return TextSpan(style: base, children: spans);
}

/// «Шапка: …» — ключ жирним.
TextSpan kvSpan(String s, TextStyle base, {bool time = false}) {
  final m = descKv.firstMatch(s);
  if (m == null) return inlineSpans(s, base, time: time);
  return TextSpan(style: base, children: [
    TextSpan(text: '${m.group(1)}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
    inlineSpans(m.group(2)!, base, time: time),
  ]);
}

const kDescText = TextStyle(color: AppTheme.darkGreen, fontSize: 14, height: 1.35);

/// Рядки опису: абзаци, списки, «Ключ: значення», таблиці (стовпці через табуляцію).
class DescBlocks extends StatelessWidget {
  const DescBlocks({super.key, required this.lines, this.time = false});

  final List<String> lines;

  /// Підсвічувати час приготування (кулінарні розділи).
  final bool time;

  @override
  Widget build(BuildContext context) {
    const base = kDescText;
    final out = <Widget>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final t = line.trim();
      if (t.isEmpty) {
        i++;
        continue;
      }
      if (line.contains('\t')) {
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].contains('\t')) {
          rows.add(lines[i].split(RegExp(r'\t+')).map((c) => c.trim()).toList());
          i++;
        }
        out.add(DescTable(rows: rows));
        continue;
      }
      if (descBullet.hasMatch(t)) {
        final items = <String>[];
        while (i < lines.length && descBullet.hasMatch(lines[i].trim())) {
          items.add(lines[i].trim().replaceFirst(descBullet, ''));
          i++;
        }
        out.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final it in items) DescBullet(child: Text.rich(kvSpan(it, base, time: time)))],
          ),
        ));
        continue;
      }
      // Абзац: рядки до порожнього / таблиці / списку.
      final buf = <String>[t];
      var j = i + 1;
      while (j < lines.length) {
        final n = lines[j].trim();
        if (n.isEmpty || lines[j].contains('\t') || descBullet.hasMatch(n) || descHeading(n) != null) break;
        if (descKv.hasMatch(n) && !descKv.hasMatch(t)) break;
        buf.add(n);
        j++;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text.rich(buf.length == 1 ? kvSpan(buf.first, base, time: time) : inlineSpans(buf.join('\n'), base, time: time)),
      ));
      i = j;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }
}

class DescBullet extends StatelessWidget {
  const DescBullet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 5, color: AppTheme.darkGreen)),
            Expanded(child: child),
          ],
        ),
      );
}

/// Таблиця з опису: 2–3 стовпці — на ширину екрана; більше — прокручується вбік.
class DescTable extends StatelessWidget {
  const DescTable({super.key, required this.rows});

  final List<List<String>> rows;

  static bool hasHeader(List<List<String>> rows) =>
      rows.length > 1 && rows.first.every((c) => c.length < 40 && !c.endsWith('.'));

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: AppTheme.darkGreen, fontSize: 13, height: 1.3);
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final header = hasHeader(rows);
    Widget cell(String c, {bool bold = false, Color? bg}) => Container(
          padding: const EdgeInsets.all(8),
          color: bg,
          child: Text.rich(inlineSpans(c, bold ? base.copyWith(fontWeight: FontWeight.w700) : base)),
        );
    final table = Table(
      border: TableBorder.all(color: const Color(0xffe3dccb), borderRadius: BorderRadius.circular(8)),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      columnWidths: cols <= 2
          ? const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)}
          : cols == 3
              ? const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2)}
              : {for (var k = 0; k < cols; k++) k: const FixedColumnWidth(150)},
      children: [
        for (var r = 0; r < rows.length; r++)
          TableRow(children: [
            for (var c = 0; c < cols; c++)
              cell(
                c < rows[r].length ? rows[r][c] : '',
                bold: (header && r == 0) || c == 0,
                bg: header && r == 0 ? const Color(0xfff4efe2) : null,
              ),
          ]),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: cols <= 3 ? table : SingleChildScrollView(scrollDirection: Axis.horizontal, child: table),
    );
  }
}
