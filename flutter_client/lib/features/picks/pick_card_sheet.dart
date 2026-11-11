import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';

/// Картка тук-тука (тап по точці на карті): фото, назва, опис, дата, статус.
/// Усі підписи — із сервера; для чужих точок місце показано приблизно.
Future<void> showPickCard(BuildContext context, String pickId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, controller) => PickCardView(pickId: pickId, scrollController: controller),
      ),
    );

class PickCardView extends ConsumerWidget {
  const PickCardView({super.key, required this.pickId, this.scrollController});

  final String pickId;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(pickCardProvider(pickId));
    return card.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              e is ApiException ? e.userMessage : 'Не вдалося відкрити точку.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(pickCardProvider(pickId)),
              child: const Text('Повторити'),
            ),
          ],
        ),
      ),
      data: (c) => _PickCardContent(card: c, scrollController: scrollController),
    );
  }
}

class _PickCardContent extends StatelessWidget {
  const _PickCardContent({required this.card, this.scrollController});

  final PickCard card;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final pick = card.pick;
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (card.photoUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              card.photoUrl!,
              height: 240,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
              errorBuilder: (context, error, stack) => Container(
                height: 120,
                color: Colors.white,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                pick.nameLabel,
                style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: pick.markerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                pick.statusLabel,
                style: TextStyle(color: pick.markerColor, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
        if (card.dateLabel != null) ...[
          const SizedBox(height: 4),
          Text(card.dateLabel!, style: TextStyle(color: muted)),
        ],
        if (card.description != null && card.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(card.description!),
        ],
        const SizedBox(height: 16),
        ForecastInfoCard(
          icon: pick.isExact ? Icons.my_location_rounded : Icons.blur_circular_rounded,
          text: pick.isExact
              ? 'Це ваша точка — місце показано точно.'
              : 'Місце показано приблизно: справжнє — у межах пів кілометра.',
        ),
        if (card.disclaimerLabel != null) ...[
          const SizedBox(height: 8),
          ForecastInfoCard(
            icon: Icons.warning_amber_rounded,
            text: card.disclaimerLabel!,
            color: AppTheme.accentOrange,
          ),
        ],
      ],
    );
  }
}
