import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/ui.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/picks/pick_card_sheet.dart';

/// «Точки від друзів» (B9.4, ADR-021 §21.5): приватні точки, якими з вами поділилися друзі.
/// Тап — картка з точним місцем, фото й «Відкрити в Google Картах». Точка зникає зі списку,
/// коли друг відкликав доступ, видалив її, зробив публічною або ви більше не друзі.
class SharedPicksScreen extends ConsumerWidget {
  const SharedPicksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(sharedPicksProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: Text('Точки від друзів', style: AppTheme.appBarTitle)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(sharedPicksProvider.future),
        child: picks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  e is ApiException ? e.userMessage : 'Не вдалося завантажити. Перевірте інтернет.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      key: ValueKey('shared-picks-empty'),
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Поки ніхто не поділився з вами точкою. Коли друг поділиться своїм місцем, '
                        'воно з’явиться тут і на карті.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return AppTile(
                      key: ValueKey('shared-pick-${p.id}'),
                      leading: const Icon(Icons.card_giftcard_rounded, color: AppTheme.darkGreen),
                      title: p.nameLabel,
                      subtitle: [p.sharedFromLabel, if (p.dateLabel != null) p.dateLabel!].join(' · '),
                      onTap: () async {
                        await showPickCard(context, p.id);
                        // друг міг відкликати доступ, поки картка була відкрита
                        ref.invalidate(sharedPicksProvider);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
