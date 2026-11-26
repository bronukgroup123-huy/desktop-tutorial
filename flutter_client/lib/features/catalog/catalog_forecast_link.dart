import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart' show levelIcon;

/// Вид у ділянці сьогодні: рівень і хвиля — підписи із сервера (Thin Client).
typedef AreaSpeciesHit = ({String area, String level, String levelLabel, Color levelColor, String? waveLabel});

/// Де цей вид є в останніх результатах ділянок користувача (сьогоднішній день результату).
List<AreaSpeciesHit> speciesInAreas(AnalysisOverview overview, String speciesId) {
  final out = <AreaSpeciesHit>[];
  for (final a in overview.areas) {
    final r = a.lastResult;
    if (r == null) continue;
    final day = r.days.isEmpty ? null : r.days.first;
    final main = [day?.top1 ?? r.top1, day?.alternative ?? r.alternative]
        .whereType<AnalysisSpecies>()
        .map((x) => x.species)
        .where((x) => x.mushroomType == speciesId)
        .firstOrNull;
    if (main != null) {
      out.add((area: a.title, level: main.level, levelLabel: main.levelLabel, levelColor: main.levelColor, waveLabel: main.wave?.label));
      continue;
    }
    final b = (r.basket ?? const <AnalysisBasketSpecies>[]).where((x) => x.type == speciesId).firstOrNull;
    if (b != null) out.add((area: a.title, level: b.level, levelLabel: b.levelLabel, levelColor: b.levelColor, waveLabel: null));
  }
  return out;
}

/// «У ваших ділянках»: рівень цього гриба сьогодні в кожній ділянці; дотик — «Прогноз».
class CatalogForecastLink extends ConsumerWidget {
  const CatalogForecastLink({super.key, required this.speciesId});

  final String speciesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(analysisOverviewProvider).valueOrNull;
    if (overview == null) return const SizedBox.shrink();
    final hits = speciesInAreas(overview, speciesId);
    if (hits.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('catalog-forecast-link'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/forecast'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.radar_rounded, color: AppTheme.darkGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('У ваших ділянках сьогодні', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                    for (final h in hits)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Text(h.area, style: const TextStyle(color: AppTheme.darkGreen)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: h.levelColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(levelIcon(h.level), size: 13, color: h.levelColor),
                                  const SizedBox(width: 3),
                                  Text(h.levelLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: h.levelColor)),
                                ],
                              ),
                            ),
                            if (h.waveLabel != null)
                              Text(h.waveLabel!, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.darkGreen),
            ],
          ),
        ),
      ),
    );
  }
}
