import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pose_landmark.dart';
import '../models/pose_result.dart';
import '../models/try_on_filter.dart';
import '../utils/camera_coordinate_mapper.dart';
import 'garment_surface.dart';
import 'tracked_garment_overlay.dart';

class VirtualClothingOverlay extends StatefulWidget {
  const VirtualClothingOverlay({
    super.key,
    required this.pose,
    required this.filter,
    required this.mapper,
    required this.manualTransform,
    required this.onTransformChanged,
    this.onSelected,
    this.use3D = false,
  });

  final PoseResult pose;
  final TryOnFilter filter;
  final CameraCoordinateMapper mapper;
  final ManualFilterTransform manualTransform;
  final ValueChanged<ManualFilterTransform> onTransformChanged;
  final VoidCallback? onSelected;
  final bool use3D;

  @override
  State<VirtualClothingOverlay> createState() => _VirtualClothingOverlayState();
}

class _VirtualClothingOverlayState extends State<VirtualClothingOverlay> {
  late ManualFilterTransform _startTransform;
  Offset _startFocalPoint = Offset.zero;

  @override
  Widget build(BuildContext context) {
    if (widget.use3D && widget.filter.supports3D) {
      return TrackedGarmentOverlay(
        pose: widget.pose,
        filter: widget.filter,
        mapper: widget.mapper,
        manualTransform: widget.manualTransform,
        onTransformChanged: widget.onTransformChanged,
        onSelected: widget.onSelected,
      );
    }
    final placements = _placements(widget.pose, widget.filter, widget.mapper);
    if (placements.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final placement in placements) _buildPlacement(placement),
      ],
    );
  }

  Widget _buildPlacement(_FilterPlacement placement) {
    final manual = widget.manualTransform;
    final width = placement.width * manual.scale;
    final height = placement.height * manual.scale;
    final center = placement.center + manual.offset;
    final provider = widget.filter.imageBytes != null
        ? MemoryImage(widget.filter.imageBytes!)
        : AssetImage(widget.filter.assetPath) as ImageProvider;
    Widget image = placement.shoeHalf != null
        ? Image(
            image: provider,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          )
        : GarmentSurface(
            image: provider,
            yaw: placement.yaw,
            hemRatio: placement.hemRatio,
            meshCategory: widget.use3D && widget.filter.supports3D
                ? widget.filter.category
                : null,
            fitTrackedWidth: true,
            volume: widget.filter.volume,
          );
    if (placement.shoeHalf != null) {
      image = ClipRect(
        child: Align(
          alignment: placement.shoeHalf == 0
              ? Alignment.centerLeft
              : Alignment.centerRight,
          widthFactor: 0.5,
          child: SizedBox(width: width * 2, height: height, child: image),
        ),
      );
    }
    return Positioned(
      left: center.dx - width / 2,
      top: center.dy - height / 2,
      width: width,
      height: height,
      child: Transform(
        alignment: Alignment.center,
        // Vai xác định trục ngang, thân xác định trục dọc. Áo bám theo
        // người nghiêng thay vì chỉ xoay cả hình chữ nhật theo đường vai.
        transform: Matrix4.rotationZ(manual.rotation)
          ..multiply(
            Matrix4.identity()
              ..setEntry(0, 0, math.cos(placement.angle))
              ..setEntry(1, 0, math.sin(placement.angle))
              ..setEntry(
                0,
                1,
                -math.sin(placement.bodyAngle ?? placement.angle),
              )
              ..setEntry(
                1,
                1,
                math.cos(placement.bodyAngle ?? placement.angle),
              ),
          ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onSelected,
          onScaleStart: (details) {
            _startTransform = widget.manualTransform;
            _startFocalPoint = details.focalPoint;
            widget.onSelected?.call();
          },
          onScaleUpdate: (details) {
            widget.onTransformChanged(
              _startTransform.copyWith(
                offset:
                    _startTransform.offset +
                    (details.focalPoint - _startFocalPoint),
                scale: _startTransform.scale * details.scale,
                rotation: _startTransform.rotation + details.rotation,
              ),
            );
          },
          onScaleEnd: (_) {},
          child: image,
        ),
      ),
    );
  }
}

class _FilterPlacement {
  const _FilterPlacement({
    required this.center,
    required this.width,
    required this.height,
    required this.angle,
    this.bodyAngle,
    this.shoeHalf,
    this.yaw = 0,
    this.hemRatio = 1,
  });

  final Offset center;
  final double width;
  final double height;
  final double angle;
  final double? bodyAngle;
  final int? shoeHalf;
  final double yaw;
  final double hemRatio;
}

