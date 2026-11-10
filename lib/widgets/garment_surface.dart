import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/garment_mesh.dart';
import '../models/body_garment_pose.dart';
import '../models/try_on_filter.dart';
import '../painters/garment_mesh_painter.dart';

/// Shares one decoded photo between the flat filter and the 3D shell renderer.
class GarmentSurface extends StatefulWidget {
  const GarmentSurface({
    super.key,
    required this.image,
    this.yaw = 0,
    this.hemRatio = 1,
    this.meshCategory,
    this.pitch = 0,
    this.volume = 1,
    this.wireframe = false,
    this.fitTrackedWidth = false,
    this.bodyPose,
  });
  final ImageProvider image;
  final double yaw;
  final double hemRatio;
  final TryOnFilterCategory? meshCategory;
  final double pitch;
  final double volume;
  final bool wireframe;
  final bool fitTrackedWidth;
  final BodyGarmentPose? bodyPose;

  @override
  State<GarmentSurface> createState() => _GarmentSurfaceState();
}

class _GarmentSurfaceState extends State<GarmentSurface> {
  ImageStream? _stream;
  ImageInfo? _info;
  ui.ImageShader? _shader;
  bool _failed = false;
  Color _materialColor = const Color(0xff899b9a);
  ImageInfo? _materialRequestedFor;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant GarmentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
    if (widget.meshCategory != null && _info != null) {
      unawaited(_readMaterial(_info!));
    }
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _shader?.dispose();
    _shader = null;
    _info?.dispose();
    _info = null;
    _materialRequestedFor = null;
    _materialColor = const Color(0xff899b9a);
    _failed = false;
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final oldInfo = _info;
    final oldShader = _shader;
    setState(() {
      _info = info;
      _failed = false;
      _shader = ui.ImageShader(
        info.image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      );
    });
    oldShader?.dispose();
    oldInfo?.dispose();
    if (widget.meshCategory != null) unawaited(_readMaterial(info));
  }

  Future<void> _readMaterial(ImageInfo info) async {
    if (identical(_materialRequestedFor, info)) return;
    _materialRequestedFor = info;
    // Only a tiny in-memory thumbnail is read, once per image, never per pose.
    final source = info.image.clone();
    try {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        const Rect.fromLTWH(0, 0, 32, 32),
        Paint(),
      );
      final picture = recorder.endRecording();
      final ui.Image thumbnail;
      try {
        thumbnail = await picture.toImage(32, 32);
      } finally {
        picture.dispose();
      }
      try {
        final rgba = await thumbnail.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (rgba == null || !mounted || !identical(info, _info)) return;
        var r = 0, g = 0, b = 0, count = 0;
        for (var i = 0; i < rgba.lengthInBytes; i += 4) {
          if (rgba.getUint8(i + 3) < 200) continue;
          r += rgba.getUint8(i);
          g += rgba.getUint8(i + 1);
          b += rgba.getUint8(i + 2);
          count++;
        }
        if (count > 0) {
          setState(
            () => _materialColor = Color.fromARGB(
              255,
              (r / count).round(),
              (g / count).round(),
              (b / count).round(),
            ),
          );
        }
      } finally {
        thumbnail.dispose();
      }
    } catch (_) {
      // A failed colour read keeps the neutral material; the photo still draws.
    } finally {
      source.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final shader = _shader;
    if (_failed) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white70),
      );
    }
    if (info == null || shader == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        painter: widget.meshCategory != null
            ? GarmentMeshPainter(
                mesh: GarmentMesh.forCategory(widget.meshCategory!),
                image: info.image,
                shader: shader,
                yaw: widget.yaw,
                pitch: widget.pitch,
                volume: widget.volume,
                hemRatio: widget.hemRatio,
                wireframe: widget.wireframe,
                fitTrackedWidth: widget.fitTrackedWidth,
                materialColor: _materialColor,
                bodyPose: widget.bodyPose,
              )
            : GarmentSurfacePainter(
                image: info.image,
                shader: shader,
                yaw: widget.yaw,
                hemRatio: widget.hemRatio,
              ),
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _shader?.dispose();
    _info?.dispose();
    super.dispose();
  }
}

class GarmentSurfacePainter extends CustomPainter {
  const GarmentSurfacePainter({
    required this.image,
    required this.shader,
    this.yaw = 0,
    this.hemRatio = 1,
  });
  final ui.Image image;
  final ui.ImageShader shader;
  final double yaw;
  final double hemRatio;
  static const _columns = 16;
  static const _rows = 12;
  static final _triangles = <int>[
    for (var y = 0; y < _rows; y++)
      for (var x = 0; x < _columns; x++) ...[
        y * (_columns + 1) + x,
        y * (_columns + 1) + x + 1,
        (y + 1) * (_columns + 1) + x,
        y * (_columns + 1) + x + 1,
        (y + 1) * (_columns + 1) + x + 1,
        (y + 1) * (_columns + 1) + x,
      ],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final positions = <Offset>[];
    final texture = <Offset>[];
    final colors = <Color>[];
    final turn = math.sin(yaw.clamp(-.75, .75));
    final hem = hemRatio.clamp(.75, 1.15);
    for (var row = 0; row <= _rows; row++) {
      final v = row / _rows;
      final taper = 1 + (hem - 1) * ((v - .10) / .85).clamp(0, 1);
      for (var column = 0; column <= _columns; column++) {
        final u = column / _columns;
        final horizontal = u * 2 - 1;
        final curvedX = math.sin(horizontal * .52) / math.sin(.52);
        final bulge =
            (math.cos(horizontal * .52) - math.cos(.52)) / (1 - math.cos(.52));
        final perspective = 1 + turn * curvedX * .10;
        positions.add(
          Offset(
            (.5 + curvedX * .5 * taper / perspective) * size.width,
            (.5 +
                    (v - .5) / perspective +
                    .012 * bulge * math.sin(math.pi * v)) *
                size.height,
          ),
        );
        texture.add(Offset(u * image.width, v * image.height));
        final light =
            (.94 +
                    .06 * bulge -
                    .12 * horizontal.abs() -
                    .10 * turn * horizontal)
                .clamp(.68, 1.0);
        final channel = (255 * light).round();
        colors.add(Color.fromARGB(255, channel, channel, channel));
      }
    }
    final mesh = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      colors: colors,
      indices: _triangles,
    );
    try {
      // Multiplication keeps transparent pixels transparent, including the neck
      // and the gap between trouser legs. No opaque rectangular shadow is added.
      canvas.drawVertices(mesh, BlendMode.modulate, Paint()..shader = shader);
    } finally {
      mesh.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant GarmentSurfacePainter old) =>
      image != old.image || yaw != old.yaw || hemRatio != old.hemRatio;
}
