/// Quản lý tập trung địa chỉ FastAPI cho mọi nền tảng.
abstract final class ApiConfig {
  static const String _environmentBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static String get baseUrl => normalizeBaseUrl(_environmentBaseUrl);

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

  static Uri outfitAnalysisUri({String? baseUrlOverride}) {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrlOverride ?? baseUrl);
    final parsedBaseUrl = Uri.tryParse(normalizedBaseUrl);
    if (parsedBaseUrl == null ||
        !parsedBaseUrl.hasScheme ||
        parsedBaseUrl.host.isEmpty ||
        (parsedBaseUrl.scheme != 'http' && parsedBaseUrl.scheme != 'https')) {
      throw const FormatException('Địa chỉ máy chủ không hợp lệ.');
    }
    return Uri.parse('$normalizedBaseUrl/api/v1/outfit/analyze');
  }

  static Uri poseWebSocketUri({String? baseUrlOverride}) {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrlOverride ?? baseUrl);
    final parsedBaseUrl = Uri.tryParse(normalizedBaseUrl);
    if (parsedBaseUrl == null ||
        !parsedBaseUrl.hasScheme ||
        parsedBaseUrl.host.isEmpty ||
        (parsedBaseUrl.scheme != 'http' && parsedBaseUrl.scheme != 'https')) {
      throw const FormatException('Địa chỉ máy chủ không hợp lệ.');
    }
    return parsedBaseUrl.replace(
      scheme: parsedBaseUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '${parsedBaseUrl.path}/api/v1/pose/ws'.replaceAll('//', '/'),
      query: null,
      fragment: null,
    );
  }
}
