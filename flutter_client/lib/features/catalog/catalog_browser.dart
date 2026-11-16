import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/catalog.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/catalog/catalog_offline.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';

/// Категорії довідника — як чіпи у веб-довіднику (landing.html).
enum CatalogCategory {
  all('Усі'),
  top20('Топ-20'),
  popular('Популярні'),
  poisonous('Отруйні'),
  red('Червона книга');

  const CatalogCategory(this.label);
  final String label;
}

/// Відбір видів: пошук за назвою / латиною, категорія, дерева, сезони.
List<CatalogSpecies> filterCatalog(
  List<CatalogSpecies> all, {
  String query = '',
  CatalogCategory category = CatalogCategory.all,
  Set<String> trees = const {},
  Set<String> seasons = const {},
  int? inSeasonMonth,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final s in all)
      if ((q.isEmpty || s.name.toLowerCase().contains(q) || s.latin.toLowerCase().contains(q)) &&
          switch (category) {
            CatalogCategory.all => true,
            CatalogCategory.top20 => s.top20,
            CatalogCategory.popular => s.popular,
            CatalogCategory.poisonous => s.poisonous,
            CatalogCategory.red => s.redListed,
          } &&
          (trees.isEmpty || s.tree.any(trees.contains)) &&
          (seasons.isEmpty || s.season.any(seasons.contains)) &&
          (inSeasonMonth == null || s.inSeason(inSeasonMonth)))
        s,
  ];
}

/// «Довідник грибів»: пошук, категорії, фільтри «Дерево» / «Сезон», сітка карток.
/// Картка відкриває сторінку виду `/catalog/<id>`.
class CatalogBrowser extends ConsumerStatefulWidget {
  const CatalogBrowser({super.key});

  @override
  ConsumerState<CatalogBrowser> createState() => _CatalogBrowserState();
}

class _CatalogBrowserState extends ConsumerState<CatalogBrowser> {
  final _search = TextEditingController();
  String _query = '';
  CatalogCategory _category = CatalogCategory.all;
  Set<String> _trees = {};
  Set<String> _seasons = {};
  bool _nowOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(String title, Map<String, String> options, Set<String> current, ValueChanged<Set<String>> onDone) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppTheme.backgroundColor,
      builder: (_) => _MultiPick(title: title, options: options, initial: current),
    );
    if (picked != null) setState(() => onDone(picked));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Не вдалося відкрити довідник')),
      data: (c) {
        final trees = {for (final s in c.species) ...s.tree};
        final seasons = {for (final s in c.species) ...s.season};
        final month = DateTime.now().month;
        final list = filterCatalog(c.species,
            query: _query, category: _category, trees: _trees, seasons: _seasons, inSeasonMonth: _nowOnly ? month : null);
        return CustomScrollView(
          key: const ValueKey('catalog-browser'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverList.list(children: [
                Text('Довідник грибів',
                    style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
                const SizedBox(height: 10),
                // Фото всіх грибів на телефон — щоб у лісі без зв'язку відкривався будь-який вид.
                const CatalogOfflineCard(),
                TextField(
                  key: const ValueKey('catalog-search'),
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Пошук гриба...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final cat in CatalogCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            key: ValueKey('catalog-cat-${cat.name}'),
                            label: Text(cat.label),
                            selected: _category == cat,
                            onSelected: (_) => setState(() => _category = cat),
                            selectedColor: AppTheme.darkGreen,
                            labelStyle: TextStyle(color: _category == cat ? Colors.white : AppTheme.darkGreen),
                            showCheckmark: false,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _FacetChip(
                      key: const ValueKey('catalog-facet-tree'),
                      icon: Icons.park_outlined,
                      label: 'Дерево',
                      count: _trees.length,
                      onTap: () => _pick('Дерево', {for (final t in trees) t: kTreeLabels[t] ?? t}, _trees, (v) => _trees = v),
                    ),
                    const SizedBox(width: 6),
                    _FacetChip(
                      key: const ValueKey('catalog-facet-season'),
                      icon: Icons.calendar_month_outlined,
                      label: 'Сезон',
                      count: _seasons.length,
                      onTap: () => _pick(
                          'Сезон',
                          {for (final k in kSeasonLabels.keys) if (seasons.contains(k)) k: kSeasonLabels[k]!},
                          _seasons,
                          (v) => _seasons = v),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const ValueKey('catalog-now'),
                      label: const Text('Зараз сезон'),
                      selected: _nowOnly,
                      onSelected: (v) => setState(() => _nowOnly = v),
                      selectedColor: const Color(0xffcfe8d2),
                      showCheckmark: false,
                      avatar: const Text('🍂'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${list.length} ${_species(list.length)}',
                          key: const ValueKey('catalog-count'),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(color: AppTheme.darkGreen.withValues(alpha: 0.7), fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ]),
            ),
            if (list.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Нічого не знайдено', style: TextStyle(color: AppTheme.darkGreen))),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid.builder(
                  itemCount: list.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.74,
                  ),
                  itemBuilder: (context, i) => CatalogCard(species: list[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _species(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'вид';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'види';
  return 'видів';
}

/// Картка виду в сітці: фото, назва, латина, значок їстівності.
class CatalogCard extends StatelessWidget {
  const CatalogCard({super.key, required this.species});

  final CatalogSpecies species;

  @override
  Widget build(BuildContext context) {
    final badge = edibilityBadge(species);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('catalog-card-${species.id}'),
        onTap: () => context.push('/catalog/${species.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CatalogPhoto(name: species.thumb, speciesId: species.id),
                  if (species.inSeason(DateTime.now().month))
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        key: ValueKey('season-now-${species.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xff2e7d32).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                        child: const Text('Сезон', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(species.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkGreen)),
                  Text(species.latin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.darkGreen.withValues(alpha: 0.65))),
                  const SizedBox(height: 6),
                  EdibilityBadge(label: badge.label, color: Color(badge.color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EdibilityBadge extends StatelessWidget {
  const EdibilityBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      );
}

class _FacetChip extends StatelessWidget {
  const _FacetChip({super.key, required this.icon, required this.label, required this.count, required this.onTap});

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 18, color: count > 0 ? Colors.white : AppTheme.darkGreen),
        label: Text(count > 0 ? '$label · $count' : label),
        labelStyle: TextStyle(color: count > 0 ? Colors.white : AppTheme.darkGreen),
        backgroundColor: count > 0 ? AppTheme.darkGreen : null,
        onPressed: onTap,
      );
}

/// Вибір кількох значень фільтра.
class _MultiPick extends StatefulWidget {
  const _MultiPick({required this.title, required this.options, required this.initial});

  final String title;
  final Map<String, String> options;
  final Set<String> initial;

  @override
  State<_MultiPick> createState() => _MultiPickState();
}

class _MultiPickState extends State<_MultiPick> {
  late final Set<String> _sel = {...widget.initial};

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in widget.options.entries)
                    FilterChip(
                      key: ValueKey('catalog-opt-${e.key}'),
                      label: Text(e.value),
                      selected: _sel.contains(e.key),
                      onSelected: (v) => setState(() => v ? _sel.add(e.key) : _sel.remove(e.key)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, <String>{}), child: const Text('Скинути')),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('catalog-opt-apply'),
                    onPressed: () => Navigator.pop(context, _sel),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen),
                    child: const Text('Показати'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
