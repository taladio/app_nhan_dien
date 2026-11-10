import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:app_nhan_dien/models/body_garment_pose.dart';
import 'package:app_nhan_dien/models/garment_mesh.dart';
import 'package:app_nhan_dien/models/pose_landmark.dart';
import 'package:app_nhan_dien/models/pose_result.dart';
import 'package:app_nhan_dien/models/try_on_filter.dart';
import 'package:app_nhan_dien/utils/camera_coordinate_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

PoseResult turnedBody(
  double yaw, {
  double lean = 0,
  int frameId = 1,
  double hiddenVisibility = .95,
  bool world = true,
}) {
  final map = <String, MeshPoint>{
    'left_shoulder': const MeshPoint(.2, -.5, 0),
    'right_shoulder': const MeshPoint(-.2, -.5, 0),
    'left_hip': const MeshPoint(.15, 0, 0),
    'right_hip': const MeshPoint(-.15, 0, 0),
    'left_knee': const MeshPoint(.15, .5, 0),
    'right_knee': const MeshPoint(-.15, .5, 0),
    'left_ankle': const MeshPoint(.15, 1, 0),
    'right_ankle': const MeshPoint(-.15, 1, 0),
  };
  MeshPoint rotate(MeshPoint p) {
    final x = p.x * math.cos(yaw) + p.z * math.sin(yaw);
    final z = -p.x * math.sin(yaw) + p.z * math.cos(yaw);
    return MeshPoint(
      x,
      p.y * math.cos(lean) - z * math.sin(lean),
      p.y * math.sin(lean) + z * math.cos(lean),
    );
  }

  final imagePoints = <String, PoseLandmark>{};
  final worldPoints = <String, PoseLandmark>{};
  for (final entry in map.entries) {
    final p = rotate(entry.value);
    final visibility = entry.key.startsWith('right') ? hiddenVisibility : .95;
    imagePoints[entry.key] = PoseLandmark(
      x: .5 + p.x * .5,
      y: .65 + p.y / 3,
      z: -p.z * .5,
      visibility: visibility,
    );
    worldPoints[entry.key] = PoseLandmark(
      x: p.x,
      y: p.y,
      z: -p.z,
      visibility: visibility,
    );
  }
  return PoseResult(
    frameId: frameId,
    timestampMs: frameId * 100,
    processingMs: 25,
    poseDetected: true,
    bodyVisible: true,
    landmarks: imagePoints,
    worldLandmarks: world ? worldPoints : {},
  );
}

TryOnFilter trackedFilter([
  TryOnFilterCategory category = TryOnFilterCategory.top,
]) => TryOnFilter.fromImage(
  id: 'tracked',
  category: category,
  bytes: Uint8List(0),
  templateAligned: true,
);

CameraCoordinateMapper trackedMapper({
  bool mirrored = false,
  int rotation = 0,
}) => CameraCoordinateMapper(
  imageSize: const Size(400, 600),
  viewportSize: const Size(400, 600),
  rotationDegrees: rotation,
  mirrored: mirrored,
);

BodyGarmentPose? track(
  PoseResult pose, {
  bool mirrored = false,
  TryOnFilterCategory category = TryOnFilterCategory.top,
}) => BodyGarmentPose.fromPose(
  pose,
  trackedFilter(category),
  trackedMapper(mirrored: mirrored),
  const ManualFilterTransform(),
);

void main() {
  test('full body turn reaches sides and back with constant garment size', () {
    final front = track(turnedBody(0))!;
    for (var degree = 0; degree <= 360; degree += 15) {
      final angle = degree * math.pi / 180;
      final current = track(turnedBody(angle))!;
      final forward = current.orientation.apply(const MeshPoint(0, 0, 1));
      expect(
        forward.x,
        closeTo(math.sin(angle), 1e-6),
        reason: 'angle=$degree',
      );
      expect(
        forward.z,
        closeTo(math.cos(angle), 1e-6),
        reason: 'angle=$degree',
      );
      expect(
        current.width,
        closeTo(front.width, 1e-6),
        reason: 'angle=$degree',
      );
      expect(current.height, closeTo(front.height, 1e-6));
    }
  });

  test(
    'mirrored selfie keeps the same front/back and reflects projection only',
    () {
      for (final angle in [0.0, math.pi / 2, math.pi, -math.pi / 2]) {
        final rearCamera = track(turnedBody(angle))!;
        final selfie = track(turnedBody(angle), mirrored: true)!;
        final vertex = const MeshPoint(.72, .4, .13);
        final a = rearCamera.rotateVertex(vertex, 1);
        final b = selfie.rotateVertex(vertex, 1);
        expect(a.z, closeTo(b.z, 1e-6));
        expect(
          rearCamera.project(a).dx + selfie.project(b).dx,
          closeTo(400, 1e-6),
        );
        expect(rearCamera.project(a).dy, closeTo(selfie.project(b).dy, 1e-6));
      }
    },
  );

  test('bending rotates the garment in depth rather than a 2D shear', () {
    final current = track(turnedBody(.4, lean: .6))!;
    final down = current.orientation.apply(const MeshPoint(0, 1, 0));
    expect(down.z, closeTo(math.sin(.6), 1e-6));
    expect(down.y, closeTo(math.cos(.6), 1e-6));
  });

  test('interpolation crosses 180 degrees without showing the front', () {
    final before = track(turnedBody(179 * math.pi / 180))!;
    final after = track(turnedBody(-179 * math.pi / 180))!;
    final middle = BodyGarmentPose.lerp(before, after, .5);
    expect(
      middle.orientation.apply(const MeshPoint(0, 0, 1)).z,
      closeTo(-1, 1e-6),
    );
    expect(middle.width, closeTo(before.width, 1e-6));
  });

  test('one occluded side can track but unreliable/missing 3D data cannot', () {
    expect(track(turnedBody(math.pi / 2, hiddenVisibility: .2)), isNotNull);
    expect(track(turnedBody(math.pi / 2, hiddenVisibility: .01)), isNull);
    expect(track(turnedBody(0, world: false)), isNull);
  });

  test(
    'lower body garments also turn to the back without shoulder sorting',
    () {
      for (final category in [
        TryOnFilterCategory.pants,
        TryOnFilterCategory.skirt,
        TryOnFilterCategory.dress,
      ]) {
        final front = track(turnedBody(0), category: category)!;
        final back = track(turnedBody(math.pi), category: category)!;
        expect(back.width, closeTo(front.width, 1e-6));
        expect(
          back.orientation.apply(const MeshPoint(0, 0, 1)).z,
          closeTo(-1, 1e-6),
        );
      }
    },
  );

  test('nonfinite coordinates and fully cropped torso hide the 3D garment', () {
    final pose = turnedBody(0);
    pose.worldLandmarks['left_shoulder'] = const PoseLandmark(
      x: double.nan,
      y: 0,
      z: 0,
      visibility: 1,
    );
    expect(track(pose), isNull);
    final cropped = turnedBody(0);
    for (final name in ['left_hip', 'right_hip']) {
      cropped.landmarks[name] = const PoseLandmark(
        x: .5,
        y: 1.5,
        z: 0,
        visibility: .8,
      );
    }
    expect(track(cropped), isNull);
  });
}
