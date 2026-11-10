import 'dart:typed_data';

import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/models/weather_snapshot.dart';
import 'package:app_nhan_dien/services/outfit_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('missing measurements and weather are omitted from multipart, never sent as null text', () async {
    String? body;
    final service = OutfitAnalysisService(
      baseUrl: 'http://example.test:8000',
      client: MockClient((request) async {
        body = request.body;
        return http.Response('{"detail":"test"}', 400);
      }),
    );
    await expectLater(
      service.analyze(
        image: PreparedAnalysisImage(
          bytes: Uint8List.fromList([1]),
          filename: 'a.jpg',
          mimeType: 'image/jpeg',
        ),
        heightCm: null,
        weightKg: null,
        season: null,
        temperatureC: null,
        style: 'casual',
        occasion: 'outing',
        confidence: .25,
      ),
      throwsA(isA<OutfitAnalysisException>()),
    );
    expect(body, isNotNull);
    for (final field in [
      'height_cm',
      'weight_kg',
      'temperature_c',
      'season',
      'weather_json',
    ]) {
      expect(body, isNot(contains('name="$field"')));
    }
  });
  test('large analysis image is resized before upload', () {
    final source = image_lib.Image(width: 2200, height: 1100);
    image_lib.fill(source, color: image_lib.ColorRgb8(80, 120, 180));

    final prepared = prepareAnalysisImage(
      bytes: Uint8List.fromList(image_lib.encodePng(source)),
      filename: 'large.png',
    );
    final decoded = image_lib.decodeImage(prepared.bytes);

    expect(decoded, isNotNull);
    expect(decoded!.width, 1600);
    expect(decoded.height, 800);
    expect(prepared.mimeType, 'image/jpeg');
    expect(prepared.filename, 'large.jpg');
    expect(prepared.bytes.length, lessThan(maxAnalysisImageBytes));
  });

  test('analysis network timeout allows Gemini to finish', () {
    final service = OutfitAnalysisService();
    addTearDown(service.close);

    expect(service.timeout, const Duration(seconds: 60));
  });

  test(
    'sends structured Open-Meteo weather with YOLO analysis fields',
    () async {
      String? sentBody;
      final service = OutfitAnalysisService(
        baseUrl: 'http://example.test:8000',
        client: MockClient((request) async {
          sentBody = request.body;
          return http.Response('{"detail":"test"}', 400);
        }),
      );
      const weather = WeatherSnapshot(
        temperatureC: 30,
        apparentTemperatureC: 35,
        precipitationMmCurrentInterval: 0.4,
        precipitationIntervalMinutes: 15,
        weatherCode: 61,
        temperatureMaxCToday: 32,
        temperatureMinCToday: 25,
        precipitationProbabilityMaxPercentToday: 70,
        observedAtLocal: '2026-09-28T14:15',
        todayDate: '2026-09-28',
        timezone: 'Asia/Ho_Chi_Minh',
        latitude: 16.1,
        longitude: 108.2,
      );
      await expectLater(
        service.analyze(
          image: PreparedAnalysisImage(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            filename: 'outfit.jpg',
            mimeType: 'image/jpeg',
          ),
          heightCm: 170,
          weightKg: 70,
          gender: BodyGender.male,
          season: 'summer',
          temperatureC: 38,
          style: 'casual',
          occasion: 'work',
          confidence: 0.25,
          weather: weather,
        ),
        throwsA(isA<OutfitAnalysisException>()),
      );
      expect(sentBody, contains('weather_json'));
      expect(sentBody, contains('Open-Meteo'));
      expect(sentBody, contains('precipitation_mm_current_interval'));
      expect(sentBody, contains('occasion'));
      expect(sentBody, isNot(contains('name="season"')));
      expect(sentBody, contains('name="temperature_c"\r\n\r\n30.0'));
      expect(sentBody, contains('name="gender"\r\n\r\nmale'));
    },
  );
}
