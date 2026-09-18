import 'package:flutter/material.dart';

import '../models/pose_result.dart';
import '../utils/camera_coordinate_mapper.dart';

class PoseSkeletonPainter extends CustomPainter {
  PoseSkeletonPainter({required this.pose, required this.mapper});

  final PoseResult pose;
  final CameraCoordinateMapper mapper;

  static const List<(String, String)> _connections = <(String, String)>[
    ('left_shoulder', 'right_shoulder'),
    ('left_shoulder', 'left_hip'),
    ('right_shoulder', 'right_hip'),
    ('left_hip', 'right_hip'),
    ('left_hip', 'left_knee'),
    ('left_knee', 'left_ankle'),
    ('right_hip', 'right_knee'),
    ('right_knee', 'right_ankle'),
    ('left_ankle', 'left_heel'),
    ('left_heel', 'left_foot_index'),
    ('right_ankle', 'right_heel'),
    ('right_heel', 'right_foot_index'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.lightGreenAccent.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    for (final connection in _connections) {
      final first = pose.landmarks[connection.$1];
      final second = pose.landmarks[connection.$2];
      if (first == null || second == null) continue;
      canvas.drawLine(
        mapper.mapNormalized(first.normalizedOffset),
        mapper.mapNormalized(second.normalizedOffset),
        linePaint,
      );
    }
    for (final landmark in pose.landmarks.values) {
      canvas.drawCircle(
        mapper.mapNormalized(landmark.normalizedOffset),
        4,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter oldDelegate) {
    return oldDelegate.pose.frameId != pose.frameId ||
        oldDelegate.mapper.viewportSize != mapper.viewportSize ||
        oldDelegate.mapper.mirrored != mapper.mirrored ||
        oldDelegate.mapper.rotationDegrees != mapper.rotationDegrees;
  }
}
