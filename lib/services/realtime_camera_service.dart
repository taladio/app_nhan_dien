import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;

@immutable
class RealtimeCameraFrame {
  const RealtimeCameraFrame({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

class RealtimeCameraException implements Exception {
  const RealtimeCameraException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class RealtimeCameraSession {
  bool get isInitialized;

  bool get canSwitchCamera;

  Future<void> initialize();

  Widget buildPreview({Widget? overlay});

  Future<void> startFrameStream({
    required ValueChanged<RealtimeCameraFrame> onFrame,
    required ValueChanged<Object> onError,
  });

  Future<void> stopFrameStream();

  Future<void> switchCamera();

  Future<void> dispose();
}

/// Camera session dùng image stream, không thu âm và không lưu video.
///
/// Chỉ một frame được mã hóa tại một thời điểm. [frameInterval] tiếp tục giới
/// hạn tần suất để điện thoại và backend không bị quá tải.
class PluginRealtimeCameraSession implements RealtimeCameraSession {
  PluginRealtimeCameraSession({
    this.frameInterval = const Duration(milliseconds: 700),
  });

  final Duration frameInterval;

  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _acceptFrames = false;
  bool _isEncoding = false;
  DateTime? _lastEncodedAt;
  int _frameSequence = 0;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  bool get canSwitchCamera => _cameras.length > 1;

  ImageFormatGroup get _preferredImageFormat {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ImageFormatGroup.bgra8888;
    }
    return ImageFormatGroup.yuv420;
  }

  @override
  Future<void> initialize() async {
    try {
      await _disposeController();
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) {
          throw const RealtimeCameraException(
            'Không tìm thấy camera trên thiết bị.',
          );
        }
        final backCameraIndex = _cameras.indexWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = backCameraIndex < 0 ? 0 : backCameraIndex;
      }
      await _createController(_cameraIndex);
    } on CameraException catch (error) {
      throw RealtimeCameraException(_cameraErrorMessage(error));
    }
  }

  Future<void> _createController(int index) async {
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: _preferredImageFormat,
    );
    _controller = controller;
    await controller.initialize();
    try {
      await controller.setFlashMode(FlashMode.off);
    } on CameraException {
      // Một số camera không hỗ trợ điều khiển flash; preview vẫn dùng được.
    }
  }

  @override
  Widget buildPreview({Widget? overlay}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller, child: overlay);
  }

  @override
  Future<void> startFrameStream({
    required ValueChanged<RealtimeCameraFrame> onFrame,
    required ValueChanged<Object> onError,
  }) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const RealtimeCameraException('Camera chưa sẵn sàng.');
    }
    if (controller.value.isStreamingImages) {
      _acceptFrames = true;
      return;
    }

    _acceptFrames = true;
    _lastEncodedAt = null;
    try {
      await controller.startImageStream((cameraImage) {
        final now = DateTime.now();
        final lastEncodedAt = _lastEncodedAt;
        if (!_acceptFrames ||
            _isEncoding ||
            (lastEncodedAt != null &&
                now.difference(lastEncodedAt) < frameInterval)) {
          return;
        }

        _isEncoding = true;
        _lastEncodedAt = now;
        final rawFrame = _copyFrame(
          cameraImage,
          rotationDegrees: _captureRotationDegrees(controller),
        );
        unawaited(
          compute(_encodeCameraFrame, rawFrame)
              .then((bytes) {
                if (_acceptFrames && bytes.isNotEmpty) {
                  _frameSequence += 1;
                  onFrame(
                    RealtimeCameraFrame(
                      bytes: bytes,
                      filename: 'realtime_$_frameSequence.jpg',
                    ),
                  );
                }
              })
              .catchError((Object error) {
                if (_acceptFrames) {
                  onError(error);
                }
              })
              .whenComplete(() => _isEncoding = false),
        );
      });
    } on CameraException catch (error) {
      _acceptFrames = false;
      throw RealtimeCameraException(_cameraErrorMessage(error));
    }
  }

  @override
  Future<void> stopFrameStream() async {
    _acceptFrames = false;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } on CameraException {
        // Camera có thể đã dừng bởi vòng đời hệ điều hành.
      }
    }
  }

  @override
  Future<void> switchCamera() async {
    if (!canSwitchCamera) {
      return;
    }
    await stopFrameStream();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      await _disposeController();
      await _createController(_cameraIndex);
    } on CameraException catch (error) {
      throw RealtimeCameraException(_cameraErrorMessage(error));
    }
  }

  @override
  Future<void> dispose() => _disposeController();

  Future<void> _disposeController() async {
    _acceptFrames = false;
    final controller = _controller;
    _controller = null;
    if (controller == null) {
      return;
    }
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } on CameraException {
        // Tiếp tục giải phóng controller nếu stream đã bị hệ điều hành dừng.
      }
    }
    await controller.dispose();
  }
}

