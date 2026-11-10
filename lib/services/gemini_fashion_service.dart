import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/gemini_fashion.dart';

class GeminiFashionException implements Exception {
  const GeminiFashionException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class GeminiFashionServiceContract {
  Future<GeminiSuggestion> suggest(GeminiOutfitContext context);
  Future<String> chat(
    GeminiOutfitContext context,
    String message,
    List<GeminiChatTurn> history,
  );
  void close();
}

class GeminiFashionService implements GeminiFashionServiceContract {
  GeminiFashionService({
    http.Client? client,
    this.baseUrl,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String? baseUrl;
  final Duration timeout;

  @override
  Future<GeminiSuggestion> suggest(GeminiOutfitContext context) async {
    final response = await _post(
      ApiConfig.geminiSuggestionUri(baseUrlOverride: baseUrl),
      <String, Object?>{'context': context.toJson()},
    );
    final suggestion = GeminiSuggestion.fromJson(response);
    if (!context.hasColorData && suggestion.colorScore != null) {
      return GeminiSuggestion(
        assessment: suggestion.assessment,
        reason: suggestion.reason,
        adjustments: suggestion.adjustments,
        colorScore: null,
      );
    }
    return suggestion;
  }

  @override
  Future<String> chat(
    GeminiOutfitContext context,
    String message,
    List<GeminiChatTurn> history,
  ) async {
    final response = await _post(
      ApiConfig.geminiChatUri(baseUrlOverride: baseUrl),
      <String, Object?>{
        'context': context.toJson(),
        'message': message,
        'history':
            (history.length <= 6
                    ? history
                    : history.sublist(history.length - 6))
                .map(
                  (turn) => <String, String>{
                    'role': turn.role,
                    'content': turn.content.length <= 500
                        ? turn.content
                        : turn.content.substring(0, 500),
                  },
                )
                .toList(),
      },
    );
    final reply = response['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const GeminiFashionException('Chatbot trả dữ liệu không hợp lệ.');
    }
    return reply;
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, Object?> body) async {
    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw GeminiFashionException(
        'Backend ${uri.host} không phản hồi trong ${timeout.inSeconds} giây. '
        'Hãy kiểm tra backend và IP Wi-Fi rồi thử lại.',
      );
    } on http.ClientException {
      throw const GeminiFashionException(
        'Không kết nối được backend. Kiểm tra USB/Wi-Fi và thử lại.',
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        final detail = decoded is Map ? decoded['detail'] : null;
        throw GeminiFashionException(
          detail is String ? detail : 'Không lấy được tư vấn AI. Hãy thử lại.',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const GeminiFashionException('Dữ liệu AI không hợp lệ.');
      }
      return decoded;
    } on FormatException {
      throw const GeminiFashionException('Dữ liệu AI không hợp lệ.');
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
