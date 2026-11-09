import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/region.dart';
import 'package:flutter_client/data/providers.dart';

/// Онбординг (план v8.2 §3.7): вибір області + згода з EULA / Privacy Policy.
///
/// Список областей — з сервера (`GET /regions`), на сервер відправляється лише `slug`.
/// Чи можна змінити вже обрану область — вирішує сервер (`region_change.allowed`).
class RegionSelectionScreen extends ConsumerStatefulWidget {
  const RegionSelectionScreen({super.key});

  @override
  ConsumerState<RegionSelectionScreen> createState() => _RegionSelectionScreenState();
}

class _RegionSelectionScreenState extends ConsumerState<RegionSelectionScreen> {
  String _query = '';
  String? _selectedSlug;
  bool _termsAccepted = false;
  bool _submitting = false;

  Future<void> _submit() async {
    final slug = _selectedSlug;
    if (slug == null || !_termsAccepted) return;
    setState(() => _submitting = true);
    try {
      await ref.read(meProvider.notifier).completeOnboarding(slug);
      // Далі роутер сам перейде на карту за onboarding.next_step.
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося зберегти. Спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull;
    final regions = ref.watch(regionsProvider);

    // Область уже обрана, а змінювати її не можна — лишаємо тільки крок згоди.
    final lockedSlug =
        (me?.homeRegion != null && me?.regionChange.allowed == false) ? me!.homeRegion!.slug : null;
    _selectedSlug ??= me?.homeRegion?.slug;
    if (lockedSlug != null) _selectedSlug = lockedSlug;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                me?.onboarding.nextStepLabel ?? 'Оберіть свою область',
                style: GoogleFonts.merriweather(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Карта, ліси та прогноз доступні в межах вашої області.',
                style: GoogleFonts.inter(color: AppTheme.darkGreen.withValues(alpha: 0.7)),
              ),
              if (lockedSlug != null && me != null) ...[
                const SizedBox(height: 8),
                // Чому область не можна змінити — текст із сервера (ADR-016).
                Text(
                  me.regionChange.reasonLabel,
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.accentOrange),
                ),
              ],
              const SizedBox(height: 16),
              if (lockedSlug == null)
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Пошук області',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: regions.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _RegionsError(
                    message: e is ApiException ? e.userMessage : 'Не вдалося завантажити області.',
                    onRetry: () => ref.invalidate(regionsProvider),
                  ),
                  data: (list) => _RegionList(
                    regions: list
                        .where((r) => lockedSlug == null || r.slug == lockedSlug)
                        .where((r) => _query.isEmpty || r.name.toLowerCase().contains(_query))
                        .toList(),
                    selectedSlug: _selectedSlug,
                    onSelect: lockedSlug == null ? (slug) => setState(() => _selectedSlug = slug) : null,
                  ),
                ),
              ),
              CheckboxListTile(
                value: _termsAccepted,
                onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Я приймаю Умови використання та Політику конфіденційності'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: (_selectedSlug != null && _termsAccepted && !_submitting) ? _submit : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Продовжити'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionList extends StatelessWidget {
  const _RegionList({required this.regions, required this.selectedSlug, required this.onSelect});

  final List<RegionSummary> regions;
  final String? selectedSlug;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) return const Center(child: Text('Нічого не знайдено'));
    return ListView.builder(
      itemCount: regions.length,
      itemBuilder: (context, i) {
        final r = regions[i];
        final selected = r.slug == selectedSlug;
        return ListTile(
          title: Text(r.name),
          trailing: selected ? const Icon(Icons.check_circle_rounded, color: AppTheme.darkGreen) : null,
          selected: selected,
          onTap: onSelect == null ? null : () => onSelect!(r.slug),
        );
      },
    );
  }
}

class _RegionsError extends StatelessWidget {
  const _RegionsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            TextButton(onPressed: onRetry, child: const Text('Повторити')),
          ],
        ),
      );
}
