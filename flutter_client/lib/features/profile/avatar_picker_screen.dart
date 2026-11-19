import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/core/toast.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/profile/custom_avatar.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';

/// Каталог деталей конструктора з замками — з сервера.
final avatarCatalogProvider = FutureProvider.autoDispose<AvatarCatalog>((ref) => ref.watch(meRepositoryProvider).avatarCatalog());

/// Аватар (ADR-021 §21.7): грибна наліпка — персонаж (безкоштовні, за рівень, у Pro) і деталі
/// поверх (капелюх, річ, ефект; ще й за «спори» та сезонні). Статичний.
class AvatarPickerScreen extends StatelessWidget {
  const AvatarPickerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Аватар', style: GoogleFonts.merriweather(color: AppTheme.darkGreen))),
        body: const AvatarBuilder(),
      );
}

/// Конструктор: попередній перегляд, категорії, деталі (кожна — мініатюра аватара з нею).
class AvatarBuilder extends ConsumerStatefulWidget {
  const AvatarBuilder({super.key});

  @override
  ConsumerState<AvatarBuilder> createState() => _AvatarBuilderState();
}

class _AvatarBuilderState extends ConsumerState<AvatarBuilder> {
  Map<String, String?> _draft = kDefaultAvatarParts;
  bool _seeded = false;
  String _category = 'sticker';
  bool _saving = false;

  /// Почати з поточного аватара (профіль міг довантажитися вже після відкриття екрана).
  void _seed() {
    if (_seeded) return;
    final a = ref.watch(meProvider).valueOrNull?.avatar;
    if (a == null) return;
    _seeded = true;
    if (a.isCustom) _draft = {...kDefaultAvatarParts, ...a.parts};
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(meProvider.notifier).setCustomAvatar(_draft);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage, isError: true);
    } catch (_) {
      if (mounted) showToast(context, 'Не вдалося зберегти аватар. Перевірте інтернет.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _seed();
    final catalog = ref.watch(avatarCatalogProvider);
    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Не вдалося завантажити деталі. Перевірте інтернет.'),
          TextButton(onPressed: () => ref.invalidate(avatarCatalogProvider), child: const Text('Спробувати ще')),
        ]),
      ),
      data: (cat) {
        final current = cat.categories.firstWhere((c) => c.id == _category, orElse: () => cat.categories.first);
        return Column(
          children: [
            const SizedBox(height: 12),
            UserAvatar(key: const ValueKey('builder-preview'), avatar: Avatar(kind: 'custom', parts: _draft), size: 150),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in cat.categories)
                    ChoiceChip(
                      key: ValueKey('cat-${c.id}'),
                      label: Text(c.label),
                      selected: c.id == current.id,
                      onSelected: (_) => setState(() => _category = c.id),
                    ),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                key: const ValueKey('builder-parts'),
                crossAxisCount: current.id == 'sticker' ? 4 : 3,
                padding: const EdgeInsets.all(12),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: current.id == 'sticker' ? 0.72 : 0.78,
                children: [
                  if (current.optional)
                    _PartTile(
                      key: ValueKey('part-${current.id}-none'),
                      label: 'Без нічого',
                      parts: {..._draft, current.id: null},
                      selected: _draft[current.id] == null,
                      onTap: () => setState(() => _draft = {..._draft, current.id: null}),
                    ),
                  for (final p in current.parts)
                    _PartTile(
                      key: ValueKey('part-${current.id}-${p.id}'),
                      label: p.label,
                      parts: {..._draft, current.id: p.id},
                      selected: _draft[current.id] == p.id,
                      lockLabel: p.open || _draft[current.id] == p.id ? null : p.lockLabel,
                      badge: p.badge,
                      onTap: p.open || _draft[current.id] == p.id
                          ? () => setState(() => _draft = {..._draft, current.id: p.id})
                          : () => showToast(context, '«${p.label}» — ${p.lockLabel ?? 'поки закрито'}'),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('builder-save'),
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(_saving ? 'Зберігаємо…' : 'Зберегти аватар'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({super.key, required this.label, required this.parts, required this.selected, required this.onTap, this.lockLabel, this.badge});

  final String label;
  final Map<String, String?> parts;
  final bool selected;
  final VoidCallback onTap;
  final String? lockLabel;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final locked = lockLabel != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? const Color(0xffd97706) : Colors.transparent, width: 2.5),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(opacity: locked ? 0.35 : 1, child: UserAvatar(avatar: Avatar(kind: 'custom', parts: parts), size: 70)),
                  if (locked) const Icon(Icons.lock_rounded, color: AppTheme.darkGreen, size: 26),
                ],
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
            ),
            Text(
              lockLabel ?? badge ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: locked ? const Color(0xffb45309) : AppTheme.darkGreen.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
