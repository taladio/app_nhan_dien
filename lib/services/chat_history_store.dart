import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/gemini_fashion.dart';

/// Text only, scoped to the signed-in account. No photos or location are saved.
class ChatHistory {
  const ChatHistory({
    this.turns = const [],
    this.draft = '',
    this.pendingMessage,
  });

  static const maxTurns = 200;
  final List<GeminiChatTurn> turns;
  final String draft;
  final String? pendingMessage;

  Map<String, Object?> toJson() => {
    'turns': turns
        .skip((turns.length - maxTurns).clamp(0, turns.length))
        .map((turn) => turn.toJson())
        .toList(),
    'draft': draft,
    'pending': pendingMessage,
  };

  factory ChatHistory.fromJson(Object? value) {
    if (value is! Map || value['turns'] is! List) {
      throw const FormatException('Invalid chat history');
    }
    final raw = value['turns'] as List;
    final turns = <GeminiChatTurn>[];
    // Only restore complete user/assistant pairs, never arbitrary roles.
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final user = raw[i];
      final assistant = raw[i + 1];
      if (user is! Map ||
          assistant is! Map ||
          user['role'] != 'user' ||
          assistant['role'] != 'assistant') {
        continue;
      }
      final question = user['content'];
      final reply = assistant['content'];
      if (question is! String ||
          reply is! String ||
          question.trim().isEmpty ||
          question.length > 500 ||
          reply.trim().isEmpty ||
          reply.length > 12000) {
        continue;
      }
      turns.add(GeminiChatTurn(role: 'user', content: question));
      turns.add(GeminiChatTurn(role: 'assistant', content: reply));
    }
    String safeInput(Object? input) =>
        input is String && input.length <= 500 ? input : '';
    final pending = safeInput(value['pending']);
    return ChatHistory(
      turns: turns
          .skip((turns.length - maxTurns).clamp(0, turns.length))
          .toList(),
      draft: safeInput(value['draft']),
      pendingMessage: pending.trim().isEmpty ? null : pending,
    );
  }
}

abstract interface class ChatHistoryStore {
  Future<ChatHistory> load();
  Future<void> save(ChatHistory history);
}

class SharedPreferencesChatHistoryStore implements ChatHistoryStore {
  SharedPreferencesChatHistoryStore(String userId)
    : _key = 'outfit_chat_v1_$userId';

  final String _key;

  @override
  Future<ChatHistory> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return const ChatHistory();
    return ChatHistory.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> save(ChatHistory history) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key,
      jsonEncode(history.toJson()),
    );
    if (!saved) throw StateError('Không thể lưu hội thoại.');
  }
}
