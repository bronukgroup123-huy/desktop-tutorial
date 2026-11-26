import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/trip_feedback.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/analysis_repository.dart';
import 'package:flutter_client/features/safety/guardian/guardian_session.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';

/// Середина треку й день походу — для «Знайшли?». Треку немає — питати нема про що (`null`).
TripSummary? tripSummary(HikeState hike) {
  final track = hike.track;
  if (track.isEmpty) return null;
  final lat = track.map((p) => p.lat).reduce((a, b) => a + b) / track.length;
  final lng = track.map((p) => p.lng).reduce((a, b) => a + b) / track.length;
  final start = (hike.startedAt ?? track.first.t).toLocal();
  final day = '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  return (lat: double.parse(lat.toStringAsFixed(4)), lng: double.parse(lng.toStringAsFixed(4)), day: day);
}

/// «Я вдома» (ADR-022 + B3.11): зупинити запис на телефоні, завершити похід у Наглядача й — якщо сервер знайшов
/// зв'язок походу з прогнозом ділянки чи Наглядачем — спитати «Знайшли?». Усе потрібне береться одразу, тож екран,
/// з якого натиснули, можна закрити, не чекаючи; аркуш покаже [nav].
Future<void> finishHike(WidgetRef ref, NavigatorState nav) async {
  final hike = ref.read(hikeProvider);
  final hikeCtrl = ref.read(hikeProvider.notifier);
  // Наглядач і сервер — не обов'язкові: запис на телефоні зупиняється за будь-яких умов.
  GuardianSessionController? guardian;
  AnalysisRepository? repo;
  try {
    guardian = ref.read(guardianSessionProvider.notifier);
  } catch (_) {}
  try {
    repo = ref.read(analysisRepositoryProvider);
  } catch (_) {}
  final trip = tripSummary(hike);
  // Поверталися за допомогою «Додому» — позначка для трофея «Своїм слідом».
  final usedHomeNav = hike.returnMode != null;
  await hikeCtrl.finish();
  // Наглядач більше не бачить ні місця, ні треку (без мережі — повідомимо пізніше). Збій тут не скасовує
  // «Знайшли?»: зв'язок з прогнозом ділянки від Наглядача не залежить.
  try {
    await guardian?.finish(usedHomeNav: usedHomeNav);
  } catch (_) {}
  if (trip != null && repo != null) await askTripFeedback(nav, repo, trip);
}

/// Спитати «Знайшли?», якщо сервер вважає, що є про що. Без мережі чи без зв'язку — мовчки нічого.
Future<void> askTripFeedback(NavigatorState nav, AnalysisRepository repo, TripSummary trip) async {
  TripFeedbackPrompt prompt;
  try {
    prompt = await repo.feedbackPrompt(trip);
  } catch (_) {
    return;
  }
  if (!prompt.ask || !nav.mounted) return;
  await showModalBottomSheet<void>(
    context: nav.context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TripFeedbackSheet(prompt: prompt, trip: trip),
  );
}

/// «Знайшли гриби?» — Так / Ні / Не зараз; після відповіді — подяка, бали й «прогноз для вас збувся».
class TripFeedbackSheet extends ConsumerStatefulWidget {
  const TripFeedbackSheet({super.key, required this.prompt, required this.trip});

  final TripFeedbackPrompt prompt;
  final TripSummary trip;

  @override
  ConsumerState<TripFeedbackSheet> createState() => _TripFeedbackSheetState();
}

class _TripFeedbackSheetState extends ConsumerState<TripFeedbackSheet> {
  bool _busy = false;
  TripFeedbackResult? _result;
  String? _error;

  Future<void> _answer(String id) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(analysisRepositoryProvider).sendFeedback(widget.trip, id);
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не вдалося надіслати відповідь. Спробуйте ще раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _note(String text, {Key? key, IconData icon = Icons.info_outline_rounded, Color color = AppTheme.textMuted}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.prompt;
    final r = _result;
    final done = r != null;
    final accuracy = r?.accuracyLabel ?? p.accuracyLabel;
    final children = <Widget>[
      Text(done ? r.messageLabel : p.title, style: AppTheme.blockTitle),
      if (!done && p.subtitle.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(p.subtitle, style: const TextStyle(color: AppTheme.textMuted))),
      if (!done && p.explainLabel.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.tint, borderRadius: BorderRadius.circular(AppTheme.radiusField)),
          child: Text(p.explainLabel, key: const ValueKey('feedback-explain'), style: const TextStyle(fontSize: 13, color: AppTheme.darkGreen)),
        ),
      if (!done) ...[
        const SizedBox(height: 16),
        for (final (i, a) in p.answers.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: i == 0
                  ? FilledButton(
                      key: ValueKey('feedback-${a.id}'),
                      onPressed: _busy ? null : () => _answer(a.id),
                      child: Text(a.label),
                    )
                  : OutlinedButton(
                      key: ValueKey('feedback-${a.id}'),
                      onPressed: _busy ? null : () => _answer(a.id),
                      child: Text(a.label),
                    ),
            ),
          ),
        if (p.pointsLabel != null) _note(p.pointsLabel!, icon: Icons.stars_rounded),
        if (_error != null) _note(_error!, key: const ValueKey('feedback-error'), icon: Icons.error_outline_rounded, color: AppTheme.errorRed),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            key: const ValueKey('feedback-skip'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(p.skipLabel),
          ),
        ),
      ] else ...[
        if (r.pointsLabel != null)
          _note(r.pointsLabel!, key: const ValueKey('feedback-points'), icon: r.points == 'pending' ? Icons.stars_rounded : Icons.info_outline_rounded),
      ],
      if (accuracy != null) _note(accuracy, key: const ValueKey('feedback-accuracy'), icon: Icons.insights_rounded, color: AppTheme.darkGreen),
      if (done) ...[
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(key: const ValueKey('feedback-done'), onPressed: () => Navigator.of(context).pop(), child: const Text('Готово')),
        ),
      ],
    ];
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('trip-feedback-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
