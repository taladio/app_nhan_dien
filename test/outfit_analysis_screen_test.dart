import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/models/outfit_analysis_result.dart';
import 'package:app_nhan_dien/models/weather_snapshot.dart';
import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/screens/outfit_analysis_screen.dart';
import 'package:app_nhan_dien/services/analysis_preferences.dart';
import 'package:app_nhan_dien/services/body_profile_store.dart';
import 'package:app_nhan_dien/services/outfit_analysis_service.dart';
import 'package:app_nhan_dien/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class FakeAnalysisPreferences implements AnalysisPreferencesStore {
  AnalysisPreferencesData data = const AnalysisPreferencesData(
    heightCm: '170',
    weightKg: '65',
    temperatureC: '32',
  );

  @override
  Future<AnalysisPreferencesData> load() async => data;

  @override
  Future<void> save(AnalysisPreferencesData newData) async => data = newData;
}

class FakeAnalysisService implements OutfitAnalysisServiceContract {
  FakeAnalysisService(this.handler);

  final Future<OutfitAnalysisResult> Function() handler;
  int callCount = 0;
  double? lastHeightCm;
  double? lastWeightKg;
  BodyGender? lastGender;
  double? lastTemperatureC;
  String? lastSeason;
  String? lastStyle;
  String? lastOccasion;
  WeatherSnapshot? lastWeather;

  @override
  Future<OutfitAnalysisResult> analyze({
    required PreparedAnalysisImage image,
    required double? heightCm,
    required double? weightKg,
    required String? season,
    required double? temperatureC,
    required String style,
    required String occasion,
    required double confidence,
    WeatherSnapshot? weather,
    BodyGender gender = BodyGender.unspecified,
  }) {
    callCount += 1;
    lastHeightCm = heightCm;
    lastWeightKg = weightKg;
    lastGender = gender;
    lastTemperatureC = temperatureC;
    lastSeason = season;
    lastStyle = style;
    lastOccasion = occasion;
    lastWeather = weather;
    return handler();
  }

  @override
  void close() {}
}

class FakeBodyProfileStore implements BodyProfileStore {
  BodyProfileCollection data = const BodyProfileCollection(
    profiles: <BodyProfile>[
      BodyProfile(id: 'a', name: 'Hồ sơ A', heightCm: 170, weightKg: 65),
      BodyProfile(
        id: 'b',
        name: 'Hồ sơ B',
        heightCm: 180,
        weightKg: 75,
        gender: BodyGender.female,
      ),
    ],
    selectedId: 'a',
  );

  @override
  Future<BodyProfileCollection> load() async => data;

  @override
  Future<void> save(BodyProfileCollection collection) async =>
      data = collection;
}

class _Location implements CurrentLocationService {
  @override
  Future<CurrentLocation> current() async => const CurrentLocation(16.1, 108.2);
}

class _DeniedLocation implements CurrentLocationService {
  @override
  Future<CurrentLocation> current() async =>
      throw const WeatherException('Bạn chưa cấp quyền vị trí.');
}

class _Weather implements WeatherService {
  @override
  Future<WeatherSnapshot> currentAt(CurrentLocation location) async =>
      const WeatherSnapshot(
        temperatureC: 27.6,
        apparentTemperatureC: 31.2,
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
      );
}

final Uint8List _validPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

PreparedAnalysisImage get _selectedImage => PreparedAnalysisImage(
  bytes: _validPng,
  filename: 'outfit.png',
  mimeType: 'image/png',
);

