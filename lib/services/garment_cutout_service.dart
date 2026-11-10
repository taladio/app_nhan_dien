import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../config/api_config.dart';

class GarmentCutoutException implements Exception {
  const GarmentCutoutException(this.message);
  final String message;
}

class GarmentCutoutService {
  GarmentCutoutService({http.Client? client, this.baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String? baseUrl;

  Future<Uint8List> cutout(Uint8List bytes, Rect crop) async {
    final mime = lookupMimeType('image', headerBytes: bytes);
    if (!{'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
      throw const GarmentCutoutException('Chọn ảnh JPEG, PNG hoặc WebP.');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw const GarmentCutoutException('Ảnh tối đa 10 MB.');
    }
    final request =
        http.MultipartRequest(
            'POST',
            ApiConfig.garmentCutoutUri(baseUrlOverride: baseUrl),
          )
          ..fields.addAll({
            'x': '${crop.left}',
            'y': '${crop.top}',
            'width': '${crop.width}',
            'height': '${crop.height}',
          })
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: 'garment',
              contentType: MediaType.parse(mime!),
            ),
          );
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        String? detail;
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map && body['detail'] is String) detail = body['detail'];
        } catch (_) {}
        throw GarmentCutoutException(
          detail ?? 'Không tách được nền. Hãy thử lại.',
        );
      }
      final result = response.bodyBytes;
      if (lookupMimeType('cutout', headerBytes: result) != 'image/png') {
        throw const GarmentCutoutException('Ảnh tách nền trả về không hợp lệ.');
      }
      return result;
    } on TimeoutException {
      throw const GarmentCutoutException(
        'Tách nền quá lâu. Hãy chọn ảnh nhỏ hơn và thử lại.',
      );
    } on http.ClientException {
      throw const GarmentCutoutException(
        'Không kết nối được máy chủ tách nền. Kiểm tra Wi-Fi và thử lại.',
      );
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
