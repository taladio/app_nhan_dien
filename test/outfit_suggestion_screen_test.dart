import 'dart:async';

import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/models/gemini_fashion.dart';
import 'package:app_nhan_dien/models/weather_snapshot.dart';
import 'package:app_nhan_dien/screens/outfit_suggestion_screen.dart';
import 'package:app_nhan_dien/services/body_profile_store.dart';
import 'package:app_nhan_dien/services/gemini_fashion_service.dart';
import 'package:app_nhan_dien/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements BodyProfileStore {
  BodyProfileCollection data = const BodyProfileCollection(
    profiles: <BodyProfile>[
      BodyProfile(
        id: 'a',
        name: 'Hồ sơ A',
        heightCm: 170,
        weightKg: 70,
        gender: BodyGender.male,
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
}

class _DelayedWeather implements WeatherService {
  final completer = Completer<WeatherSnapshot>();

  @override
  Future<WeatherSnapshot> currentAt(CurrentLocation location) =>
      completer.future;
}

class _Gemini implements GeminiFashionServiceContract {
  bool failFirst = true;
  int suggestCalls = 0;
  GeminiOutfitContext? lastContext;
  int lastHistoryLength = -1;

  @override
  Future<GeminiSuggestion> suggest(GeminiOutfitContext context) async {
    suggestCalls++;
    lastContext = context;
    if (failFirst && suggestCalls == 1) {
      throw const GeminiFashionException('Gemini tạm thời lỗi.');
    }
    return const GeminiSuggestion(
      assessment: 'Bộ đồ phù hợp',
      reason: 'Hợp hoàn cảnh đi chơi.',
      adjustments: <String>['Đổi sang giày chống trượt.'],
      colorScore: null,
    );
  }

  @override
  Future<String> chat(
    GeminiOutfitContext context,
    String message,
    List<GeminiChatTurn> history,
  ) async {
    lastHistoryLength = history.length;
    lastContext = context;
    return 'Nếu mưa, chọn giày đế bám.';
  }

  @override
  void close() {}
}

class _DelayedGemini extends _Gemini {
  final pending = Completer<GeminiSuggestion>();

  @override
  Future<GeminiSuggestion> suggest(GeminiOutfitContext context) {
    suggestCalls++;
    lastContext = context;
    return pending.future;
  }
}

void main() {
  testWidgets(
    'empty cloud profiles do not resurrect initial measurements after deletion',
    (tester) async {
      final profiles = _Store()..data = const BodyProfileCollection();
      final contexts = <GeminiOutfitContext>[];
      await tester.pumpWidget(
        MaterialApp(
          home: OutfitSuggestionScreen(
            profileStore: profiles,
            initialSeason: 'summer',
            initialTemperatureC: '28',
            initialHeightCm: 170,
            initialWeightKg: 70,
            initialGender: BodyGender.male,
            onContextChanged: contexts.add,
            geminiService: _Gemini(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(contexts.last.heightCm, isNull);
      expect(contexts.last.weightKg, isNull);
      expect(contexts.last.gender, BodyGender.unspecified);
    },
  );
  testWidgets('gender change discards pending advice for the old profile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store();
    final gemini = _DelayedGemini();
    final contexts = <GeminiOutfitContext>[];
    Widget screen(int revision) => MaterialApp(
      home: OutfitSuggestionScreen(
        profileStore: store,
        initialSeason: 'summer',
        initialTemperatureC: '28',
        geminiService: gemini,
        profileRevision: revision,
        onContextChanged: contexts.add,
      ),
    );
    await tester.pumpWidget(screen(0));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('generate_suggestion_button'));
    await tester.scrollUntilVisible(
      button,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button);
    await tester.pump();
    expect(gemini.lastContext?.gender, BodyGender.male);
    store.data = store.data.upsert(
      store.data.selected!.copyWith(gender: BodyGender.female),
    );
    await tester.pumpWidget(screen(1));
    await tester.pumpAndSettle();
    expect(contexts.last.gender, BodyGender.female);
    gemini.pending.complete(
      const GeminiSuggestion(
        assessment: 'Gợi ý cho hồ sơ cũ',
        reason: 'Cũ',
        adjustments: ['Cũ'],
        colorScore: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gợi ý cho hồ sơ cũ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suggestion and follow-up chat use no photo metadata', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gemini = _Gemini();
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitSuggestionScreen(
          profileStore: _Store(),
          initialSeason: 'summer',
          initialTemperatureC: '28',
          geminiService: gemini,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final generate = find.byKey(const Key('generate_suggestion_button'));
    await tester.scrollUntilVisible(
      generate,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('Gemini tạm thời lỗi.'), findsOneWidget);
    expect(gemini.suggestCalls, 1);
    final retry = find.byKey(const Key('retry_ai_suggestion_button'));
    await tester.scrollUntilVisible(
      retry,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('Bộ đồ phù hợp'), findsOneWidget);
    expect(find.textContaining('Điểm phối màu tham khảo'), findsNothing);
    expect(
      find.text('Chưa có dữ liệu thời tiết cho gợi ý này.'),
      findsOneWidget,
    );
    expect(gemini.lastContext?.items, isEmpty);
    expect(gemini.lastContext?.weather, isNull);
    final chat = find.byKey(const Key('open_outfit_chat_button'));
    await tester.scrollUntilVisible(
      chat,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(chat);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat_message_field')),
      'Nếu trời mưa thì thay giày nào?',
    );
    await tester.tap(find.byKey(const Key('chat_send_button')));
    await tester.pumpAndSettle();
    expect(find.text('Nếu mưa, chọn giày đế bám.'), findsOneWidget);
    expect(gemini.lastHistoryLength, 0);
    expect(gemini.lastContext?.gender, BodyGender.male);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual mode gets AI advice without a photo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gemini = _Gemini()..failFirst = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitSuggestionScreen(
          profileStore: _Store(),
          initialSeason: 'summer',
          initialTemperatureC: '32',
          weatherService: _Weather(),
          locationService: _Location(),
          geminiService: gemini,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hè'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate_suggestion_button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('generate_suggestion_button')));
    await tester.pumpAndSettle();
    expect(find.text('Gợi ý từ Gemini'), findsOneWidget);
    expect(gemini.lastContext?.items, isEmpty);
    expect(gemini.lastContext?.heightCm, 170);
    expect(gemini.lastContext?.weightKg, 70);
    expect(gemini.lastContext?.gender, BodyGender.male);
    expect(gemini.lastContext?.temperatureC, 32);
    await tester.tap(find.byKey(const Key('generate_suggestion_button')));
    await tester.pumpAndSettle();
    expect(gemini.suggestCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather mode uses Open-Meteo data and shows attribution', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gemini = _Gemini()..failFirst = false;
    final contexts = <GeminiOutfitContext>[];
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitSuggestionScreen(
          profileStore: _Store(),
          initialSeason: 'summer',
          initialTemperatureC: '32',
          weatherService: _Weather(),
          locationService: _Location(),
          geminiService: gemini,
          onContextChanged: contexts.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thời tiết hiện tại'));
    await tester.pumpAndSettle();
    expect(find.text('30°C'), findsOneWidget);
    expect(find.text('Dữ liệu thời tiết: Open-Meteo'), findsOneWidget);
    expect(find.byKey(const Key('suggestion_season_summer')), findsNothing);
    expect(find.byKey(const Key('suggestion_temperature_field')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('suggestion_style_dropdown')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('suggestion_style_dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggestion_style_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thanh lịch').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('suggestion_occasion_dropdown')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('suggestion_occasion_dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggestion_occasion_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đi làm').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate_suggestion_button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('generate_suggestion_button')));
    await tester.pumpAndSettle();
    expect(find.text('Gợi ý từ Gemini'), findsOneWidget);
    expect(gemini.lastContext?.items, isEmpty);
    expect(gemini.lastContext?.weather?.temperatureC, 30);
    expect(gemini.lastContext?.season, isNull);
    expect(gemini.lastContext?.temperatureC, 30);
    expect(gemini.lastContext?.style, 'elegant');
    expect(gemini.lastContext?.occasion, 'work');
    expect(contexts.last.style, 'elegant');
    expect(contexts.last.occasion, 'work');
    expect(contexts.last.season, isNull);
    await tester.scrollUntilVisible(
      find.text('Thủ công'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Thủ công'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thủ công'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate_suggestion_button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('generate_suggestion_button')));
    await tester.pumpAndSettle();
    expect(gemini.lastContext?.weather, isNull);
    expect(gemini.lastContext?.season, 'summer');
    expect(gemini.lastContext?.temperatureC, 32);
    expect(gemini.lastContext?.style, 'elegant');
    expect(gemini.lastContext?.occasion, 'work');
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied location can fall back to a chosen city', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitSuggestionScreen(
          profileStore: _Store(),
          initialSeason: 'summer',
          initialTemperatureC: '32',
          weatherService: _Weather(),
          locationService: _DeniedLocation(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thời tiết hiện tại'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('chưa cấp quyền vị trí'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('chưa cấp quyền vị trí'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('weather_city_dropdown')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('weather_city_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đà Nẵng').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('load_city_weather_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Thời tiết: Đà Nẵng'), findsOneWidget);
    expect(find.text('30°C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores a late weather response after switching to manual', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final delayed = _DelayedWeather();
    final changes = <WeatherSnapshot?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitSuggestionScreen(
          profileStore: _Store(),
          initialSeason: 'summer',
          initialTemperatureC: '28',
          weatherService: delayed,
          locationService: _Location(),
          onWeatherChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thời tiết hiện tại'));
    await tester.pump();
    await tester.tap(find.text('Thủ công'));
    await tester.pump();
    delayed.completer.complete(
      await _Weather().currentAt(const CurrentLocation(16.1, 108.2)),
    );
    await tester.pumpAndSettle();
    expect(changes.whereType<WeatherSnapshot>(), isEmpty);
    expect(find.text('Chỉnh thủ công'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
