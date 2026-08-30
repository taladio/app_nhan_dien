import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../config/api_config.dart';
import '../models/detection_result.dart';

abstract interface class FashionDetectionService {
  Future<DetectionResponse> detectClothing({
    required Uint8List imageBytes,
    required String filename,
    required double confidence,
    double iou,
  });

  void close();
}

class FashionApiException implements Exception {
  const FashionApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class FashionApiService implements FashionDetectionService {
  FashionApiService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseUrl = ApiConfig.normalizeBaseUrl(baseUrl ?? ApiConfig.baseUrl);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<DetectionResponse> detectClothing({
    required Uint8List imageBytes,
    required String filename,
    required double confidence,
    double iou = 0.45,
  }) async {
    if (imageBytes.isEmpty) {
      throw const FashionApiException('Ảnh đã chọn không có dữ liệu.');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const FashionApiException('Ngưỡng tin cậy không hợp lệ.');
    }
    if (!iou.isFinite || iou < 0 || iou > 1) {
      throw const FashionApiException('Ngưỡng IoU không hợp lệ.');
    }

    final mimeType = detectSupportedImageMimeType(filename, imageBytes);
    if (mimeType == null) {
      throw const FashionApiException('Chỉ chấp nhận ảnh JPEG, PNG hoặc WebP.');
    }

    final Uri uri;
    try {
      uri = ApiConfig.detectionUri(
        baseUrlOverride: _baseUrl,
        confidence: confidence,
        iou: iou,
      );
    } on FormatException {
      throw const FashionApiException('Địa chỉ máy chủ không hợp lệ.');
    }

    final safeFilename = _safeFilename(filename, mimeType);
    final mediaParts = mimeType.split('/');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: safeFilename,
          contentType: MediaType(mediaParts.first, mediaParts.last),
        ),
      );

    late final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const FashionApiException(
        'Máy chủ phản hồi quá lâu. Vui lòng thử lại.',
      );
    } on http.ClientException {
      throw const FashionApiException('Không thể kết nối đến máy chủ.');
    } catch (_) {
      throw const FashionApiException('Không thể kết nối đến máy chủ.');
    }

    final String responseText;
    try {
      responseText = utf8.decode(response.bodyBytes);
    } on FormatException {
      throw const FashionApiException('Máy chủ trả về dữ liệu không hợp lệ.');
    }

    if (response.statusCode != 200) {
      throw FashionApiException(
        _errorMessageFor(response.statusCode, responseText),
        statusCode: response.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(responseText);
      if (decoded is! Map) {
        throw const FormatException();
      }
      return DetectionResponse.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      throw const FashionApiException('Máy chủ trả về dữ liệu không hợp lệ.');
    } catch (_) {
      throw const FashionApiException('Không thể đọc kết quả nhận diện.');
    }
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

String? detectSupportedImageMimeType(String filename, Uint8List bytes) {
  final signatureMime = _mimeFromSignature(bytes);
  if (signatureMime == null) {
    return null;
  }

  final headerLength = bytes.length < 16 ? bytes.length : 16;
  final headerMime = lookupMimeType(
    'upload',
    headerBytes: bytes.sublist(0, headerLength),
  );
  final filenameMime = lookupMimeType(filename);
  if (headerMime != signatureMime) {
    return null;
  }
  if (filenameMime != null && filenameMime != signatureMime) {
    return null;
  }
  return signatureMime;
}

String? _mimeFromSignature(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

String _safeFilename(String filename, String mimeType) {
  final parts = filename.trim().split(RegExp(r'[\\/]'));
  final safeName = parts.isEmpty ? '' : parts.last;
  if (safeName.isNotEmpty) {
    return safeName;
  }
  return switch (mimeType) {
    'image/png' => 'upload.png',
    'image/webp' => 'upload.webp',
    _ => 'upload.jpg',
  };
}

String _errorMessageFor(int statusCode, String responseBody) {
  final detail = _extractDetail(responseBody);
  switch (statusCode) {
    case 400:
    case 422:
      return detail ?? 'Ảnh hoặc tham số gửi lên không hợp lệ.';
    case 500:
      return 'Máy chủ gặp lỗi khi phân tích ảnh. Vui lòng thử lại.';
    case 503:
      return detail ?? 'Mô hình nhận diện chưa sẵn sàng trên máy chủ.';
    default:
      return detail ?? 'Không thể xử lý yêu cầu. Vui lòng thử lại.';
  }
}

String? _extractDetail(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}
