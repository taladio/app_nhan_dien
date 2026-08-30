import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import 'detection_painter.dart';

class DetectionImageView extends StatelessWidget {
  const DetectionImageView({
    super.key,
    required this.imageBytes,
    this.response,
    this.showBoundingBoxes = true,
    this.highlightedIndex,
  });

  final Uint8List imageBytes;
  final DetectionResponse? response;
  final bool showBoundingBoxes;
  final int? highlightedIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 600.0;
        final height = (width * 1.05).clamp(280.0, 560.0).toDouble();
        final result = response;

        return Container(
          key: const Key('detection_image_view'),
          width: double.infinity,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.memory(
                imageBytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text('Không thể hiển thị ảnh đã chọn.'),
                  );
                },
              ),
              if (result != null)
                IgnorePointer(
                  child: CustomPaint(
                    painter: DetectionPainter(
                      detections: result.detections,
                      imageSize: Size(
                        result.imageWidth.toDouble(),
                        result.imageHeight.toDouble(),
                      ),
                      showBoundingBoxes: showBoundingBoxes,
                      highlightedIndex: highlightedIndex,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
