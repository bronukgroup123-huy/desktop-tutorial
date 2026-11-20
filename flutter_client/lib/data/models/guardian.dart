import 'json.dart';
import 'me.dart';

/// Кнопка з сервера (Thin Client): що можна зробити і як це назвати.
class GuardianButton {
  const GuardianButton({required this.id, required this.label, required this.style});

  factory GuardianButton.fromJson(Map<String, dynamic> j) =>
      GuardianButton(id: req<String>(j, 'id'), label: req<String>(j, 'label'), style: opt<String>(j, 'style') ?? 'secondary');

  final String id;
  final String label;

  /// primary | secondary | danger
  final String style;
}

List<GuardianButton> _buttons(Map<String, dynamic> j) =>
    [for (final a in (opt<List<dynamic>>(j, 'actions') ?? const []).cast<Map<String, dynamic>>()) GuardianButton.fromJson(a)];

/// Людина (друг): нік, ім'я, аватар.
class GuardianPerson {
  const GuardianPerson({required this.id, required this.handle, this.name, required this.avatar, this.status, this.label, this.actions = const []});

  factory GuardianPerson.fromJson(Map<String, dynamic> j) => GuardianPerson(
        id: req<String>(j, 'id'),
        handle: opt<String>(j, 'handle') ?? '',
        name: opt<String>(j, 'name'),
        avatar: Avatar.fromJson(req<Map<String, dynamic>>(j, 'avatar')),
        status: opt<String>(j, 'status'),
        label: opt<String>(j, 'status_label') ?? opt<String>(j, 'label'),
        actions: _buttons(j),
      );

  final String id;
  final String handle;
  final String? name;
  final Avatar avatar;

  /// Для «моїх Наглядачів»: pending | accepted.
  final String? status;
  final String? label;
  final List<GuardianButton> actions;

  bool get accepted => status == 'accepted';
}

/// Мій похід на сервері (сесія Наглядача): статус, «Все добре?», кнопки.
class OwnerHike {
  const OwnerHike({
    required this.id,
    required this.status,
    required this.statusLabel,
    this.detailLabel,
    required this.askOk,
    required this.expectedReturn,
    required this.guardians,
    required this.actions,
  });

  factory OwnerHike.fromJson(Map<String, dynamic> j) => OwnerHike(
        id: req<String>(j, 'id'),
        status: req<String>(j, 'status'),
        statusLabel: req<String>(j, 'status_label'),
        detailLabel: opt<String>(j, 'detail_label'),
        askOk: opt<bool>(j, 'ask_ok') ?? false,
        expectedReturn: DateTime.parse(req<String>(j, 'expected_return')),
        guardians: [for (final g in (opt<List<dynamic>>(j, 'guardians') ?? const []).cast<Map<String, dynamic>>()) GuardianPerson.fromJson(g)],
        actions: _buttons(j),
      );

  final String id;

  /// active | check | alert | sos | closed
  final String status;
  final String statusLabel;
  final String? detailLabel;

  /// Показати «Все добре?» (настав час повернення).
  final bool askOk;
  final DateTime expectedReturn;
  final List<GuardianPerson> guardians;
  final List<GuardianButton> actions;

  bool get sos => status == 'sos';
}

typedef HikePos = ({double lat, double lng, double? accuracy, DateTime? at});

/// Похід друга, за яким я дивлюсь (картка Наглядача).
class WatchedHike {
  const WatchedHike({
    required this.hikeId,
    required this.owner,
    required this.status,
    required this.statusLabel,
    this.detailLabel,
    required this.alarm,
    this.batteryLabel,
    required this.lastSignalLabel,
    required this.noSignal,
    this.gpsIssueLabel,
    this.last,
  });

  factory WatchedHike.fromJson(Map<String, dynamic> j) {
    final last = opt<Map<String, dynamic>>(j, 'last');
    return WatchedHike(
      hikeId: req<String>(j, 'hike_id'),
      owner: GuardianPerson.fromJson(req<Map<String, dynamic>>(j, 'owner')),
      status: req<String>(j, 'status'),
      statusLabel: req<String>(j, 'status_label'),
      detailLabel: opt<String>(j, 'detail_label'),
      alarm: opt<bool>(j, 'alarm') ?? false,
      batteryLabel: opt<String>(j, 'battery_label'),
      lastSignalLabel: opt<String>(j, 'last_signal_label') ?? '',
      noSignal: opt<bool>(j, 'no_signal') ?? false,
      gpsIssueLabel: opt<String>(j, 'gps_issue_label'),
      last: last == null
          ? null
          : (
              lat: toDouble(last['lat'], 'last.lat'),
              lng: toDouble(last['lng'], 'last.lng'),
              accuracy: (last['accuracy'] as num?)?.toDouble(),
              at: DateTime.tryParse(last['at'] as String? ?? ''),
            ),
    );
  }

