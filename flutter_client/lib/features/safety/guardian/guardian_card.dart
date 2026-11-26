import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/models/guardian.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';
import 'package:flutter_client/features/safety/guardian/watched_hikes.dart';

const _alarmRed = AppTheme.danger;
const _violet = Color(0xff6d28d9);

/// «Наглядач» на вкладці «Безпека» (ADR-022 §22.2): походи друзів, де я Наглядач (тривожні —
/// червоним, згори), прохання «будь моїм Наглядачем», мої Наглядачі, Telegram. Лише для акаунта
/// (гість бачить, що це дасть вхід).
class GuardianCard extends ConsumerWidget {
  const GuardianCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    if (me == null || me.isGuest) {
      return _Box(
        key: const ValueKey('guardian-guest'),
        child: Row(
          children: [
            const Icon(Icons.shield_moon_rounded, color: _violet),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Наглядач — друг, що бачить ваш похід і отримує тривоги. Доступно після входу через Google.',
                  style: TextStyle(color: AppTheme.textMuted)),
            ),
          ],
        ),
      );
    }
    final overview = ref.watch(guardianProvider);
    final data = overview.valueOrNull;
    final watched = ref.watch(watchedHikesProvider).valueOrNull;
    final summaries = watched != null ? [for (final d in watched) d.summary] : data?.watched ?? const <WatchedHike>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in summaries) Padding(padding: const EdgeInsets.only(bottom: 8), child: WatchedHikeTile(hike: w)),
        for (final i in data?.invites ?? const <GuardianPerson>[])
          Padding(padding: const EdgeInsets.only(bottom: 8), child: _InviteTile(person: i)),
        _Box(
          key: const ValueKey('guardian-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.shield_moon_rounded, color: _violet),
                  SizedBox(width: 8),
                  Text('Наглядач', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.darkGreen)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Друг, що бачить ваш похід, поки він триває, і отримує тривоги: SOS або якщо ви не відповіли на «Все добре?» '
                'у час повернення. Після «Я вдома» — нічого не бачить.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
              ),
              if (overview.hasError && data == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Немає зв\'язку — Наглядачів покажемо, щойно з\'явиться інтернет',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                ),
              if (data != null) ...[
                for (final g in data.guardians) _GuardianRow(person: g),
                if (data.watching.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Ви Наглядач для: ${data.watching.map((w) => '@${w.handle}').join(', ')}',
                        key: const ValueKey('guardian-watching'),
                        style: const TextStyle(color: _violet, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('guardian-add'),
                      onPressed: () => _pickFriend(context, ref, data),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: Text(data.guardians.isEmpty ? 'Обрати Наглядача' : 'Додати Наглядача'),
                    ),
                    if (data.telegramAvailable)
                      OutlinedButton.icon(
                        key: const ValueKey('guardian-telegram'),
                        onPressed: () => _telegram(context, ref, data.telegramLinked),
                        icon: Icon(data.telegramLinked ? Icons.check_circle_rounded : Icons.send_rounded, size: 18),
                        label: Text(data.telegramLinked ? 'Telegram підключено' : 'Тривоги в Telegram'),
                      ),
                  ],
                ),
                if (data.limitLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(data.limitLabel!, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickFriend(BuildContext context, WidgetRef ref, GuardianOverview data) async {
    final FriendsOverview friends;
    try {
      friends = await ref.read(friendsProvider.future);
    } catch (_) {
      if (context.mounted) showToast(context, 'Не вдалося завантажити друзів — перевірте інтернет', isError: true);
      return;
    }
    if (!context.mounted) return;
    final taken = {for (final g in data.guardians) g.id};
    final candidates = friends.friends.where((f) => !taken.contains(f.id)).toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          key: const ValueKey('guardian-pick'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text('Наглядача обирають серед друзів. Друг підтвердить у своєму застосунку.',
                style: TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              ListTile(
                key: const ValueKey('guardian-pick-empty'),
                leading: const Icon(Icons.group_add_rounded),
                title: const Text('Спершу додайте друзів'),
                subtitle: const Text('Пошук за @ніком'),
                onTap: () {
                  Navigator.of(c).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
                },
              ),
            for (final f in candidates)
              ListTile(
                key: ValueKey('guardian-pick-${f.id}'),
                leading: UserAvatar(avatar: f.avatar, size: 40),
                title: Text('@${f.handle}'),
                subtitle: f.name == null ? null : Text(f.name!),
                onTap: () => Navigator.of(c).pop(f.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _personAction(context, ref, 'invite', picked);
  }

  Future<void> _telegram(BuildContext context, WidgetRef ref, bool linked) async {
    try {
      if (linked) {
        await ref.read(guardianRepositoryProvider).telegramUnlink();
        if (context.mounted) showToast(context, 'Telegram відключено');
      } else {
        final url = await ref.read(guardianRepositoryProvider).telegramLink();
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      ref.invalidate(guardianProvider);
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.userMessage, isError: true);
    }
  }
}

Future<void> _personAction(BuildContext context, WidgetRef ref, String action, String userId) async {
  try {
    final done = await ref.read(guardianRepositoryProvider).person(action, userId);
    if (context.mounted && done != null) showToast(context, done);
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.userMessage, isError: true);
  }
  ref.invalidate(guardianProvider);
}

class _GuardianRow extends ConsumerWidget {
  const _GuardianRow({required this.person});

  final GuardianPerson person;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          key: ValueKey('guardian-${person.id}'),
          children: [
            UserAvatar(avatar: person.avatar, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${person.handle}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                  if (person.label != null)
                    Text(person.label!,
                        style: TextStyle(fontSize: 13, color: person.accepted ? _violet : AppTheme.accentOrange, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            for (final a in person.actions)
              IconButton(
                key: ValueKey('guardian-${a.id}-${person.id}'),
                tooltip: a.label,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => _personAction(context, ref, a.id, person.id),
              ),
          ],
        ),
      );
}

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.person});

  final GuardianPerson person;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Box(
        key: ValueKey('guardian-invite-${person.id}'),
        border: _violet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(avatar: person.avatar, size: 44),
                const SizedBox(width: 10),
                Expanded(child: Text(person.label ?? '@${person.handle}', style: const TextStyle(color: AppTheme.darkGreen))),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final a in person.actions)
                  a.style == 'primary'
                      ? FilledButton(
                          key: ValueKey('guardian-${a.id}'),
                          style: FilledButton.styleFrom(backgroundColor: _violet),
                          onPressed: () => _personAction(context, ref, a.id, person.id),
                          child: Text(a.label),
                        )
                      : OutlinedButton(
                          key: ValueKey('guardian-${a.id}'),
                          onPressed: () => _personAction(context, ref, a.id, person.id),
                          child: Text(a.label),
                        ),
              ],
            ),
          ],
        ),
      );
}

