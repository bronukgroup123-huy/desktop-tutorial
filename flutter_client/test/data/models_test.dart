import 'package:flutter/painting.dart';
import 'package:flutter_client/data/models/forecast.dart';
import 'package:flutter_client/data/models/forest_zone.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/region.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> meJson({String nextStep = 'done', Map<String, dynamic>? region}) => {
      'id': '6f1c0d8e-0000-4000-8000-000000000001',
      'name': 'Гриб',
      'rating': 0,
      'total_verified_picks': 0,
      'home_region': region,
      'created_at': '2026-11-09T12:00:00.000Z',
      'is_guest': true,
      'onboarding': {
        'region_done': region != null,
        'terms_done': nextStep == 'done',
        'terms_version': '2026-11',
        'next_step': nextStep,
        'next_step_label': 'Оберіть свою область',
      },
      'region_change': {'allowed': true, 'reason_label': 'Оберіть свою область'},
    };

void main() {
  group('Me', () {
    test('розбір профілю гостя без області', () {
      final me = Me.fromJson(meJson(nextStep: 'select_region'));
      expect(me.isGuest, isTrue);
      expect(me.homeRegion, isNull);
      expect(me.onboarding.nextStep, OnboardingStep.selectRegion);
      expect(me.onboarding.isComplete, isFalse);
      expect(me.onboarding.termsVersion, '2026-11');
    });

    test('профіль з областю', () {
      final me = Me.fromJson(meJson(region: {'id': 10, 'slug': 'kyivska', 'name': 'Київська'}));
      expect(me.homeRegion!.slug, 'kyivska');
      expect(me.onboarding.isComplete, isTrue);
    });

    test('невідомий next_step → unknown (не пропускаємо онбординг)', () {
      final me = Me.fromJson(meJson(nextStep: 'verify_phone'));
      expect(me.onboarding.nextStep, OnboardingStep.unknown);
      expect(me.onboarding.isComplete, isFalse);
    });

    test('некоректне поле → FormatException з назвою поля', () {
      final bad = meJson()..['is_guest'] = 'yes';
      expect(() => Me.fromJson(bad), throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('is_guest'))));
    });
  });

  test('RegionGeometry: MultiPolygon, bbox, центр ([lng,lat] → LatLng)', () {
    final g = RegionGeometry.fromJson({
      'id': 10,
      'slug': 'kyivska',
      'name': 'Київська',
      'bbox': [29.3, 49.2, 32.2, 51.6],
      'center': [30.6, 50.4],
      'zoom': 6,
      'geometry': {
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [[29.3, 49.2], [32.2, 49.2], [32.2, 51.6], [29.3, 49.2]],
            [[30.4, 50.3], [30.6, 50.3], [30.6, 50.5], [30.4, 50.3]],
          ],
          [
            [[31.0, 50.0], [31.1, 50.0], [31.1, 50.1], [31.0, 50.0]],
          ],
        ],
      },
    });
    expect(g.center.latitude, 50.4);
    expect(g.center.longitude, 30.6);
    expect(g.bounds.southWest.latitude, 49.2);
    expect(g.bounds.toQuery(), '29.30000,49.20000,32.20000,51.60000');
    expect(g.polygons.length, 2);
    expect(g.polygons.first.holes.length, 1);
    expect(g.polygons.first.outer.first.latitude, 49.2);
  });

  test('ForestZone: підпис і колір типу — з сервера', () {
    final zones = ForestZone.listFromFeatureCollection({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'id': 'a',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[[30.0, 50.0], [30.1, 50.0], [30.1, 50.1], [30.0, 50.0]]],
          },
          'properties': {
            'id': 'a',
            'forest_type': 'pine',
            'stand_age_years': 50,
            'type_label': 'Сосновий ліс',
            'type_color': '#81c784',
          },
        },
      ],
    });
    expect(zones.single.typeLabel, 'Сосновий ліс');
    expect(zones.single.typeColor, const Color(0xFF81C784));
    expect(zones.single.standAgeYears, 50);
    expect(zones.single.polygons.single.outer.length, 4);
    expect(parseHexColor('nope'), const Color(0xFF9E9E9E));
  });

  test('Forecast: рівні й підписи, без числових ймовірностей', () {
    final f = Forecast.fromJson({
      'regionName': 'Київська',
      'date': '2026-11-09',
      'forest': 'pine',
      'top1': {
        'mushroom_type': 'boletus_edulis',
        'name_ua': 'Білий гриб',
        'level': 'high',
        'level_label': 'Висока ймовірність',
        'level_color': '#22c55e',
        'when_label': 'Хвиля: autumn',
        'where_label': 'Південні схили',
        'why_labels': ['Дощ 16 мм 3 дні тому'],
      },
      'alternative': null,
      'warnings': [],
    });
    expect(f.top1!.levelLabel, 'Висока ймовірність');
    expect(f.top1!.whyLabels, ['Дощ 16 мм 3 дні тому']);
    expect(f.alternative, isNull);
    expect(f.noDataReason, isNull);
  });
}
