import 'dart:math' as math;

/// Точка на землі.
typedef Geo = ({double lat, double lng});

const _earthM = 6371000.0;
double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Відстань між точками, м (гаверсинус).
double distanceM(Geo a, Geo b) {
  final dLat = _rad(b.lat - a.lat), dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthM * math.asin(math.min(1, math.sqrt(h)));
}

/// Азимут з [a] на [b] від справжньої півночі, 0…360° за годинниковою стрілкою.
double bearingDeg(Geo a, Geo b) {
  final y = math.sin(_rad(b.lng - a.lng)) * math.cos(_rad(b.lat));
  final x = math.cos(_rad(a.lat)) * math.sin(_rad(b.lat)) - math.sin(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.cos(_rad(b.lng - a.lng));
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Кут повороту стрілки: напрямок на ціль відносно того, куди дивиться телефон, −180…180°.
double relativeDeg(double bearing, double heading) => ((bearing - heading + 540) % 360) - 180;

/// «1,2 км» / «350 м».
String distanceLabel(double m) {
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1).replaceAll('.', ',')} км';
  return '${(m / 10).round() * 10} м';
}

/// «пн», «пн-сх»… для компаса.
String cardinal(double deg) {
  const names = ['Пн', 'Пн-Сх', 'Сх', 'Пд-Сх', 'Пд', 'Пд-Зх', 'Зх', 'Пн-Зх'];
  return names[(((deg % 360) + 22.5) ~/ 45) % 8];
}

/// Магнітне схилення в Україні (орієнтовно, 2025–2027): ≈ 6,5° на заході → ≈ 10° на сході.
/// Компас телефона показує магнітну північ; стрілка на ціль — від справжньої.
double declinationUa(double lng) => (6.5 + (lng - 24) * 0.23).clamp(4.0, 11.0);

/// Курс телефона за акселерометром і магнітометром (як `SensorManager.getRotationMatrix` +
/// `getOrientation`): магнітний азимут 0…360°; `null` — телефон «на ребрі» або датчиків немає.
double? headingFromSensors(List<double> gravity, List<double> magnetic) {
  final ax = gravity[0], ay = gravity[1], az = gravity[2];
  final ex = magnetic[0], ey = magnetic[1], ez = magnetic[2];
  var hx = ey * az - ez * ay, hy = ez * ax - ex * az, hz = ex * ay - ey * ax;
  final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
  if (normH < 0.1) return null;
  hx /= normH;
  hy /= normH;
  hz /= normH;
  final invA = 1 / math.sqrt(ax * ax + ay * ay + az * az);
  final gx = ax * invA, gz = az * invA;
  final my = gz * hx - gx * hz;
  return (_deg(math.atan2(hy, my)) + 360) % 360;
}

/// Плавне усереднення кута (без стрибка 359° → 0°).
double smoothAngle(double prev, double next, [double k = 0.15]) {
  final d = relativeDeg(next, prev);
  return (prev + d * k + 360) % 360;
}

/// Схід і захід сонця (алгоритм NOAA, зеніт 90,833°) на дату [day] у місцевому часі телефона.
/// `null` — полярний день / ніч (в Україні не буває).
({DateTime sunrise, DateTime sunset})? sunTimes(Geo p, DateTime day) {
  final n = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(day.year, 1, 1)).inDays + 1;
  DateTime? at(bool rising) {
    final lngHour = p.lng / 15;
    final t = n + ((rising ? 6 : 18) - lngHour) / 24;
    final m = 0.9856 * t - 3.289;
    var l = m + 1.916 * math.sin(_rad(m)) + 0.020 * math.sin(_rad(2 * m)) + 282.634;
    l = (l + 360) % 360;
    var ra = _deg(math.atan(0.91764 * math.tan(_rad(l))));
    ra = (ra + 360) % 360;
    ra += (l ~/ 90) * 90 - (ra ~/ 90) * 90;
    ra /= 15;
    final sinDec = 0.39782 * math.sin(_rad(l));
    final cosDec = math.cos(math.asin(sinDec));
    final cosH = (math.cos(_rad(90.833)) - sinDec * math.sin(_rad(p.lat))) / (cosDec * math.cos(_rad(p.lat)));
    if (cosH > 1 || cosH < -1) return null;
    var h = rising ? 360 - _deg(math.acos(cosH)) : _deg(math.acos(cosH));
    h /= 15;
    final localT = h + ra - 0.06571 * t - 6.622;
    final ut = ((localT - lngHour) % 24 + 24) % 24;
    final minutes = (ut * 60).round();
    return DateTime.utc(day.year, day.month, day.day).add(Duration(minutes: minutes)).toLocal();
  }

  final r = at(true), s = at(false);
  return r == null || s == null ? null : (sunrise: r, sunset: s);
}

/// Точка треку: координати, час, точність.
typedef TrackPoint = ({double lat, double lng, DateTime t, double acc});

Geo geoOf(TrackPoint p) => (lat: p.lat, lng: p.lng);

/// Довжина треку від точки [from] до початку, м.
double trackLengthToStart(List<TrackPoint> track, int from) {
  var m = 0.0;
  for (var i = from; i > 0; i--) {
    m += distanceM(geoOf(track[i]), geoOf(track[i - 1]));
  }
  return m;
}

/// Чому точку не взято в трек (ADR-022 §22.5 п.5): погана точність GPS або «стрибок» —
/// глушіння / підміна сигналу. `null` — точка добра.
enum TrackReject { lowAccuracy, jump, tooClose }

TrackReject? checkTrackPoint(TrackPoint? last, TrackPoint next, {double maxAccM = 100, double minStepM = 10, double maxKmh = 40}) {
  if (next.acc > maxAccM) return TrackReject.lowAccuracy;
  if (last == null) return null;
  final d = distanceM(geoOf(last), geoOf(next));
  if (d < minStepM) return TrackReject.tooClose;
  final s = next.t.difference(last.t).inMilliseconds / 1000;
  if (d > 200 && s > 0 && d / s * 3.6 > maxKmh) return TrackReject.jump;
  return null;
}

/// Повернення «За маршрутом»: найближча точка треку, далі — назад по треку на ≥ [lookAheadM];
/// повертає ціль для стрілки й залишок шляху до старту по треку.
({Geo target, double remainingM, int nearest}) backtrackTarget(List<TrackPoint> track, Geo here, {double lookAheadM = 40}) {
  var nearest = 0;
  var best = double.infinity;
  for (var i = 0; i < track.length; i++) {
    final d = distanceM(here, geoOf(track[i]));
    if (d < best) {
      best = d;
      nearest = i;
    }
  }
  var j = nearest;
  var ahead = 0.0;
  while (j > 0 && ahead < lookAheadM) {
    ahead += distanceM(geoOf(track[j]), geoOf(track[j - 1]));
    j--;
  }
  return (target: geoOf(track[j]), remainingM: best + trackLengthToStart(track, nearest), nearest: nearest);
}