List<_FilterPlacement> _placements(
  PoseResult pose,
  TryOnFilter filter,
  CameraCoordinateMapper mapper,
) {
  Offset? point(String name) {
    final landmark = pose.landmarks[name];
    return landmark == null ||
            landmark.visibility < 0.5 ||
            !landmark.x.isFinite ||
            !landmark.y.isFinite
        ? null
        : mapper.mapNormalized(landmark.normalizedOffset);
  }

  double yaw(String firstName, String secondName) {
    final first = pose.landmarks[firstName]!;
    final second = pose.landmarks[secondName]!;
    if (!first.z.isFinite || !second.z.isFinite) return 0;
    final firstScreen = point(firstName)!;
    final secondScreen = point(secondName)!;
    final depth = firstScreen.dx <= secondScreen.dx
        ? second.z - first.z
        : first.z - second.z;
    final span =
        (secondScreen - firstScreen).distance /
        (mapper.imageSize.width * mapper.coverScale);
    return math.atan2(depth, math.max(span, .05)).clamp(-.75, .75);
  }

  _FilterPlacement placement({
    required Offset start,
    required Offset end,
    required double width,
    required double angle,
    double yaw = 0,
    double hemRatio = 1,
  }) {
    final height = (end - start).distance * filter.heightMultiplier;
    final center =
        _midpoint(start, end) +
        Offset(filter.offsetX * width, filter.offsetY * height);
    return _FilterPlacement(
      center: center,
      width: math.max(width * filter.widthMultiplier, 24),
      height: math.max(height, 24),
      angle: angle + filter.defaultRotation,
      yaw: yaw,
      hemRatio: hemRatio,
      bodyAngle:
          math.atan2(end.dy - start.dy, end.dx - start.dx) -
          math.pi / 2 +
          filter.defaultRotation,
    );
  }

  switch (filter.category) {
    case TryOnFilterCategory.top:
    case TryOnFilterCategory.jacket:
    case TryOnFilterCategory.dress:
      final leftShoulder = point('left_shoulder');
      final rightShoulder = point('right_shoulder');
      final isDress = filter.category == TryOnFilterCategory.dress;
      final leftLower = point(isDress ? 'left_knee' : 'left_hip');
      final rightLower = point(isDress ? 'right_knee' : 'right_hip');
      if (leftShoulder == null ||
          rightShoulder == null ||
          leftLower == null ||
          rightLower == null) {
        return const [];
      }
      return <_FilterPlacement>[
        placement(
          start: _midpoint(leftShoulder, rightShoulder),
          end: _midpoint(leftLower, rightLower),
          width: (rightShoulder - leftShoulder).distance,
          angle: _uprightAngle(leftShoulder, rightShoulder),
          yaw: yaw('left_shoulder', 'right_shoulder'),
          hemRatio: isDress
              ? 1
              : ((rightLower - leftLower).distance /
                        math.max((rightShoulder - leftShoulder).distance, 1))
                    .clamp(.75, 1.15),
        ),
      ];
    case TryOnFilterCategory.pants:
    case TryOnFilterCategory.skirt:
      final leftHip = point('left_hip');
      final rightHip = point('right_hip');
      final leftLower = filter.category == TryOnFilterCategory.skirt
          ? point('left_knee')
          : point('left_ankle');
      final rightLower = filter.category == TryOnFilterCategory.skirt
          ? point('right_knee')
          : point('right_ankle');
      if (leftHip == null ||
          rightHip == null ||
          leftLower == null ||
          rightLower == null) {
        return const [];
      }
      return <_FilterPlacement>[
        placement(
          start: _midpoint(leftHip, rightHip),
          end: _midpoint(leftLower, rightLower),
          width: (rightHip - leftHip).distance,
          angle: _uprightAngle(leftHip, rightHip),
          yaw: yaw('left_hip', 'right_hip'),
        ),
      ];
    case TryOnFilterCategory.shoes:
      return _shoePlacements(pose.landmarks, filter, mapper);
  }
}

List<_FilterPlacement> _shoePlacements(
  Map<String, PoseLandmark> landmarks,
  TryOnFilter filter,
  CameraCoordinateMapper mapper,
) {
  final output = <_FilterPlacement>[];
  for (final side in const <String>['left', 'right']) {
    final ankle = landmarks['${side}_ankle'];
    final heel = landmarks['${side}_heel'];
    final toe = landmarks['${side}_foot_index'];
    if (ankle == null ||
        heel == null ||
        toe == null ||
        ankle.visibility < 0.5 ||
        heel.visibility < 0.5 ||
        toe.visibility < 0.5) {
      continue;
    }
    final anklePoint = mapper.mapNormalized(ankle.normalizedOffset);
    final heelPoint = mapper.mapNormalized(heel.normalizedOffset);
    final toePoint = mapper.mapNormalized(toe.normalizedOffset);
    final footLength = math.max((toePoint - heelPoint).distance, 18);
    final width = footLength * filter.widthMultiplier * 1.8;
    output.add(
      _FilterPlacement(
        center:
            _midpoint(anklePoint, toePoint) +
            Offset(filter.offsetX * width, filter.offsetY * width),
        width: width,
        height: math.max(width * filter.heightMultiplier, 18),
        angle: _angle(heelPoint, toePoint) + filter.defaultRotation,
        shoeHalf: side == 'left' ? 0 : 1,
      ),
    );
  }
  return output;
}

Offset _midpoint(Offset first, Offset second) => (first + second) / 2;

double _angle(Offset first, Offset second) {
  return math.atan2(second.dy - first.dy, second.dx - first.dx);
}

// MediaPipe dùng trái/phải của người, có thể ngược với trái/phải màn hình.
// Sắp theo tọa độ màn hình để đổi camera không làm áo lộn ngược 180 độ.
double _uprightAngle(Offset first, Offset second) =>
    first.dx <= second.dx ? _angle(first, second) : _angle(second, first);
