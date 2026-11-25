import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/features/catalog/catalog_browser.dart';
import 'package:flutter_client/features/recognize/recognition_flow.dart';
import 'package:flutter_client/features/recognize/recognition_history.dart';

/// Вкладка «Розпізнати»: банер-камера ШІ (локальна модель, ADR-006) і довідник грибів під ним.
/// Угорі — історія розпізнавань (лише на телефоні).
class RecognizeScreen extends StatelessWidget {
  const RecognizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Розпізнати', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('history-open'),
            tooltip: 'Історія розпізнавань',
            icon: const Icon(Icons.history_rounded, color: AppTheme.darkGreen),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              backgroundColor: AppTheme.backgroundColor,
              builder: (_) => const RecognitionHistorySheet(),
            ),
          ),
        ],
      ),
      body: const CatalogBrowser(),
    );
  }
}

/// Історія: мініатюра, час, найімовірніший гриб і його рівень; торкнутися — повний результат.
class RecognitionHistorySheet extends ConsumerWidget {
  const RecognitionHistorySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(recognitionHistoryProvider).valueOrNull ?? const <HistoryEntry>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Історія розпізнавань',
                        style: GoogleFonts.merriweather(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
                  ),
                  if (history.isNotEmpty)
                    TextButton(
                      key: const ValueKey('history-clear'),
                      onPressed: () async {
                        await RecognitionHistory.clear();
                        ref.invalidate(recognitionHistoryProvider);
                      },
                      child: const Text('Очистити'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Зберігається лише на цьому телефоні.', style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
            ),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Text('Тут з\'являться ваші розпізнавання.', style: TextStyle(color: AppTheme.darkGreen)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, i) => _HistoryTile(entry: history[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final r = entry.recognition;
    final top = r.candidates.firstOrNull;
    return FutureBuilder<File?>(
      future: RecognitionHistory.thumbFile(entry),
      builder: (context, snap) {
        final file = snap.data;
        final ImageProvider thumb = file != null ? FileImage(file) : const AssetImage('assets/icons/ic_recognize.svg') as ImageProvider;
        return ListTile(
          key: ValueKey('history-${entry.id}'),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: file == null ? Container(color: const Color(0xfff1ece0)) : Image(image: thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xfff1ece0))),
            ),
          ),
          title: Text(r.notMushroom ? 'Не схоже на гриб' : (top?.label.name ?? '—'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
          subtitle: Text(
            [historyDate(entry.at), if (top != null && !r.notMushroom) top.likelihood.label, if (r.dangerous != null) '⚠ серед схожих отруйний'].join(' · '),
            style: TextStyle(fontSize: 12, color: r.dangerous != null ? AppTheme.danger : AppTheme.darkGreen.withValues(alpha: 0.65)),
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HistoryResultScreen(entry: entry, thumb: thumb))),
        );
      },
    );
  }
}
