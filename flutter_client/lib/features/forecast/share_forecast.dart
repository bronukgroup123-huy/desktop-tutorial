import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart' show levelIcon;
import 'package:flutter_client/features/analysis/weather_scene.dart';

/// «Поділитися прогнозом» (рішення PO 2026-11-15): картинка зі сценою маскота, рівнем,
/// найкращим грибом і днем — для Viber / Telegram. Показується попередній вигляд, далі —
/// системне вікно «Поділитися». Точне місце ділянки на картинці не показуємо.
Future<void> showShareForecast(BuildContext context, {required String areaTitle, required AnalysisResult result}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (_) => _ShareSheet(areaTitle: areaTitle, result: result),
    );

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.areaTitle, required this.result});

  final String areaTitle;
  final AnalysisResult result;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _key = GlobalKey();
  bool _busy = false;

  String get _text {
    final r = widget.result;
    final top = r.top1?.species;
    return [
      'Прогноз грибів: ${widget.areaTitle}',
      if (top != null) '${top.nameUa} — ${top.levelLabel.toLowerCase()}',
      if (r.bestDay != null) r.bestDay!.label,
      '— Грибний Радар',
    ].join('\n');
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mushroom_forecast.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: _text,
      ));
    } catch (_) {
      // Немає картинки (тести, збій рендеру) — ділимося текстом.
      try {
        await SharePlus.instance.share(ShareParams(text: _text));
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(key: _key, child: ShareForecastCard(areaTitle: widget.areaTitle, result: widget.result)),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('share-send'),
              onPressed: _busy ? null : _share,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Поділитися'),
            ),
          ],
        ),
      );
}

/// Картинка прогнозу для поширення: сцена погоди з маскотом, рівень, найкращий гриб і день.
class ShareForecastCard extends StatelessWidget {
  const ShareForecastCard({super.key, required this.areaTitle, required this.result});

  final String areaTitle;
  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final today = result.days.isEmpty ? null : result.days.first;
    final weather = today?.weather ?? result.weather;
    final scene = parseWeatherScene(weather?.scene) ?? WeatherSceneKind.partlyCloudy;
    final top = (today?.top1 ?? result.top1)?.species;
    return Container(
      key: const ValueKey('share-card'),
      width: 340,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.eco_rounded, color: AppTheme.darkGreen, size: 18),
              const SizedBox(width: 6),
              const Text('Грибний Радар', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
              const Spacer(),
              Flexible(
                child: Text(areaTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          WeatherScene(
            kind: scene,
            sprouts: sproutCount(weather?.sprouts),
            height: 150,
            child: weather?.dayLabel == null
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(10)),
                    child: Text(weather!.dayLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                  ),
          ),
          const SizedBox(height: 12),
          if (top != null)
            Row(
              children: [
                Expanded(
                  child: Text(top.nameUa,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: top.levelColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(levelIcon(top.level), size: 14, color: top.levelColor),
                      const SizedBox(width: 3),
                      Text(top.levelLabel, style: TextStyle(color: top.levelColor, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            )
          else
            Text(result.noDataReason ?? 'Сьогодні грибів зі шансом немає',
                style: const TextStyle(color: AppTheme.darkGreen)),
          if (top?.wave?.label != null) ...[
            const SizedBox(height: 4),
            Text(top!.wave!.label!, style: TextStyle(color: AppTheme.textMuted)),
          ],
          if (result.bestDay != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.star_rounded, size: 18, color: AppTheme.accentOrange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(result.bestDay!.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
