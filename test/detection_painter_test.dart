import 'dart:ui';

import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/widgets/detection_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chuyển box khi ảnh và canvas cùng tỉ lệ', () {
    final rect = calculateFittedBoundingBox(
      boundingBox: const BoundingBox(x1: 10, y1: 20, x2: 50, y2: 70),
      imageSize: const Size(100, 100),
      canvasSize: const Size(200, 200),
    );

    expect(rect, const Rect.fromLTRB(20, 40, 100, 140));
  });

  test('chuyển box đúng khi có khoảng trống trên và dưới', () {
    final rect = calculateFittedBoundingBox(
      boundingBox: const BoundingBox(x1: 0, y1: 0, x2: 200, y2: 100),
      imageSize: const Size(200, 100),
      canvasSize: const Size(200, 200),
    );

    expect(rect, const Rect.fromLTRB(0, 50, 200, 150));
  });

  test('chuyển box đúng khi có khoảng trống trái và phải', () {
    final rect = calculateFittedBoundingBox(
      boundingBox: const BoundingBox(x1: 0, y1: 0, x2: 100, y2: 200),
      imageSize: const Size(100, 200),
      canvasSize: const Size(200, 200),
    );

    expect(rect, const Rect.fromLTRB(50, 0, 150, 200));
  });

  test('clamp box vào kích thước ảnh', () {
    final rect = calculateFittedBoundingBox(
      boundingBox: const BoundingBox(x1: -20, y1: -10, x2: 130, y2: 120),
      imageSize: const Size(100, 100),
      canvasSize: const Size(100, 100),
    );

    expect(rect, const Rect.fromLTRB(0, 0, 100, 100));
  });

  test('bỏ bounding box không hợp lệ', () {
    final rect = calculateFittedBoundingBox(
      boundingBox: const BoundingBox(x1: 40, y1: 20, x2: 40, y2: 70),
      imageSize: const Size(100, 100),
      canvasSize: const Size(200, 200),
    );

    expect(rect, isNull);
  });
}
