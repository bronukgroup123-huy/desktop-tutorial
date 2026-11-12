import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';

/// Вкладка «Прогноз» (план v8.2 §3.1). Показує, що обрано на карті останнім:
///   * результат аналізу ділянки 5×5 / 10×10 км (ADR-015) — повноцінним екраном;
///   * або прогноз для точки лісу, по якій торкнулися.
/// Нічого не обрано — підказка відкрити карту.
class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(analysisResultProvider);
    final point = ref.watch(selectedPointProvider);
    final title = analysis != null ? 'Аналіз ділянки' : 'Прогноз';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.merriweather(color: AppTheme.darkGreen, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (analysis != null) ...[
            IconButton(
              tooltip: 'Показати ділянку на карті',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => context.go('/map'),
            ),
            IconButton(
              tooltip: 'Закрити аналіз',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => ref.read(analysisResultProvider.notifier).state = null,
            ),
          ] else if (point != null)
            IconButton(
              tooltip: 'Оновити',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(forecastProvider(point)),
            ),
        ],
      ),
      body: analysis != null
          ? AnalysisResultView(result: analysis)
          : point == null
              ? _EmptyState(onOpenMap: () => context.go('/map'))
              : ForecastView(point: point),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpenMap});

  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forest_rounded, size: 56, color: AppTheme.darkGreen),
              const SizedBox(height: 16),
              Text(
                'Оберіть ліс на карті',
                style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
              ),
              const SizedBox(height: 8),
              const Text(
                'Торкніться зеленої ділянки лісу або проаналізуйте ділянку 5×5 км — '
                'і тут з\'явиться прогноз: погода, які гриби ростуть і чому.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpenMap,
                icon: const Icon(Icons.map_rounded),
                label: const Text('Відкрити карту'),
              ),
            ],
          ),
        ),
      );
}
