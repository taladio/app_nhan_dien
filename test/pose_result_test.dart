import 'package:app_nhan_dien/models/pose_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse pose result with landmarks and anchors', () {
    final result = PoseResult.fromJson(<String, dynamic>{
      'type': 'pose_result',
      'frame_id': 25,
      'timestamp_ms': 1758000000000,
      'processing_ms': 42.5,
      'pose_detected': true,
      'body_visible': true,
      'landmarks': <String, dynamic>{
        'left_shoulder': <String, dynamic>{
          'x': 0.31,
          'y': 0.24,
          'z': -0.05,
          'visibility': 0.98,
        },
      },
      'world_landmarks': <String, dynamic>{
        'left_shoulder': {'x': -.2, 'y': -.5, 'z': .15, 'visibility': .9},
      },
      'anchors': <String, dynamic>{
        'shoulder_center': <String, dynamic>{'x': 0.49, 'y': 0.245},
        'shoulder_width': 0.36,
        'shoulder_angle': 0.03,
        'hip_center': <String, dynamic>{'x': 0.495, 'y': 0.545},
        'hip_width': 0.21,
        'hip_angle': 0.02,
        'torso_center': <String, dynamic>{'x': 0.493, 'y': 0.395},
        'torso_height': 0.30,
        'left_leg_length': 0.41,
        'right_leg_length': 0.42,
        'body_visible': true,
      },
    });

    expect(result.frameId, 25);
    expect(result.processingMs, 42.5);
    expect(result.poseDetected, isTrue);
    expect(result.landmarks['left_shoulder']!.visibility, 0.98);
    expect(result.anchors!.shoulderCenter.x, 0.49);
    expect(result.anchors!.torsoHeight, 0.30);
    expect(result.worldLandmarks['left_shoulder']!.x, -.2);
    expect(result.worldLandmarks['left_shoulder']!.y, -.5);
  });

  test('parse response when pose is missing', () {
    final result = PoseResult.fromJson(<String, dynamic>{
      'type': 'pose_result',
      'pose_detected': false,
      'body_visible': false,
      'message': 'Hãy đứng lùi lại.',
    });

    expect(result.poseDetected, isFalse);
    expect(result.anchors, isNull);
    expect(result.landmarks, isEmpty);
    expect(result.worldLandmarks, isEmpty);
  });
}
