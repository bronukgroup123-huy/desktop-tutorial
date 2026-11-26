import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
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
    final muted = AppTheme.textMuted;
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
                style: AppTheme.blockTitle,
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
        if (card.actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _OwnPickActions(card: card),
        ],
      ],
    );
  }
}

/// Дії автора над своєю точкою (B3.4). Які кнопки показати — вирішує сервер (`actions`);
/// ліміти й правила видимості перевіряє він же, клієнт лише показує його відповідь.
class _OwnPickActions extends ConsumerStatefulWidget {
  const _OwnPickActions({required this.card});

  final PickCard card;

  @override
  ConsumerState<_OwnPickActions> createState() => _OwnPickActionsState();
}

class _OwnPickActionsState extends ConsumerState<_OwnPickActions> {
  bool _busy = false;

  String get _id => widget.card.pick.id;

  Future<void> _run(Future<void> Function() action, String done, {bool close = false}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(picksMapProvider);
      ref.invalidate(meProvider); // ліміти точок і підказки в профілі
      if (!mounted) return;
      showToast(context, done);
      if (close) {
        Navigator.of(context).pop();
      } else {
        ref.invalidate(pickCardProvider(_id));
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося. Перевірте інтернет і спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String text, String yes, {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
            TextButton(
              key: const ValueKey('pick-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              style: danger ? TextButton.styleFrom(foregroundColor: AppTheme.errorRed) : null,
              child: Text(yes),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _editDescription() async {
    final controller = TextEditingController(text: widget.card.description ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Опис точки'),
        content: TextField(
          key: const ValueKey('pick-description-field'),
          controller: controller,
          autofocus: true,
          maxLength: 500,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Під якими деревами, яка погода…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          TextButton(
            key: const ValueKey('pick-description-save'),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );
    if (text == null) return;
    final repo = ref.read(picksRepositoryProvider);
    await _run(
      () => text.trim().isEmpty ? repo.updatePick(_id, clearDescription: true) : repo.updatePick(_id, description: text),
      'Опис збережено',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(picksRepositoryProvider);
    final actions = widget.card.actions;
    final buttons = <Widget>[
      if (actions.contains('make_public'))
        FilledButton.icon(
          key: const ValueKey('pick-make-public'),
          onPressed: _busy
              ? null
              : () async {
                  if (await _confirm('Точку побачать інші грибники. Місце покажемо приблизно — у межах пів кілометра.', 'Опублікувати')) {
                    await _run(() => repo.updatePick(_id, visibility: 'public'), 'Точку опубліковано');
                  }
                },
          icon: const Icon(Icons.public_rounded),
          label: const Text('Зробити публічною'),
        ),
      if (actions.contains('make_private'))
        OutlinedButton.icon(
          key: const ValueKey('pick-make-private'),
          onPressed: _busy ? null : () => _run(() => repo.updatePick(_id, visibility: 'private'), 'Точку сховано — тепер її бачите лише ви'),
          icon: const Icon(Icons.lock_outline_rounded),
          label: const Text('Зробити приватною'),
        ),
      if (actions.contains('edit_description'))
        OutlinedButton.icon(
          key: const ValueKey('pick-edit-description'),
          onPressed: _busy ? null : _editDescription,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Змінити опис'),
        ),
      if (actions.contains('delete'))
        TextButton.icon(
          key: const ValueKey('pick-delete'),
          onPressed: _busy
              ? null
              : () async {
                  if (await _confirm('Видалити цю точку? Вона зникне з карти.', 'Видалити', danger: true)) {
                    await _run(() => repo.deletePick(_id), 'Точку видалено', close: true);
                  }
                },
          style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Видалити точку'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
      ],
    );
  }
}
