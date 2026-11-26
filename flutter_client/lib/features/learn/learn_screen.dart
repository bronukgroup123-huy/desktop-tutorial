import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/core/ui.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/quiz.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/learn/quiz_screen.dart';

/// «Навчання» (ADR-023): сім модулів від «Як працює Грибний Радар» до «Отруйних двійників», по черзі.
/// Що відкрито, скільки балів і чи є сертифікат — вирішує сервер.
class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(quizOverviewProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: Text('Навчання', style: AppTheme.appBarTitle), backgroundColor: Colors.transparent, elevation: 0),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(e is ApiException ? e.userMessage : 'Не вдалося завантажити тести', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(onPressed: () => ref.invalidate(quizOverviewProvider), child: const Text('Повторити')),
            ]),
          ),
        ),
        data: (o) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(quizOverviewProvider),
          child: ListView(
            key: const ValueKey('learn-list'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _ProgressCard(overview: o),
              if (o.guestLabel != null) ...[
                const SizedBox(height: 8),
                _Note(key: const ValueKey('learn-guest'), icon: Icons.person_outline_rounded, text: o.guestLabel!),
              ],
              const SectionTitle('Модулі'),
              for (final m in o.modules) ...[
                _ModuleTile(module: m, guest: o.guestLabel != null),
                const SizedBox(height: 8),
              ],
              if (o.disclaimerLabel != null) _Note(icon: Icons.info_outline_rounded, text: o.disclaimerLabel!),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.overview});

  final QuizOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final certified = o.certifiedAt != null;
    return AppCard(
      key: const ValueKey('learn-progress'),
      child: Row(children: [
        Icon(certified ? Icons.workspace_premium_rounded : Icons.school_rounded, size: 40,
            color: certified ? AppTheme.accentOrange : AppTheme.darkGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(certified ? 'Сертифікат знань отримано' : 'Пройдено ${o.passedCount} з ${o.total}', style: AppTheme.sectionTitle),
            const SizedBox(height: 4),
            Text(
              certified
                  ? 'Ви пройшли всі модулі — рівень із позначкою «Досвідчений»'
                  : 'Пройдіть усі модулі, щоб отримати сертифікат знань і рівень «Грибознавець»',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: o.total == 0 ? 0 : o.passedCount / o.total, minHeight: 6,
                  backgroundColor: AppTheme.tint),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ModuleTile extends ConsumerWidget {
  const _ModuleTile({required this.module, required this.guest});

  final QuizModule module;
  final bool guest;

  String get _subtitle => switch (module.status) {
        QuizModuleStatus.passed => 'Зараховано · ${module.bestPercent ?? 0} % · +${module.points} балів',
        QuizModuleStatus.open => '${module.summary} · ${module.points} балів',
        QuizModuleStatus.locked => 'Спершу пройдіть попередній модуль',
        QuizModuleStatus.soon => 'Готується',
      };

  Widget get _trailing => switch (module.status) {
        QuizModuleStatus.passed => const Icon(Icons.check_circle_rounded, color: AppTheme.success),
        QuizModuleStatus.open => const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
        QuizModuleStatus.locked => const Icon(Icons.lock_outline_rounded, color: AppTheme.textMuted),
        QuizModuleStatus.soon => const Text('скоро', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = module.status == QuizModuleStatus.open || module.status == QuizModuleStatus.passed;
    return AppTile(
      key: ValueKey('learn-module-${module.id}'),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: available ? AppTheme.tint : AppTheme.hairline,
        child: Text('${module.position}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
      ),
      title: module.title,
      subtitle: _subtitle,
      trailing: _trailing,
      onTap: available ? () => _choose(context, ref) : null,
    );
  }

  /// Пройти на бали чи тренуватися: на бали — якщо модуль ще не зараховано, не гість і минула пауза.
  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final wait = module.nextScoredAt;
    final scoredAllowed = module.status == QuizModuleStatus.open && !guest && (wait == null || wait.isBefore(DateTime.now()));
    final practice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(module.title, style: AppTheme.blockTitle),
            const SizedBox(height: 6),
            Text(
              '${module.questionsPerAttempt} питань-ситуацій. Зараховано — від ${module.passPercent} %. '
              'Після спроби — пояснення до кожної відповіді.',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            if (scoredAllowed)
              FilledButton(
                key: const ValueKey('learn-start-scored'),
                onPressed: () => Navigator.of(c).pop(false),
                child: Text('Пройти на бали (+${module.points})'),
              )
            else if (module.status == QuizModuleStatus.open && wait != null && !guest)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Наступна спроба на бали — ${_when(wait)}. Поки можна тренуватися.',
                  key: const ValueKey('learn-wait'),
                  style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('learn-start-practice'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Тренування без балів'),
            ),
          ]),
        ),
      ),
    );
    if (practice == null || !context.mounted) return;
    try {
      final attempt = await ref.read(quizRepositoryProvider).start(module.id, practice: practice);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizScreen(module: module, attempt: attempt)));
      ref.invalidate(quizOverviewProvider);
      ref.invalidate(meProvider); // бали й рівень могли змінитись
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.userMessage, isError: true);
    }
  }

  static String _when(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)} о ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted))),
        ]),
      );
}
