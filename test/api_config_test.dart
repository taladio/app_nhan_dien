import 'package:app_nhan_dien/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
