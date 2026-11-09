import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/features/map/map_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const region = GeoBounds(southWest: LatLng(49.6, 27.2), northEast: LatLng(51.6, 30.6)); // Житомирська

  test('віддалена карта: bbox запиту обрізається до меж області', () {
    final visible = LatLngBounds(const LatLng(44.0, 20.0), const LatLng(56.0, 38.0));
    final q = clipToRegion(visible, region)!;
    expect(q.toQuery(), '27.20000,49.60000,30.60000,51.60000');
  });

  test('видима частина всередині області — без змін', () {
    final visible = LatLngBounds(const LatLng(50.0, 28.0), const LatLng(50.5, 28.8));
    expect(clipToRegion(visible, region)!.toQuery(), '28.00000,50.00000,28.80000,50.50000');
  });

  test('видима частина поза областю → null (запиту немає)', () {
    final visible = LatLngBounds(const LatLng(46.0, 33.0), const LatLng(47.0, 34.0));
    expect(clipToRegion(visible, region), isNull);
  });
}
