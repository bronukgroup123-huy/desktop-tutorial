import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart' show SpeciesIcon;
import 'package:flutter_client/features/catalog/catalog_offline.dart';
import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_client/features/recognize/ai_model.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart' show trailsSyncProvider;
import 'package:flutter_client/features/safety/safety_content.dart';

const kSosRed = AppTheme.danger;

/// Довідковий екран (ADR-022 §22.3 п.9, 10, 14): тексти з сервера, кроки нумеровані.
class SafetyGuideScreen extends StatelessWidget {
  const SafetyGuideScreen({super.key, required this.guide});

  final SafetyGuide guide;

  @override
  Widget build(BuildContext context) {
    final dim = AppTheme.textMuted;
    return Scaffold(
      appBar: AppBar(title: Text(guide.title, style: TextStyle(fontFamily: AppTheme.serif, color: AppTheme.darkGreen, fontSize: 18))),
      body: ListView(
        key: ValueKey('guide-${guide.id}'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (guide.subtitle.isNotEmpty) Text(guide.subtitle, style: TextStyle(color: dim, fontSize: 14)),
          for (final s in guide.sections) ...[
            if (s.title != null) ...[
              const SizedBox(height: 18),
              Text(s.title!, style: AppTheme.sectionTitle),
            ],
            const SizedBox(height: 8),
            for (final (i, item) in s.items.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppTheme.darkGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkGreen)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item, style: const TextStyle(fontSize: 15, height: 1.35, color: AppTheme.darkGreen))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Банер ДСНС та інші оголошення безпеки (ADR-003): текст і посилання — із сервера.
class SafetyNoticeBanner extends StatelessWidget {
  const SafetyNoticeBanner({super.key, required this.notice});

  final SafetyNotice notice;

  @override
  Widget build(BuildContext context) {
    final color = switch (notice.severity) {
      'warning' => AppTheme.warning,
      'info' => const Color(0xff1e6091),
      _ => kSosRed,
    };
    // Текст на підфарбованому тлі банера — темніший відтінок, щоб контраст лишався ≥ 4,5 (UI-004).
    final ink = color == kSosRed ? AppTheme.errorRed : color;
    return Container(
      key: ValueKey('notice-${notice.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(child: Text(notice.title, style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 15))),
            ],
          ),
          const SizedBox(height: 4),
          Text(notice.body, style: TextStyle(color: AppTheme.darkGreen, fontSize: 14, height: 1.3)),
          if (notice.linkUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(notice.linkUrl!), mode: LaunchMode.externalApplication),
                style: TextButton.styleFrom(foregroundColor: ink, padding: EdgeInsets.zero),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(notice.linkLabel ?? notice.linkUrl!),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// «Повітряна тривога в області» (ADR-022 §22.5 п.5) — для області застосунку; поради для лісу.
class AirAlertBanner extends ConsumerWidget {
  const AirAlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = ref.watch(homeRegionSlugProvider);
    final async = ref.watch(airAlertsProvider);
    // Поки перший раз вантажимо — тримаємо місце рядка, щоб вкладка не «стрибала».
    final state = async.valueOrNull;
    if (slug == null) return const SizedBox.shrink();
    if (state == null) return const _AirStatusRow(key: ValueKey('air-alert-loading'), text: 'Перевіряємо повітряну тривогу…', icon: Icons.sync_rounded);
    if (!state.available) {
      return const _AirStatusRow(
        key: ValueKey('air-alert-unknown'),
        text: 'Повітряна тривога: дані зараз недоступні',
        icon: Icons.cloud_off_rounded,
        muted: true,
      );
    }
    final alert = state.alerts.where((a) => a.slug == slug).firstOrNull;
    final at = state.updatedAt;
    final hm = at == null ? null : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final stamp = state.offline ? ' · немає зв\'язку${hm == null ? '' : ', дані на $hm'}' : (hm == null ? '' : ' · оновлено $hm');
    if (alert == null) {
      // Тривоги немає — спокійний рядок: видно, що перевірка працює і для якої області.
      final region = ref.watch(homeRegionNameProvider) ?? 'Ваша область';
      return _AirStatusRow(
        key: const ValueKey('air-alert-clear'),
        text: '$region: повітряної тривоги немає$stamp',
        icon: state.offline ? Icons.cloud_off_rounded : Icons.verified_user_rounded,
        muted: state.offline,
      );
    }
    final content = ref.watch(safetyContentProvider).valueOrNull;
    return Container(
      key: const ValueKey('air-alert'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: const Color(0xffb71c1c), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(alert.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
            ],
          ),
          if (state.offline)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 32),
              child: Text(stamp.replaceFirst(' · ', ''),
                  key: const ValueKey('air-alert-offline'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          for (final t in content?.airAlertTips ?? const <String>[])
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 32),
              child: Text('• $t', style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3)),
            ),
        ],
      ),
    );
  }
}

class _AirStatusRow extends StatelessWidget {
  const _AirStatusRow({super.key, required this.text, required this.icon, this.muted = false});

  final String text;
  final IconData icon;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: muted ? AppTheme.textMuted : AppTheme.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            ),
          ],
        ),
      );
}

