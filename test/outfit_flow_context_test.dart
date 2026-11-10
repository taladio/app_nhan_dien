import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/models/outfit_analysis_result.dart';
import 'package:app_nhan_dien/models/outfit_flow_context.dart';
import 'package:app_nhan_dien/models/weather_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

const _weather = WeatherSnapshot(
  temperatureC: 26,
  apparentTemperatureC: 31,
  precipitationMmCurrentInterval: 0.9,
  precipitationIntervalMinutes: 15,
  weatherCode: 95,
  temperatureMaxCToday: 28,
  temperatureMinCToday: 24,
  precipitationProbabilityMaxPercentToday: 100,
  observedAtLocal: '2026-10-08T15:00',
  todayDate: '2026-10-08',
  timezone: 'Asia/Ho_Chi_Minh',
  latitude: 16.1,
  longitude: 108.2,
);

void main() {
  test(
    'current weather chat context never includes manual season or temperature',
    () {
      const flow = OutfitFlowContext(
        season: 'summer',
        temperature: '38',
        style: 'elegant',
        occasion: 'work',
        useCurrentWeather: true,
        weather: _weather,
        gender: BodyGender.female,
      );
      final context = flow.chatContext;
      expect(context.season, isNull);
      expect(context.temperatureC, 26);
      expect(context.style, 'elegant');
      expect(context.occasion, 'work');
      expect(context.toJson()['gender'], 'female');
      expect(context.toJson()['season'], isNull);
    },
  );

  test('manual chat context does not reuse cached current weather', () {
    const flow = OutfitFlowContext(
      season: 'winter',
      temperature: '16',
      style: 'office',
      occasion: 'work',
      weather: _weather,
    );
    final context = flow.chatContext;
    expect(context.weather, isNull);
    expect(context.season, 'winter');
    expect(context.temperatureC, 16);
    expect(context.style, 'office');
  });

  test('chat context never inherits YOLO clothes from photo analysis', () {
    final analysis = OutfitAnalysisResult(
      filename: 'outfit.jpg',
      imageWidth: 100,
      imageHeight: 100,
      source: OutfitAnalysisSource.unavailable,
      detectedItems: <DetectedOutfitItem>[
        DetectedOutfitItem(
          detectionId: 'det_1',
          classId: 5,
          rawClassName: 'skirt',
          className: 'skirt',
          classNameVi: 'Chân váy',
          primaryColor: 'Đen',
          secondaryColors: <String>[],
          confidence: 0.9,
          boundingBox: BoundingBox(x1: 1, y1: 1, x2: 20, y2: 30),
        ),
      ],
      evaluation: null,
      aiError: 'test',
    );
    final context = OutfitFlowContext(
      analysisResult: analysis,
      gender: BodyGender.male,
    ).chatContext;

    expect(context.items, isEmpty);
    expect(context.gender, BodyGender.male);
  });
}
