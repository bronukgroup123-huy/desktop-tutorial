import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/providers.dart';

/// Вибір користувача в списку видів: вид із довідника або «Не знаю, що це».
class SpeciesChoice {
  const SpeciesChoice.known(PickSpecies this.species) : label = null;
  const SpeciesChoice.unknown(String this.label) : species = null;

  /// `null` — «Не знаю, що це».
  final PickSpecies? species;
  final String? label;

  String get title => species?.nameLabel ?? label ?? '';
}

/// Список видів із пошуком (ADR-018 §18.3: назва — тільки з довідника).
Future<SpeciesChoice?> showSpeciesPicker(BuildContext context) => showModalBottomSheet<SpeciesChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => _SpeciesPicker(scrollController: controller),
      ),
    );

class _SpeciesPicker extends ConsumerStatefulWidget {
  const _SpeciesPicker({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_SpeciesPicker> createState() => _SpeciesPickerState();
}

class _SpeciesPickerState extends ConsumerState<_SpeciesPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(pickSpeciesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Пошук виду',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e is ApiException ? e.userMessage : 'Не вдалося завантажити список видів.'),
                  TextButton(
                    onPressed: () => ref.invalidate(pickSpeciesProvider),
                    child: const Text('Повторити'),
                  ),
                ],
              ),
            ),
            data: (data) {
              final found = data.species.where((s) => s.matches(_query)).toList(growable: false);
              return ListView.builder(
                controller: widget.scrollController,
                itemCount: found.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return ListTile(
                      leading: const Icon(Icons.help_outline_rounded, color: AppTheme.accentOrange),
                      title: Text(data.unknownLabel),
                      onTap: () => Navigator.of(context).pop(SpeciesChoice.unknown(data.unknownLabel)),
                    );
                  }
                  final s = found[i - 1];
                  return ListTile(
                    title: Text(s.nameLabel),
                    subtitle: s.latinLabel == null
                        ? null
                        : Text(s.latinLabel!, style: const TextStyle(fontStyle: FontStyle.italic)),
                    onTap: () => Navigator.of(context).pop(SpeciesChoice.known(s)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
