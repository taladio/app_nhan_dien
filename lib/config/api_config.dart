/// Quản lý tập trung địa chỉ FastAPI cho mọi nền tảng.
abstract final class ApiConfig {
  // Địa chỉ Wi-Fi của máy chạy FastAPI khi phát triển bằng điện thoại thật.
  // Đổi mạng: sửa IP tại đây, lưu, Stop rồi Run lại main.dart trong Android Studio.
  // Backend tự chạy trước app; luôn nhận kết nối ở 0.0.0.0:8000.
  // API_BASE_URL chỉ ghi đè giá trị này khi chủ động truyền --dart-define.
  static const String localWifiBaseUrl = 'http://172.16.15.143:8000';

  static const String _environmentBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: localWifiBaseUrl,
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

  static Uri weatherCurrentUri({String? baseUrlOverride}) {
    final base = Uri.tryParse(normalizeBaseUrl(baseUrlOverride ?? baseUrl));
    if (base == null ||
        !base.hasScheme ||
        base.host.isEmpty ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw const FormatException('Địa chỉ máy chủ không hợp lệ.');
    }
    return base.replace(
      path: '${base.path}/api/v1/weather/current'.replaceAll('//', '/'),
    );
  }

  static Uri geminiSuggestionUri({String? baseUrlOverride}) =>
      _outfitUri('/api/v1/outfit/suggest', baseUrlOverride);

  static Uri geminiChatUri({String? baseUrlOverride}) =>
      _outfitUri('/api/v1/outfit/chat', baseUrlOverride);

  static Uri garmentCutoutUri({String? baseUrlOverride}) =>
      _outfitUri('/api/v1/try-on/cutout', baseUrlOverride);

  static Uri _outfitUri(String path, String? baseUrlOverride) {
    final base = Uri.tryParse(normalizeBaseUrl(baseUrlOverride ?? baseUrl));
    if (base == null ||
        !base.hasScheme ||
        base.host.isEmpty ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw const FormatException('Địa chỉ máy chủ không hợp lệ.');
    }
    return base.replace(path: '${base.path}$path'.replaceAll('//', '/'));
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
