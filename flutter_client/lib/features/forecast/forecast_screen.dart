import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';

/// Вкладка «Прогноз» (план v8.2 §3.1): з'являється ТІЛЬКИ після вибору точки на карті.
class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final point = ref.watch(selectedPointProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Прогноз', style: GoogleFonts.merriweather(color: AppTheme.darkGreen, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (point != null)
            IconButton(
              tooltip: 'Оновити',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(forecastProvider(point)),
            ),
        ],
      ),
      body: point == null
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
                'Торкніться зеленої ділянки лісу — і тут з\'явиться прогноз для неї: погода, які гриби ростуть і чому.',
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
