import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as image_lib;

import '../config/api_config.dart';
import '../models/outfit_analysis_result.dart';

const int maxAnalysisImageBytes = 10 * 1024 * 1024;

class PreparedAnalysisImage {
  const PreparedAnalysisImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

abstract interface class OutfitAnalysisServiceContract {
  Future<OutfitAnalysisResult> analyze({
    required PreparedAnalysisImage image,
    required double heightCm,
    required double weightKg,
    required String season,
    required double temperatureC,
    required String style,
    required String occasion,
    required double confidence,
  });

  void close();
}

class OutfitAnalysisException implements Exception {
  const OutfitAnalysisException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

PreparedAnalysisImage prepareAnalysisImage({
  required Uint8List bytes,
  required String filename,
}) {
  if (bytes.isEmpty) {
    throw const OutfitAnalysisException('Ảnh đã chọn không có dữ liệu.');
  }

  final mimeType = _analysisMimeFromSignature(bytes);
  if (mimeType == null) {
    throw const OutfitAnalysisException(
      'Chỉ chấp nhận ảnh JPG, JPEG hoặc PNG.',
    );
  }

  final safeFilename = _safeFilename(filename, mimeType);
  if (bytes.length <= maxAnalysisImageBytes) {
    return PreparedAnalysisImage(
      bytes: bytes,
      filename: safeFilename,
      mimeType: mimeType,
    );
  }

  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) {
    throw const OutfitAnalysisException('Không thể đọc ảnh đã chọn.');
  }

  image_lib.Image working = decoded;
  const maxDimension = 1920;
  if (working.width > maxDimension || working.height > maxDimension) {
    if (working.width >= working.height) {
      working = image_lib.copyResize(working, width: maxDimension);
    } else {
      working = image_lib.copyResize(working, height: maxDimension);
    }
  }

  for (final quality in <int>[82, 72, 62, 52]) {
    final encoded = Uint8List.fromList(
      image_lib.encodeJpg(working, quality: quality),
    );
    if (encoded.length <= maxAnalysisImageBytes) {
      return PreparedAnalysisImage(
        bytes: encoded,
        filename: _replaceExtension(safeFilename, '.jpg'),
        mimeType: 'image/jpeg',
      );
    }
  }

  working = image_lib.copyResize(
    working,
    width: working.width >= working.height ? 1280 : null,
    height: working.height > working.width ? 1280 : null,
  );
  final encoded = Uint8List.fromList(image_lib.encodeJpg(working, quality: 52));
  if (encoded.length > maxAnalysisImageBytes) {
    throw const OutfitAnalysisException(
      'Ảnh vẫn lớn hơn 10 MB sau khi nén. Vui lòng chọn ảnh khác.',
    );
  }
  return PreparedAnalysisImage(
    bytes: encoded,
    filename: _replaceExtension(safeFilename, '.jpg'),
    mimeType: 'image/jpeg',
  );
}

class OutfitAnalysisService implements OutfitAnalysisServiceContract {
  OutfitAnalysisService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 75),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseUrl = ApiConfig.normalizeBaseUrl(baseUrl ?? ApiConfig.baseUrl);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<OutfitAnalysisResult> analyze({
    required PreparedAnalysisImage image,
    required double heightCm,
    required double weightKg,
    required String season,
    required double temperatureC,
    required String style,
    required String occasion,
    required double confidence,
  }) async {
    if (image.bytes.isEmpty || image.bytes.length > maxAnalysisImageBytes) {
      throw const OutfitAnalysisException(
        'Ảnh gửi lên phải nhỏ hơn hoặc bằng 10 MB.',
      );
    }
    if (!heightCm.isFinite || heightCm <= 0 || heightCm > 300) {
      throw const OutfitAnalysisException('Chiều cao không hợp lệ.');
    }
    if (!weightKg.isFinite || weightKg <= 0 || weightKg > 500) {
      throw const OutfitAnalysisException('Cân nặng không hợp lệ.');
    }
    if (!temperatureC.isFinite || temperatureC < -100 || temperatureC > 100) {
      throw const OutfitAnalysisException('Nhiệt độ không hợp lệ.');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const OutfitAnalysisException('Ngưỡng tin cậy không hợp lệ.');
    }

    final Uri uri;
    try {
      uri = ApiConfig.outfitAnalysisUri(baseUrlOverride: _baseUrl);
    } on FormatException {
      throw const OutfitAnalysisException('Địa chỉ máy chủ không hợp lệ.');
    }

    final mediaParts = image.mimeType.split('/');
    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll(<String, String>{
        'height_cm': heightCm.toString(),
        'weight_kg': weightKg.toString(),
        'season': season,
        'temperature_c': temperatureC.toString(),
        'style': style,
        'occasion': occasion,
        'confidence': confidence.toStringAsFixed(2),
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          image.bytes,
          filename: image.filename,
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
      throw const OutfitAnalysisException(
        'Phân tích mất quá nhiều thời gian. Vui lòng thử lại.',
      );
    } on http.ClientException {
      throw const OutfitAnalysisException(
        'Không thể kết nối backend. Hãy kiểm tra máy chủ và mạng.',
      );
    } catch (_) {
      throw const OutfitAnalysisException(
        'Không thể kết nối backend. Hãy kiểm tra máy chủ và mạng.',
      );
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw OutfitAnalysisException(
        _errorMessage(response.statusCode, body),
        statusCode: response.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException();
      return OutfitAnalysisResult.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      throw const OutfitAnalysisException(
        'Backend trả về kết quả không đúng cấu trúc.',
      );
    } catch (_) {
      throw const OutfitAnalysisException('Không thể đọc kết quả phân tích.');
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

String? _analysisMimeFromSignature(Uint8List bytes) {
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
  return null;
}

String _safeFilename(String filename, String mimeType) {
  final parts = filename.trim().split(RegExp(r'[\\/]'));
  final name = parts.isEmpty ? '' : parts.last.trim();
  if (name.isNotEmpty) return name;
  return mimeType == 'image/png' ? 'outfit.png' : 'outfit.jpg';
}

String _replaceExtension(String filename, String extension) {
  final dot = filename.lastIndexOf('.');
  final stem = dot > 0 ? filename.substring(0, dot) : filename;
  return '$stem$extension';
}

String _errorMessage(int statusCode, String body) {
  String? detail;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['detail'] is String) {
      detail = (decoded['detail'] as String).trim();
    }
  } catch (_) {
    detail = null;
  }
  return switch (statusCode) {
    400 || 422 =>
      detail?.isNotEmpty == true
          ? detail!
          : 'Ảnh hoặc thông tin nhập chưa hợp lệ.',
    503 =>
      detail?.isNotEmpty == true
          ? detail!
          : 'Mô hình YOLO chưa sẵn sàng trên backend.',
    500 => 'Backend gặp lỗi khi phân tích ảnh. Vui lòng thử lại.',
    _ =>
      detail?.isNotEmpty == true
          ? detail!
          : 'Không thể phân tích trang phục. Vui lòng thử lại.',
  };
}
