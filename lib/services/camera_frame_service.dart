import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;

class EncodedCameraFrame {
  const EncodedCameraFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

enum _RawFormat { jpeg, bgra8888, yuv420, nv21 }

class _RawFrame {
  const _RawFrame({
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
  final _RawFormat format;
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
  final int rotationDegrees;
}

Future<EncodedCameraFrame> encodeCameraFrame(
  CameraImage image, {
  required int rotationDegrees,
}) {
  final format = switch (image.format.group) {
    ImageFormatGroup.jpeg => _RawFormat.jpeg,
    ImageFormatGroup.bgra8888 => _RawFormat.bgra8888,
    ImageFormatGroup.nv21 => _RawFormat.nv21,
    _ => _RawFormat.yuv420,
  };
  final raw = _RawFrame(
    width: image.width,
    height: image.height,
    format: format,
    planes: image.planes
        .map((plane) => Uint8List.fromList(plane.bytes))
        .toList(growable: false),
    bytesPerRow: image.planes
        .map((plane) => plane.bytesPerRow)
        .toList(growable: false),
    bytesPerPixel: image.planes
        .map((plane) => plane.bytesPerPixel ?? 1)
        .toList(growable: false),
    rotationDegrees: rotationDegrees,
  );
  return compute(_encode, raw);
}

EncodedCameraFrame _encode(_RawFrame frame) {
  const maxSide = 640;
  final scale = math.min(1.0, maxSide / math.max(frame.width, frame.height));
  final targetWidth = math.max(1, (frame.width * scale).round()).toInt();
  final targetHeight = math.max(1, (frame.height * scale).round()).toInt();

  image_lib.Image image = switch (frame.format) {
    _RawFormat.jpeg => _resizeIfNeeded(
      _decodeJpeg(frame),
      targetWidth,
      targetHeight,
    ),
    _RawFormat.bgra8888 => _decodeBgra(frame, targetWidth, targetHeight),
    _RawFormat.nv21 => _decodeNv21(frame, targetWidth, targetHeight),
    _RawFormat.yuv420 => _decodeYuv420(frame, targetWidth, targetHeight),
  };
  if (frame.rotationDegrees != 0) {
    image = image_lib.copyRotate(
      image,
      angle: frame.rotationDegrees.toDouble(),
    );
  }
  return EncodedCameraFrame(
    bytes: Uint8List.fromList(image_lib.encodeJpg(image, quality: 68)),
    width: image.width,
    height: image.height,
  );
}

image_lib.Image _decodeJpeg(_RawFrame frame) {
  final image = image_lib.decodeImage(frame.planes.first);
  if (image == null) throw const FormatException('Frame JPEG không hợp lệ.');
  return image;
}

image_lib.Image _decodeBgra(
  _RawFrame frame,
  int targetWidth,
  int targetHeight,
) {
  if (frame.planes.isEmpty) {
    throw const FormatException('Frame BGRA không có dữ liệu.');
  }
  final source = frame.planes.first;
  final rowStride = frame.bytesPerRow.first;
  final pixelStride = frame.bytesPerPixel.first;
  final image = image_lib.Image(width: targetWidth, height: targetHeight);
  for (var y = 0; y < targetHeight; y++) {
    final sourceY = math
        .min(frame.height - 1, y * frame.height ~/ targetHeight)
        .toInt();
    for (var x = 0; x < targetWidth; x++) {
      final sourceX = math
          .min(frame.width - 1, x * frame.width ~/ targetWidth)
          .toInt();
      final offset = sourceY * rowStride + sourceX * pixelStride;
      if (offset + 2 < source.length) {
        image.setPixelRgb(
          x,
          y,
          source[offset + 2],
          source[offset + 1],
          source[offset],
        );
      }
    }
  }
  return image;
}

image_lib.Image _decodeYuv420(
  _RawFrame frame,
  int targetWidth,
  int targetHeight,
) {
  if (frame.planes.length < 3) {
    return _decodeNv21(frame, targetWidth, targetHeight);
  }
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final yRowStride = frame.bytesPerRow[0];
  final uvRowStride = frame.bytesPerRow[1];
  final uvPixelStride = frame.bytesPerPixel[1];
  final image = image_lib.Image(width: targetWidth, height: targetHeight);
  for (var y = 0; y < targetHeight; y++) {
    final sourceY = math
        .min(frame.height - 1, y * frame.height ~/ targetHeight)
        .toInt();
    for (var x = 0; x < targetWidth; x++) {
      final sourceX = math
          .min(frame.width - 1, x * frame.width ~/ targetWidth)
          .toInt();
      final yIndex = sourceY * yRowStride + sourceX;
      final uvIndex =
          (sourceY ~/ 2) * uvRowStride + (sourceX ~/ 2) * uvPixelStride;
      if (yIndex < yPlane.length &&
          uvIndex < uPlane.length &&
          uvIndex < vPlane.length) {
        _setYuvPixel(
          image,
          x,
          y,
          yPlane[yIndex],
          uPlane[uvIndex],
          vPlane[uvIndex],
        );
      }
    }
  }
  return image;
}

image_lib.Image _decodeNv21(
  _RawFrame frame,
  int targetWidth,
  int targetHeight,
) {
  if (frame.planes.isEmpty) {
    throw const FormatException('Frame NV21 không có dữ liệu.');
  }
  final yPlane = frame.planes.first;
  final uvPlane = frame.planes.length > 1 ? frame.planes[1] : yPlane;
  final yRowStride = frame.bytesPerRow.first;
  final separateUvPlane = frame.planes.length > 1;
  final uvStart = separateUvPlane ? 0 : yRowStride * frame.height;
  final uvRowStride = separateUvPlane ? frame.bytesPerRow[1] : yRowStride;
  final image = image_lib.Image(width: targetWidth, height: targetHeight);
  for (var y = 0; y < targetHeight; y++) {
    final sourceY = math
        .min(frame.height - 1, y * frame.height ~/ targetHeight)
        .toInt();
    for (var x = 0; x < targetWidth; x++) {
      final sourceX = math
          .min(frame.width - 1, x * frame.width ~/ targetWidth)
          .toInt();
      final yIndex = sourceY * yRowStride + sourceX;
      final uvIndex =
          uvStart + (sourceY ~/ 2) * uvRowStride + (sourceX ~/ 2) * 2;
      if (yIndex < yPlane.length && uvIndex + 1 < uvPlane.length) {
        _setYuvPixel(
          image,
          x,
          y,
          yPlane[yIndex],
          uvPlane[uvIndex + 1],
          uvPlane[uvIndex],
        );
      }
    }
  }
  return image;
}

image_lib.Image _resizeIfNeeded(
  image_lib.Image image,
  int targetWidth,
  int targetHeight,
) {
  if (image.width == targetWidth && image.height == targetHeight) return image;
  return image_lib.copyResize(image, width: targetWidth, height: targetHeight);
}

void _setYuvPixel(
  image_lib.Image image,
  int x,
  int y,
  int yByte,
  int uByte,
  int vByte,
) {
  final luminance = yByte.toDouble();
  final u = uByte.toDouble() - 128;
  final v = vByte.toDouble() - 128;
  image.setPixelRgb(
    x,
    y,
    (luminance + 1.402 * v).round().clamp(0, 255),
    (luminance - 0.344136 * u - 0.714136 * v).round().clamp(0, 255),
    (luminance + 1.772 * u).round().clamp(0, 255),
  );
}

int cameraRotationDegrees(CameraController controller) {
  const deviceRotation = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  final sensor = controller.description.sensorOrientation;
  final device = deviceRotation[controller.value.deviceOrientation] ?? 0;
  if (controller.description.lensDirection == CameraLensDirection.front) {
    return (sensor + device) % 360;
  }
  return (sensor - device + 360) % 360;
}
