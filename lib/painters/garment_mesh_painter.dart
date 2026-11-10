import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/garment_mesh.dart';
import '../models/body_garment_pose.dart';

/// Projects actual XYZ geometry with perspective, lighting and depth ordering.
/// Flutter draws the projected triangles; no external engine or API is needed.
class GarmentMeshPainter extends CustomPainter {
  const GarmentMeshPainter({
    required this.mesh,
    required this.image,
    required this.shader,
    this.yaw = 0,
    this.pitch = 0,
    this.volume = 1,
    this.hemRatio = 1,
    this.fitTrackedWidth = false,
    this.wireframe = false,
    this.materialColor = const Color(0xff899b9a),
    this.bodyPose,
  });

  final GarmentMesh mesh;
  final ui.Image image;
  final ui.ImageShader shader;
  final double yaw, pitch, volume, hemRatio;
  final bool fitTrackedWidth, wireframe;
  final Color materialColor;
  final BodyGarmentPose? bodyPose;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final turn = yaw.isFinite ? yaw : 0.0;
    final tilt = pitch.isFinite ? pitch.clamp(-1.2, 1.2) : 0.0;
    final depth = volume.isFinite ? volume.clamp(.4, 1.8) : 1.0;
    final hem = hemRatio.isFinite ? hemRatio.clamp(.75, 1.15) : 1.0;
    final cy = math.cos(turn), sy = math.sin(turn);
    final cp = math.cos(tilt), sp = math.sin(tilt);
    // Pose width is already foreshortened. Undo that once in live mode only.
    final fit = fitTrackedWidth ? 1 / math.max(cy.abs(), .65) : 1.0;
    final points = <MeshPoint>[];
    final projected = <Offset>[];
    for (final vertex in mesh.vertices) {
      final p = vertex.position;
      final tracked = bodyPose;
      if (tracked != null) {
        final cameraPoint = tracked.rotateVertex(p, depth);
        // Fit from real-world bone lengths once. No screen-width compensation,
        // yaw clamp, or second 2D transform can flatten the body-space mesh.
        points.add(cameraPoint * (1 / size.width));
        projected.add(tracked.project(cameraPoint));
        continue;
      }
      final taper = 1 + (hem - 1) * ((p.y - .1) / .85).clamp(0, 1);
      final x = (p.x - .5) * taper;
      final y = (p.y - .5) * size.height / size.width;
      final z = p.z * depth;
      final rx = x * cy + z * sy;
      final rz = -x * sy + z * cy;
      final rotated = MeshPoint(rx, y * cp - rz * sp, y * sp + rz * cp);
      points.add(rotated);
      final perspective = 4 / math.max(4 - rotated.z, 1);
      projected.add(
        Offset(
          size.width * (.5 + rotated.x * perspective * fit),
          size.height * .5 + rotated.y * size.width * perspective,
        ),
      );
    }

    final visible = <(GarmentFace, double)>[];
    final normals = List.filled(points.length, const MeshPoint(0, 0, 0));
    const light = MeshPoint(-.35, -.45, .82);
    for (final face in mesh.faces) {
      final a = points[face.a], b = points[face.b], c = points[face.c];
      final normal = (b - a).cross(c - a);
      for (final index in [face.a, face.b, face.c]) {
        normals[index] = normals[index] + normal;
      }
      final center = (a + b + c) * (1 / 3);
      final facing = bodyPose == null
          ? normal.dot(const MeshPoint(0, 0, 4) - center)
          : normal.z;
      if (facing <= 0) continue;
      visible.add((face, center.z));
    }
    visible.sort((a, b) => a.$2.compareTo(b.$2));

    // Batch contiguous materials without disturbing far-to-near ordering.
    var positions = <Offset>[];
    var texture = <Offset>[];
    var colors = <Color>[];
    bool? textured;
    void flush() {
      if (positions.isEmpty) return;
      final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: texture,
        colors: colors,
      );
      try {
        canvas.drawVertices(
          vertices,
          textured! ? BlendMode.modulate : BlendMode.dst,
          Paint()..shader = shader,
        );
      } finally {
        vertices.dispose();
      }
      positions = [];
      texture = [];
      colors = [];
    }

    for (final (face, _) in visible) {
      if (textured != face.textured) {
        flush();
        textured = face.textured;
      }
      final base = face.textured ? Colors.white : materialColor;
      for (final index in [face.a, face.b, face.c]) {
        final brightness =
            (.48 + .52 * math.max(0, normals[index].normalized.dot(light)))
                .clamp(.35, 1.0);
        final color = Color.fromARGB(
          255,
          (base.r * 255 * brightness).round(),
          (base.g * 255 * brightness).round(),
          (base.b * 255 * brightness).round(),
        );
        positions.add(projected[index]);
        final uv = mesh.vertices[index].uv;
        texture.add(Offset(uv.dx * image.width, uv.dy * image.height));
        colors.add(color);
      }
    }
    flush();
    if (wireframe) {
      final lines = Path();
      for (final (face, _) in visible) {
        final a = projected[face.a],
            b = projected[face.b],
            c = projected[face.c];
        lines.moveTo(a.dx, a.dy);
        lines.lineTo(b.dx, b.dy);
        lines.lineTo(c.dx, c.dy);
        lines.close();
      }
      canvas.drawPath(
        lines,
        Paint()
          ..color = const Color(0x667df4d7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GarmentMeshPainter old) =>
      mesh != old.mesh ||
      image != old.image ||
      shader != old.shader ||
      yaw != old.yaw ||
      pitch != old.pitch ||
      volume != old.volume ||
      hemRatio != old.hemRatio ||
      fitTrackedWidth != old.fitTrackedWidth ||
      wireframe != old.wireframe ||
      materialColor != old.materialColor ||
      bodyPose != old.bodyPose;
}
