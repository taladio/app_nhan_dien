import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pose_landmark.dart';
import '../models/pose_result.dart';
import '../models/try_on_filter.dart';
import '../utils/camera_coordinate_mapper.dart';

class VirtualClothingOverlay extends StatefulWidget {
  const VirtualClothingOverlay({
    super.key,
    required this.pose,
    required this.filter,
    required this.mapper,
    required this.manualTransform,
    required this.onTransformChanged,
    this.onSelected,
  });

  final PoseResult pose;
  final TryOnFilter filter;
  final CameraCoordinateMapper mapper;
  final ManualFilterTransform manualTransform;
  final ValueChanged<ManualFilterTransform> onTransformChanged;
  final VoidCallback? onSelected;

  @override
  State<VirtualClothingOverlay> createState() => _VirtualClothingOverlayState();
}

class _VirtualClothingOverlayState extends State<VirtualClothingOverlay> {
  late ManualFilterTransform _startTransform;
  Offset _startFocalPoint = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final placements = _placements(widget.pose, widget.filter, widget.mapper);
    if (placements.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (var index = 0; index < placements.length; index++)
          _buildPlacement(
            placements[index],
            shoeHalf: placements.length == 2 ? index : null,
          ),
      ],
    );
  }

  Widget _buildPlacement(_FilterPlacement placement, {int? shoeHalf}) {
    final manual = widget.manualTransform;
    final width = placement.width * manual.scale;
    final height = placement.height * manual.scale;
    final center = placement.center + manual.offset;
    Widget image = Image.asset(
      widget.filter.assetPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    if (shoeHalf != null) {
      image = ClipRect(
        child: Align(
          alignment: shoeHalf == 0
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
      child: Transform.rotate(
        angle: placement.angle + manual.rotation,
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
  });

  final Offset center;
  final double width;
  final double height;
  final double angle;
}

List<_FilterPlacement> _placements(
  PoseResult pose,
  TryOnFilter filter,
  CameraCoordinateMapper mapper,
) {
  Offset? point(String name) {
    final landmark = pose.landmarks[name];
    return landmark == null
        ? null
        : mapper.mapNormalized(landmark.normalizedOffset);
  }

  final leftShoulder = point('left_shoulder');
  final rightShoulder = point('right_shoulder');
  final leftHip = point('left_hip');
  final rightHip = point('right_hip');
  if (leftShoulder == null ||
      rightShoulder == null ||
      leftHip == null ||
      rightHip == null) {
    return const <_FilterPlacement>[];
  }
  final shoulderCenter = _midpoint(leftShoulder, rightShoulder);
  final hipCenter = _midpoint(leftHip, rightHip);
  final shoulderWidth = (rightShoulder - leftShoulder).distance;
  final hipWidth = (rightHip - leftHip).distance;
  final shoulderAngle = _angle(leftShoulder, rightShoulder);
  final hipAngle = _angle(leftHip, rightHip);

  _FilterPlacement placement({
    required Offset start,
    required Offset end,
    required double width,
    required double angle,
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
    );
  }

  switch (filter.category) {
    case TryOnFilterCategory.top:
    case TryOnFilterCategory.jacket:
      return <_FilterPlacement>[
        placement(
          start: shoulderCenter,
          end: hipCenter,
          width: shoulderWidth,
          angle: shoulderAngle,
        ),
      ];
    case TryOnFilterCategory.pants:
    case TryOnFilterCategory.skirt:
      final leftLower = filter.category == TryOnFilterCategory.skirt
          ? point('left_knee')
          : point('left_ankle');
      final rightLower = filter.category == TryOnFilterCategory.skirt
          ? point('right_knee')
          : point('right_ankle');
      if (leftLower == null || rightLower == null) return const [];
      return <_FilterPlacement>[
        placement(
          start: hipCenter,
          end: _midpoint(leftLower, rightLower),
          width: hipWidth,
          angle: hipAngle,
        ),
      ];
    case TryOnFilterCategory.dress:
      final leftKnee = point('left_knee');
      final rightKnee = point('right_knee');
      if (leftKnee == null || rightKnee == null) return const [];
      return <_FilterPlacement>[
        placement(
          start: shoulderCenter,
          end: _midpoint(leftKnee, rightKnee),
          width: shoulderWidth,
          angle: shoulderAngle,
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
    if (ankle == null || heel == null || toe == null) continue;
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
      ),
    );
  }
  return output;
}

Offset _midpoint(Offset first, Offset second) => (first + second) / 2;

double _angle(Offset first, Offset second) {
  return math.atan2(second.dy - first.dy, second.dx - first.dx);
}
