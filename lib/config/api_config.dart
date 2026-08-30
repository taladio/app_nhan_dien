import 'package:flutter/foundation.dart';

/// Quản lý tập trung địa chỉ FastAPI cho mọi nền tảng.
abstract final class ApiConfig {
  static const String _environmentBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static String get baseUrl {
    final configuredUrl = _environmentBaseUrl.trim();
    if (configuredUrl.isNotEmpty) {
      return normalizeBaseUrl(configuredUrl);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static String normalizeBaseUrl(String value) {
    var normalized = value.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static Uri detectionUri({
    String? baseUrlOverride,
    required double confidence,
    required double iou,
  }) {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrlOverride ?? baseUrl);
    final parsedBaseUrl = Uri.tryParse(normalizedBaseUrl);
    if (parsedBaseUrl == null ||
        !parsedBaseUrl.hasScheme ||
        parsedBaseUrl.host.isEmpty ||
        (parsedBaseUrl.scheme != 'http' && parsedBaseUrl.scheme != 'https')) {
      throw const FormatException('Địa chỉ máy chủ không hợp lệ.');
    }

    return Uri.parse('$normalizedBaseUrl/api/v1/detect').replace(
      queryParameters: <String, String>{
        'confidence': confidence.toStringAsFixed(2),
        'iou': iou.toStringAsFixed(2),
      },
    );
  }
}
