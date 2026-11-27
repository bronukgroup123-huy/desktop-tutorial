import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/forecast/forecast_view.dart';
import 'package:flutter_client/features/picks/new_pick_screen.dart' show replyFindStarterProvider;

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
        // Підтвердження відповідями знахідкою (B3.8) і двійник — підписи з сервера.
        if (card.confirmedLabel != null) ...[
          const SizedBox(height: 12),
          ForecastInfoCard(
            key: const ValueKey('pick-confirmed'),
            icon: Icons.verified_rounded,
            text: card.confirmedByMe ? '${card.confirmedLabel!}. Серед них — ви' : card.confirmedLabel!,
          ),
        ],
        if (card.twinWarningLabel != null) ...[
          const SizedBox(height: 8),
          ForecastInfoCard(
            key: const ValueKey('pick-twin-warning'),
            icon: Icons.dangerous_outlined,
            text: card.twinWarningLabel!,
            color: AppTheme.danger,
          ),
        ],
        const SizedBox(height: 16),
        ForecastInfoCard(
          key: pick.isShared ? const ValueKey('pick-shared-from') : null,
          icon: pick.isShared
              ? Icons.card_giftcard_rounded
              : pick.isExact
                  ? Icons.my_location_rounded
                  : Icons.blur_circular_rounded,
          text: pick.isShared
              ? '${pick.sharedFromLabel!}. Друг поділився з вами точним місцем — переслати точку далі не можна.'
              : pick.isMine
                  ? 'Це ваша точка — місце показано точно.'
                  : 'Місце показано приблизно: справжнє — у межах пів кілометра.',
        ),
        // Своя приватна точка: з ким ви нею поділилися (B9.4) — можна прибрати будь-кого.
        if (pick.isMine && card.sharedWith.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SharedWithList(card: card),
        ],
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
/// Посилання, що відкриває місце в Google Картах (застосунок, якщо встановлений, інакше браузер).
Uri googleMapsUri(double lat, double lng) => Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
    });

/// Як відкрити зовнішнє посилання (провайдер — щоб тести не відкривали браузер).
final externalLauncherProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

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

  Future<void> _replyFound() async {
    final pick = widget.card.pick;
    final saved = await ref.read(replyFindStarterProvider)(
      context,
      (pickId: pick.id, species: PickSpecies(id: pick.speciesId!, nameLabel: pick.nameLabel, latinLabel: null)),
    );
    if (!saved || !mounted) return;
    ref.invalidate(pickCardProvider(pick.id));
    ref.invalidate(picksMapProvider);
    ref.invalidate(meProvider);
  }

  Future<void> _share() async {
    final already = {for (final r in widget.card.sharedWith) r.userId};
    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (_) => _FriendPicker(exclude: already),
    );
    if (chosen == null || chosen.isEmpty) return;
    String? label;
    await _run(() async {
      label = await ref.read(picksRepositoryProvider).sharePick(_id, chosen);
    }, chosen.length == 1 ? 'Поділилися з другом' : 'Поділилися з друзями');
    if (label != null && mounted) showToast(context, label!);
  }

  Future<void> _openInMaps() async {
    final p = widget.card.pick.point;
    var opened = false;
    try {
      opened = await ref.read(externalLauncherProvider)(googleMapsUri(p.latitude, p.longitude));
    } catch (_) {}
    if (!opened && mounted) showToast(context, 'Не вдалося відкрити карти на цьому телефоні', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(picksRepositoryProvider);
    final actions = widget.card.actions;
    final buttons = <Widget>[
      // Чужа публічна точка: відповісти своєю знахідкою (B3.8b). Кнопку показує сервер лише тим, хто може.
      if (actions.contains('reply_found') && widget.card.pick.speciesId != null)
        FilledButton.icon(
          key: const ValueKey('pick-reply-found'),
          onPressed: _busy ? null : _replyFound,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Я теж знайшов тут'),
        ),
      // Поділитися своєю приватною точкою з друзями (B9.4, ADR-021 §21.5).
      if (actions.contains('share'))
        FilledButton.icon(
          key: const ValueKey('pick-share'),
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.card_giftcard_rounded),
          label: const Text('Поділитися з другом'),
        ),
      // Своє місце — у звичній карті: прокласти маршрут, зберегти в Google (замість файлу-експорту, B6.1).
      if (actions.contains('open_in_maps'))
        OutlinedButton.icon(
          key: const ValueKey('pick-open-in-maps'),
          onPressed: _busy ? null : _openInMaps,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Відкрити в Google Картах'),
        ),
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

/// З ким автор поділився своєю приватною точкою; «Прибрати» відкликає доступ в одного друга.
class _SharedWithList extends ConsumerStatefulWidget {
  const _SharedWithList({required this.card});

  final PickCard card;

  @override
  ConsumerState<_SharedWithList> createState() => _SharedWithListState();
}

class _SharedWithListState extends ConsumerState<_SharedWithList> {
  String? _busyId;

  Future<void> _revoke(PickShareRecipient r) async {
    final id = widget.card.pick.id;
    setState(() => _busyId = r.userId);
    try {
      await ref.read(picksRepositoryProvider).revokeShare(id, friendId: r.userId);
      ref.invalidate(pickCardProvider(id));
      if (mounted) showToast(context, '${r.label} більше не бачить цю точку');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося. Перевірте інтернет і спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Container(
      key: const ValueKey('pick-shared-with'),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.sharedWithLabel ?? 'Бачать друзі', style: AppTheme.sectionTitle),
          for (final r in card.sharedWith)
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(r.label, overflow: TextOverflow.ellipsis)),
                TextButton(
                  key: ValueKey('pick-share-revoke-${r.userId}'),
                  onPressed: _busyId == null ? () => _revoke(r) : null,
                  child: const Text('Прибрати'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Вибір друзів, з якими поділитися точкою. Тих, хто вже бачить точку, не показуємо.
class _FriendPicker extends ConsumerStatefulWidget {
  const _FriendPicker({required this.exclude});

  final Set<String> exclude;

  @override
  ConsumerState<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends ConsumerState<_FriendPicker> {
  final _chosen = <String>{};
  static const _max = 20;

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: friends.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(
            height: 160,
            child: Center(child: Text(e is ApiException ? e.userMessage : 'Не вдалося завантажити друзів')),
          ),
          data: (o) {
            final list = [for (final f in o.friends) if (!widget.exclude.contains(f.id)) f];
            if (list.isEmpty) {
              return SizedBox(
                height: 160,
                child: Center(
                  key: const ValueKey('pick-share-no-friends'),
                  child: Text(
                    o.friends.isEmpty
                        ? 'Поки немає друзів. Додайте їх у Профілі → «Друзі».'
                        : 'Цю точку вже бачать усі ваші друзі.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Поділитися з друзями', style: AppTheme.blockTitle),
                const SizedBox(height: 4),
                Text(
                  'Друзі побачать точне місце, фото й опис. Переслати точку далі вони не зможуть, '
                  'а ви будь-коли можете прибрати доступ.',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in list)
                        CheckboxListTile(
                          key: ValueKey('pick-share-friend-${f.id}'),
                          value: _chosen.contains(f.id),
                          onChanged: (v) => setState(() {
                            if (v == true && _chosen.length < _max) {
                              _chosen.add(f.id);
                            } else {
                              _chosen.remove(f.id);
                            }
                          }),
                          title: Text('@${f.handle}'),
                          subtitle: f.name == null ? null : Text(f.name!),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('pick-share-send'),
                  onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, _chosen.toList()),
                  child: Text(_chosen.isEmpty ? 'Оберіть друзів' : 'Поділитися (${_chosen.length})'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
