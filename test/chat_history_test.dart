import 'package:app_nhan_dien/models/gemini_fashion.dart';
import 'package:app_nhan_dien/screens/outfit_chat_screen.dart';
import 'package:app_nhan_dien/services/chat_history_store.dart';
import 'package:app_nhan_dien/services/gemini_fashion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AI implements GeminiFashionServiceContract {
  int calls = 0;
  List<GeminiChatTurn> history = [];
  bool fail = false;
  @override
  Future<String> chat(
    GeminiOutfitContext context,
    String message,
    List<GeminiChatTurn> previous,
  ) async {
    calls++;
    history = previous;
    if (fail) throw const GeminiFashionException('Mất kết nối.');
    return 'Phối áo sơ mi với quần dài.';
  }

  @override
  Future<GeminiSuggestion> suggest(GeminiOutfitContext context) =>
      throw UnimplementedError();
  @override
  void close() {}
}

class _FailingStore implements ChatHistoryStore {
  bool failRead = true;
  bool failWrite = false;
  ChatHistory saved = const ChatHistory();
  @override
  Future<ChatHistory> load() async {
    if (failRead) throw StateError('unavailable');
    return saved;
  }

  @override
  Future<void> save(ChatHistory value) async {
    if (failWrite) throw StateError('full');
    saved = value;
  }
}

Future<void> _mount(WidgetTester tester, ChatHistoryStore store, _AI ai) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OutfitChatScreen(
        contextData: GeminiOutfitContext(items: const [], style: 'casual'),
        historyStore: store,
        service: ai,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String message) async {
  await tester.enterText(find.byKey(const Key('chat_message_field')), message);
  await tester.tap(find.byKey(const Key('chat_send_button')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'history is bounded, restores text and is isolated per account',
    () async {
      final a = SharedPreferencesChatHistoryStore('a');
      final turns = <GeminiChatTurn>[
        for (var i = 0; i < 130; i++) ...[
          GeminiChatTurn(role: 'user', content: 'Question $i'),
          GeminiChatTurn(role: 'assistant', content: 'Reply $i'),
        ],
      ];
      await a.save(
        ChatHistory(turns: turns, draft: 'Bản nháp', pendingMessage: 'Giày?'),
      );
      final restored = await SharedPreferencesChatHistoryStore('a').load();
      expect(restored.turns, hasLength(200));
      expect(restored.turns.first.content, 'Question 30');
      expect(restored.draft, 'Bản nháp');
      expect(restored.pendingMessage, 'Giày?');
      expect(
        (await SharedPreferencesChatHistoryStore('b').load()).turns,
        isEmpty,
      );
      final parsed = ChatHistory.fromJson({
        'turns': [
          {'role': 'system', 'content': 'not allowed'},
          {'role': 'assistant', 'content': 'reply'},
        ],
      });
      expect(parsed.turns, isEmpty);
    },
  );

  testWidgets('restart restores conversation and draft without calling AI', (
    tester,
  ) async {
    final ai = _AI();
    final store = SharedPreferencesChatHistoryStore('a');
    await _mount(tester, store, ai);
    await _send(tester, 'Hôm nay mặc gì?');
    await tester.enterText(
      find.byKey(const Key('chat_message_field')),
      'Còn giày?',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _mount(tester, SharedPreferencesChatHistoryStore('a'), ai);
    expect(find.text('Hôm nay mặc gì?'), findsOneWidget);
    expect(find.text('Phối áo sơ mi với quần dài.'), findsOneWidget);
    expect(find.text('Còn giày?'), findsOneWidget);
    expect(ai.calls, 1);
    await tester.tap(find.byKey(const Key('chat_send_button')));
    await tester.pumpAndSettle();
    expect(ai.history.map((turn) => turn.role), ['user', 'assistant']);
  });

  testWidgets(
    'failed question survives restart and retries without duplicates',
    (tester) async {
      final ai = _AI()..fail = true;
      final store = SharedPreferencesChatHistoryStore('a');
      await _mount(tester, store, ai);
      await _send(tester, 'Chọn giày nào?');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      ai.fail = false;
      await _mount(tester, store, ai);
      expect(ai.calls, 1);
      expect(find.textContaining('Câu hỏi trước'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat_retry_button')));
      await tester.pumpAndSettle();
      final saved = await store.load();
      expect(saved.turns, hasLength(2));
      expect(saved.pendingMessage, isNull);
      expect(ai.history, isEmpty);
      expect(find.text('Chọn giày nào?'), findsOneWidget);
    },
  );

  testWidgets('new conversation clears persisted history after confirmation', (
    tester,
  ) async {
    final store = SharedPreferencesChatHistoryStore('a');
    final ai = _AI();
    await _mount(tester, store, ai);
    await _send(tester, 'Áo nào?');
    await tester.tap(find.byKey(const Key('chat_new_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect((await store.load()).turns, hasLength(2));
    await tester.tap(find.byKey(const Key('chat_new_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa và bắt đầu'));
    await tester.pumpAndSettle();
    expect((await store.load()).turns, isEmpty);
    expect(ai.calls, 1);
  });

  testWidgets('storage failures are visible and retry preserves conversation', (
    tester,
  ) async {
    final store = _FailingStore();
    final ai = _AI();
    await _mount(tester, store, ai);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_message_field')))
          .enabled,
      false,
    );
    store.failRead = false;
    store.failWrite = true;
    await tester.tap(find.text('Tải lại'));
    await tester.pumpAndSettle();
    await _send(tester, 'Áo nào?');
    expect(find.textContaining('Chưa lưu được'), findsOneWidget);
    store.failWrite = false;
    await tester.tap(find.text('Lưu lại'));
    await tester.pumpAndSettle();
    expect(store.saved.turns, hasLength(2));
    expect(find.textContaining('Chưa lưu được'), findsNothing);
  });

  testWidgets('new replies scroll into view and only six turns go to AI', (
    tester,
  ) async {
    final ai = _AI();
    await _mount(tester, SharedPreferencesChatHistoryStore('a'), ai);
    for (var i = 0; i < 9; i++) {
      await _send(tester, 'Câu hỏi số $i về bộ đồ hôm nay');
    }
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
    expect(ai.history, hasLength(6));
  });
}
