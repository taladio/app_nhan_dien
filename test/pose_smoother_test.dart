import 'package:app_nhan_dien/models/pose_landmark.dart';
import 'package:app_nhan_dien/models/pose_result.dart';
import 'package:app_nhan_dien/utils/pose_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

PoseResult _pose(double x, {bool detected = true}) {
  return PoseResult(
    frameId: x.round(),
    timestampMs: 1,
    processingMs: 10,
    poseDetected: detected,
    bodyVisible: detected,
    landmarks: detected
        ? <String, PoseLandmark>{
            'left_shoulder': PoseLandmark(x: x, y: 0.2, z: 0, visibility: 1),
          }
        : const <String, PoseLandmark>{},
    anchors: detected
        ? PoseAnchors(
            shoulderCenter: PoseAnchorPoint(x: x, y: 0.2),
            shoulderWidth: x,
            shoulderAngle: 0,
            hipCenter: PoseAnchorPoint(x: x, y: 0.5),
            hipWidth: x,
            hipAngle: 0,
            torsoCenter: PoseAnchorPoint(x: x, y: 0.35),
            torsoHeight: 0.3,
            leftLegLength: 0.4,
            rightLegLength: 0.4,
            bodyVisible: true,
          )
        : null,
  );
}

void main() {
  test('uses exponential moving average', () {
    final smoother = PoseSmoother(alpha: 0.25);
    final now = DateTime(2026);
    smoother.update(_pose(0.2), now: now);
    final result = smoother.update(
      _pose(0.6),
      now: now.add(const Duration(milliseconds: 100)),
    );

    expect(result!.landmarks['left_shoulder']!.x, closeTo(0.3, 0.0001));
    expect(result.anchors!.shoulderWidth, closeTo(0.3, 0.0001));
  });

  test('holds last pose briefly then hides it', () {
    final smoother = PoseSmoother(
      holdDuration: const Duration(milliseconds: 250),
    );
    final now = DateTime(2026);
    smoother.update(_pose(0.4), now: now);

    expect(
      smoother.update(
        _pose(0, detected: false),
        now: now.add(const Duration(milliseconds: 200)),
      ),
      isNotNull,
    );
    expect(
      smoother.update(
        _pose(0, detected: false),
        now: now.add(const Duration(milliseconds: 300)),
      ),
      isNull,
    );
  });

  test('keeps partial pose even when torso anchors are unavailable', () {
    final smoother = PoseSmoother();
    final partial = PoseResult(
      frameId: 1,
      timestampMs: 1,
      processingMs: 10,
      poseDetected: true,
      bodyVisible: false,
      landmarks: const <String, PoseLandmark>{
        'left_elbow': PoseLandmark(x: 0.4, y: 0.3, z: 0, visibility: 0.9),
      },
    );
    expect(smoother.update(partial)?.landmarks['left_elbow'], isNotNull);
    expect(smoother.update(partial)?.anchors, isNull);
  });
}
