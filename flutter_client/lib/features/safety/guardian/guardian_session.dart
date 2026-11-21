import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/guardian.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';

/// Похід із Наглядачем на телефоні (ADR-022 §22.2): id походу на сервері, скільки точок треку
/// вже відправлено, останній стан із сервера («Все добре?»), незавершене «Я вдома» без зв'язку.
class GuardianSessionState {
  const GuardianSessionState({this.hikeId, this.sent = 0, this.view, this.pendingFinish, this.pendingHomeNav = false});

  final String? hikeId;

  /// Скільки точок локального треку вже на сервері.
  final int sent;
  final OwnerHike? view;

  /// «Я вдома» натиснуто без зв'язку — повторимо, щойно буде інтернет (Наглядач має знати).
  final String? pendingFinish;

  /// Для відкладеного «Я вдома»: чи поверталися за допомогою «Додому» (трофей «Своїм слідом»).
  final bool pendingHomeNav;

  bool get active => hikeId != null;

  Map<String, dynamic> toJson() => {'hike_id': hikeId, 'sent': sent, 'pending_finish': pendingFinish, 'pending_home_nav': pendingHomeNav};

  factory GuardianSessionState.fromJson(Map<String, dynamic> j) => GuardianSessionState(
        hikeId: j['hike_id'] as String?,
        sent: (j['sent'] as num?)?.toInt() ?? 0,
        pendingFinish: j['pending_finish'] as String?,
        pendingHomeNav: j['pending_home_nav'] == true,
      );
}

/// Синхронізація походу з Наглядачем: трек — раз на хвилину (і одразу після старту), разом із
/// батареєю; відповідь сервера каже, чи настав час «Все добре?». Без мережі точки чекають на
/// телефоні й ідуть пізніше (§22.5 п.5).
class GuardianSessionController extends Notifier<GuardianSessionState> {
  static const storeKey = 'guardian_hike';
  static Duration syncEvery = const Duration(minutes: 1);
  Timer? _timer;
  bool _syncing = false;

  @override
  GuardianSessionState build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(_restore);
    return const GuardianSessionState();
  }

  Future<void> _restore() async {
    try {
      final e = await ref.read(localStoreProvider).read(storeKey);
      if (e?.data is! Map || state.active) return;
      state = GuardianSessionState.fromJson((e!.data as Map).cast<String, dynamic>());
      if (state.active || state.pendingFinish != null) _schedule();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await ref.read(localStoreProvider).write(storeKey, state.toJson());
    } catch (_) {}
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(syncEvery, (_) => sync());
  }

  /// Почати похід з Наглядачем (після того, як похід на телефоні почався).
  /// [checklistDone] — перед стартом пройдено чек-лист (трофей «Готовий до лісу»).
  Future<OwnerHike> start({required DateTime expectedReturn, required List<String> guardianIds, bool checklistDone = false}) async {
    final hike = ref.read(hikeProvider);
    final clientId = '${hike.startedAt?.millisecondsSinceEpoch ?? 0}-${Random().nextInt(1 << 30)}';
    final view = await ref.read(guardianRepositoryProvider).start(
          route: [for (final p in hike.route) (lat: p.lat, lng: p.lng, label: p.label)],
          expectedReturn: expectedReturn,
          guardianIds: guardianIds,
          clientId: clientId,
          checklistDone: checklistDone,
        );
    state = GuardianSessionState(hikeId: view.id, view: view);
    await _save();
    _schedule();
    unawaited(sync());
    return view;
  }

  /// Відправити нові точки треку (до 500 за раз) і батарею; оновити стан.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final pending = state.pendingFinish;
      if (pending != null) {
        await ref.read(guardianRepositoryProvider).hikeAction('finish', pending, usedHomeNav: state.pendingHomeNav);
        state = const GuardianSessionState();
        await _save();
        _timer?.cancel();
        return;
      }
      final id = state.hikeId;
      if (id == null) return;
      final track = ref.read(hikeProvider).track;
      final from = state.sent.clamp(0, track.length);
      final batch = track.sublist(from, min(track.length, from + 500));
      int? battery;
      try {
        battery = await ref.read(hikeDeviceProvider).battery();
      } catch (_) {}
      final view = await ref.read(guardianRepositoryProvider).track(id, batch, battery: battery);
      state = GuardianSessionState(hikeId: id, sent: from + batch.length, view: view);
      await _save();
    } on ApiException catch (e) {
      // Похід уже закрито на сервері (автозакриття / інший телефон) — перестаємо слати.
      if (e.code == 'hike_closed' || e.code == 'hike_not_found') {
        state = const GuardianSessionState();
        await _save();
        _timer?.cancel();
      }
    } catch (_) {
      // немає мережі — наступного разу
    } finally {
      _syncing = false;
    }
  }

  /// «Так, все добре» / «Продовжити на годину» / SOS / «Скасувати SOS» → текст для підказки.
  Future<String?> act(String action) async {
    final id = state.hikeId;
    if (id == null) return null;
    final r = await ref.read(guardianRepositoryProvider).hikeAction(action, id);
    state = GuardianSessionState(hikeId: id, sent: state.sent, view: r.hike ?? state.view);
    return r.done;
  }

  /// SOS на телефоні — тривога Наглядачам (якщо похід із Наглядачем); без мережі — тихо.
  Future<void> sos() async {
    if (!state.active || state.view?.sos == true) return;
    try {
      await act('sos');
    } catch (_) {}
  }

  /// «Я вдома»: Наглядач більше не бачить ні місця, ні треку (трек видаляється на сервері).
  /// Без мережі — повторимо пізніше.
  /// [usedHomeNav] — повернулися за допомогою «Додому» (трофей «Своїм слідом»).
  Future<void> finish({bool usedHomeNav = false}) async {
    final id = state.hikeId;
    if (id == null) return;
    try {
      await ref.read(guardianRepositoryProvider).hikeAction('finish', id, usedHomeNav: usedHomeNav);
      state = const GuardianSessionState();
      _timer?.cancel();
    } on ApiException catch (e) {
      if (e.code == 'hike_closed' || e.code == 'hike_not_found') {
        state = const GuardianSessionState();
        _timer?.cancel();
      } else {
        state = GuardianSessionState(pendingFinish: id, pendingHomeNav: usedHomeNav);
        _schedule();
      }
    } catch (_) {
      state = GuardianSessionState(pendingFinish: id, pendingHomeNav: usedHomeNav);
      _schedule();
    }
    await _save();
  }
}

final guardianSessionProvider = NotifierProvider<GuardianSessionController, GuardianSessionState>(GuardianSessionController.new);
