import 'dart:convert';
import 'dart:typed_data';

import 'package:app_nhan_dien/services/fashion_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  test('gửi multipart field file, MIME và query đúng', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'filename': 'outfit.png',
          'image_width': 1,
          'image_height': 1,
          'ignored_detection_count': 0,
          'detections': <Object>[],
          'summary': <Object>[],
        }),
        200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final service = FashionApiService(
      client: client,
      baseUrl: 'http://127.0.0.1:8000/',
    );

    final result = await service.detectClothing(
      imageBytes: _pngBytes,
      filename: 'outfit.png',
      confidence: 0.25,
    );

    expect(result.detectionCount, 0);
    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/v1/detect');
    expect(capturedRequest.url.queryParameters['confidence'], '0.25');
    expect(capturedRequest.url.queryParameters['iou'], '0.45');
    expect(
      capturedRequest.headers['content-type'],
      startsWith('multipart/form-data'),
    );
    final multipartBody = latin1.decode(capturedRequest.bodyBytes);
    expect(multipartBody, contains('name="file"'));
    expect(multipartBody, contains('filename="outfit.png"'));
    expect(multipartBody.toLowerCase(), contains('content-type: image/png'));
  });

  test('đọc thông báo detail tiếng Việt khi backend trả 503', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, String>{
            'detail': 'Mô hình chưa sẵn sàng. Hãy đặt best.pt đúng vị trí.',
          }),
        ),
        503,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final service = FashionApiService(
      client: client,
      baseUrl: 'http://127.0.0.1:8000',
    );

    expect(
      () => service.detectClothing(
        imageBytes: _pngBytes,
        filename: 'outfit.png',
        confidence: 0.25,
      ),
      throwsA(
        isA<FashionApiException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.message, 'message', contains('best.pt')),
      ),
    );
  });
}
