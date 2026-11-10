import 'dart:async';

import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/models/gemini_fashion.dart';
import 'package:app_nhan_dien/models/outfit_flow_context.dart';
import 'package:app_nhan_dien/screens/outfit_analysis_screen.dart';
import 'package:app_nhan_dien/screens/outfit_chat_screen.dart';
import 'package:app_nhan_dien/screens/outfit_suggestion_screen.dart';
import 'package:app_nhan_dien/screens/personal_info_screen.dart';
import 'package:app_nhan_dien/services/body_profile_store.dart';
import 'package:app_nhan_dien/services/gemini_fashion_service.dart';
import 'package:app_nhan_dien/widgets/app_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileStore implements BodyProfileStore {
  BodyProfileCollection value = const BodyProfileCollection();

  @override
  Future<BodyProfileCollection> load() async => value;

  @override
  Future<void> save(BodyProfileCollection collection) async {
    value = collection;
  }
}

class _ChatService implements GeminiFashionServiceContract {
  final messages = <String>[];
  final histories = <List<GeminiChatTurn>>[];
  final contexts = <GeminiOutfitContext>[];
  Completer<String>? response;

  @override
  Future<String> chat(
    GeminiOutfitContext context,
    String message,
    List<GeminiChatTurn> history,
  ) async {
    contexts.add(context);
    messages.add(message);
    histories.add(List.of(history));
    return response == null ? 'Gợi ý ${messages.length}' : response!.future;
  }

  @override
  Future<GeminiSuggestion> suggest(GeminiOutfitContext context) async =>
      throw UnimplementedError();

  @override
  void close() {}
}

Future<void> _openChat(WidgetTester tester, _ChatService service) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: AppHome(
        profileStore: _ProfileStore(),
        accountName: 'Khang',
        accountEmail: 'khang@example.com',
        onChangePassword: (_, _) async {},
        onSignOut: () async {},
        chatService: service,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Hỏi đáp').last);
  await tester.pumpAndSettle();
}

Future<void> _sendQuestion(WidgetTester tester, String message) async {
  await tester.enterText(find.byKey(const Key('chat_message_field')), message);
  await tester.tap(find.byKey(const Key('chat_send_button')));
  // Không pumpAndSettle: một số bài kiểm tra giữ request đang chờ trả lời.
  await tester.pump();
}

