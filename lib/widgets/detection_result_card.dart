import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import 'detection_painter.dart';

class DetectionResultCard extends StatelessWidget {
  const DetectionResultCard({
    super.key,
    required this.detection,
    required this.index,
    this.isHighlighted = false,
    this.onTap,
  });

  final ClothingDetection detection;
  final int index;
  final bool isHighlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = detectionColorForClass(detection.className);
    return Card(
      key: Key('detection_card_$index'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isHighlighted ? color : Colors.transparent,
          width: isHighlighted ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: color,
                foregroundColor: Colors.white,
                child: Text('${index + 1}'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      detection.classNameVi,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Màu: ${detection.color}'),
                    Text(
                      'Độ tin cậy: '
                      '${detection.confidencePercent.toStringAsFixed(2)}%',
                    ),
                    Text('Lớp: ${detection.className}'),
                  ],
                ),
              ),
              if (isHighlighted) Icon(Icons.center_focus_strong, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
