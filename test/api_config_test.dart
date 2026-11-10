import 'package:app_nhan_dien/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the real phone Wi-Fi backend by default', () {
    expect(ApiConfig.baseUrl, ApiConfig.localWifiBaseUrl);
    final wifiHost = Uri.parse(ApiConfig.localWifiBaseUrl).host;
    expect(ApiConfig.detectionUri(confidence: 0.25, iou: 0.45).host, wifiHost);
    expect(ApiConfig.outfitAnalysisUri().host, wifiHost);
    expect(ApiConfig.weatherCurrentUri().host, wifiHost);
    expect(ApiConfig.geminiSuggestionUri().host, wifiHost);
    expect(ApiConfig.geminiChatUri().host, wifiHost);
    expect(ApiConfig.garmentCutoutUri().host, wifiHost);
    expect(ApiConfig.poseWebSocketUri().host, wifiHost);
  });

  test('converts HTTP API base URL to pose WebSocket URL', () {
    expect(
      ApiConfig.poseWebSocketUri(baseUrlOverride: 'http://10.0.2.2:8000/')
          .toString(),
      'ws://10.0.2.2:8000/api/v1/pose/ws',
    );
  });

  test('converts HTTPS and keeps a base path', () {
    expect(
      ApiConfig.poseWebSocketUri(baseUrlOverride: 'https://example.com/fashion')
          .toString(),
      'wss://example.com/fashion/api/v1/pose/ws',
    );
  });
}
