import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_client/core/uuid.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/pick.dart';
import 'package:flutter_client/data/repositories/picks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fake_adapter.dart';

Map<String, dynamic> pointJson({bool mine = false, String visibility = 'public'}) => {
      'id': '99999999-9999-4999-8999-999999999999',
      'lat': 50.4537,
      'lng': 30.5234,
      'is_exact': mine,
      'is_mine': mine,
      'visibility': visibility,
      'species_id': 'boletus_edulis',
      'name_label': 'Білий гриб',
      'status_label': 'Перевіряється',
      'marker_color': '#9e9e9e',
    };

const clientId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

NewPick newPick({PickVisibility visibility = PickVisibility.private, String? speciesId, String? description}) =>
    NewPick(
      clientId: clientId,
      point: const LatLng(50.4501, 30.5234),
      capturedAt: DateTime.utc(2026, 11, 10, 9, 30),
      visibility: visibility,
      speciesId: speciesId,
      description: description,
    );

PickPhoto photo() => PickPhoto(
      openRead: () => Stream.value(const [0xff, 0xd8, 0xff, 0xd9]),
      sizeBytes: 4,
      contentType: 'image/jpeg',
    );

const uploadTarget = FakeResponse(200, {
  'data': {'upload_url': 'https://storage.test/upload/u/c.jpg?token=t', 'path': 'u/c.jpg'},
});