/// Небезпечна погода сьогодні на ділянці (ADR-022 §22.3 п.12): гроза з годинами, спека, мороз —
/// з останнього прогнозу ділянки. Немає ділянки чи прогнозу на сьогодні — не показується.
class WeatherHazardsCard extends ConsumerWidget {
  const WeatherHazardsCard({super.key});

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(analysisOverviewProvider).valueOrNull;
    final selected = ref.watch(selectedAreaIdProvider);
    final areas = overview?.areas ?? const <AnalysisArea>[];
    final area = areas.where((a) => a.id == selected).firstOrNull ?? areas.where((a) => a.lastResult != null).firstOrNull;
    final today = _today();
    final day = area?.lastResult?.days.where((d) => d.date == today).firstOrNull;
    final hazards = day?.weather?.hazards ?? const <String>[];
    if (area == null || hazards.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('weather-hazards'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xfffff4e5),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Небезпечна погода сьогодні · ${area.title}',
              style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w800)),
          for (final h in hazards)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    h.startsWith('Гроза') ? Icons.thunderstorm_rounded : h.startsWith('Спека') ? Icons.wb_sunny_rounded : Icons.ac_unit_rounded,
                    size: 18,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(h, style: const TextStyle(fontSize: 14, color: AppTheme.darkGreen, height: 1.3))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Небезпечні гриби (ADR-022 §22.3 п.5) — смертельно отруйні з довідника (тексти книги) і
