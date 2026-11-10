import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/models/weather_snapshot.dart';
import 'package:app_nhan_dien/models/outfit_analysis_result.dart';
import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/services/outfit_suggestion_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = BodyProfile(
  id: 'a',
  name: 'Hồ sơ A',
  heightCm: 170,
  weightKg: 70,
);

void main() {
  test('manual summer suggestion uses profile measurements', () {
    final result = suggestOutfit(
      profile: profile,
      season: 'summer',
      temperatureC: 32,
    );
    expect(result.title, contains('Thoáng'));
    expect(result.fitTip, contains('170 cm / 70 kg'));
  });

  test('Open-Meteo rain amount takes priority over selected season', () {
    const weather = WeatherSnapshot(
      temperatureC: 30,
      apparentTemperatureC: 35,
      precipitationMmCurrentInterval: 0.4,
      precipitationIntervalMinutes: 15,
      weatherCode: 61,
      temperatureMaxCToday: 32,
      temperatureMinCToday: 25,
      precipitationProbabilityMaxPercentToday: 75,
      observedAtLocal: '2026-09-28T14:15',
      todayDate: '2026-09-28',
      timezone: 'Asia/Ho_Chi_Minh',
      latitude: 16,
      longitude: 108,
    );
    final result = suggestOutfit(
      profile: profile,
      season: 'autumn',
      temperatureC: weather.temperatureC,
      weather: weather,
    );
    expect(result.title, contains('mưa'));
    expect(result.shoes, contains('đế bám'));
    expect(result.reason, contains('0.4 mm'));
  });

  test('detected YOLO jacket and occasion influence outfit', () {
    final item = DetectedOutfitItem(
      detectionId: 'det_1',
      classId: 1,
      rawClassName: 'Jacket',
      className: 'jacket',
      classNameVi: 'Áo khoác',
      primaryColor: 'Xanh',
      secondaryColors: const <String>[],
      confidence: 0.9,
      boundingBox: const BoundingBox(x1: 1, y1: 1, x2: 20, y2: 20),
    );
    final result = suggestOutfit(
      profile: profile,
      season: 'summer',
      temperatureC: 32,
      detectedItems: <DetectedOutfitItem>[item],
      occasion: 'work',
    );
    expect(result.top, contains('áo khoác đã nhận diện'));
    expect(result.bottom, contains('học/làm'));
    expect(result.reason, contains('Áo khoác'));
  });
}