void main() {
  group('моделі тук-туків', () {
    test('MapPick: чужа точка — приблизне місце, підпис і колір із сервера', () {
      final p = MapPick.fromJson(pointJson());
      expect(p.point, const LatLng(50.4537, 30.5234));
      expect(p.isExact, isFalse);
      expect(p.isMine, isFalse);
      expect(p.visibility, PickVisibility.public);
      expect(p.nameLabel, 'Білий гриб');
      expect(p.statusLabel, 'Перевіряється');
      expect(p.markerColor, const Color(0xFF9E9E9E));
    });

    test('PicksMap: список точок і позначка «є ще»', () {
      final map = PicksMap.fromJson({
        'points': [pointJson(), pointJson(mine: true, visibility: 'private')],
        'truncated': true,
      });
      expect(map.points.length, 2);
      expect(map.points.last.isMine, isTrue);
      expect(map.points.last.visibility, PickVisibility.private);
      expect(map.truncated, isTrue);
      expect(PicksMap.fromJson(const <String, dynamic>{}).points, isEmpty);
    });

    test('PickCard: фото, опис, дата і застереження', () {
      final card = PickCard.fromJson({
        ...pointJson(),
        'description': 'Під сосною',
        'date_label': '10 листопада 2026 р.',
        'captured_at': null,
        'photo_url': 'https://proj.supabase.co/signed/picks/x.jpg?token=t',
        'disclaimer_label': 'Фото користувача — не порада їсти гриб',
        'actions': <String>[],
      });
      expect(card.pick.nameLabel, 'Білий гриб');
      expect(card.description, 'Під сосною');
      expect(card.dateLabel, '10 листопада 2026 р.');
      expect(card.photoUrl, startsWith('https://'));
      expect(card.disclaimerLabel, contains('не порада'));
      expect(card.actions, isEmpty);
    });

    test('SpeciesList і пошук виду за українською чи латинською назвою', () {
      final list = SpeciesList.fromJson({
        'species': [
          {'id': 'boletus_edulis', 'name_label': 'Білий гриб', 'latin_label': 'Boletus edulis'},
          {'id': 'cantharellus_cibarius', 'name_label': 'Лисичка справжня', 'latin_label': null},
        ],
        'unknown_label': 'Не знаю, що це',
      });
      expect(list.unknownLabel, 'Не знаю, що це');
      final white = list.species.first;
      expect(white.matches(''), isTrue);
      expect(white.matches(' біл '), isTrue);
      expect(white.matches('BOLETUS'), isTrue);
      expect(white.matches('лисич'), isFalse);
      expect(list.species.last.matches('cantharellus'), isFalse, reason: 'латинської назви немає');
    });

    test('тип фото за розширенням файлу', () {
      expect(PickPhoto.contentTypeForPath('/tmp/a.JPG'), 'image/jpeg');
      expect(PickPhoto.contentTypeForPath('/tmp/a.png'), 'image/png');
      expect(PickPhoto.contentTypeForPath('/tmp/a.webp'), 'image/webp');
      expect(PickPhoto.contentTypeForPath('/tmp/scaled_photo'), 'image/jpeg');
    });

    test('uuidV4: формат і унікальність', () {
      final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final ids = {for (var i = 0; i < 200; i++) uuidV4()};
      expect(ids.length, 200);
      expect(ids.every(re.hasMatch), isTrue);
      expect(uuidV4(Random(1)), uuidV4(Random(1)), reason: 'той самий генератор — той самий id');
    });
  });

  group('PicksRepository', () {
    test('fetchMap: mine у query; fetchCard і fetchSpecies — свої шляхи', () async {
      final (api, adapter) = makeClient((req) {
        if (req.path == '/v1-picks/map') {
          return FakeResponse(200, {
            'data': {
              'points': [pointJson()],
              'truncated': false,
            },
          });
        }
        if (req.path == '/v1-picks/species') {
          return const FakeResponse(200, {
            'data': {'species': <Object>[], 'unknown_label': 'Не знаю, що це'},
          });
        }
        return FakeResponse(200, {'data': pointJson(mine: true)});
      });
      final (uploads, _) = makeFilesDio((_) => const FakeResponse(200, <String, Object>{}));
      final repo = PicksRepository(api, uploads: uploads);

      expect((await repo.fetchMap()).points.single.nameLabel, 'Білий гриб');
      await repo.fetchMap(mine: true);
      expect(adapter.requests[0].queryParameters['mine'], 'false');
      expect(adapter.requests[1].queryParameters['mine'], 'true');

      final card = await repo.fetchCard('99999999-9999-4999-8999-999999999999');
      expect(adapter.requests[2].path, '/v1-picks/99999999-9999-4999-8999-999999999999');
      expect(card.pick.isExact, isTrue);

      expect((await repo.fetchSpecies()).unknownLabel, 'Не знаю, що це');
      expect(adapter.requests[3].method, 'GET');
    });

    test('createPick: посилання → PUT файлу без ключів → точка з тим самим client_id', () async {
      final (api, adapter) = makeClient((req) {
        if (req.path == '/v1-picks/upload-url') return uploadTarget;
        return const FakeResponse(201, {
          'data': {
            'id': '99999999-9999-4999-8999-999999999999',
            'visibility': 'public',
            'status_label': 'Перевіряється',
            'marker_color': '#9e9e9e',
          },
        });
      });
      final (uploads, uploadAdapter) = makeFilesDio((_) => const FakeResponse(200, <String, Object>{}));

      final created = await PicksRepository(api, uploads: uploads).createPick(
        newPick(visibility: PickVisibility.public, speciesId: 'boletus_edulis', description: '  Під сосною  '),
        photo(),
      );
      expect(created.statusLabel, 'Перевіряється');
      expect(created.visibility, PickVisibility.public);

      // 1. посилання
      expect(adapter.requests[0].path, '/v1-picks/upload-url');
      expect(adapter.requests[0].data, {'client_id': clientId, 'content_type': 'image/jpeg', 'size_bytes': 4});

      // 2. файл — прямо в сховище, без apikey / Authorization
      final put = uploadAdapter.requests.single;
      expect(put.method, 'PUT');
      expect(put.uri.toString(), 'https://storage.test/upload/u/c.jpg?token=t');
      expect(put.headers['content-type'], 'image/jpeg');
      expect(put.headers.containsKey('apikey'), isFalse);
      expect(put.headers.containsKey('Authorization'), isFalse);

      // 3. точка
      expect(adapter.requests[1].path, '/v1-picks');
      expect(adapter.requests[1].data, {
        'client_id': clientId,
        'path': 'u/c.jpg',
        'lat': 50.4501,
        'lng': 30.5234,
        'captured_at': '2026-11-10T09:30:00.000Z',
        'visibility': 'public',
        'species_id': 'boletus_edulis',
        'description': 'Під сосною',
      });
    });

    test('createPick: «Не знаю» → species_id null; порожній опис не надсилається', () async {
      final (api, adapter) = makeClient((req) => req.path == '/v1-picks/upload-url'
          ? uploadTarget
          : const FakeResponse(201, {
              'data': {
                'id': 'x',
                'visibility': 'private',
                'status_label': 'Приватна точка',
                'marker_color': '#1e88e5',
              },
            }));
      final (uploads, _) = makeFilesDio((_) => const FakeResponse(200, <String, Object>{}));
      await PicksRepository(api, uploads: uploads).createPick(newPick(description: '   '), photo());
      final body = adapter.requests[1].data as Map<String, dynamic>;
      expect(body.containsKey('species_id'), isTrue);
      expect(body['species_id'], isNull);
      expect(body.containsKey('description'), isFalse);
      expect(body['visibility'], 'private');
    });

    test('createPick: сховище відхилило файл → upload_failed, точка не створюється', () async {
      final (api, adapter) = makeClient((_) => uploadTarget);
      final (uploads, _) = makeFilesDio((_) => const FakeResponse(413, {'error': 'Payload too large'}));
      await expectLater(
        PicksRepository(api, uploads: uploads).createPick(newPick(), photo()),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiException.uploadFailed)
            .having((e) => e.userMessage, 'userMessage', contains('фото'))),
      );
      expect(adapter.requests.length, 1, reason: 'POST /v1-picks не викликався');
    });

    test('createPick: немає мережі під час завантаження → network_error', () async {
      final (api, _) = makeClient((_) => uploadTarget);
      final (uploads, _) = makeFilesDio((_) => const FakeResponse.offline());
      await expectLater(
        PicksRepository(api, uploads: uploads).createPick(newPick(), photo()),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });

    test('createPick: відмова сервера (ліміт) передається з текстом для користувача', () async {
      final (api, _) = makeClient((req) => req.path == '/v1-picks/upload-url'
          ? uploadTarget
          : const FakeResponse(429, {
              'error': 'daily_limit_reached',
              'message': 'Ліміт — 5 приватних точок на добу. Спробуйте пізніше.',
            }));
      final (uploads, _) = makeFilesDio((_) => const FakeResponse(200, <String, Object>{}));
      await expectLater(
        PicksRepository(api, uploads: uploads).createPick(newPick(), photo()),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'daily_limit_reached')
            .having((e) => e.userMessage, 'userMessage', startsWith('Ліміт'))),
      );
    });
  });
}
