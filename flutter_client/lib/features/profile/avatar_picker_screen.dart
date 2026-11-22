import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/avatars.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';

/// Вибір готового аватара (ADR-021 §21.7, PO 2026-11-21): групи за рівнями, рамка показує
/// рівень. Що відкрито й чому закрито — із сервера (`GET v1-me?avatars=1`); закритий не
/// вибирається — дотик показує, на якому рівні відкриється.
class AvatarPickerScreen extends ConsumerStatefulWidget {
  const AvatarPickerScreen({super.key});

  @override
  ConsumerState<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends ConsumerState<AvatarPickerScreen> {
  String? _picked;
  bool _saving = false;

  Future<void> _save(AvatarChoices c) async {
    final id = _picked;
    if (id == null || id == c.current.id) return;
    setState(() => _saving = true);
    try {
      await ref.read(meProvider.notifier).setAvatar(id);
      ref.invalidate(avatarChoicesProvider);
      if (!mounted) return;
      showToast(context, 'Аватар змінено');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося зберегти. Перевірте інтернет і спробуйте ще раз.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(avatarChoicesProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Аватар', style: GoogleFonts.merriweather(color: AppTheme.darkGreen)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is ApiException ? e.userMessage : 'Не вдалося завантажити аватари', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => ref.invalidate(avatarChoicesProvider), child: const Text('Повторити')),
              ],
            ),
          ),
        ),
        data: (c) => _body(c),
      ),
    );
  }

  Widget _body(AvatarChoices c) {
    final selectedId = _picked ?? c.current.id;
    AvatarChoice? selected;
    for (final g in c.groups) {
      for (final a in g.avatars) {
        if (a.id == selectedId) selected = a;
      }
    }
    final changed = _picked != null && _picked != c.current.id;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            key: const ValueKey('avatar-list'),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    children: [
                      UserAvatar(key: const ValueKey('avatar-preview'), avatar: Avatar(id: selectedId), size: 168),
                      const SizedBox(height: 8),
                      if (selected != null) ...[
                        Text(selected.title, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                        Text(selected.role, style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.7))),
                      ],
                      if (!c.canChange && c.reasonLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(c.reasonLabel!, key: const ValueKey('avatar-reason'), textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.accentOrange, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              ),
              for (final g in c.groups) ...[
                SliverToBoxAdapter(child: _GroupHeader(group: g)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisSpacing: 6, crossAxisSpacing: 6),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final a = g.avatars[i];
                        return _Tile(
                          avatar: a,
                          selected: a.id == selectedId,
                          onTap: () {
                            if (!a.open) {
                              showToast(context, g.lockLabel ?? 'Цей аватар відкривається на вищому рівні');
                            } else if (c.canChange) {
                              setState(() => _picked = a.id);
                            } else if (c.reasonLabel != null) {
                              showToast(context, c.reasonLabel!);
                            }
                          },
                        );
                      },
                      childCount: g.avatars.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        if (c.canChange)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('avatar-save'),
                  onPressed: changed && !_saving ? () => _save(c) : null,
                  child: Text(_saving ? 'Зберігаємо…' : 'Зберегти'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final AvatarGroup group;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        // Назва рівня, під нею — коли відкриється; з великим шрифтом обидва переносяться (UI-001).
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(group.open ? Icons.eco_rounded : Icons.lock_rounded, size: 18, color: group.open ? AppTheme.darkGreen : Colors.black45),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.label, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                  if (group.lockLabel != null)
                    Text(group.lockLabel!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.avatar, required this.selected, required this.onTap});

  final AvatarChoice avatar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${avatar.title}, ${avatar.role}${avatar.open ? '' : ', закрито'}',
        child: InkWell(
          key: ValueKey('avatar-${avatar.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected ? AppTheme.darkGreen.withValues(alpha: 0.12) : null,
              border: Border.all(color: selected ? AppTheme.darkGreen : Colors.transparent, width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(opacity: avatar.open ? 1 : 0.35, child: UserAvatar(avatar: Avatar(id: avatar.id), size: 84)),
                if (!avatar.open)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.lock_rounded, size: 16, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      );
}
