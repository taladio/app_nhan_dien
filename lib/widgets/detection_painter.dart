import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/detection_result.dart';

/// Chuyển bounding box của ảnh gốc sang canvas khi ảnh dùng BoxFit.contain.
Rect? calculateFittedBoundingBox({
  required BoundingBox boundingBox,
  required Size imageSize,
  required Size canvasSize,
}) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      canvasSize.width <= 0 ||
      canvasSize.height <= 0) {
    return null;
  }

  final clamped = boundingBox.clamped(
    width: imageSize.width,
    height: imageSize.height,
  );
  if (!clamped.isValid) {
    return null;
  }

  final scale = math.min(
    canvasSize.width / imageSize.width,
    canvasSize.height / imageSize.height,
  );
  final displayedWidth = imageSize.width * scale;
  final displayedHeight = imageSize.height * scale;
  final offsetX = (canvasSize.width - displayedWidth) / 2;
  final offsetY = (canvasSize.height - displayedHeight) / 2;

  return Rect.fromLTRB(
    offsetX + clamped.x1 * scale,
    offsetY + clamped.y1 * scale,
    offsetX + clamped.x2 * scale,
    offsetY + clamped.y2 * scale,
  );
}

Color detectionColorForClass(String className) {
  return switch (className) {
    'tshirt' => const Color(0xFF1976D2),
    'shirt' => const Color(0xFF00897B),
    'jacket' => const Color(0xFFF57C00),
    'pants' => const Color(0xFF7B1FA2),
    'shorts' => const Color(0xFFF9A825),
    'skirt' => const Color(0xFFD81B60),
    'dress' => const Color(0xFFD32F2F),
    'shoes' => const Color(0xFF2E7D32),
    _ => const Color(0xFF546E7A),
  };
}

class DetectionPainter extends CustomPainter {
  const DetectionPainter({
    required this.detections,
    required this.imageSize,
    this.showBoundingBoxes = true,
    this.highlightedIndex,
  });

  final List<ClothingDetection> detections;
  final Size imageSize;
  final bool showBoundingBoxes;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showBoundingBoxes) {
      return;
    }

    for (var index = 0; index < detections.length; index++) {
      final detection = detections[index];
      final rect = calculateFittedBoundingBox(
        boundingBox: detection.boundingBox,
        imageSize: imageSize,
        canvasSize: size,
      );
      if (rect == null) {
        continue;
      }

      final color = detectionColorForClass(detection.className);
      final isHighlighted = highlightedIndex == index;
      if (highlightedIndex != null && !isHighlighted) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.45),
        );
        continue;
      }

      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? 5 : 3
          ..color = color,
      );
      _paintLabel(canvas, size, rect, detection, color);
    }
  }

  void _paintLabel(
    Canvas canvas,
    Size canvasSize,
    Rect rect,
    ClothingDetection detection,
    Color color,
  ) {
    final availableWidth = math.max(canvasSize.width - 8, 1).toDouble();
    final label =
        '${detection.classNameVi} • ${detection.color} • '
        '${detection.confidencePercent.round()}%';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 2)],
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: availableWidth - 8);

    const horizontalPadding = 4.0;
    const verticalPadding = 3.0;
    final labelWidth = textPainter.width + horizontalPadding * 2;
    final labelHeight = textPainter.height + verticalPadding * 2;
    final maxLeft = math.max(0, canvasSize.width - labelWidth).toDouble();
    final labelLeft = rect.left.clamp(0, maxLeft).toDouble();
    final preferredTop = rect.top - labelHeight - 2;
    final maxTop = math.max(0, canvasSize.height - labelHeight).toDouble();
    final labelTop = (preferredTop >= 0 ? preferredTop : rect.top + 2)
        .clamp(0, maxTop)
        .toDouble();
    final labelRect = Rect.fromLTWH(
      labelLeft,
      labelTop,
      labelWidth,
      labelHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      Paint()..color = color.withValues(alpha: 0.94),
    );
    textPainter.paint(
      canvas,
      Offset(labelLeft + horizontalPadding, labelTop + verticalPadding),
    );
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize ||
        oldDelegate.showBoundingBoxes != showBoundingBoxes ||
        oldDelegate.highlightedIndex != highlightedIndex ||
        !listEquals(oldDelegate.detections, detections);
  }
}
