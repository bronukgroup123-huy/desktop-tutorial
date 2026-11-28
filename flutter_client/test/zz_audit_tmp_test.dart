import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/features/catalog/catalog_article.dart';
import 'package:flutter_client/features/catalog/catalog_description.dart';
void main() {
  test('audit', () {
    final j = jsonDecode(utf8.decode(gzip.decode(File('assets/catalog/catalog.json.gz').readAsBytesSync()))) as Map<String, dynamic>;
    final sb = StringBuffer();
    for (final s in (j['species'] as List)) {
      for (final sec in descSections(s['description'] as String? ?? '')) {
        if (articleKind(sec) != ArticleKind.passport) continue;
        final body = passportBody(sec.lines);
        for (final line in sec.lines) {
          final m = descKv.firstMatch(line.trim());
          if (m == null || line.contains('\t')) continue;
          sb.writeln('${s['id']}\t${m.group(1)}\t${passportStickerRule(m.group(1)!, m.group(2)!, body: body) ?? '-'}\t${passportSticker(m.group(1)!, m.group(2)!, body: body) ?? '-'}');
        }
      }
    }
    File('/tmp/claude-0/-home-user-desktop-tutorial/e3e99e7e-88ce-58fa-a1bf-16967b6efdfb/scratchpad/passport_audit6.tsv').writeAsStringSync(sb.toString());
  });
}
