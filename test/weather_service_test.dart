import 'dart:convert';

import 'package:app_nhan_dien/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'backend Open-Meteo response decodes current and daily measures',
    () async {
      final service = BackendWeatherService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/weather/current');
          expect(request.method, 'POST');
          expect(jsonDecode(request.body)['latitude'], 16.1);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'temperature_c': 30,
                'apparent_temperature_c': 35,
                'precipitation_mm_current_interval': 0.4,
                'precipitation_interval_minutes': 15,
                'weather_code': 61,
                'temperature_max_c_today': 32,
                'temperature_min_c_today': 25,
                'precipitation_probability_max_percent_today': 70,
                'observed_at_local': '2026-09-28T14:15',
                'today_date': '2026-09-28',
                'timezone': 'Asia/Ho_Chi_Minh',
                'latitude': 16.1,
                'longitude': 108.2,
                'source': 'Open-Meteo',
              }),
            ),
            200,
          );
        }),
      );

      final weather = await service.currentAt(
        const CurrentLocation(16.1, 108.2),
      );
      expect(weather.temperatureC, 30);
      expect(weather.isRainingNow, isTrue);
      expect(weather.precipitationProbabilityMaxPercentToday, 70);
    },
  );

  test('backend Open-Meteo error is not replaced with fake weather', () async {
    final service = BackendWeatherService(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, String>{
              'detail': 'Open-Meteo tạm thời không phản hồi.',
            }),
          ),
          503,
        ),
      ),
    );
    expect(
      service.currentAt(const CurrentLocation(16.1, 108.2)),
      throwsA(
        isA<WeatherException>().having(
          (error) => error.message,
          'message',
          contains('Open-Meteo'),
        ),
      ),
    );
  });
}
