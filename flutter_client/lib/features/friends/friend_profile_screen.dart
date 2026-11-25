import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/friends.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/friends/friends_screen.dart';
import 'package:flutter_client/features/profile/profile_hero.dart';
import 'package:flutter_client/features/profile/trophies_view.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';

/// Публічний профіль грибника (ADR-021 §21.2; PO 2026-11-21): лише блок аватара (аватар,
/// ім'я, @нік, рівень, дії), трофеї на дубовій поличці й подарунки. Ніколи — балів, прогресу,
/// кількості друзів, координат, області, телефону, email, точок. Кнопки дій — із сервера.
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
        : FriendProfile(card: updated, isMe: p.isMe, trophies: p.trophies));
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
          title: Text(card == null ? 'Профіль' : '@${card.handle}', style: AppTheme.appBarTitle),
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
              ProfileHeroBackground(
                key: const ValueKey('friend-profile'),
                levelId: card.levelId,
                glowCenterY: 0.32,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Column(
                    children: [
                      UserAvatar(avatar: card.avatar, size: 208),
                      const SizedBox(height: 2),
                      Text(
                        card.name != null && card.name!.isNotEmpty ? card.name! : '@${card.handle}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: heroCream, shadows: const [Shadow(color: Colors.black54, blurRadius: 6)]),
                      ),
                      if (card.name != null && card.name!.isNotEmpty)
                        Text('@${card.handle}', style: TextStyle(color: heroCream.withValues(alpha: 0.75), fontSize: 13)),
                      if (card.levelLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        LevelBadge(levelId: card.levelId, label: card.levelLabel),
                      ],
                      if (card.relationLabel != null) ...[
                        const SizedBox(height: 10),
                        Text(card.relationLabel!, key: const ValueKey('friend-relation'), style: const TextStyle(color: heroGold, fontWeight: FontWeight.w700)),
                      ],
                      if (p != null && !p.isMe && p.card.buttons.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [for (final a in p.card.buttons) FriendActionChip(button: a, busy: _busy, onDark: true, onTap: () => _run(a))],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TrophyShowcase(
                key: const ValueKey('friend-trophies'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, size: 20, color: heroGold),
                        const SizedBox(width: 6),
                        Text(
                          p == null || p.trophies.isEmpty ? 'Трофеї' : 'Трофеї · ${p.trophies.length}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: heroCream, shadows: [Shadow(color: Color(0xAA2B180A), blurRadius: 4)]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (p == null || p.trophies.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Трофеїв поки немає', style: TextStyle(color: heroCream, shadows: [Shadow(color: Color(0xAA2B180A), blurRadius: 4)])),
                      )
                    else
                      TrophyShelfRow(
                        onDark: true,
                        items: [for (final t in p.trophies) (id: t.id, title: t.title, earned: true, progressLabel: null, onTap: null)],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ParchmentTile(
                key: const ValueKey('friend-gifts'),
                icon: Icons.card_giftcard_rounded,
                title: 'Подарунки',
                subtitle: 'Подарунки від друзів — скоро',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
