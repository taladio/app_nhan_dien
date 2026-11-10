import 'package:app_nhan_dien/models/pose_landmark.dart';
import 'package:app_nhan_dien/models/pose_result.dart';
import 'package:app_nhan_dien/models/try_on_filter.dart';
import 'package:app_nhan_dien/utils/camera_coordinate_mapper.dart';
import 'package:app_nhan_dien/widgets/virtual_clothing_overlay.dart';
import 'package:app_nhan_dien/widgets/garment_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'body_garment_pose_test.dart' show turnedBody;

import 'package:app_nhan_dien/models/garment_mesh.dart';
import 'package:app_nhan_dien/widgets/tracked_garment_overlay.dart';

import 'dart:math' as math;

Future<void> showOverlay(
  WidgetTester tester,
  TryOnFilterCategory category,
  Map<String, PoseLandmark> landmarks,
) => tester.pumpWidget(
  MaterialApp(
    home: VirtualClothingOverlay(
      pose: PoseResult(
        frameId: 1,
        timestampMs: 1,
        processingMs: 1,
        poseDetected: true,
        bodyVisible: false,
        landmarks: landmarks,
      ),
      filter: tryOnFilters.firstWhere((item) => item.category == category),
      mapper: const CameraCoordinateMapper(
        imageSize: Size(400, 600),
        viewportSize: Size(400, 600),
        rotationDegrees: 0,
        mirrored: false,
      ),
      manualTransform: const ManualFilterTransform(),
      onTransformChanged: (_) {},
    ),
  ),
);

PoseLandmark point(
  double x,
  double y, {
  double visibility = 0.9,
  double z = 0,
}) => PoseLandmark(x: x, y: y, z: z, visibility: visibility);

