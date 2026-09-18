import 'dart:ui';

class PoseLandmark {
  const PoseLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  factory PoseLandmark.fromJson(Map<String, dynamic> json) {
    return PoseLandmark(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      visibility: (json['visibility'] as num).toDouble(),
    );
  }

  final double x;
  final double y;
  final double z;
  final double visibility;

  Offset get normalizedOffset => Offset(x, y);

  static PoseLandmark lerp(
    PoseLandmark previous,
    PoseLandmark current,
    double alpha,
  ) {
    return PoseLandmark(
      x: _mix(previous.x, current.x, alpha),
      y: _mix(previous.y, current.y, alpha),
      z: _mix(previous.z, current.z, alpha),
      visibility: _mix(previous.visibility, current.visibility, alpha),
    );
  }
}

double _mix(double previous, double current, double alpha) {
  return previous + (current - previous) * alpha;
}
