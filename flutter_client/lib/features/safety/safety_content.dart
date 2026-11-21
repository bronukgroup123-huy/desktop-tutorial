import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/data/providers.dart';

/// Банер на вкладці «Безпека» (ADR-003: мінна небезпека — статичний банер ДСНС).
class SafetyNotice {
  const SafetyNotice({required this.id, required this.title, required this.body, this.linkLabel, this.linkUrl, this.severity = 'danger'});

  factory SafetyNotice.fromJson(Map<String, dynamic> j) => SafetyNotice(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        linkLabel: j['link_label'] as String?,
        linkUrl: j['link_url'] as String?,
        severity: (j['severity'] as String?) ?? 'danger',
      );

  final String id;
  final String title;
  final String body;
  final String? linkLabel;
  final String? linkUrl;

  /// `danger | warning | info`
  final String severity;
}

/// Довідковий екран: «Заблукали?», «Отруєння: що робити», «Інші небезпеки».
class SafetyGuide {
  const SafetyGuide({required this.id, required this.title, required this.subtitle, required this.sections});

  factory SafetyGuide.fromJson(Map<String, dynamic> j) => SafetyGuide(
        id: j['id'] as String,
        title: j['title'] as String,
        subtitle: (j['subtitle'] as String?) ?? '',
        sections: [
          for (final s in (j['sections'] as List? ?? const []).cast<Map<String, dynamic>>())
            (title: s['title'] as String?, items: [for (final i in (s['items'] as List? ?? const [])) i as String]),
        ],
      );

  final String id;
  final String title;
  final String subtitle;
  final List<({String? title, List<String> items})> sections;
}

/// Тексти вкладки «Безпека» із сервера (`GET v1-app-config`, ADR-022 §22.3, B4.10).
class SafetyContent {
  const SafetyContent({
    required this.version,
    required this.notices,
    required this.guides,
    required this.checklist,
    required this.airAlertTitle,
    required this.airAlertTips,
  });

