import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;
import 'package:flutter_client/features/analysis/weather_scene.dart' show Mascot;
import 'package:flutter_client/features/catalog/catalog_browser.dart' show EdibilityBadge;
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/catalog/mushroom_character.dart';
import 'package:flutter_client/features/recognize/recognition_history.dart';
import 'package:flutter_client/features/recognize/recognizer.dart';

/// Після знімка: «ШІ думає» (маскот з лупою, назви кандидатів вилітають з кадру) → результат рівнями
/// без відсотків, червона плашка, якщо серед схожих є отруйний, «не гриб» з маскотом (рішення PO 2026-11-17).
class RecognitionFlowScreen extends ConsumerStatefulWidget {
  const RecognitionFlowScreen({super.key, required this.photos});

  final List<Uint8List> photos;

  /// Мінімальна тривалість «ШІ думає» — щоб анімацію встигли побачити.
  static const minThinking = Duration(milliseconds: 2200);

  @override
  ConsumerState<RecognitionFlowScreen> createState() => _RecognitionFlowScreenState();
}

class _RecognitionFlowScreenState extends ConsumerState<RecognitionFlowScreen> {
  Recognition? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final minimum = Future<void>.delayed(RecognitionFlowScreen.minThinking);
    try {
      final recognizer = await ref.read(recognizerProvider.future);
      if (recognizer == null) throw StateError('no model');
      final r = await recognizer.recognize(widget.photos);
      await minimum;
      await RecognitionHistory.add(r, widget.photos.first);
      ref.invalidate(recognitionHistoryProvider);
      if (mounted) setState(() => _result = r);
    } catch (_) {
      await minimum;
      // ADR-006: помилка на телефоні (брак пам'яті тощо) — пропонуємо знайти гриб у довіднику вручну.
      if (mounted) setState(() => _error = 'Не вдалося розпізнати на цьому телефоні. Спробуйте ще раз або знайдіть гриб у довіднику за назвою.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppTheme.darkGreen,
        title: Text(r == null && _error == null ? 'Розпізнаю…' : 'Результат', style: AppTheme.appBarTitle),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _error != null
            ? _ErrorView(key: const ValueKey('flow-error'), text: _error!)
            : r == null
                ? ThinkingView(key: const ValueKey('flow-thinking'), photo: widget.photos.first)
                : SingleChildScrollView(
                    key: const ValueKey('flow-result'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: RecognitionResultView(recognition: r, photo: MemoryImage(widget.photos.first)),
                  ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: AppTheme.accentOrange),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.darkGreen)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen),
                child: const Text('До довідника'),
              ),
            ],
          ),
        ),
      );
}

// ─── «ШІ думає» ─────────────────────────────────────────────────────────────

/// Кадр у рамці, по ньому ходить лупа; з кадру вилітають назви грибів; маскот поруч.
class ThinkingView extends ConsumerStatefulWidget {
  const ThinkingView({super.key, required this.photo});

  final Uint8List photo;

  @override
  ConsumerState<ThinkingView> createState() => _ThinkingViewState();
}