  final String hikeId;
  final GuardianPerson owner;
  final String status;
  final String statusLabel;
  final String? detailLabel;

  /// Тривога (немає відповіді на «Все добре?» або SOS) — червоним і згори.
  final bool alarm;
  final String? batteryLabel;
  final String lastSignalLabel;
  final bool noSignal;
  final String? gpsIssueLabel;
  final HikePos? last;
}

typedef HikeTrackPoint = ({double lat, double lng, bool lowAccuracy, DateTime t});

/// Похід для Наглядача з маршрутом і треком (`GET v1-guardian?hike=`).
class HikeDetail {
  const HikeDetail({
    required this.summary,
    required this.route,
    required this.track,
    this.rescueCoords,
    this.rescueAt,
    this.rescueSms,
    required this.serverTime,
  });

  factory HikeDetail.fromJson(Map<String, dynamic> j) {
    final rescue = opt<Map<String, dynamic>>(j, 'rescue');
    return HikeDetail(
      summary: WatchedHike.fromJson(j),
      route: [
        for (final p in (opt<List<dynamic>>(j, 'route') ?? const []).cast<Map<String, dynamic>>())
          (lat: toDouble(p['lat'], 'route.lat'), lng: toDouble(p['lng'], 'route.lng'), label: p['label'] as String? ?? ''),
      ],
      track: [
        for (final p in (opt<List<dynamic>>(j, 'track') ?? const []).cast<Map<String, dynamic>>())
          (
            lat: toDouble(p['lat'], 'track.lat'),
            lng: toDouble(p['lng'], 'track.lng'),
            lowAccuracy: p['low_accuracy'] == true,
            t: DateTime.parse(p['t'] as String),
          ),
      ],
      rescueCoords: rescue?['coords_label'] as String?,
      rescueAt: rescue?['at_label'] as String?,
      rescueSms: rescue?['sms_text'] as String?,
      serverTime: DateTime.tryParse(opt<String>(j, 'server_time') ?? '') ?? DateTime.now(),
    );
  }

  final WatchedHike summary;
  final List<({double lat, double lng, String label})> route;
  final List<HikeTrackPoint> track;
  final String? rescueCoords;
  final String? rescueAt;
  final String? rescueSms;
  final DateTime serverTime;

  HikeDetail withMore(HikeDetail fresh) => HikeDetail(
        summary: fresh.summary,
        route: fresh.route,
        track: [...track, ...fresh.track],
        rescueCoords: fresh.rescueCoords,
        rescueAt: fresh.rescueAt,
        rescueSms: fresh.rescueSms,
        serverTime: fresh.serverTime,
      );
}

/// `GET /v1-guardian`.
class GuardianOverview {
  const GuardianOverview({
    this.guardians = const [],
    this.invites = const [],
    this.watching = const [],
    this.hike,
    this.watched = const [],
    this.maxPerHike = 1,
    this.limitLabel,
    this.telegramAvailable = false,
    this.telegramLinked = false,
  });

  factory GuardianOverview.fromJson(Map<String, dynamic> j) {
    List<GuardianPerson> people(String k) =>
        [for (final e in (opt<List<dynamic>>(j, k) ?? const []).cast<Map<String, dynamic>>()) GuardianPerson.fromJson(e)];
    final limits = opt<Map<String, dynamic>>(j, 'limits') ?? const {};
    final tg = opt<Map<String, dynamic>>(j, 'telegram') ?? const {};
    final hike = opt<Map<String, dynamic>>(j, 'hike');
    return GuardianOverview(
      guardians: people('guardians'),
      invites: people('invites'),
      watching: people('watching'),
      hike: hike == null ? null : OwnerHike.fromJson(hike),
      watched: [for (final e in (opt<List<dynamic>>(j, 'watched') ?? const []).cast<Map<String, dynamic>>()) WatchedHike.fromJson(e)],
      maxPerHike: (limits['max_guardians_per_hike'] as num?)?.toInt() ?? 1,
      limitLabel: limits['label'] as String?,
      telegramAvailable: tg['available'] == true,
      telegramLinked: tg['linked'] == true,
    );
  }

  final List<GuardianPerson> guardians;
  final List<GuardianPerson> invites;
  final List<GuardianPerson> watching;
  final OwnerHike? hike;
  final List<WatchedHike> watched;
  final int maxPerHike;
  final String? limitLabel;
  final bool telegramAvailable;
  final bool telegramLinked;

  List<GuardianPerson> get acceptedGuardians => guardians.where((g) => g.accepted).toList();
}