  factory SafetyContent.fromJson(Map<String, dynamic> j) {
    final air = (j['air_alert'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SafetyContent(
      version: (j['version'] as num?)?.toInt() ?? 0,
      notices: [for (final n in (j['notices'] as List? ?? const []).cast<Map<String, dynamic>>()) SafetyNotice.fromJson(n)],
      guides: [for (final g in (j['guides'] as List? ?? const []).cast<Map<String, dynamic>>()) SafetyGuide.fromJson(g)],
      checklist: [
        for (final c in (j['checklist'] as List? ?? const []).cast<Map<String, dynamic>>())
          (id: c['id'] as String, label: c['label'] as String),
      ],
      airAlertTitle: (air['title'] as String?) ?? 'Повітряна тривога',
      airAlertTips: [for (final t in (air['tips'] as List? ?? const [])) t as String],
    );
  }

  final int version;
  final List<SafetyNotice> notices;
  final List<SafetyGuide> guides;
  final List<({String id, String label})> checklist;
  final String airAlertTitle;
  final List<String> airAlertTips;

  SafetyGuide? guide(String id) => guides.where((g) => g.id == id).firstOrNull;
}

/// Вбудовані тексти (ті самі, що типові на сервері — тест бекенду звіряє): у лісі без зв'язку
/// вкладка працює з першого запуску.
const kSafetyContentAsset = 'assets/safety/safety_content.json';

const _cacheKey = 'safety_content';

/// Тексти безпеки: одразу — збережена копія або вбудовані; далі тихо оновлюються з сервера.
class SafetyContentNotifier extends AsyncNotifier<SafetyContent> {
  @override
  Future<SafetyContent> build() async {
    SafetyContent? local;
    try {
      final cached = await ref.read(localStoreProvider).read(_cacheKey);
      if (cached?.data is Map) local = SafetyContent.fromJson((cached!.data as Map).cast<String, dynamic>());
    } catch (_) {
      // Немає сховища (тести) або зіпсований файл — вбудовані тексти.
    }
    local ??= SafetyContent.fromJson(jsonDecode(await rootBundle.loadString(kSafetyContentAsset)) as Map<String, dynamic>);
    unawaited(_refresh());
    return local;
  }

  Future<void> _refresh() async {
    try {
      final data = await ref.read(apiClientProvider).get('/v1-app-config') as Map<String, dynamic>;
      final safety = (data['safety'] as Map).cast<String, dynamic>();
      final fresh = SafetyContent.fromJson(safety);
      state = AsyncData(fresh);
      try {
        await ref.read(localStoreProvider).write(_cacheKey, safety);
      } catch (_) {}
    } catch (_) {
      // Без мережі — лишаються збережені / вбудовані тексти.
    }
  }
}

final safetyContentProvider = AsyncNotifierProvider<SafetyContentNotifier, SafetyContent>(SafetyContentNotifier.new);

/// Область застосунку (Home Region) — гість теж її має (ADR-001).
final homeRegionSlugProvider = Provider<String?>((ref) => ref.watch(meProvider.select((m) => m.valueOrNull?.homeRegion?.slug)));

/// Назва області застосунку («Житомирська область»).
final homeRegionNameProvider = Provider<String?>((ref) => ref.watch(meProvider.select((m) => m.valueOrNull?.homeRegion?.name)));

/// Повітряна тривога в області застосунку (ADR-022 §22.5 п.5): `scope` — `oblast` (уся) або `part`.
typedef AirAlert = ({String slug, String scope, String title});

/// Стан тривог: [available] — є дані (сервер має ключ і зв'язок із alerts.in.ua, або є збережені
/// на телефоні); [updatedAt] — коли дані оновлено на сервері; [alerts] — тривоги (лише область
/// застосунку); [offline] — свіжих даних зараз немає (немає інтернету), показано останні збережені.
typedef AirAlertState = ({bool available, DateTime? updatedAt, List<AirAlert> alerts, bool offline});

const kNoAirAlertData = (available: false, updatedAt: null, alerts: <AirAlert>[], offline: false);

/// Як часто оновлювати тривоги, поки вкладка «Безпека» відкрита.
Duration airAlertsRefresh = const Duration(minutes: 1);

String _airKey(String? slug) => 'air_alerts_${slug ?? 'all'}';

Map<String, dynamic> _airJson(AirAlertState s) => {
      'updated_at': s.updatedAt?.toUtc().toIso8601String(),
      'regions': [for (final a in s.alerts) {'slug': a.slug, 'scope': a.scope, 'title': a.title}],
    };

AirAlertState _airFrom(Map<String, dynamic> data, {bool offline = false}) => (
      available: true,
      updatedAt: DateTime.tryParse((data['updated_at'] as String?) ?? '')?.toLocal(),
      alerts: [
        for (final r in (data['regions'] as List? ?? const []).cast<Map<String, dynamic>>())
          (slug: r['slug'] as String, scope: (r['scope'] as String?) ?? 'oblast', title: r['title'] as String),
      ],
      offline: offline,
    );

/// Тривоги з `GET v1-air-alerts` (оновлення раз на хвилину, поки банер на екрані).
///
/// Банер не зникає й не «блимає»: стан живе, поки застосунок відкритий (прокрутка вкладки
/// чи перехід на іншу не скидає його), останні дані зберігаються на телефоні й показуються одразу
/// після запуску та без інтернету — з позначкою «немає зв'язку · дані на HH:MM».
final airAlertsProvider = StreamProvider.autoDispose<AirAlertState>((ref) {
  ref.keepAlive();
  final api = ref.watch(apiClientProvider);
  final store = ref.watch(localStoreProvider);
  // Сервер бере один список на всю Україну й віддає лише область застосунку.
  final slug = ref.watch(homeRegionSlugProvider);
  final controller = StreamController<AirAlertState>();
  AirAlertState? last;

  void emit(AirAlertState s) {
    last = s;
    if (!controller.isClosed) controller.add(s);
  }

  Future<void> load() async {
    try {
      final data = await api.get('/v1-air-alerts', query: slug == null ? null : {'region': slug}) as Map<String, dynamic>;
      if (data['available'] != true) {
        // Сервер без ключа чи без зв'язку з alerts.in.ua: якщо є збережене — лишаємо його з позначкою.
        final l = last;
        emit(l != null && l.available ? (available: true, updatedAt: l.updatedAt, alerts: l.alerts, offline: true) : kNoAirAlertData);
        return;
      }
      final s = _airFrom(data);
      emit(s);
      try {
        await store.write(_airKey(slug), _airJson(s));
      } catch (_) {}
    } catch (_) {
      // Немає інтернету — останні дані лишаються на місці.
      final l = last;
      if (l != null && l.available) {
        emit((available: true, updatedAt: l.updatedAt, alerts: l.alerts, offline: true));
      } else if (l == null) {
        emit(kNoAirAlertData);
      }
    }
  }

  Timer? timer;
  void start() {
    timer?.cancel();
    timer = Timer.periodic(airAlertsRefresh, (_) => load());
  }

  // Спершу — збережене на телефоні (миттєво й без інтернету), потім — із сервера.
  () async {
    try {
      final saved = await store.read(_airKey(slug));
      if (saved?.data is Map && last == null) emit(_airFrom((saved!.data as Map).cast<String, dynamic>(), offline: true));
    } catch (_) {}
    await load();
  }();
  start();
  // Банер сховано (інша вкладка) — не опитуємо сервер; повернулися — одразу оновити.
  ref.onCancel(() => timer?.cancel());
  ref.onResume(() {
    load();
    start();
  });
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});
