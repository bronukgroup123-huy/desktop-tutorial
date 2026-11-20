import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/guardian.dart';
import 'package:flutter_client/features/profile/user_avatar.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';

/// Вибір перед «Почати похід» (ADR-022 §22.3 п.2): час повернення (чипи «+2 год», «+4 год»,
/// «до заходу сонця») і Наглядач із друзів, що погодились. `null` — скасовано;
/// `guardianIds` порожній — похід без Наглядача (лише на телефоні).
typedef GuardianStartChoice = ({DateTime expectedReturn, List<String> guardianIds});

Future<GuardianStartChoice?> showGuardianStartSheet(BuildContext context, GuardianOverview data, {DateTime? sunset}) =>
    showModalBottomSheet<GuardianStartChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Sheet(data: data, sunset: sunset),
    );

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.data, this.sunset});

  final GuardianOverview data;
  final DateTime? sunset;

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  late final List<(String, DateTime)> _options;
  int _option = 0;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    final now = HikeController.now();
    _options = [
      ('+2 год', now.add(const Duration(hours: 2))),
      ('+4 год', now.add(const Duration(hours: 4))),
      if (widget.sunset != null && widget.sunset!.isAfter(now.add(const Duration(minutes: 30))))
        ('до заходу сонця', widget.sunset!),
    ];
    final g = widget.data.acceptedGuardians;
    if (g.isNotEmpty) _picked.add(g.first.id);
  }

  String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final guardians = widget.data.acceptedGuardians;
    final max = widget.data.maxPerHike;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const ValueKey('guardian-start-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Йду в ліс', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
            const SizedBox(height: 12),
            const Text('Коли повернетесь?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final (i, (label, t)) in _options.indexed)
                  ChoiceChip(
                    key: ValueKey('return-$i'),
                    label: Text('$label · ${_hm(t)}'),
                    selected: _option == i,
                    onSelected: (_) => setState(() => _option = i),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('У цей час спитаємо «Все добре?». Не відповісте 15 хв — сповістимо Наглядача.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black.withValues(alpha: 0.6))),
            ),
            const SizedBox(height: 14),
            Text(max > 1 ? 'Наглядачі (до $max)' : 'Наглядач', style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final g in guardians)
              CheckboxListTile(
                key: ValueKey('start-guardian-${g.id}'),
                contentPadding: EdgeInsets.zero,
                value: _picked.contains(g.id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    if (max == 1) _picked.clear();
                    if (_picked.length < max) _picked.add(g.id);
                  } else {
                    _picked.remove(g.id);
                  }
                }),
                secondary: UserAvatar(avatar: g.avatar, size: 36),
                title: Text('@${g.handle}'),
              ),
            if (widget.data.limitLabel != null)
              Text(widget.data.limitLabel!, style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45))),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('start-with-guardian'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop((expectedReturn: _options[_option].$2, guardianIds: _picked.toList())),
                icon: const Icon(Icons.shield_moon_rounded),
                label: const Text('Почати з Наглядачем'),
              ),
            ),
            TextButton(
              key: const ValueKey('start-without-guardian'),
              onPressed: () => Navigator.of(context).pop((expectedReturn: _options[_option].$2, guardianIds: const <String>[])),
              child: const Text('Без Наглядача (лише на телефоні)'),
            ),
          ],
        ),
      ),
    );
  }
}
