import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/guardian.dart';
import 'package:flutter_client/data/providers.dart';

/// Як часто оновлювати походи друзів, за якими я Наглядач (є такі / немає).
Duration watchedRefresh = const Duration(seconds: 30);
Duration watchedIdleRefresh = const Duration(minutes: 3);

/// Походи друзів, де я Наглядач, — з маршрутом і треком (для головної карти й картки).
/// Немає таких — тихо перевіряємо раз на 3 хв; є — оновлюємо кожні 30 с, трек — лише нові точки.
/// Гість / без мережі — порожньо (ADR-022 §22.2: «Головна карта Наглядача показує грибника»).
final watchedHikesProvider = StreamProvider.autoDispose<List<HikeDetail>>((ref) {
  final controller = StreamController<List<HikeDetail>>();
  final details = <String, HikeDetail>{};
  Timer? timer;
  var alive = true;

  Future<void> poll() async {
    var next = watchedIdleRefresh;
    try {
      final me = await ref.read(meProvider.future);
      if (me == null || me.isGuest || me.handle == null) {
        if (alive) controller.add(const []);
        return;
      }
      final repo = ref.read(guardianRepositoryProvider);
      final overview = await repo.overview();
      final ids = {for (final w in overview.watched) w.hikeId};
      details.removeWhere((id, _) => !ids.contains(id));
      for (final id in ids) {
        final old = details[id];
        final lastT = old == null || old.track.isEmpty ? null : old.track.last.t;
        final fresh = await repo.hike(id, since: lastT);
        details[id] = old == null ? fresh : old.withMore(fresh);
      }
      if (ids.isNotEmpty) next = watchedRefresh;
      if (alive) controller.add([for (final id in ids) details[id]!]..sort((a, b) => (b.summary.alarm ? 1 : 0) - (a.summary.alarm ? 1 : 0)));
    } catch (_) {
      if (details.isNotEmpty) next = watchedRefresh;
      if (alive && details.isEmpty) controller.add(const []);
    } finally {
      if (alive) timer = Timer(next, poll);
    }
  }

  unawaited(poll());
  ref.onDispose(() {
    alive = false;
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Навести головну карту на точку (останнє місце друга з картки Наглядача).
final mapFocusPointProvider = StateProvider<LatLng?>((ref) => null);