OutfitAnalysisResult _result() => OutfitAnalysisResult(
  filename: 'outfit.png',
  imageWidth: 100,
  imageHeight: 100,
  source: OutfitAnalysisSource.gemini,
  detectedItems: <DetectedOutfitItem>[
    DetectedOutfitItem(
      detectionId: 'det_1',
      classId: 0,
      rawClassName: 'T-Shirt',
      className: 'tshirt',
      classNameVi: 'Áo thun',
      primaryColor: 'Trắng',
      secondaryColors: const <String>[],
      confidence: 0.9,
      boundingBox: const BoundingBox(x1: 10, y1: 10, x2: 90, y2: 90),
    ),
  ],
  evaluation: OutfitEvaluation(
    overallScore: 80,
    rating: 'Phù hợp',
    colorScore: 80,
    seasonTemperatureScore: 80,
    bodyProportionScore: 80,
    styleScore: 80,
    occasionScore: 80,
    summary: 'Đánh giá từ Gemini.',
    strengths: <String>['Màu dễ phối.'],
    problems: <String>[],
    recommendations: <String>['Giữ cách phối.'],
    suggestedOutfit: SuggestedOutfit(
      top: 'Áo trắng',
      bottom: 'Quần be',
      outerwear: null,
      shoes: 'Giày trắng',
      reason: 'Phù hợp.',
    ),
  ),
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required OutfitAnalysisServiceContract service,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: OutfitAnalysisScreen(
        service: service,
        preferencesStore: FakeAnalysisPreferences(),
        imageSelectionCallback: (ImageSource _) async => _selectedImage,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectAndAnalyze(WidgetTester tester) async {
  final gallery = find.byKey(const Key('gallery_button'));
  await tester.ensureVisible(gallery);
  await tester.pumpAndSettle();
  await tester.tap(gallery);
  await tester.pumpAndSettle();
  final button = find.byKey(const Key('analyze_button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  testWidgets(
    'missing profile and denied GPS still allow image analysis without fake context',
    (tester) async {
      final service = FakeAnalysisService(() async => _result());
      final profiles = FakeBodyProfileStore()
        ..data = const BodyProfileCollection();
      final preferences = FakeAnalysisPreferences()
        ..data = const AnalysisPreferencesData(
          useCurrentWeather: true,
          temperatureC: '38',
          season: 'summer',
        );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: OutfitAnalysisScreen(
            service: service,
            profileStore: profiles,
            preferencesStore: preferences,
            imageSelectionCallback: (_) async => _selectedImage,
            weatherService: _Weather(),
            locationService: _DeniedLocation(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('temperature_field')), findsNothing);
      await _selectAndAnalyze(tester);
      await tester.pumpAndSettle();
      expect(service.callCount, 1);
      expect(service.lastHeightCm, isNull);
      expect(service.lastWeightKg, isNull);
      expect(service.lastWeather, isNull);
      expect(service.lastTemperatureC, isNull);
      expect(service.lastSeason, isNull);
      expect(preferences.data.useCurrentWeather, true);
      expect(preferences.data.temperatureC, '38');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('analysis toggle replaces manual temperature with weather', (
    tester,
  ) async {
    final service = FakeAnalysisService(() async => _result());
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitAnalysisScreen(
          service: service,
          preferencesStore: FakeAnalysisPreferences(),
          imageSelectionCallback: (_) async => _selectedImage,
          weatherService: _Weather(),
          locationService: _Location(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('temperature_field')), findsOneWidget);

    final weatherChoice = find.text('Thời tiết hiện tại');
    await tester.ensureVisible(weatherChoice);
    await tester.pumpAndSettle();
    await tester.tap(weatherChoice);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('season_dropdown')), findsNothing);
    expect(find.byKey(const Key('temperature_field')), findsNothing);
    expect(find.textContaining('27.6°C · Cảm nhận 31.2°C'), findsOneWidget);
    expect(find.text('Dữ liệu thời tiết: Open-Meteo'), findsOneWidget);

    await _selectAndAnalyze(tester);
    await tester.pumpAndSettle();
    expect(service.lastTemperatureC, 27.6);
    expect(service.lastSeason, isNull);
    expect(service.lastWeather?.temperatureC, 27.6);

    final manualChoice = find.text('Thủ công');
    await tester.ensureVisible(manualChoice);
    await tester.pumpAndSettle();
    await tester.tap(manualChoice);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('season_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('temperature_field')), findsOneWidget);
    expect(find.textContaining('27.6°C · Cảm nhận'), findsNothing);
    await _selectAndAnalyze(tester);
    await tester.pumpAndSettle();
    expect(service.lastSeason, 'summer');
    expect(service.lastTemperatureC, 32);
    expect(service.lastWeather, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analysis weather allows city after denied location', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitAnalysisScreen(
          service: FakeAnalysisService(() async => _result()),
          preferencesStore: FakeAnalysisPreferences(),
          weatherService: _Weather(),
          locationService: _DeniedLocation(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final weatherChoice = find.text('Thời tiết hiện tại');
    await tester.ensureVisible(weatherChoice);
    await tester.pumpAndSettle();
    await tester.tap(weatherChoice);
    await tester.pumpAndSettle();
    expect(find.textContaining('chưa cấp quyền vị trí'), findsOneWidget);

    final cityDropdown = find.byKey(const Key('analysis_city_dropdown'));
    await tester.ensureVisible(cityDropdown);
    await tester.pumpAndSettle();
    await tester.tap(cityDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đà Nẵng').last);
    await tester.pumpAndSettle();
    final cityButton = find.byKey(
      const Key('analysis_load_city_weather_button'),
    );
    await tester.ensureVisible(cityButton);
    await tester.pumpAndSettle();
    await tester.tap(cityButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('27.6°C · Cảm nhận 31.2°C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses selected named profile for photo analysis', (tester) async {
    final service = FakeAnalysisService(() async => _result());
    final profiles = FakeBodyProfileStore();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitAnalysisScreen(
          service: service,
          profileStore: profiles,
          preferencesStore: FakeAnalysisPreferences(),
          imageSelectionCallback: (_) async => _selectedImage,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const Key('profile_dropdown_a'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hồ sơ B').last);
    await tester.pumpAndSettle();
    expect(profiles.data.selected?.name, 'Hồ sơ B');

    await _selectAndAnalyze(tester);
    await tester.pumpAndSettle();
    expect(service.lastHeightCm, 180);
    expect(service.lastWeightKg, 75);
    expect(service.lastGender, BodyGender.female);
  });

  testWidgets('khóa nút và hiển thị loading khi request đang chạy', (
    tester,
  ) async {
    final completer = Completer<OutfitAnalysisResult>();
    final service = FakeAnalysisService(() => completer.future);
    await _pumpScreen(tester, service: service);

    await _selectAndAnalyze(tester);

    expect(find.byKey(const Key('loading_panel')), findsOneWidget);
    expect(service.callCount, 1);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('analyze_button')),
    );
    expect(button.onPressed, isNull);

    completer.complete(_result());
    await tester.pumpAndSettle();
    expect(find.text('Gemini AI'), findsOneWidget);
    expect(find.byKey(const Key('analyze_again_button')), findsOneWidget);
  });

  testWidgets('gender change discards pending photo advice', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<OutfitAnalysisResult>();
    final service = FakeAnalysisService(() => pending.future);
    final profiles = FakeBodyProfileStore();
    final preferences = FakeAnalysisPreferences();
    Widget screen(int revision) => MaterialApp(
      home: OutfitAnalysisScreen(
        service: service,
        profileStore: profiles,
        profileRevision: revision,
        preferencesStore: preferences,
        imageSelectionCallback: (_) async => _selectedImage,
      ),
    );
    await tester.pumpWidget(screen(0));
    await tester.pumpAndSettle();
    await _selectAndAnalyze(tester);
    expect(service.callCount, 1);
    profiles.data = profiles.data.upsert(
      profiles.data.selected!.copyWith(gender: BodyGender.female),
    );
    await tester.pumpWidget(screen(1));
    await tester.pumpAndSettle();
    pending.complete(_result());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('outfit_score_card')), findsNothing);
    expect(find.byKey(const Key('loading_panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gemini lỗi vẫn hiển thị YOLO nhưng không tạo điểm giả', (
    tester,
  ) async {
    final detected = _result().detectedItems;
    final partial = OutfitAnalysisResult(
      filename: 'outfit.png',
      imageWidth: 100,
      imageHeight: 100,
      source: OutfitAnalysisSource.unavailable,
      detectedItems: detected,
      evaluation: null,
      aiError: 'Gemini đang hết hạn mức. Hãy thử lại.',
    );
    await _pumpScreen(
      tester,
      service: FakeAnalysisService(() async => partial),
    );
    await _selectAndAnalyze(tester);
    await tester.pumpAndSettle();
    expect(find.text('AI chưa khả dụng'), findsOneWidget);
    expect(find.text('Áo thun · Trắng'), findsOneWidget);
    expect(find.textContaining('hết hạn mức'), findsOneWidget);
    expect(find.byKey(const Key('outfit_score_card')), findsNothing);
  });

  testWidgets('hiển thị lỗi tiếng Việt khi service thất bại', (tester) async {
    final service = FakeAnalysisService(
      () async => throw const OutfitAnalysisException(
        'Không thể kết nối backend. Hãy kiểm tra máy chủ và mạng.',
      ),
    );
    await _pumpScreen(tester, service: service);

    await _selectAndAnalyze(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error_panel')), findsOneWidget);
    expect(find.textContaining('Không thể kết nối backend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
