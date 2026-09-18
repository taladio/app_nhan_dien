import '../models/pose_landmark.dart';
import '../models/pose_result.dart';

class PoseSmoother {
  PoseSmoother({
    this.alpha = 0.32,
    this.holdDuration = const Duration(milliseconds: 250),
  }) : assert(alpha > 0 && alpha <= 1);

  final double alpha;
  final Duration holdDuration;
  PoseResult? _last;
  DateTime? _lastDetectedAt;

  PoseResult? update(PoseResult current, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    if (!current.poseDetected || current.anchors == null) {
      final lastDetectedAt = _lastDetectedAt;
      if (_last != null &&
          lastDetectedAt != null &&
          currentTime.difference(lastDetectedAt) <= holdDuration) {
        return _last;
      }
      reset();
      return null;
    }

    _lastDetectedAt = currentTime;
    final previous = _last;
    if (previous == null || previous.anchors == null) {
      _last = current;
      return current;
    }

    final smoothedLandmarks = <String, PoseLandmark>{};
    for (final entry in current.landmarks.entries) {
      final old = previous.landmarks[entry.key];
      smoothedLandmarks[entry.key] = old == null
          ? entry.value
          : PoseLandmark.lerp(old, entry.value, alpha);
    }
    _last = PoseResult(
      frameId: current.frameId,
      timestampMs: current.timestampMs,
      processingMs: current.processingMs,
      poseDetected: true,
      bodyVisible: current.bodyVisible,
      landmarks: smoothedLandmarks,
      anchors: PoseAnchors.lerp(previous.anchors!, current.anchors!, alpha),
      message: current.message,
    );
    return _last;
  }

  void reset() {
    _last = null;
    _lastDetectedAt = null;
  }
}
