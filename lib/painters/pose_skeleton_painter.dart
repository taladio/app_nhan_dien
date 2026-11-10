import 'package:flutter/material.dart';

import '../models/pose_result.dart';
import '../utils/camera_coordinate_mapper.dart';

class PoseSkeletonPainter extends CustomPainter {
  PoseSkeletonPainter({required this.pose, required this.mapper});

  final PoseResult pose;
  final CameraCoordinateMapper mapper;

  static const List<(String, String)> _connections = <(String, String)>[
    ('left_eye_inner', 'left_eye'),
    ('left_eye', 'left_eye_outer'),
    ('right_eye_inner', 'right_eye'),
    ('right_eye', 'right_eye_outer'),
    ('left_eye_outer', 'left_ear'),
    ('right_eye_outer', 'right_ear'),
    ('mouth_left', 'mouth_right'),
    ('left_shoulder', 'right_shoulder'),
    ('left_shoulder', 'left_elbow'),
    ('left_elbow', 'left_wrist'),
    ('left_wrist', 'left_pinky'),
    ('left_wrist', 'left_index'),
    ('left_wrist', 'left_thumb'),
    ('left_pinky', 'left_index'),
    ('right_shoulder', 'right_elbow'),
    ('right_elbow', 'right_wrist'),
    ('right_wrist', 'right_pinky'),
    ('right_wrist', 'right_index'),
    ('right_wrist', 'right_thumb'),
    ('right_pinky', 'right_index'),
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
    const minimumVisibility = 0.35;
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
      if (first == null ||
          second == null ||
          first.visibility < minimumVisibility ||
          second.visibility < minimumVisibility) {
        continue;
      }
      canvas.drawLine(
        mapper.mapNormalized(first.normalizedOffset),
        mapper.mapNormalized(second.normalizedOffset),
        linePaint,
      );
    }
    for (final landmark in pose.landmarks.values) {
      if (landmark.visibility < minimumVisibility) continue;
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
