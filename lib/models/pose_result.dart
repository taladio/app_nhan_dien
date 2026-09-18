import 'dart:math' as math;
import 'dart:ui';

import 'pose_landmark.dart';

class PoseAnchorPoint {
  const PoseAnchorPoint({required this.x, required this.y});

  factory PoseAnchorPoint.fromJson(Map<String, dynamic> json) {
    return PoseAnchorPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  final double x;
  final double y;

  Offset get normalizedOffset => Offset(x, y);

  static PoseAnchorPoint lerp(
    PoseAnchorPoint previous,
    PoseAnchorPoint current,
    double alpha,
  ) {
    return PoseAnchorPoint(
      x: previous.x + (current.x - previous.x) * alpha,
      y: previous.y + (current.y - previous.y) * alpha,
    );
  }
}

class PoseAnchors {
  const PoseAnchors({
    required this.shoulderCenter,
    required this.shoulderWidth,
    required this.shoulderAngle,
    required this.hipCenter,
    required this.hipWidth,
    required this.hipAngle,
    required this.torsoCenter,
    required this.torsoHeight,
    required this.leftLegLength,
    required this.rightLegLength,
    required this.bodyVisible,
  });

  factory PoseAnchors.fromJson(Map<String, dynamic> json) {
    return PoseAnchors(
      shoulderCenter: PoseAnchorPoint.fromJson(
        json['shoulder_center'] as Map<String, dynamic>,
      ),
      shoulderWidth: (json['shoulder_width'] as num).toDouble(),
      shoulderAngle: (json['shoulder_angle'] as num).toDouble(),
      hipCenter: PoseAnchorPoint.fromJson(
        json['hip_center'] as Map<String, dynamic>,
      ),
      hipWidth: (json['hip_width'] as num).toDouble(),
      hipAngle: (json['hip_angle'] as num).toDouble(),
      torsoCenter: PoseAnchorPoint.fromJson(
        json['torso_center'] as Map<String, dynamic>,
      ),
      torsoHeight: (json['torso_height'] as num).toDouble(),
      leftLegLength: (json['left_leg_length'] as num?)?.toDouble() ?? 0,
      rightLegLength: (json['right_leg_length'] as num?)?.toDouble() ?? 0,
      bodyVisible: json['body_visible'] as bool? ?? false,
    );
  }

  final PoseAnchorPoint shoulderCenter;
  final double shoulderWidth;
  final double shoulderAngle;
  final PoseAnchorPoint hipCenter;
  final double hipWidth;
  final double hipAngle;
  final PoseAnchorPoint torsoCenter;
  final double torsoHeight;
  final double leftLegLength;
  final double rightLegLength;
  final bool bodyVisible;

  static PoseAnchors lerp(
    PoseAnchors previous,
    PoseAnchors current,
    double alpha,
  ) {
    return PoseAnchors(
      shoulderCenter: PoseAnchorPoint.lerp(
        previous.shoulderCenter,
        current.shoulderCenter,
        alpha,
      ),
      shoulderWidth: _mix(previous.shoulderWidth, current.shoulderWidth, alpha),
      shoulderAngle: _lerpAngle(
        previous.shoulderAngle,
        current.shoulderAngle,
        alpha,
      ),
      hipCenter: PoseAnchorPoint.lerp(
        previous.hipCenter,
        current.hipCenter,
        alpha,
      ),
      hipWidth: _mix(previous.hipWidth, current.hipWidth, alpha),
      hipAngle: _lerpAngle(previous.hipAngle, current.hipAngle, alpha),
      torsoCenter: PoseAnchorPoint.lerp(
        previous.torsoCenter,
        current.torsoCenter,
        alpha,
      ),
      torsoHeight: _mix(previous.torsoHeight, current.torsoHeight, alpha),
      leftLegLength: _mix(previous.leftLegLength, current.leftLegLength, alpha),
      rightLegLength: _mix(
        previous.rightLegLength,
        current.rightLegLength,
        alpha,
      ),
      bodyVisible: current.bodyVisible,
    );
  }
}

class PoseResult {
  const PoseResult({
    required this.frameId,
    required this.timestampMs,
    required this.processingMs,
    required this.poseDetected,
    required this.bodyVisible,
    required this.landmarks,
    this.anchors,
    this.message,
  });

  factory PoseResult.fromJson(Map<String, dynamic> json) {
    final rawLandmarks =
        json['landmarks'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final rawAnchors = json['anchors'] as Map<String, dynamic>?;
    return PoseResult(
      frameId: (json['frame_id'] as num?)?.toInt() ?? 0,
      timestampMs: (json['timestamp_ms'] as num?)?.toInt() ?? 0,
      processingMs: (json['processing_ms'] as num?)?.toDouble() ?? 0,
      poseDetected: json['pose_detected'] as bool? ?? false,
      bodyVisible: json['body_visible'] as bool? ?? false,
      landmarks: rawLandmarks.map(
        (name, value) => MapEntry(
          name,
          PoseLandmark.fromJson(value as Map<String, dynamic>),
        ),
      ),
      anchors: rawAnchors == null ? null : PoseAnchors.fromJson(rawAnchors),
      message: json['message'] as String?,
    );
  }

  final int frameId;
  final int timestampMs;
  final double processingMs;
  final bool poseDetected;
  final bool bodyVisible;
  final Map<String, PoseLandmark> landmarks;
  final PoseAnchors? anchors;
  final String? message;
}

double _mix(double previous, double current, double alpha) {
  return previous + (current - previous) * alpha;
}

double _lerpAngle(double previous, double current, double alpha) {
  var difference = (current - previous) % (math.pi * 2);
  if (difference > math.pi) difference -= math.pi * 2;
  if (difference < -math.pi) difference += math.pi * 2;
  return previous + difference * alpha;
}
