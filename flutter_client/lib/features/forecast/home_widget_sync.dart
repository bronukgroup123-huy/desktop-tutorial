import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'package:flutter_client/data/models/analysis.dart';

/// Віджет «Грибний Радар» на головному екрані Android (рішення PO 2026-11-15): після кожного
/// показу прогнозу ділянки записуємо короткі підписи (ділянка, рівень сьогодні, найкращий гриб і
/// день) і просимо віджет оновитися. Усі тексти — із сервера. Немає віджета чи платформи
/// (тести, iOS без розширення) — тихо нічого.
class HomeWidgetSync {
  static const androidProvider = 'MushroomWidgetProvider';

  static String? _last;

  /// Записати дані віджета; ті самі дані вдруге не пишемо.
  static Future<void> update(AnalysisArea area, AnalysisResult result, {DateTime? now}) async {
    if (kIsWeb) return;
    final today = result.days.isEmpty ? null : result.days.first;
    final level = today == null ? result.top1?.species.levelLabel : '${today.dayLabel}: ${today.levelLabel.toLowerCase()}';
    final top = (today?.top1 ?? result.top1)?.species.nameUa;
    final t = now ?? DateTime.now();
    final data = <String, String>{
      'title': area.title,
      'level': level ?? 'Відкрийте «Прогноз»',
      'species': top == null ? '' : 'Найкращий: $top',
      'best': result.bestDay?.label ?? '',
      'updated': 'Оновлено ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    };
    final key = data.entries.where((e) => e.key != 'updated').map((e) => e.value).join('|');
    if (key == _last) return;
    try {
      for (final e in data.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(androidName: androidProvider);
      _last = key;
    } catch (_) {
      // Немає плагіна / віджета — нічого страшного.
    }
  }

  @visibleForTesting
  static void reset() => _last = null;
}