/// Похід друга: статус, повернення, батарея, сигнал; тривога — червона рамка. Дотик — деталі.
class WatchedHikeTile extends StatelessWidget {
  const WatchedHikeTile({super.key, required this.hike});

  final WatchedHike hike;

  @override
  Widget build(BuildContext context) {
    final color = hike.alarm ? _alarmRed : _violet;
    return Material(
      key: ValueKey('watched-${hike.hikeId}'),
      color: hike.alarm ? const Color(0xfffdecea) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color, width: hike.alarm ? 2 : 1.2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WatchedHikeScreen(hikeId: hike.hikeId, initial: hike))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(avatar: hike.owner.avatar, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${hike.owner.handle} · ${hike.statusLabel}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                    if (hike.detailLabel != null) Text(hike.detailLabel!, style: const TextStyle(color: AppTheme.darkGreen, fontSize: 13)),
                    Text(
                      [hike.lastSignalLabel, if (hike.batteryLabel != null) hike.batteryLabel!].join(' · '),
                      style: TextStyle(color: hike.noSignal ? _alarmRed : AppTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Картка грибника для Наглядача: статус, повернення, батарея, сигнал, «Показати на карті»,
/// «Передати рятувальникам» — координати великими цифрами й готовий текст SMS на 112, без посилань.
class WatchedHikeScreen extends ConsumerWidget {
  const WatchedHikeScreen({super.key, required this.hikeId, this.initial});

  final String hikeId;
  final WatchedHike? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(watchedHikesProvider).valueOrNull;
    final detail = list?.where((d) => d.summary.hikeId == hikeId).firstOrNull;
    final h = detail?.summary ?? initial;
    final ended = list != null && detail == null;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(h == null ? 'Похід' : '@${h.owner.handle}', style: const TextStyle(color: AppTheme.darkGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (ended)
            const _Box(
              key: ValueKey('watched-ended'),
              child: Text('Похід завершено — місце й трек більше не видно.'),
            )
          else if (h != null) ...[
            _Box(
              border: h.alarm ? _alarmRed : _violet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.statusLabel,
                      key: const ValueKey('watched-status'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: h.alarm ? _alarmRed : _violet)),
                  if (h.detailLabel != null) Text(h.detailLabel!, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(h.lastSignalLabel, style: TextStyle(color: h.noSignal ? _alarmRed : AppTheme.darkGreen)),
                  if (h.batteryLabel != null) Text(h.batteryLabel!),
                  if (h.gpsIssueLabel != null)
                    Text(h.gpsIssueLabel!, key: const ValueKey('watched-gps'), style: const TextStyle(color: AppTheme.warning)),
                  if (h.last != null) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const ValueKey('watched-show-map'),
                      style: FilledButton.styleFrom(backgroundColor: _violet),
                      onPressed: () {
                        ref.read(mapFocusPointProvider.notifier).state = LatLng(h.last!.lat, h.last!.lng);
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        context.go('/map');
                      },
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('Показати на карті'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (detail?.rescueCoords != null) _RescueBox(detail: detail!),
          ] else
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}

class _RescueBox extends StatelessWidget {
  const _RescueBox({required this.detail});

  final HikeDetail detail;

  @override
  Widget build(BuildContext context) => _Box(
        key: const ValueKey('watched-rescue'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Передати рятувальникам', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.darkGreen)),
            const SizedBox(height: 6),
            SelectableText(detail.rescueCoords!,
                key: const ValueKey('watched-coords'),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 0.5, fontFeatures: [FontFeature.tabularFigures()])),
            if (detail.rescueAt != null) Text(detail.rescueAt!, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('watched-call'),
                  style: FilledButton.styleFrom(backgroundColor: _alarmRed),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Подзвонити 112'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('watched-sms'),
                  onPressed: () => launchUrl(Uri(scheme: 'sms', path: '112', queryParameters: {'body': detail.rescueSms ?? ''})),
                  icon: const Icon(Icons.sms_rounded),
                  label: const Text('SMS на 112'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('watched-copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: detail.rescueSms ?? detail.rescueCoords!));
                    if (context.mounted) showToast(context, 'Скопійовано');
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Скопіювати'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child, this.border});

  final Widget child;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: border == null ? null : Border.all(color: border!, width: 1.5),
        ),
        child: child,
      );
}