void main() {
  testWidgets(
    'selecting profile from a camera route updates all existing tabs without resetting style',
    (tester) async {
      final service = _ChatService();
      await _openChat(tester, service);
      await tester.tap(find.text('Cá nhân').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gợi ý').last);
      await tester.pumpAndSettle();
      final style = find.byKey(const Key('suggestion_style_dropdown'));
      await tester.scrollUntilVisible(
        style,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(style);
      await tester.pumpAndSettle();
      await tester.tap(style);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thanh lịch').last);
      await tester.pumpAndSettle();
      final suggestion = tester.widget<OutfitSuggestionScreen>(
        find.byType(OutfitSuggestionScreen),
      );
      await suggestion.profileStore.save(
        const BodyProfileCollection(
          profiles: [
            BodyProfile(
              id: 'b',
              name: 'Hồ sơ B',
              heightCm: 165,
              weightKg: 55,
              gender: BodyGender.female,
            ),
          ],
          selectedId: 'b',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cá nhân').last);
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ B'), findsOneWidget);
      await tester.tap(find.text('Hỏi đáp').last);
      await tester.pumpAndSettle();
      await _sendQuestion(tester, 'Mặc gì?');
      await tester.pumpAndSettle();
      expect(service.contexts.last.heightCm, 165);
      expect(service.contexts.last.gender, BodyGender.female);
      expect(service.contexts.last.style, 'elegant');
      await tester.tap(find.text('Gợi ý').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutfitSuggestionScreen>(find.byType(OutfitSuggestionScreen))
            .key,
        suggestion.key,
      );
      await tester.tap(find.text('Phân tích').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile_dropdown_b')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('history and draft survive suggestion and analysis updates', (
    tester,
  ) async {
    final service = _ChatService();
    await _openChat(tester, service);
    await _sendQuestion(tester, 'Hôm nay nên mặc gì?');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat_message_field')),
      'Thế còn giày?',
    );

    // Mở tab Gợi ý lần đầu sẽ tải hồ sơ và phát onContextChanged.
    await tester.tap(find.text('Gợi ý').last);
    await tester.pumpAndSettle();
    tester
        .widget<OutfitSuggestionScreen>(find.byType(OutfitSuggestionScreen))
        .onContextChanged!(
      GeminiOutfitContext(items: [], style: 'elegant', occasion: 'work'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    expect(find.text('Hôm nay nên mặc gì?'), findsOneWidget);
    expect(find.text('Gợi ý 1'), findsOneWidget);
    expect(find.text('Thế còn giày?'), findsOneWidget);
    expect(service.messages, hasLength(1));

    await tester.tap(find.byKey(const Key('chat_send_button')));
    await tester.pumpAndSettle();
    expect(service.contexts.last.style, 'elegant');
    expect(service.contexts.last.occasion, 'work');
    expect(service.histories.last.map((turn) => turn.content), [
      'Hôm nay nên mặc gì?',
      'Gợi ý 1',
    ]);

    await tester.tap(find.text('Phân tích').last);
    await tester.pumpAndSettle();
    tester
        .widget<OutfitAnalysisScreen>(find.byType(OutfitAnalysisScreen))
        .onAnalysisCompleted!(const OutfitFlowContext(temperature: '19'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    expect(find.text('Hôm nay nên mặc gì?'), findsOneWidget);
    expect(find.text('Gợi ý 2'), findsOneWidget);
    expect(service.messages, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reply arrives after leaving tab and changing profile', (
    tester,
  ) async {
    final service = _ChatService()..response = Completer<String>();
    await _openChat(tester, service);
    await _sendQuestion(tester, 'Tôi nên chọn áo nào?');
    await tester.tap(find.text('Cá nhân').last);
    // Request vẫn đang chờ; thanh tiến trình tiếp tục chạy trong IndexedStack.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    const profiles = BodyProfileCollection(
      profiles: [
        BodyProfile(
          id: 'updated',
          name: 'Hồ sơ mới',
          heightCm: 170,
          weightKg: 65,
          gender: BodyGender.male,
        ),
      ],
      selectedId: 'updated',
    );
    final personal = tester.widget<PersonalInfoScreen>(
      find.byType(PersonalInfoScreen),
    );
    await personal.profileStore.save(profiles);
    personal.onProfilesChanged!(profiles);
    await tester.pump();
    service.response!.complete('Áo sơ mi xanh nhạt.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    expect(find.text('Tôi nên chọn áo nào?'), findsOneWidget);
    expect(find.text('Áo sơ mi xanh nhạt.'), findsOneWidget);

    service.response = null;
    await _sendQuestion(tester, 'Phối cùng quần nào?');
    await tester.pumpAndSettle();
    expect(service.contexts.last.gender, BodyGender.male);
    expect(service.contexts.last.heightCm, 170);
    expect(service.histories.last.map((turn) => turn.content), [
      'Tôi nên chọn áo nào?',
      'Áo sơ mi xanh nhạt.',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed request can be retried after changing tabs', (
    tester,
  ) async {
    final service = _ChatService()..response = Completer<String>();
    await _openChat(tester, service);
    await _sendQuestion(tester, 'Nếu trời mưa thì sao?');
    service.response!.completeError(
      const GeminiFashionException('Tạm mất kết nối.'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gợi ý').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    expect(find.text('Tạm mất kết nối.'), findsOneWidget);
    service.response = null;
    await tester.tap(find.byKey(const Key('chat_retry_button')));
    await tester.pumpAndSettle();
    expect(service.messages, [
      'Nếu trời mưa thì sao?',
      'Nếu trời mưa thì sao?',
    ]);
    expect(service.histories.last, isEmpty);
    expect(find.text('Nếu trời mưa thì sao?'), findsOneWidget);
    expect(find.text('Gợi ý 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps older messages while bounding history sent to AI', (
    tester,
  ) async {
    final service = _ChatService();
    await _openChat(tester, service);
    for (var index = 1; index <= 8; index++) {
      await _sendQuestion(tester, 'Câu hỏi $index');
      await tester.pumpAndSettle();
    }
    // New replies scroll to the bottom; older messages remain available above.
    await tester.drag(find.byType(ListView).first, const Offset(0, 1800));
    await tester.pumpAndSettle();
    expect(find.text('Câu hỏi 1'), findsOneWidget);
    expect(find.text('Gợi ý 1'), findsOneWidget);
    expect(service.histories.last, hasLength(6));
    expect(service.histories.last.first.content, 'Câu hỏi 5');
    expect(service.histories.last.last.content, 'Gợi ý 7');
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a different gender updates existing chat context', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _ProfileStore()
      ..value = const BodyProfileCollection(
        profiles: [
          BodyProfile(
            id: 'a',
            name: 'A',
            heightCm: 170,
            weightKg: 65,
            gender: BodyGender.male,
          ),
        ],
        selectedId: 'a',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AppHome(
          profileStore: store,
          accountName: 'Khang',
          accountEmail: 'khang@example.com',
          onChangePassword: (_, _) async {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gợi ý').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutfitChatScreen>(find.byType(OutfitChatScreen))
          .contextData
          .gender,
      BodyGender.male,
    );
    await tester.tap(find.text('Cá nhân').last);
    await tester.pumpAndSettle();
    final updated = store.value.upsert(
      store.value.selected!.copyWith(gender: BodyGender.female),
    );
    await store.save(updated);
    tester
        .widget<PersonalInfoScreen>(find.byType(PersonalInfoScreen))
        .onProfilesChanged!(updated);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutfitChatScreen>(find.byType(OutfitChatScreen))
          .contextData
          .gender,
      BodyGender.female,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom tabs open no-photo advice, chatbot and profile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AppHome(
          profileStore: _ProfileStore(),
          accountName: 'Khang',
          accountEmail: 'khang@example.com',
          onChangePassword: (_, _) async {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Gợi ý').last);
    await tester.pumpAndSettle();
    expect(find.text('Một bộ đồ hợp với hôm nay'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate_suggestion_button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('generate_suggestion_button')), findsOneWidget);

    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    expect(find.text('Hỏi đáp phối đồ'), findsOneWidget);
    expect(find.textContaining('chưa chụp ảnh'), findsOneWidget);

    await tester.tap(find.text('Cá nhân').last);
    await tester.pumpAndSettle();
    expect(find.text('khang@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat tab receives style and occasion chosen in suggestion tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AppHome(
          profileStore: _ProfileStore(),
          accountName: 'Khang',
          accountEmail: 'khang@example.com',
          onChangePassword: (_, _) async {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gợi ý').last);
    await tester.pumpAndSettle();
    final style = find.byKey(const Key('suggestion_style_dropdown'));
    await tester.scrollUntilVisible(
      style,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(style);
    await tester.pumpAndSettle();
    await tester.tap(style);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thanh lịch').last);
    await tester.pumpAndSettle();
    final occasion = find.byKey(const Key('suggestion_occasion_dropdown'));
    await tester.scrollUntilVisible(
      occasion,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(occasion);
    await tester.pumpAndSettle();
    await tester.tap(occasion);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đi làm').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hỏi đáp').last);
    await tester.pumpAndSettle();
    final chat = tester.widget<OutfitChatScreen>(find.byType(OutfitChatScreen));
    expect(chat.contextData.style, 'elegant');
    expect(chat.contextData.occasion, 'work');
    expect(tester.takeException(), isNull);
  });
}
