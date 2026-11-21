import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/profile/trophies_view.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';

/// Публічний профіль грибника (ADR-021 §21.2): аватар, @нік, ім'я, рівень, рейтинг, друзі.
/// Ніколи — координат, області, телефону, email, точок. Кнопки дій — із сервера.
/// Повертає (через `Navigator.pop`) оновлену картку, якщо стан змінився.
class FriendProfileScreen extends ConsumerStatefulWidget {
  const FriendProfileScreen({super.key, required this.userId, this.initial});

  final String userId;
  final FriendCard? initial;

  @override
  ConsumerState<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends ConsumerState<FriendProfileScreen> {
  FriendProfile? _profile;
  FriendCard? _changed;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(friendsRepositoryProvider).profile(widget.userId);
      if (mounted) setState(() => _profile = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    }
  }

  Future<void> _run(FriendActionButton a) async {
    final card = _profile?.card ?? widget.initial;
    if (card == null) return;
    setState(() => _busy = true);
    final updated = await runFriendAction(context, ref, card, a);
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated == null) return;
    _changed = updated;
    ref.invalidate(friendsProvider);
    if (updated.relation == 'blocked') {
      Navigator.of(context).pop(updated);
      return;
    }
    final p = _profile;
    setState(() => _profile = p == null
        ? null
        : FriendProfile(
            card: updated,
            isMe: p.isMe,
            rating: p.rating,
            trophies: p.trophies,
            friendsCount: p.friendsCount + (updated.relation == 'friends' ? 1 : 0) - (card.relation == 'friends' && updated.relation != 'friends' ? 1 : 0)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final card = p?.card ?? widget.initial;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: Text(card == null ? 'Профіль' : '@${card.handle}', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (p != null && p.card.menu.isNotEmpty)
              PopupMenuButton<FriendActionButton>(
                key: const ValueKey('profile-menu'),
                icon: const Icon(Icons.more_vert_rounded, color: AppTheme.darkGreen),
                onSelected: _run,
                itemBuilder: (_) => [
                  for (final a in p.card.menu)
                    PopupMenuItem(value: a, child: Text(a.label, style: TextStyle(color: a.style == 'danger' ? AppTheme.errorRed : null))),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, key: const ValueKey('friend-profile-error'), textAlign: TextAlign.center),
              )
            else if (card == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else ...[
              Container(
                key: const ValueKey('friend-profile'),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  children: [
                    UserAvatar(avatar: card.avatar, size: 112),
                    const SizedBox(height: 12),
                    Text('@${card.handle}', style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                    if (card.name != null && card.name!.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(card.name!, style: const TextStyle(fontSize: 15))),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (card.levelLabel.isNotEmpty) _Pill(Icons.eco_rounded, card.levelLabel),
                        if (p != null) _Pill(Icons.star_rounded, '${p.rating} ${_points(p.rating)}'),
                        if (p != null) _Pill(Icons.group_rounded, '${p.friendsCount} ${_friendsWord(p.friendsCount)}'),
                      ],
                    ),
                    if (card.relationLabel != null) ...[
                      const SizedBox(height: 12),
                      Text(card.relationLabel!, key: const ValueKey('friend-relation'), style: const TextStyle(color: AppTheme.accentOrange, fontWeight: FontWeight.w700)),
                    ],
                    if (p != null && !p.isMe && p.card.buttons.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [for (final a in p.card.buttons) FriendActionChip(button: a, busy: _busy, onTap: () => _run(a))],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: p == null || p.trophies.isEmpty
                    ? Row(
                        children: [
                          Icon(Icons.emoji_events_rounded, color: AppTheme.accentOrange.withValues(alpha: 0.8)),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Трофеїв поки немає', style: TextStyle(color: Colors.black54))),
                        ],
                      )
                    : Column(
                        key: const ValueKey('friend-trophies'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Трофеї · ${p.trophies.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final t in p.trophies)
                                Tooltip(message: t.title, child: TrophyBadge(id: t.id, earned: true, size: 56)),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _points(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'бал';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'бали';
  return 'балів';
}

String _friendsWord(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'друг';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'друзі';
  return 'друзів';
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xffeef4e6), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.darkGreen),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(color: AppTheme.darkGreen, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}