/// «Ще N отруйних». Дотик — стаття довідника.
class DangerousMushrooms extends ConsumerWidget {
  const DangerousMushrooms({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    if (catalog == null) return const SizedBox.shrink();
    final deadly = catalog.species.where((s) => s.edibility == 'deadly_poisonous').toList();
    final poisonous = catalog.species.where((s) => s.edibility == 'poisonous').toList();
    final list = [...deadly, ...poisonous];
    if (list.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      key: const ValueKey('dangerous-mushrooms'),
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final s = list[i];
          final deadlyOne = s.edibility == 'deadly_poisonous';
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('danger-${s.id}'),
              onTap: () => context.push('/catalog/${s.id}'),
              child: SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 96,
                      width: 130,
                      child: s.thumb == null
                          ? Center(child: SpeciesIcon(type: s.id, fallbackColor: kSosRed, size: 56))
                          : CatalogPhoto(name: s.thumb, speciesId: s.id),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Text(s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.darkGreen)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                      child: Text(deadlyOne ? 'Смертельно отруйний' : 'Отруйний',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: deadlyOne ? kSosRed : AppTheme.warning)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Чек-лист перед походом (ADR-022 §22.3 п.7) ────────────────────────────

/// Позначки чек-листа — на сьогодні (наступного дня — заново), лише на телефоні.
class ChecklistNotifier extends AsyncNotifier<Set<String>> {
  static const key = 'safety_checklist';

  static String today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  @override
  Future<Set<String>> build() async {
    try {
      final e = await ref.read(localStoreProvider).read(key);
      final m = e?.data as Map?;
      if (m != null && m['date'] == today()) return {for (final x in (m['done'] as List? ?? const [])) x as String};
    } catch (_) {}
    return {};
  }

  Future<void> toggle(String id) async {
    final next = {...state.valueOrNull ?? <String>{}};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = AsyncData(next);
    try {
      await ref.read(localStoreProvider).write(key, {'date': today(), 'done': next.toList()});
    } catch (_) {}
  }
}

final checklistProvider = AsyncNotifierProvider<ChecklistNotifier, Set<String>>(ChecklistNotifier.new);

/// Готовність до лісу без інтернету: офлайн карта області, фото довідника, ШІ-розпізнавач.
typedef ReadinessItem = ({String id, String label, bool ready, String action, String route});

final offlineReadinessProvider = Provider<List<ReadinessItem>>((ref) {
  final slug = ref.watch(homeRegionSlugProvider);
  final map = slug == null ? null : ref.watch(localBasemapProvider(slug)).valueOrNull;
  final photos = ref.watch(catalogOfflineProvider);
  final ai = ref.watch(aiModelProvider);
  final trails = slug != null && map != null && (ref.watch(trailsSyncProvider(slug)).valueOrNull ?? false);
  return [
    (id: 'map', label: 'Офлайн карта області', ready: map != null, action: 'Завантажити', route: '/map'),
    // Мережа стежок — разом з офлайн-картою (ADR-022 §22.7): маршрут «Додому» без інтернету.
    (id: 'trails', label: 'Стежки для маршруту «Додому»', ready: trails, action: 'Завантажити', route: '/map'),
    (id: 'photos', label: 'Фото довідника', ready: photos.complete, action: 'Завантажити', route: '/recognize'),
    (id: 'ai', label: 'ШІ-розпізнавання', ready: ai.ready, action: 'Завантажити', route: '/recognize'),
  ];
});

class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(safetyContentProvider).valueOrNull;
    final done = ref.watch(checklistProvider).valueOrNull ?? const <String>{};
    final readiness = ref.watch(offlineReadinessProvider);
    final items = content?.checklist ?? const <({String id, String label})>[];
    return Scaffold(
      appBar: AppBar(title: Text('Перед походом', style: TextStyle(fontFamily: AppTheme.serif, color: AppTheme.darkGreen, fontSize: 18))),
      body: ListView(
        key: const ValueKey('checklist'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('${done.where((d) => items.any((i) => i.id == d)).length} з ${items.length}',
              key: const ValueKey('checklist-progress'),
              style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          for (final i in items)
            Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: CheckboxListTile(
                key: ValueKey('check-${i.id}'),
                value: done.contains(i.id),
                onChanged: (_) => ref.read(checklistProvider.notifier).toggle(i.id),
                title: Text(i.label, style: const TextStyle(color: AppTheme.darkGreen)),
                activeColor: AppTheme.darkGreen,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          const SizedBox(height: 14),
          Text('Готові до лісу без інтернету?',
              style: AppTheme.sectionTitle),
          const SizedBox(height: 6),
          for (final r in readiness)
            ListTile(
              key: ValueKey('ready-${r.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.ready ? Icons.check_circle_rounded : Icons.cloud_download_outlined,
                  color: r.ready ? AppTheme.success : AppTheme.warning),
              title: Text(r.label, style: const TextStyle(color: AppTheme.darkGreen)),
              subtitle: Text(r.ready ? 'Є на телефоні' : 'Не завантажено — у лісі може не бути зв\'язку'),
              trailing: r.ready ? null : TextButton(onPressed: () => context.go(r.route), child: Text(r.action)),
            ),
        ],
      ),
    );
  }
}

// ─── Картка для рятувальників (ADR-022 §22.3 п.16) ─────────────────────────

/// Лише на телефоні (не надсилається на сервер), показується на екрані SOS.
class RescueCard {
  const RescueCard({this.name = '', this.bloodType = '', this.allergies = '', this.conditions = '', this.contact = ''});

  factory RescueCard.fromJson(Map<String, dynamic> j) => RescueCard(
        name: (j['name'] as String?) ?? '',
        bloodType: (j['blood_type'] as String?) ?? '',
        allergies: (j['allergies'] as String?) ?? '',
        conditions: (j['conditions'] as String?) ?? '',
        contact: (j['contact'] as String?) ?? '',
      );

  final String name;
  final String bloodType;
  final String allergies;

  /// Хвороби й ліки.
  final String conditions;

  /// Кому з рідних дзвонити: «Мама, 067…».
  final String contact;

  bool get isEmpty => [name, bloodType, allergies, conditions, contact].every((x) => x.trim().isEmpty);

  Map<String, dynamic> toJson() =>
      {'name': name, 'blood_type': bloodType, 'allergies': allergies, 'conditions': conditions, 'contact': contact};

  /// Рядки «Підпис: значення» лише для заповненого.
  List<(String, String)> get rows => [
        if (name.trim().isNotEmpty) ('Ім\'я', name.trim()),
        if (bloodType.trim().isNotEmpty) ('Група крові', bloodType.trim()),
        if (allergies.trim().isNotEmpty) ('Алергії', allergies.trim()),
        if (conditions.trim().isNotEmpty) ('Хвороби, ліки', conditions.trim()),
        if (contact.trim().isNotEmpty) ('Рідні', contact.trim()),
      ];
}

class RescueCardNotifier extends AsyncNotifier<RescueCard> {
  static const key = 'rescue_card';

  @override
  Future<RescueCard> build() async {
    try {
      final e = await ref.read(localStoreProvider).read(key);
      if (e?.data is Map) return RescueCard.fromJson((e!.data as Map).cast<String, dynamic>());
    } catch (_) {}
    return const RescueCard();
  }

  Future<void> save(RescueCard card) async {
    state = AsyncData(card);
    try {
      await ref.read(localStoreProvider).write(key, card.toJson());
    } catch (_) {}
  }
}

final rescueCardProvider = AsyncNotifierProvider<RescueCardNotifier, RescueCard>(RescueCardNotifier.new);

const kBloodTypes = ['0(I) Rh+', '0(I) Rh−', 'A(II) Rh+', 'A(II) Rh−', 'B(III) Rh+', 'B(III) Rh−', 'AB(IV) Rh+', 'AB(IV) Rh−'];

class RescueCardScreen extends ConsumerStatefulWidget {
  const RescueCardScreen({super.key});

  @override
  ConsumerState<RescueCardScreen> createState() => _RescueCardScreenState();
}

class _RescueCardScreenState extends ConsumerState<RescueCardScreen> {
  final _name = TextEditingController();
  final _allergies = TextEditingController();
  final _conditions = TextEditingController();
  final _contact = TextEditingController();
  String _blood = '';
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [_name, _allergies, _conditions, _contact]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(rescueCardProvider).valueOrNull;
    if (card == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_loaded) {
      _loaded = true;
      _name.text = card.name;
      _allergies.text = card.allergies;
      _conditions.text = card.conditions;
      _contact.text = card.contact;
      _blood = card.bloodType;
    }
    InputDecoration deco(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        );
    return Scaffold(
      appBar: AppBar(title: Text('Картка для рятувальників', style: TextStyle(fontFamily: AppTheme.serif, color: AppTheme.darkGreen, fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('Необов\'язково. Зберігається лише на цьому телефоні й показується на екрані SOS — щоб рятувальники й лікарі знали головне.',
              style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('rc-name'), controller: _name, decoration: deco('Ім\'я')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey('rc-blood'),
            initialValue: _blood.isEmpty ? null : _blood,
            decoration: deco('Група крові'),
            items: [for (final b in kBloodTypes) DropdownMenuItem(value: b, child: Text(b))],
            onChanged: (v) => setState(() => _blood = v ?? ''),
          ),
          const SizedBox(height: 10),
          TextField(key: const ValueKey('rc-allergies'), controller: _allergies, decoration: deco('Алергії', 'напр. пеніцилін, укуси бджіл')),
          const SizedBox(height: 10),
          TextField(
              key: const ValueKey('rc-conditions'),
              controller: _conditions,
              decoration: deco('Хвороби й ліки', 'напр. діабет, інсулін'),
              maxLines: 2),
          const SizedBox(height: 10),
          TextField(
              key: const ValueKey('rc-contact'),
              controller: _contact,
              decoration: deco('Кому з рідних дзвонити', 'напр. Мама, 067 123 45 67'),
              keyboardType: TextInputType.text),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('rc-save'),
            onPressed: () async {
              await ref.read(rescueCardProvider.notifier).save(RescueCard(
                    name: _name.text,
                    bloodType: _blood,
                    allergies: _allergies.text,
                    conditions: _conditions.text,
                    contact: _contact.text,
                  ));
              if (context.mounted) Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.darkGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );
  }
}

/// Картка на екрані SOS (білий текст на червоному); порожня — нічого.
class RescueCardView extends ConsumerWidget {
  const RescueCardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(rescueCardProvider).valueOrNull;
    if (card == null || card.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('rescue-card-view'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.medical_information_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Для рятувальників', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 6),
          for (final (label, value) in card.rows)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$label: ', style: const TextStyle(color: Colors.white70)),
                TextSpan(text: value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ])),
            ),
        ],
      ),
    );
  }
}