void main() {
  testWidgets(
    'live overlay turns to the back and hides safely without world data',
    (tester) async {
      final filter = TryOnFilter.fromImage(
        id: 'turn',
        category: TryOnFilterCategory.top,
        bytes: Uint8List(0),
        templateAligned: true,
      );
      Future<void> show(PoseResult pose) => tester.pumpWidget(
        MaterialApp(
          home: TrackedGarmentOverlay(
            pose: pose,
            filter: filter,
            mapper: const CameraCoordinateMapper(
              imageSize: Size(400, 600),
              viewportSize: Size(400, 600),
              rotationDegrees: 0,
              mirrored: true,
            ),
            manualTransform: const ManualFilterTransform(),
            onTransformChanged: (_) {},
          ),
        ),
      );
      await show(turnedBody(0));
      final width = tester
          .widget<GarmentSurface>(find.byType(GarmentSurface))
          .bodyPose!
          .width;
      await show(turnedBody(math.pi, frameId: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final back = tester
          .widget<GarmentSurface>(find.byType(GarmentSurface))
          .bodyPose!;
      expect(
        back.orientation.apply(const MeshPoint(0, 0, 1)).z,
        closeTo(-1, 1e-6),
      );
      expect(back.width, closeTo(width, 1e-6));
      await show(turnedBody(0, world: false, frameId: 3));
      expect(find.byType(GarmentSurface), findsNothing);
      expect(find.byKey(const Key('garment_3d_tracking_hint')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('aligned imported photo uses the 3D renderer only when enabled', (
    tester,
  ) async {
    final filter = TryOnFilter.fromImage(
      id: '3d',
      category: TryOnFilterCategory.top,
      bytes: Uint8List(0),
      templateAligned: true,
      volume: 1.4,
    );
    // Inspect the render configuration before the empty fixture is decoded.
    for (final enabled in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: VirtualClothingOverlay(
            pose: turnedBody(.5),
            filter: filter,
            mapper: const CameraCoordinateMapper(
              imageSize: Size(400, 600),
              viewportSize: Size(400, 600),
              rotationDegrees: 0,
              mirrored: false,
            ),
            manualTransform: const ManualFilterTransform(),
            onTransformChanged: (_) {},
            use3D: enabled,
          ),
        ),
      );
      final surface = tester.widget<GarmentSurface>(
        find.byType(GarmentSurface),
      );
      expect(surface.meshCategory, enabled ? TryOnFilterCategory.top : null);
      expect(surface.bodyPose != null, enabled);
      expect(surface.fitTrackedWidth, !enabled);
      expect(surface.volume, 1.4);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reversed anatomical shoulders never turn the shirt upside down',
    (tester) async {
      await showOverlay(tester, TryOnFilterCategory.top, {
        'left_shoulder': point(0.7, 0.2),
        'right_shoulder': point(0.3, 0.2),
        'left_hip': point(0.65, 0.5),
        'right_hip': point(0.35, 0.5),
      });
      final transform = tester
          .widget<Transform>(
            find.descendant(
              of: find.byType(VirtualClothingOverlay),
              matching: find.byType(Transform),
            ),
          )
          .transform;
      expect(transform.entry(0, 0), closeTo(1, 0.001));
      expect(transform.entry(1, 1), closeTo(1, 0.001));
    },
  );

  testWidgets('shirt follows leaning torso even when shoulders are level', (
    tester,
  ) async {
    await showOverlay(tester, TryOnFilterCategory.top, {
      'left_shoulder': point(0.3, 0.2),
      'right_shoulder': point(0.7, 0.2),
      'left_hip': point(0.45, 0.5),
      'right_hip': point(0.75, 0.5),
    });
    final transform = tester
        .widget<Transform>(
          find.descendant(
            of: find.byType(VirtualClothingOverlay),
            matching: find.byType(Transform),
          ),
        )
        .transform;
    expect(transform.entry(0, 1), greaterThan(0));
    expect(transform.entry(1, 1), greaterThan(0));
  });

  testWidgets('top remains visible without legs or feet', (tester) async {
    await showOverlay(tester, TryOnFilterCategory.top, {
      'left_shoulder': point(0.3, 0.2),
      'right_shoulder': point(0.7, 0.2),
      'left_hip': point(0.35, 0.5),
      'right_hip': point(0.65, 0.5),
    });
    expect(find.byType(GarmentSurface), findsOneWidget);
  });

  testWidgets('pants do not require visible shoulders', (tester) async {
    await showOverlay(tester, TryOnFilterCategory.pants, {
      'left_hip': point(0.35, 0.5),
      'right_hip': point(0.65, 0.5),
      'left_ankle': point(0.35, 0.9),
      'right_ankle': point(0.65, 0.9),
    });
    expect(find.byType(GarmentSurface), findsOneWidget);
  });

  testWidgets('depth follows visible shoulders and adapts waist width', (
    tester,
  ) async {
    await showOverlay(tester, TryOnFilterCategory.top, {
      'left_shoulder': point(.3, .2, z: -.15),
      'right_shoulder': point(.7, .2, z: .15),
      'left_hip': point(.35, .5),
      'right_hip': point(.65, .5),
    });
    final first = tester.widget<GarmentSurface>(find.byType(GarmentSurface));
    expect(first.yaw, greaterThan(0));
    expect(first.hemRatio, lessThan(1));
    await showOverlay(tester, TryOnFilterCategory.top, {
      'left_shoulder': point(.7, .2, z: -.15),
      'right_shoulder': point(.3, .2, z: .15),
      'left_hip': point(.65, .5),
      'right_hip': point(.35, .5),
    });
    final mirrored = tester.widget<GarmentSurface>(find.byType(GarmentSurface));
    expect(mirrored.yaw, closeTo(-first.yaw, .001));
  });

  for (final side in ['left', 'right']) {
    testWidgets('single $side foot uses correct half of shoe image', (
      tester,
    ) async {
      await showOverlay(tester, TryOnFilterCategory.shoes, {
        '${side}_ankle': point(0.4, 0.8),
        '${side}_heel': point(0.4, 0.85),
        '${side}_foot_index': point(0.5, 0.9),
      });
      expect(find.byType(Image), findsOneWidget);
      final crop = tester.widget<Align>(
        find.byWidgetPredicate(
          (widget) => widget is Align && widget.widthFactor == 0.5,
        ),
      );
      expect(
        crop.alignment,
        side == 'left' ? Alignment.centerLeft : Alignment.centerRight,
      );
    });
  }

  testWidgets('shoe is hidden when its foot points are unreliable', (
    tester,
  ) async {
    await showOverlay(tester, TryOnFilterCategory.shoes, {
      'left_ankle': point(0.4, 0.8),
      'left_heel': point(0.4, 0.85, visibility: 0.1),
      'left_foot_index': point(0.5, 0.9),
    });
    expect(find.byType(Image), findsNothing);
  });
}
