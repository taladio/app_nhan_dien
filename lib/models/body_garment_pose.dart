import 'dart:math' as math;
import 'dart:ui';

import '../utils/camera_coordinate_mapper.dart';
import 'garment_mesh.dart';
import 'pose_landmark.dart';
import 'pose_result.dart';
import 'try_on_filter.dart';

/// A rigid garment frame in camera space. Anatomical left/right never swaps
/// when someone turns away. Reflection is applied only after projection.
class BodyGarmentPose {
  const BodyGarmentPose({
    required this.anchor,
    required this.orientation,
    required this.width,
    required this.height,
    required this.anchorV,
    required this.mirrored,
  });
  final Offset anchor;
  final BodyRotation orientation;
  final double width, height, anchorV;
  final bool mirrored;

  MeshPoint rotateVertex(MeshPoint p, double volume) => orientation.apply(
    MeshPoint(
      (p.x - .5) * width,
      (p.y - anchorV) * height,
      p.z * width * volume,
    ),
  );

  Offset project(MeshPoint cameraPoint) =>
      anchor + Offset(mirrored ? -cameraPoint.x : cameraPoint.x, cameraPoint.y);

  static BodyGarmentPose lerp(BodyGarmentPose a, BodyGarmentPose b, double t) =>
      BodyGarmentPose(
        anchor: Offset.lerp(a.anchor, b.anchor, t)!,
        orientation: BodyRotation.slerp(a.orientation, b.orientation, t),
        width: a.width + (b.width - a.width) * t,
        height: a.height + (b.height - a.height) * t,
        anchorV: b.anchorV,
        mirrored: b.mirrored,
      );

  static BodyGarmentPose? fromPose(
    PoseResult pose,
    TryOnFilter filter,
    CameraCoordinateMapper mapper,
    ManualFilterTransform manual,
  ) {
    if (!pose.poseDetected || !filter.supports3D) return null;
    final upperBody = switch (filter.category) {
      TryOnFilterCategory.top ||
      TryOnFilterCategory.jacket ||
      TryOnFilterCategory.dress => true,
      _ => false,
    };
    final upper = upperBody ? 'shoulder' : 'hip';
    final lower = switch (filter.category) {
      TryOnFilterCategory.top || TryOnFilterCategory.jacket => 'hip',
      TryOnFilterCategory.pants => 'ankle',
      _ => 'knee',
    };
    final names = [
      'left_$upper',
      'right_$upper',
      'left_$lower',
      'right_$lower',
    ];
    bool valid(PoseLandmark? p) =>
        p != null &&
        p.x.isFinite &&
        p.y.isFinite &&
        p.z.isFinite &&
        p.visibility.isFinite &&
        p.visibility >= .12;
    if (names.any(
      (n) => !valid(pose.landmarks[n]) || !valid(pose.worldLandmarks[n]),
    )) {
      return null;
    }
    final image = [for (final name in names) pose.landmarks[name]!];
    // A hidden shoulder can be estimated, but both sides cannot be unreliable.
    if (math.max(image[0].visibility, image[1].visibility) < .55 ||
        math.max(image[2].visibility, image[3].visibility) < .45) {
      return null;
    }
    final topNormalized =
        (image[0].normalizedOffset + image[1].normalizedOffset) / 2;
    final bottomNormalized =
        (image[2].normalizedOffset + image[3].normalizedOffset) / 2;
    if ([
      topNormalized,
      bottomNormalized,
    ].any((p) => p.dx < -.2 || p.dx > 1.2 || p.dy < -.2 || p.dy > 1.2)) {
      return null;
    }

    MeshPoint worldPoint(String name) {
      final p = pose.worldLandmarks[name]!;
      // MediaPipe Z grows away from camera; the renderer uses +Z toward camera.
      final xy = switch (mapper.rotationDegrees) {
        90 => Offset(-p.y, p.x),
        180 => Offset(-p.x, -p.y),
        270 => Offset(p.y, -p.x),
        _ => Offset(p.x, p.y),
      };
      return MeshPoint(xy.dx, xy.dy, -p.z);
    }

    final world = [for (final name in names) worldPoint(name)];
    final across = world[0] - world[1]; // Subject's right -> subject's left.
    final down = (world[2] + world[3] - world[0] - world[1]) * .5;
    final acrossLength = math.sqrt(across.dot(across));
    final downLength = math.sqrt(down.dot(down));
    if (acrossLength < .06 || downLength < .10) return null;
    final xAxis = across.normalized;
    final vertical = down - xAxis * down.dot(xAxis);
    if (vertical.dot(vertical) < .0025) return null;
    final yAxis = vertical.normalized;
    final zAxis = xAxis.cross(yAxis).normalized;

    final screen = [
      for (final p in image) mapper.mapNormalized(p.normalizedOffset),
    ];
    final top = (screen[0] + screen[1]) / 2;
    final bottom = (screen[2] + screen[3]) / 2;
    final widths = [across, world[2] - world[3], down];
    final spans = [
      (screen[0] - screen[1]).distance,
      (screen[2] - screen[3]).distance,
      (bottom - top).distance,
    ];
    var numerator = 0.0, denominator = 0.0;
    for (var i = 0; i < widths.length; i++) {
      final projectedLength = math.sqrt(
        widths[i].x * widths[i].x + widths[i].y * widths[i].y,
      );
      numerator += spans[i] * projectedLength;
      denominator += projectedLength * projectedLength;
    }
    if (denominator < .004) return null;
    final pixelsPerMetre = numerator / denominator;
    final (patternSpan, patternLength, anchorV) = switch (filter.category) {
      TryOnFilterCategory.top => (.52, .85, .105),
      TryOnFilterCategory.jacket => (.56, .85, .105),
      TryOnFilterCategory.dress => (.36, .90, .085),
      TryOnFilterCategory.pants => (.76, .92, .03),
      _ => (.50, .94, .02),
    };
    final width = acrossLength * pixelsPerMetre / patternSpan;
    final height = downLength * pixelsPerMetre / patternLength;
    if (!width.isFinite ||
        !height.isFinite ||
        width < 24 ||
        height < 24 ||
        width > mapper.viewportSize.longestSide * 2 ||
        height > mapper.viewportSize.longestSide * 2) {
      return null;
    }
    // Manual Z-rotation happens in camera space, before the final reflection.
    MeshPoint roll(MeshPoint p) {
      final angle = mirroredAngle(manual.rotation, mapper.mirrored);
      return MeshPoint(
        p.x * math.cos(angle) - p.y * math.sin(angle),
        p.x * math.sin(angle) + p.y * math.cos(angle),
        p.z,
      );
    }

    return BodyGarmentPose(
      anchor: top + manual.offset,
      orientation: BodyRotation.fromAxes(roll(xAxis), roll(yAxis), roll(zAxis)),
      width: width * manual.scale,
      height: height * manual.scale,
      anchorV: anchorV,
      mirrored: mapper.mirrored,
    );
  }

