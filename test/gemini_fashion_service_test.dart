import 'dart:convert';

import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/models/gemini_fashion.dart';
import 'package:app_nhan_dien/models/outfit_analysis_result.dart';
import 'package:app_nhan_dien/models/weather_snapshot.dart';
import 'package:app_nhan_dien/services/gemini_fashion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

GeminiOutfitContext _context({
  String color = 'Xanh dương',
  bool weather = true,
}) {
  return GeminiOutfitContext(
    items: <DetectedOutfitItem>[
      DetectedOutfitItem(
        detectionId: 'det_1',
        classId: 12,
        rawClassName: 'Long sleeve dress',
        className: 'dress',
        classNameVi: 'Váy liền',
        primaryColor: color,
        secondaryColors: const <String>[],
        confidence: 0.91,
        boundingBox: const BoundingBox(x1: 0, y1: 0, x2: 20, y2: 20),
      ),
    ],
    weather: weather
        ? const WeatherSnapshot(
            temperatureC: 28,
            apparentTemperatureC: 32,
            precipitationMmCurrentInterval: 0,
            precipitationIntervalMinutes: 15,
            weatherCode: 2,
            temperatureMaxCToday: 31,
            temperatureMinCToday: 25,
            precipitationProbabilityMaxPercentToday: 40,
            observedAtLocal: '2026-09-28T19:00',
            todayDate: '2026-09-28',
            timezone: 'Asia/Ho_Chi_Minh',
            latitude: 16.1,
            longitude: 108.2,
          )
        : null,
    season: 'summer',
    style: 'streetwear',
    occasion: 'outing',
    heightCm: 170,
    weightKg: 65,
    gender: BodyGender.female,
  );
}

void main() {
  test(
    'sends actual YOLO label and weather to centralized backend URL',
    () async {
      Map<String, dynamic>? sent;
      final service = GeminiFashionService(
        baseUrl: 'https://api.example.test/base',
        client: MockClient((request) async {
          expect(request.url.path, '/base/api/v1/outfit/suggest');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'assessment': 'Phù hợp',
                'reason': 'Dễ phối',
                'adjustments': <String>['Đổi giày'],
                'color_score': 80,
              }),
            ),
            200,
          );
        }),
      );
      final advice = await service.suggest(_context());
      final context = sent!['context'] as Map<String, dynamic>;
      expect((context['items'] as List).first['label'], 'Long sleeve dress');
      expect((context['weather'] as Map)['source'], 'Open-Meteo');
      expect(context['height_cm'], 170);
      expect(context['gender'], 'female');
      expect(context['style'], 'streetwear');
      expect(context['season'], isNull);
      expect(advice.colorScore, 80);
      service.close();
    },
  );

  test('unknown color and absent weather stay null', () async {
    final service = GeminiFashionService(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async {
        final context = (jsonDecode(request.body) as Map)['context'] as Map;
        expect(context['weather'], isNull);
        expect((context['items'] as List).first['color'], isNull);
        return http.Response.bytes(
          utf8.encode(
            '{"assessment":"Ổn","reason":"Hợp","adjustments":["Thử giày khác"],"color_score":85}',
          ),
          200,
        );
      }),
    );
    final advice = await service.suggest(
      _context(color: 'Không xác định', weather: false),
    );
    expect(advice.colorScore, isNull);
  });

  test('chat sends bounded history and surfaces safe backend error', () async {
    final service = GeminiFashionService(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/outfit/chat');
        final body = jsonDecode(request.body) as Map;
        expect((body['history'] as List).length, 6);
        expect((body['history'] as List).first['content'], '9');
        expect(body['message'], contains('trời mưa'));
        expect((body['context'] as Map)['gender'], 'female');
        return http.Response.bytes(
          utf8.encode('{"detail":"Gemini đang hết hạn mức."}'),
          503,
        );
      }),
    );
    await expectLater(
      service.chat(
        _context(weather: false),
        'Nếu trời mưa thì thay giày nào?',
        List<GeminiChatTurn>.generate(
          15,
          (index) => GeminiChatTurn(role: 'user', content: '$index'),
        ),
      ),
      throwsA(isA<GeminiFashionException>()),
    );
  });

  test('unset and withheld gender are not sent to AI', () {
    for (final gender in [BodyGender.unspecified, BodyGender.preferNotToSay]) {
      final payload = GeminiOutfitContext(items: [], gender: gender).toJson();
      expect(payload.containsKey('gender'), isFalse);
    }
  });

  test(
    'client timeout reports an unreachable backend instead of blaming AI',
    () async {
      final service = GeminiFashionService(
        baseUrl: 'http://10.127.48.139:8000',
        timeout: const Duration(milliseconds: 1),
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response('{}', 200);
        }),
      );
      addTearDown(service.close);

      await expectLater(
        service.suggest(_context()),
        throwsA(
          isA<GeminiFashionException>()
              .having(
                (error) => error.message,
                'message',
                contains('Backend 10.127.48.139 không phản hồi'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('AI phản hồi quá chậm')),
              ),
        ),
      );
    },
  );
}
