import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/push.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/friends/friend_profile_screen.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';

/// «Друзі» (ADR-021 §21.1): пошук за @ніком, мої друзі, запити (вхідні й надіслані), заблоковані.
/// Що можна зробити з людиною і як це назвати — каже сервер (`actions`).
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _searched = '';
  List<FriendCard>? _results;
  String? _hint;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Сповіщення «запит у друзі» / «прийнято» — тихо, якщо Firebase у збірці немає.
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerPush());
  }

  Future<void> _registerPush() async {
    if (kIsWeb || !PushService.available) return;
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || !mounted) return;
      await ref.read(friendsRepositoryProvider).registerPush(token, Platform.isIOS ? 'ios' : 'android');
    } catch (_) {
      // без сповіщень друзі працюють так само
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _hint = null;
        _searched = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final r = await ref.read(friendsRepositoryProvider).search(q);
      if (!mounted || _query.text.trim() != q) return;
      setState(() {
        _searched = q;
        _results = r.results;
        _hint = r.hint;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _hint = e.userMessage);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Після дії — оновити список і результати пошуку (стан людини змінився).
  void _changed(FriendCard updated) {
    ref.invalidate(friendsProvider);
    final r = _results;
    if (r != null) {
      setState(() => _results = [for (final c in r) c.id == updated.id ? updated : c]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(friendsProvider);
    final data = overview.valueOrNull;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Друзі', style: AppTheme.appBarTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if ((data?.blocked ?? const []).isNotEmpty)
            IconButton(
              key: const ValueKey('friends-blocked'),
              tooltip: 'Заблоковані',
              icon: const Icon(Icons.block_rounded, color: AppTheme.darkGreen),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _BlockedScreen())),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(friendsProvider.future),
        child: ListView(
          key: const ValueKey('friends-list'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            TextField(
              key: const ValueKey('friends-search'),
              controller: _query,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => v.trim().isEmpty ? null : _search(v.trim()),
              decoration: InputDecoration(
                hintText: 'Знайти за @ніком',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистити пошук',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _query.clear();
                          _onQuery('');
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            if (_results != null || _hint != null) ...[
              _Header(_searched.isEmpty ? 'Пошук' : 'Пошук: @${_searched.replaceFirst(RegExp('^@+'), '')}'),
              if (_hint != null) _Note(_hint!, key: const ValueKey('friends-search-hint')),
              for (final c in _results ?? const <FriendCard>[]) FriendTile(card: c, onChanged: _changed),
            ] else ...[
              if (overview.isLoading && data == null)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (overview.hasError && data == null)
                _Note(
                  overview.error is ApiException ? (overview.error as ApiException).userMessage : 'Не вдалося завантажити друзів',
                  key: const ValueKey('friends-error'),
                ),
              if (data != null) ...[
                if (data.incoming.isNotEmpty) ...[
                  _Header('Запити в друзі · ${data.incoming.length}'),
                  for (final c in data.incoming) FriendTile(card: c, onChanged: _changed),
                ],
                _Header(data.friends.isEmpty ? 'Мої друзі' : 'Мої друзі · ${data.friends.length}'),
                if (data.friends.isEmpty)
                  const _Note(
                    'Поки нікого. Знайдіть друзів за @ніком — і обирайте серед них Наглядача в поході.',
                    key: ValueKey('friends-empty'),
                  ),
                for (final c in data.friends) FriendTile(card: c, onChanged: _changed),
                if (data.outgoing.isNotEmpty) ...[
                  const _Header('Надіслані запити'),
                  for (final c in data.outgoing) FriendTile(card: c, onChanged: _changed),
                ],
                if (data.limitLabel != null) _Note(data.limitLabel!, small: true),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _BlockedScreen extends ConsumerWidget {
  const _BlockedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(friendsProvider).valueOrNull?.blocked ?? const [];
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Заблоковані', style: AppTheme.appBarTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const _Note('Заблоковані не бачать вашого профілю й не можуть надіслати запит. Ви їх — теж.'),
          for (final c in blocked) FriendTile(card: c, onChanged: (_) => ref.invalidate(friendsProvider)),
        ],
      ),
    );
  }
}

/// Рядок користувача: аватар, @нік, ім'я · рівень, кнопки з сервера й меню «⋮».
class FriendTile extends ConsumerStatefulWidget {
  const FriendTile({super.key, required this.card, required this.onChanged});

  final FriendCard card;
  final ValueChanged<FriendCard> onChanged;

  @override
  ConsumerState<FriendTile> createState() => _FriendTileState();
}

class _FriendTileState extends ConsumerState<FriendTile> {
  bool _busy = false;

  Future<void> _run(FriendActionButton a) async {
    setState(() => _busy = true);
    final updated = await runFriendAction(context, ref, widget.card, a);
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated != null) widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final subtitle = [if (c.name != null && c.name!.isNotEmpty) c.name!, if (c.levelLabel.isNotEmpty) c.levelLabel].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: ValueKey('friend-${c.id}'),
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: c.relation == 'blocked'
              ? null
              : () async {
                  final updated = await Navigator.of(context).push<FriendCard>(
                    MaterialPageRoute(builder: (_) => FriendProfileScreen(userId: c.id, initial: c)),
                  );
                  if (updated != null) widget.onChanged(updated);
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(avatar: c.avatar, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('@${c.handle}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen, fontSize: 15)),
                          if (subtitle.isNotEmpty)
                            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.black.withValues(alpha: 0.6), fontSize: 13)),
                          if (c.relationLabel != null && c.relation != 'friends')
                            Text(c.relationLabel!, style: const TextStyle(color: AppTheme.accentOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (c.menu.isNotEmpty)
                      PopupMenuButton<FriendActionButton>(
                        key: ValueKey('friend-menu-${c.id}'),
                        icon: const Icon(Icons.more_vert_rounded, color: AppTheme.darkGreen),
                        onSelected: _run,
                        itemBuilder: (_) => [
                          for (final a in c.menu)
                            PopupMenuItem(
                              value: a,
                              child: Text(a.label, style: TextStyle(color: a.style == 'danger' ? AppTheme.errorRed : null)),
                            ),
                        ],
                      ),
                  ],
                ),
                if (c.buttons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 60, top: 6, right: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final a in c.buttons) FriendActionChip(button: a, busy: _busy, onTap: () => _run(a)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FriendActionChip extends StatelessWidget {
  const FriendActionChip({super.key, required this.button, required this.busy, required this.onTap, this.onDark = false});

  final FriendActionButton button;
  final bool busy;
  final VoidCallback onTap;

  /// На темній шапці профілю: головна — бурштинова, інші — кремовий контур.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey('friend-action-${button.id}');
    final child = Text(button.label);
    // Без VisualDensity.compact: зона натискання — 48 px (вимога Android, UI-003).
    const pad = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    return button.style == 'primary'
        ? FilledButton(
            key: key,
            onPressed: busy ? null : onTap,
            style: FilledButton.styleFrom(
                backgroundColor: onDark ? AppTheme.accentOrange : AppTheme.darkGreen, foregroundColor: Colors.white, padding: pad),
            child: child,
          )
        : OutlinedButton(
            key: key,
            onPressed: busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: onDark ? AppTheme.backgroundColor : AppTheme.darkGreen,
              side: onDark ? BorderSide(color: AppTheme.backgroundColor.withValues(alpha: 0.6)) : null,
              padding: pad,
            ),
            child: child,
          );
  }
}

/// Виконати дію (з питанням, якщо сервер його дав; скарга — з вибором причини).
/// Повертає новий стан картки або `null` (скасовано / помилка — показано підказку).
Future<FriendCard?> runFriendAction(BuildContext context, WidgetRef ref, FriendCard card, FriendActionButton a) async {
  String? reason;
  String? comment;
  var block = false;
  if (a.id == 'report') {
    final r = await showDialog<({String reason, String comment, bool block})>(
      context: context,
      builder: (_) => _ReportDialog(handle: card.handle),
    );
    if (r == null) return null;
    reason = r.reason;
    comment = r.comment;
    block = r.block;
  } else if (a.confirmLabel != null) {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('friend-confirm'),
        content: Text(a.confirmLabel!),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Скасувати')),
          FilledButton(
            key: const ValueKey('friend-confirm-yes'),
            style: FilledButton.styleFrom(backgroundColor: a.style == 'danger' ? AppTheme.errorRed : AppTheme.darkGreen),
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(a.label),
          ),
        ],
      ),
    );
    if (yes != true) return null;
  }
  try {
    final res = await ref.read(friendsRepositoryProvider).act(a.id, card.id, reason: reason, comment: comment, block: block);
    if (context.mounted && res.done != null) showToast(context, res.done!);
    return res.user;
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.userMessage, isError: true);
    return null;
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.handle});

  final String handle;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String? _reason;
  bool _block = true;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('report-dialog'),
      title: Text('Скарга на @${widget.handle}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final (code, label) in kReportReasons)
                    RadioListTile<String>(
                      key: ValueKey('report-$code'),
                      value: code,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(label),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _comment,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Коментар (необов\'язково)'),
            ),
            CheckboxListTile(
              key: const ValueKey('report-block'),
              value: _block,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _block = v ?? false),
              title: const Text('Також заблокувати'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Скасувати')),
        FilledButton(
          key: const ValueKey('report-send'),
          onPressed: _reason == null ? null : () => Navigator.of(context).pop((reason: _reason!, comment: _comment.text, block: _block)),
          child: const Text('Надіслати'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen, fontSize: 15)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key, this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(text, style: TextStyle(color: Colors.black.withValues(alpha: small ? 0.45 : 0.65), fontSize: small ? 12 : 14)),
      );
}