  static double mirroredAngle(double angle, bool mirrored) =>
      mirrored ? -angle : angle;
}

/// Unit quaternion: smooth transitions across +180/-180 without flipping fronts.
class BodyRotation {
  const BodyRotation(this.x, this.y, this.z, this.w);
  final double x, y, z, w;

  factory BodyRotation.fromAxes(MeshPoint a, MeshPoint b, MeshPoint c) {
    final trace = a.x + b.y + c.z;
    if (trace > 0) {
      final s = math.sqrt(trace + 1) * 2;
      return BodyRotation(
        (b.z - c.y) / s,
        (c.x - a.z) / s,
        (a.y - b.x) / s,
        s / 4,
      );
    }
    if (a.x > b.y && a.x > c.z) {
      final s = math.sqrt(1 + a.x - b.y - c.z) * 2;
      return BodyRotation(
        s / 4,
        (b.x + a.y) / s,
        (c.x + a.z) / s,
        (b.z - c.y) / s,
      );
    }
    if (b.y > c.z) {
      final s = math.sqrt(1 + b.y - a.x - c.z) * 2;
      return BodyRotation(
        (b.x + a.y) / s,
        s / 4,
        (c.y + b.z) / s,
        (c.x - a.z) / s,
      );
    }
    final s = math.sqrt(1 + c.z - a.x - b.y) * 2;
    return BodyRotation(
      (c.x + a.z) / s,
      (c.y + b.z) / s,
      s / 4,
      (a.y - b.x) / s,
    );
  }

  MeshPoint apply(MeshPoint p) {
    final vector = MeshPoint(x, y, z);
    final uv = vector.cross(p);
    return p + uv * (2 * w) + vector.cross(uv) * 2;
  }

  static BodyRotation slerp(BodyRotation a, BodyRotation b, double t) {
    var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    final sign = dot < 0 ? -1.0 : 1.0;
    dot = dot.abs().clamp(0, 1);
    var left = 1 - t, right = t;
    if (dot < .9995) {
      final angle = math.acos(dot);
      left = math.sin((1 - t) * angle) / math.sin(angle);
      right = math.sin(t * angle) / math.sin(angle);
    }
    final x = a.x * left + b.x * right * sign;
    final y = a.y * left + b.y * right * sign;
    final z = a.z * left + b.z * right * sign;
    final w = a.w * left + b.w * right * sign;
    final length = math.sqrt(x * x + y * y + z * z + w * w);
    return BodyRotation(x / length, y / length, z / length, w / length);
  }
}
