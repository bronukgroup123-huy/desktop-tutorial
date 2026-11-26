import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/core/ui.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/quiz.dart';
import 'package:flutter_client/data/providers.dart';

/// Спроба тесту: по одному питанню на екрані, наприкінці — «Здати» і розбір із поясненнями (ADR-023 §23.2).
/// Правильних відповідей клієнт не знає — їх і підсумок віддає сервер після здачі.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, required this.module, required this.attempt});

  final QuizModule module;
  final QuizAttempt attempt;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  int _index = 0;
  bool _busy = false;
  QuizResult? _result;

  /// Відповіді: питання → вибрані варіанти (для «порядку» — поточний порядок).
  late final Map<String, List<String>> _answers = {
    for (final q in widget.attempt.questions)
      q.id: q.kind == QuizKind.order ? [for (final o in q.options) o.id] : <String>[],
  };

  List<QuizQuestion> get _qs => widget.attempt.questions;

  bool _answered(QuizQuestion q) => q.kind == QuizKind.order || _answers[q.id]!.isNotEmpty;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(quizRepositoryProvider).submit(widget.attempt.id, _answers);
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(widget.attempt.practice ? 'Тренування' : widget.module.title, style: AppTheme.appBarTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(child: result != null ? QuizResultView(result: result) : _question(context)),
    );
  }

  Widget _question(BuildContext context) {
    if (_qs.isEmpty) return const Center(child: Text('Питань поки немає'));
    final q = _qs[_index];
    final last = _index == _qs.length - 1;
    final hint = switch (q.kind) {
      QuizKind.single => 'Оберіть одну відповідь',
      QuizKind.multi => 'Оберіть усі правильні',
      QuizKind.order => 'Перетягніть у правильному порядку',
    };
    return Column(children: [
      LinearProgressIndicator(value: (_index + 1) / _qs.length, minHeight: 4, backgroundColor: AppTheme.tint),
      Expanded(
        child: ListView(
          key: ValueKey('quiz-question-${q.id}'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          children: [
            Text('Питання ${_index + 1} з ${_qs.length}', style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(q.prompt, style: AppTheme.sectionTitle),
            const SizedBox(height: 6),
            Text(hint, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            if (q.kind == QuizKind.order) _orderList(q) else ..._choiceList(q),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Row(children: [
          if (_index > 0)
            TextButton(onPressed: _busy ? null : () => setState(() => _index--), child: const Text('Назад')),
          const Spacer(),
          FilledButton(
            key: const ValueKey('quiz-next'),
            onPressed: _busy || !_answered(q) ? null : (last ? _submit : () => setState(() => _index++)),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(last ? 'Здати' : 'Далі'),
          ),
        ]),
      ),
    ]);
  }

  List<Widget> _choiceList(QuizQuestion q) {
    final chosen = _answers[q.id]!;
    return [
      for (final o in q.options)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            key: ValueKey('quiz-option-${q.id}-${o.id}'),
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
            color: chosen.contains(o.id) ? AppTheme.tint : AppTheme.surface,
            onTap: () => setState(() {
              if (q.kind == QuizKind.single) {
                chosen
                  ..clear()
                  ..add(o.id);
              } else {
                chosen.contains(o.id) ? chosen.remove(o.id) : chosen.add(o.id);
              }
            }),
            child: Row(children: [
              Icon(
                q.kind == QuizKind.single
                    ? (chosen.contains(o.id) ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded)
                    : (chosen.contains(o.id) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                color: AppTheme.darkGreen,
              ),
              const SizedBox(width: 8),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(o.text))),
            ]),
          ),
        ),
    ];
  }

  Widget _orderList(QuizQuestion q) {
    final order = _answers[q.id]!;
    String text(String id) => q.options.firstWhere((o) => o.id == id).text;
    return ReorderableListView(
      key: ValueKey('quiz-order-${q.id}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      // newIndex уже враховує вилучений елемент
      onReorderItem: (from, to) => setState(() => order.insert(to, order.removeAt(from))),
      children: [
        for (final (i, id) in order.indexed)
          Padding(
            key: ValueKey('quiz-order-item-$id'),
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(children: [
                CircleAvatar(radius: 12, backgroundColor: AppTheme.tint, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.darkGreen))),
                const SizedBox(width: 10),
                Expanded(child: Text(text(id))),
                const Icon(Icons.drag_handle_rounded, color: AppTheme.textMuted),
              ]),
            ),
          ),
      ],
    );
  }
}

/// Підсумок спроби й розбір: що ви обрали, що правильно, пояснення, джерело, «Помилка в питанні».
class QuizResultView extends ConsumerWidget {
  const QuizResultView({super.key, required this.result});

  final QuizResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    final color = r.passed ? AppTheme.success : AppTheme.danger;
    return ListView(
      key: const ValueKey('quiz-result'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(r.passed ? (r.certifiedNow ? Icons.workspace_premium_rounded : Icons.emoji_events_rounded) : Icons.replay_rounded,
                  color: color, size: 32),
              const SizedBox(width: 10),
              Text('${r.correct} з ${r.total} · ${r.percent} %', style: AppTheme.blockTitle),
            ]),
            const SizedBox(height: 8),
            Text(r.resultLabel, key: const ValueKey('quiz-result-label'), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SectionTitle('Розбір'),
        for (final (i, item) in r.review.indexed) ...[
          _ReviewCard(n: i + 1, item: item),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Готово')),
      ],
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.n, required this.item});

  final int n;
  final QuizReviewItem item;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    // null — скасовано; '' — без коментаря
    final comment = await showDialog<String>(context: context, builder: (_) => const _ReportDialog());
    if (comment == null || !context.mounted) return;
    try {
      await ref.read(quizRepositoryProvider).report(item.id, comment: comment.isEmpty ? null : comment);
      if (context.mounted) showToast(context, 'Дякуємо! Перевіримо це питання');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.userMessage, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ok = item.isCorrect;
    final yours = item.chosen.isEmpty ? '—' : item.chosen.map(item.textOf).join(item.kind == QuizKind.order ? ' → ' : '; ');
    final right = item.correct.map(item.textOf).join(item.kind == QuizKind.order ? ' → ' : '; ');
    return AppCard(
      key: ValueKey('quiz-review-${item.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: ok ? AppTheme.success : AppTheme.danger),
          const SizedBox(width: 8),
          Expanded(child: Text('$n. ${item.prompt}', style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        if (item.critical && !ok)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Критичне питання — у лісі така помилка може бути останньою',
                style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        if (!ok) ...[
          const SizedBox(height: 6),
          Text('Ваша відповідь: $yours', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ],
        const SizedBox(height: 4),
        Text('Правильно: $right', style: const TextStyle(fontSize: 13, color: AppTheme.success, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(item.explanation),
        const SizedBox(height: 6),
        Text('Джерело: ${item.source}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: ValueKey('quiz-report-${item.id}'),
            onPressed: () => _report(context, ref),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Помилка в питанні'),
          ),
        ),
      ]),
    );
  }
}

/// «Помилка в питанні?» — необов'язковий коментар; поле живе разом із діалогом.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Помилка в питанні?'),
        content: TextField(
          key: const ValueKey('quiz-report-comment'),
          controller: _ctrl,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Що не так (необов\'язково)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Скасувати')),
          FilledButton(
            key: const ValueKey('quiz-report-send'),
            onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
            child: const Text('Надіслати'),
          ),
        ],
      );
}