class _ThinkingViewState extends ConsumerState<ThinkingView> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: RecognitionFlowScreen.minThinking)..forward();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = [for (final s in (ref.watch(catalogProvider).valueOrNull?.species ?? const <CatalogSpecies>[]).take(40)) s.name];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 260,
            height: 260,
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final v = _t.value;
                // Лупа ходить по кадру «вісімкою».
                final lens = Offset(130 + 70 * math.sin(v * math.pi * 4), 130 + 50 * math.sin(v * math.pi * 8));
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.memory(widget.photo, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => Container(color: Colors.black12)),
                      ),
                    ),
                    // Назви кандидатів вилітають з кадру.
                    for (var i = 0; i < math.min(6, names.length); i++)
                      Builder(builder: (context) {
                        final p = ((v * 1.6) + i / 6) % 1;
                        return Positioned(
                          left: 20.0 + (i * 37) % 180,
                          top: 210 - 230 * p,
                          child: Opacity(
                            opacity: math.sin(math.pi * p).clamp(0.0, 1.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                              child: Text(names[(i * 7) % names.length],
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                            ),
                          ),
                        );
                      }),
                    Positioned(left: lens.dx - 34, top: lens.dy - 34, child: const _Magnifier()),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Mascot(size: 48),
              const SizedBox(width: 8),
              Text('ШІ розглядає гриб…', style: AppTheme.heading(16)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Фото не залишають телефон', style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

class _Magnifier extends StatelessWidget {
  const _Magnifier();

  @override
  Widget build(BuildContext context) => SizedBox(width: 68, height: 68, child: CustomPaint(painter: _MagnifierPainter()));
}

class _MagnifierPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width * 0.42, s.height * 0.42);
    c.drawLine(center + const Offset(16, 16), Offset(s.width - 4, s.height - 4), Paint()
      ..color = const Color(0xff5d4037)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round);
    c.drawCircle(center, 22, Paint()..color = Colors.white.withValues(alpha: 0.25));
    c.drawCircle(center, 22, Paint()
      ..color = const Color(0xff37474f)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4);
    c.drawArc(Rect.fromCircle(center: center, radius: 15), math.pi * 1.1, 0.9, false, Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Результат ──────────────────────────────────────────────────────────────

Color likelihoodColor(Likelihood l) => switch (l) {
      Likelihood.likely => AppTheme.success,
      Likelihood.possible => const Color(0xffd9822b),
      Likelihood.unlikely => const Color(0xff6b7a70),
    };

/// Результат розпізнавання: червона плашка (є отруйний серед схожих), кандидати рівнями, «не гриб».
class RecognitionResultView extends ConsumerWidget {
  const RecognitionResultView({super.key, required this.recognition, required this.photo});

  final Recognition recognition;
  final ImageProvider photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    if (recognition.notMushroom) return _NotMushroom(photo: photo);
    final danger = recognition.dangerous;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (danger != null)
          Container(
            key: const ValueKey('result-danger'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.dangerous_rounded, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Серед схожих є отруйний гриб — ', style: TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: danger.name, style: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline, decorationColor: Colors.white)),
                      const TextSpan(text: '. Не їжте й не куштуйте, поки не перевірите з досвідченим грибником.'),
                    ]),
                    style: const TextStyle(color: Colors.white, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image(image: photo, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64))),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Схожі гриби', style: AppTheme.heading(18)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (i, c) in recognition.candidates.indexed) _CandidateCard(key: ValueKey('candidate-$i'), candidate: c, species: catalog?.byId(c.label.id)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xfffaf3e3), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xffe8dcc0))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xffa8471f)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('ШІ-підказка, не діагноз. Перевірте в довіднику. Якщо сумніваєтеся — не їжте.',
                    style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.8))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({super.key, required this.candidate, required this.species});

  final Candidate candidate;

  /// Вид у довіднику (з фото й описом); `null` — лише в базі розпізнавання.
  final CatalogSpecies? species;

  @override
  Widget build(BuildContext context) {
    final l = candidate.label;
    final s = species;
    final color = likelihoodColor(candidate.likelihood);
    final badge = s != null ? edibilityBadge(s) : null;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: s != null
                      ? CatalogPhoto(name: s.thumb, speciesId: s.id)
                      : Container(color: const Color(0xfff1ece0), alignment: Alignment.center, child: SpeciesIcon(type: l.id, fallbackColor: const Color(0xff8d6e63), size: 40)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(candidate.likelihood.label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                    const SizedBox(height: 4),
                    Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.darkGreen)),
                    Text(l.latin, style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.65))),
                    const SizedBox(height: 4),
                    if (badge != null)
                      EdibilityBadge(label: badge.label, color: Color(badge.color))
                    else if (l.poisonous)
                      const EdibilityBadge(label: 'Отруйний', color: AppTheme.danger),
                  ],
                ),
              ),
            ],
          ),
          if (s != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  key: ValueKey('candidate-twins-${s.id}'),
                  onPressed: () => context.push('/catalog/${s.id}?focus=twins'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.darkGreen),
                  icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                  label: const Text('Як відрізнити'),
                ),
                FilledButton(
                  key: ValueKey('candidate-open-${s.id}'),
                  onPressed: () => context.push('/catalog/${s.id}'),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, visualDensity: VisualDensity.compact),
                  child: const Text('Відкрити в довіднику'),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Цього виду поки немає в довіднику з фото.', style: TextStyle(fontSize: 12, color: AppTheme.darkGreen.withValues(alpha: 0.6))),
            ),
        ],
      ),
    );
  }
}

/// «Не гриб»: персонаж розводить руками.
class _NotMushroom extends StatelessWidget {
  const _NotMushroom({required this.photo});

  final ImageProvider photo;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('result-not-mushroom'),
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image(image: photo, width: 120, height: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 120))),
              const SizedBox(width: 12),
              MushroomCharacter(
                look: kCharacterLooks['boletus_edulis']!,
                face: const Face(eyes: Eyes.open, mouth: Mouth.wavy, brows: 1, look: Offset(-1, 0)),
                left: const Arm(1.9, -0.7),
                right: const Arm(1.9, -0.7),
                size: 110,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Хм… Це не схоже на гриб', style: AppTheme.heading(18)),
          const SizedBox(height: 6),
          Text('Спробуйте ще раз — ближче до шапки, щоб гриб займав більшу частину кадру.',
              textAlign: TextAlign.center, style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.75))),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('result-retake'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen),
            icon: const Icon(Icons.photo_camera_rounded),
            label: const Text('Перезняти'),
          ),
        ],
      );
}

/// Збережений результат з історії.
class HistoryResultScreen extends StatelessWidget {
  const HistoryResultScreen({super.key, required this.entry, required this.thumb});

  final HistoryEntry entry;
  final ImageProvider thumb;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppTheme.darkGreen,
          title: Text(historyDate(entry.at), style: GoogleFonts.merriweather(color: AppTheme.darkGreen, fontSize: 17)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: RecognitionResultView(recognition: entry.recognition, photo: thumb),
        ),
      );
}

String historyDate(DateTime d) {
  const months = ['січ', 'лют', 'бер', 'кві', 'тра', 'чер', 'лип', 'сер', 'вер', 'жов', 'лис', 'гру'];
  final hh = d.hour.toString().padLeft(2, '0'), mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]}, $hh:$mm';
}
