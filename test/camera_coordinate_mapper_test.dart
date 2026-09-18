import 'dart:ui';

import 'package:app_nhan_dien/utils/camera_coordinate_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps normalized coordinate without transform', () {
    const mapper = CameraCoordinateMapper(
      imageSize: Size(100, 200),
      viewportSize: Size(100, 200),
      rotationDegrees: 0,
      mirrored: false,
    );
    expect(
      mapper.mapNormalized(const Offset(0.25, 0.75)),
      const Offset(25, 150),
    );
  });

  test('mirrors front camera on horizontal axis', () {
    const mapper = CameraCoordinateMapper(
      imageSize: Size(100, 200),
      viewportSize: Size(100, 200),
      rotationDegrees: 0,
      mirrored: true,
    );
    expect(mapper.mapNormalized(const Offset(0.2, 0.4)), const Offset(80, 80));
  });

  test('maps rotation 90 degrees and swaps image dimensions', () {
    const mapper = CameraCoordinateMapper(
      imageSize: Size(200, 100),
      viewportSize: Size(100, 200),
      rotationDegrees: 90,
      mirrored: false,
    );
    expect(mapper.orientedImageSize, const Size(100, 200));
    expect(mapper.mapNormalized(const Offset(0.25, 0.4)), const Offset(60, 50));
  });

  test('BoxFit.cover crops image horizontally', () {
    const mapper = CameraCoordinateMapper(
      imageSize: Size(100, 100),
      viewportSize: Size(100, 200),
      rotationDegrees: 0,
      mirrored: false,
    );
    expect(mapper.scaledImageSize, const Size(200, 200));
    expect(mapper.cropOffset, const Offset(50, 0));
    expect(mapper.mapNormalized(Offset.zero), const Offset(-50, 0));
  });

  test('BoxFit.cover crops image vertically', () {
    const mapper = CameraCoordinateMapper(
      imageSize: Size(100, 100),
      viewportSize: Size(200, 100),
      rotationDegrees: 0,
      mirrored: false,
    );
    expect(mapper.scaledImageSize, const Size(200, 200));
    expect(mapper.cropOffset, const Offset(0, 50));
    expect(mapper.mapNormalized(Offset.zero), const Offset(0, -50));
  });
}
