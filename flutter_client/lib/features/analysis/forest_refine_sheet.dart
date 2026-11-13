import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';

/// Що обрав користувач: нове уточнення або «Скинути до карти» (`override == null`).
typedef ForestRefineChoice = ({ForestOverride? override});

/// Аркуш «Уточнити ліс» (ADR-015 §15.6): для кожного лісу ділянки — 1–2 породи зі списку
/// сервера, плюс породи, яких карта не бачить. Лише вибір зі списку, без площ і тексту.
/// `null` — користувач закрив аркуш.
Future<ForestRefineChoice?> showForestRefineSheet(
  BuildContext context, {
  required AnalysisResult result,
  required ForestEditOptions options,
  required ForestOverride? current,
  required String? usageLabel,
}) =>
    showModalBottomSheet<ForestRefineChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (context) => ForestRefineSheet(result: result, options: options, current: current, usageLabel: usageLabel),
    );

class ForestRefineSheet extends StatefulWidget {
  const ForestRefineSheet({
    super.key,
    required this.result,
    required this.options,
    required this.current,
    required this.usageLabel,
  });

  final AnalysisResult result;
  final ForestEditOptions options;
  final ForestOverride? current;
  final String? usageLabel;

  @override
  State<ForestRefineSheet> createState() => _ForestRefineSheetState();
}

class _ForestRefineSheetState extends State<ForestRefineSheet> {
  static const _maxPerType = 2;

  late final Map<String?, List<String>> _types = {
    for (final t in widget.result.forestTypes) t.forestType: [...?widget.current?.types[t.forestType]],
  };
  late final Map<String, String> _extra = {...?widget.current?.extra};

  ForestOverride get _override => ForestOverride(types: _types, extra: _extra);

  String get _defaultPresence => widget.options.presence.isEmpty ? 'present' : widget.options.presence.last.code;

  void _toggleSpecies(String? forestType, String code) => setState(() {
        final list = _types[forestType]!;
        if (list.contains(code)) {
          list.remove(code);
        } else if (list.length < _maxPerType) {
          list.add(code);
        }
      });

  void _toggleExtra(String code) => setState(() {
        if (_extra.remove(code) == null) _extra[code] = _defaultPresence;
      });

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.darkGreen.withValues(alpha: 0.6);
    final species = widget.options.species;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            'Уточнити ліс ділянки',
            style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
          ),
          const SizedBox(height: 6),
          Text(
            'Оберіть 1–2 породи для кожного лісу — прогноз врахує гриби, що ростуть під ними. '
            'Уточнення діє лише для вашої ділянки.',
            style: TextStyle(color: muted),
          ),
          for (final t in widget.result.forestTypes) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: t.typeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(t.typeLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(t.areaLabel, style: TextStyle(color: muted)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in species)
                  FilterChip(
                    key: ValueKey('type-${t.forestType}-${s.code}'),
                    label: Text(s.label),
                    selected: _types[t.forestType]!.contains(s.code),
                    onSelected: _types[t.forestType]!.contains(s.code) || _types[t.forestType]!.length < _maxPerType
                        ? (_) => _toggleSpecies(t.forestType, s.code)
                        : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const Text('Ще є в ділянці', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Породи, яких не видно на карті.', style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in species)
                FilterChip(
                  key: ValueKey('extra-${s.code}'),
                  label: Text(s.label),
                  selected: _extra.containsKey(s.code),
                  onSelected: (_) => _toggleExtra(s.code),
                ),
            ],
          ),
          for (final e in _extra.entries) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(species.firstWhere((s) => s.code == e.key, orElse: () => (code: e.key, label: e.key)).label)),
                for (final p in widget.options.presence)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(p.label),
                      selected: e.value == p.code,
                      onSelected: (_) => setState(() => _extra[e.key] = p.code),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          if (widget.usageLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(widget.usageLabel!, style: TextStyle(color: muted, fontSize: 13)),
            ),
          FilledButton.icon(
            onPressed: _override.isEmpty ? null : () => Navigator.pop(context, (override: _override)),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Зберегти й переаналізувати'),
          ),
          if (widget.current != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, (override: null)),
              child: const Text('Скинути до карти'),
            ),
          ],
        ],
      ),
    );
  }
}
