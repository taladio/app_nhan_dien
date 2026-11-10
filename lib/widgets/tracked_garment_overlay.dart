import 'package:flutter/material.dart';

import '../models/body_garment_pose.dart';
import '../models/pose_result.dart';
import '../models/try_on_filter.dart';
import '../utils/camera_coordinate_mapper.dart';
import 'garment_surface.dart';

/// Live full-turn tracking, separate from the flat-photo placement algorithm.
class TrackedGarmentOverlay extends StatefulWidget {
  const TrackedGarmentOverlay({
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
  State<TrackedGarmentOverlay> createState() => _TrackedGarmentOverlayState();
}

class _TrackedGarmentOverlayState extends State<TrackedGarmentOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  BodyGarmentPose? _from, _target;
  late ManualFilterTransform _start;
  Offset _startFocal = Offset.zero;

  BodyGarmentPose? get _current => _target == null || _from == null
      ? _target
      : BodyGarmentPose.lerp(_from!, _target!, _motion.value);

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _update(animate: false);
  }

  void _update({required bool animate}) {
    final next = BodyGarmentPose.fromPose(
      widget.pose,
      widget.filter,
      widget.mapper,
      widget.manualTransform,
    );
    final previous = _current;
    _motion.stop();
    _from = previous;
    _target = next;
    if (animate && previous != null && next != null) {
      _motion.forward(from: 0);
    } else {
      _from = next;
      _motion.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant TrackedGarmentOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update(
      animate:
          oldWidget.filter.id == widget.filter.id &&
          oldWidget.mapper.mirrored == widget.mapper.mirrored &&
          oldWidget.mapper.rotationDegrees == widget.mapper.rotationDegrees &&
          oldWidget.pose.frameId != widget.pose.frameId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_target == null) {
      return IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -.2),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              widget.pose.worldLandmarks.isEmpty
                  ? 'Chưa có dữ liệu xoay 3D. Hãy khởi động lại backend.'
                  : 'Để đồ bám xoay, hãy đứng lùi lại cho camera thấy rõ vai và hông; quần/váy cần thấy cả chân.',
              key: const Key('garment_3d_tracking_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onSelected,
      onScaleStart: (details) {
        _start = widget.manualTransform;
        _startFocal = details.focalPoint;
        widget.onSelected?.call();
      },
      onScaleUpdate: (details) => widget.onTransformChanged(
        _start.copyWith(
          offset: _start.offset + details.focalPoint - _startFocal,
          scale: _start.scale * details.scale,
          rotation: _start.rotation + details.rotation,
        ),
      ),
      child: AnimatedBuilder(
        animation: _motion,
        builder: (_, _) => GarmentSurface(
          image: MemoryImage(widget.filter.imageBytes!),
          meshCategory: widget.filter.category,
          bodyPose: _current,
          volume: widget.filter.volume,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }
}
