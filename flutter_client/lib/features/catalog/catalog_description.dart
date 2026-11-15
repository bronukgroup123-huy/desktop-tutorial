import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';

/// Книжковий опис виду — як у веб-довіднику (landing.html, renderDescription):
/// розділи з емодзі-заголовками, таблиці (стовпці через табуляцію), списки, «Ключ: значення»,
/// абзаци; кулінарні розділи (🍳 🍽️) згорнуті.
class CatalogDescription extends StatelessWidget {
  const CatalogDescription({super.key, required this.text});

  final String text;

  static const _headings = ['🍄', '✅', '🔍', '⚠️', '🗺️', '🪱', '🍳', '🍽️', '📋', '🧪', '📍', '💡'];

  static ({String emoji, String title})? heading(String line) {
    if (line.contains('\t')) return null;
    final t = line.trim();
    for (final e in _headings) {
      if (t.startsWith('$e ') || t.startsWith('$e ')) return (emoji: e, title: t.substring(e.length).trim());
    }
    return null;
  }

  /// Розділи: (емодзі, заголовок, рядки); вступ без заголовка — з емодзі `null`.
  static List<({String? emoji, String? title, List<String> lines})> sections(String raw) {
    final out = <({String? emoji, String? title, List<String> lines})>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final h = heading(line);
      if (h != null) {
        out.add((emoji: h.emoji, title: h.title, lines: <String>[]));
      } else if (out.isEmpty) {
        out.add((emoji: null, title: null, lines: [line]));
      } else {
        out.last.lines.add(line);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return Text('Опису ще немає.', style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.6)));
    }
    final children = <Widget>[];
    for (final s in sections(text)) {
      final body = _Blocks(lines: s.lines);
      if (s.emoji == '🍳' || s.emoji == '🍽️') {
        children.add(Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(top: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey('desc-acc-${s.title}'),
              leading: Text(s.emoji!, style: const TextStyle(fontSize: 20)),
              title: Text(s.title ?? '', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [body],
            ),
          ),
        ));
      } else if (s.emoji == '🍄') {
        // Назва виду вже в шапці сторінки — лише зміст (статус, короткий опис).
        children.add(body);
      } else if (s.emoji != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.emoji!, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title ?? '',
                  style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                ),
              ),
            ],
          ),
        ));
        children.add(body);
      } else {
        children.add(body);
      }
    }
    return Column(key: const ValueKey('catalog-description'), crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

final _bullet = RegExp(r'^\s*[-•*]\s+');
final _kv = RegExp(r'^([^:\n]{1,45}):\s*(.+)$');

/// Рядок із **жирним** → TextSpan.
TextSpan inlineSpans(String s, TextStyle base) {
  final spans = <TextSpan>[];
  final re = RegExp(r'\*\*([^*]+)\*\*');
  var i = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
    spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
    i = m.end;
  }
  if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
  return TextSpan(style: base, children: spans);
}

class _Blocks extends StatelessWidget {
  const _Blocks({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: AppTheme.darkGreen, fontSize: 14, height: 1.35);
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
        out.add(_DescTable(rows: rows));
        continue;
      }
      if (_bullet.hasMatch(t)) {
        final items = <String>[];
        while (i < lines.length && _bullet.hasMatch(lines[i].trim())) {
          items.add(lines[i].trim().replaceFirst(_bullet, ''));
          i++;
        }
        out.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(padding: EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 5, color: AppTheme.darkGreen)),
                      Expanded(child: Text.rich(_kvSpan(it, base))),
                    ],
                  ),
                ),
            ],
          ),
        ));
        continue;
      }
      // Абзац: рядки до порожнього / таблиці / списку.
      final buf = <String>[t];
      var j = i + 1;
      while (j < lines.length) {
        final n = lines[j].trim();
        if (n.isEmpty || lines[j].contains('\t') || _bullet.hasMatch(n) || CatalogDescription.heading(n) != null) break;
        if (_kv.hasMatch(n) && !_kv.hasMatch(t)) break;
        buf.add(n);
        j++;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text.rich(buf.length == 1 ? _kvSpan(buf.first, base) : inlineSpans(buf.join('\n'), base)),
      ));
      i = j;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }

  /// «Шапка: …» — ключ жирним.
  static TextSpan _kvSpan(String s, TextStyle base) {
    final m = _kv.firstMatch(s);
    if (m == null) return inlineSpans(s, base);
    return TextSpan(style: base, children: [
      TextSpan(text: '${m.group(1)}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
      inlineSpans(m.group(2)!, base),
    ]);
  }
}

/// Таблиця з опису: 2–3 стовпці (ключ — значення, двійники) — на ширину екрана; більше — прокручується вбік.
class _DescTable extends StatelessWidget {
  const _DescTable({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: AppTheme.darkGreen, fontSize: 13, height: 1.3);
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final header = rows.length > 1 && rows.first.every((c) => c.length < 40 && !c.endsWith('.'));
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