enum _RawCameraFormat { jpeg, bgra8888, yuv420 }

@immutable
class _RawCameraFrame {
  const _RawCameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.rotationDegrees,
  });

  final int width;
  final int height;
  final _RawCameraFormat format;
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
  final int rotationDegrees;
}

_RawCameraFrame _copyFrame(CameraImage frame, {required int rotationDegrees}) {
  final format = switch (frame.format.group) {
    ImageFormatGroup.jpeg => _RawCameraFormat.jpeg,
    ImageFormatGroup.bgra8888 => _RawCameraFormat.bgra8888,
    _ => _RawCameraFormat.yuv420,
  };
  return _RawCameraFrame(
    width: frame.width,
    height: frame.height,
    format: format,
    planes: frame.planes
        .map((plane) => Uint8List.fromList(plane.bytes))
        .toList(growable: false),
    bytesPerRow: frame.planes
        .map((plane) => plane.bytesPerRow)
        .toList(growable: false),
    bytesPerPixel: frame.planes
        .map((plane) => plane.bytesPerPixel ?? 1)
        .toList(growable: false),
    rotationDegrees: rotationDegrees,
  );
}

Uint8List _encodeCameraFrame(_RawCameraFrame frame) {
  image_lib.Image image;
  switch (frame.format) {
    case _RawCameraFormat.jpeg:
      final decoded = image_lib.decodeImage(frame.planes.first);
      if (decoded == null) {
        throw const FormatException('Không thể đọc frame JPEG từ camera.');
      }
      image = decoded;
    case _RawCameraFormat.bgra8888:
      image = _decodeBgra(frame);
    case _RawCameraFormat.yuv420:
      image = _decodeYuv420(frame);
  }

  if (frame.rotationDegrees != 0) {
    image = image_lib.copyRotate(
      image,
      angle: frame.rotationDegrees.toDouble(),
    );
  }

  const maxSide = 640;
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? image_lib.copyResize(image, width: maxSide)
        : image_lib.copyResize(image, height: maxSide);
  }
  return Uint8List.fromList(image_lib.encodeJpg(image, quality: 76));
}

image_lib.Image _decodeBgra(_RawCameraFrame frame) {
  if (frame.planes.isEmpty) {
    throw const FormatException('Frame BGRA không có dữ liệu.');
  }
  final bytes = frame.planes.first;
  final rowStride = frame.bytesPerRow.first;
  final pixelStride = frame.bytesPerPixel.first;
  final image = image_lib.Image(width: frame.width, height: frame.height);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final offset = y * rowStride + x * pixelStride;
      if (offset + 2 >= bytes.length) {
        continue;
      }
      image.setPixelRgb(
        x,
        y,
        bytes[offset + 2],
        bytes[offset + 1],
        bytes[offset],
      );
    }
  }
  return image;
}

image_lib.Image _decodeYuv420(_RawCameraFrame frame) {
  if (frame.planes.length < 3) {
    throw const FormatException('Thiết bị trả về frame camera không hỗ trợ.');
  }
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final yRowStride = frame.bytesPerRow[0];
  final uvRowStride = frame.bytesPerRow[1];
  final uvPixelStride = frame.bytesPerPixel[1];
  final image = image_lib.Image(width: frame.width, height: frame.height);

  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
      if (yIndex >= yPlane.length ||
          uvIndex >= uPlane.length ||
          uvIndex >= vPlane.length) {
        continue;
      }

      final yValue = yPlane[yIndex].toDouble();
      final uValue = uPlane[uvIndex].toDouble() - 128;
      final vValue = vPlane[uvIndex].toDouble() - 128;
      final red = (yValue + 1.402 * vValue).round().clamp(0, 255);
      final green = (yValue - 0.344136 * uValue - 0.714136 * vValue)
          .round()
          .clamp(0, 255);
      final blue = (yValue + 1.772 * uValue).round().clamp(0, 255);
      image.setPixelRgb(x, y, red, green, blue);
    }
  }
  return image;
}

int _captureRotationDegrees(CameraController controller) {
  const deviceRotation = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  final sensorOrientation = controller.description.sensorOrientation;
  final rotation = deviceRotation[controller.value.deviceOrientation] ?? 0;
  if (controller.description.lensDirection == CameraLensDirection.front) {
    return (sensorOrientation + rotation) % 360;
  }
  return (sensorOrientation - rotation + 360) % 360;
}

String _cameraErrorMessage(CameraException error) {
  return switch (error.code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
      'Ứng dụng chưa được cấp quyền camera. Hãy bật quyền trong Cài đặt.',
    'CameraAccessRestricted' => 'Thiết bị đang hạn chế quyền sử dụng camera.',
    _ => 'Không thể mở camera. Vui lòng thử lại.',
  };
}
