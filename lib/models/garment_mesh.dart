import 'dart:math' as math;
import 'dart:ui';

import 'try_on_filter.dart';

/// A small procedural garment shell, in pattern coordinates. Front is +Z.
/// Tubes are open at the collar, cuffs and hem; this is not cloth simulation.
class GarmentMesh {
  GarmentMesh._(this.vertices, this.faces);
  final List<GarmentVertex> vertices;
  final List<GarmentFace> faces;
  static final _cache = <TryOnFilterCategory, GarmentMesh>{};

  static GarmentMesh forCategory(TryOnFilterCategory category) =>
      _cache.putIfAbsent(category, () => _build(category));

  static GarmentMesh _build(TryOnFilterCategory category) {
    final vertices = <GarmentVertex>[];
    final faces = <GarmentFace>[];
    const segments = 32;

    void tube(List<_Ring> rings) {
      final start = vertices.length;
      for (var row = 0; row < rings.length; row++) {
        final ring = rings[row];
        final before = rings[math.max(0, row - 1)].center;
        final after = rings[math.min(rings.length - 1, row + 1)].center;
        final direction = after - before;
        final perpendicular =
            Offset(direction.dy, -direction.dx) /
            math.max(direction.distance, .0001);
        for (var col = 0; col < segments; col++) {
          final angle = 2 * math.pi * col / segments;
          final across = math.cos(angle);
          final front = math.sin(angle);
          final xy = ring.center + perpendicular * (ring.radius * across);
          final position = MeshPoint(
            xy.dx,
            xy.dy + ring.neckDip * math.max(0, front),
            front * ring.depth,
          );
          vertices.add(GarmentVertex(position, Offset(position.x, position.y)));
        }
      }
      for (var row = 0; row < rings.length - 1; row++) {
        for (var col = 0; col < segments; col++) {
          final next = (col + 1) % segments;
          final a = start + row * segments + col;
          final b = start + row * segments + next;
          final c = a + segments;
          final d = b + segments;
          // The front photo is only used on the front hemisphere. Back and
          // sides use a plain material, never invented rear image details.
          final textured = math.sin(2 * math.pi * (col + .5) / segments) > .22;
          faces.add(GarmentFace(a, c, b, textured));
          faces.add(GarmentFace(b, c, d, textured));
        }
      }
    }

    void sleeve(bool right, bool long, {bool short = false}) {
      // Begin inside the torso so there is no open shoulder seam at the join.
      final start = Offset(
        right ? (short ? .64 : .67) : (short ? .36 : .33),
        .17,
      );
      final end = Offset(
        right ? (short ? .70 : .925) : (short ? .30 : .075),
        long ? .83 : (short ? .265 : .37),
      );
      tube([
        for (var i = 0; i <= 7; i++)
          _Ring(
            Offset.lerp(start, end, i / 7)!,
            (short ? .065 : .105) * (1 - .22 * i / 7),
            (short ? .05 : .072) * (1 - .20 * i / 7),
          ),
      ]);
    }

    switch (category) {
      case TryOnFilterCategory.top:
      case TryOnFilterCategory.jacket:
        final jacket = category == TryOnFilterCategory.jacket;
        tube([
          const _Ring(Offset(.5, .025), .105, .075, neckDip: .07),
          _Ring(const Offset(.5, .105), jacket ? .28 : .26, .115),
          const _Ring(Offset(.5, .23), .26, .13),
          const _Ring(Offset(.5, .35), .26, .135),
          const _Ring(Offset(.5, .50), .26, .13),
          const _Ring(Offset(.5, .66), .265, .13),
          const _Ring(Offset(.5, .82), .27, .135),
          _Ring(const Offset(.5, .98), jacket ? .26 : .28, .14),
        ]);
        sleeve(false, jacket);
        sleeve(true, jacket);
      case TryOnFilterCategory.skirt:
        tube([
          for (var i = 0; i <= 12; i++)
            _Ring(
              Offset(.5, .02 + .94 * i / 12),
              .25 + .25 * math.pow(i / 12, 1.2),
              .125 + .08 * i / 12,
            ),
        ]);
      case TryOnFilterCategory.dress:
        tube([
          const _Ring(Offset(.5, .025), .105, .07, neckDip: .045),
          const _Ring(Offset(.5, .085), .18, .095),
          const _Ring(Offset(.5, .23), .15, .10),
          const _Ring(Offset(.5, .32), .14, .09),
          const _Ring(Offset(.5, .43), .14, .08),
          for (var i = 1; i <= 8; i++)
            _Ring(
              Offset(.5, .43 + .53 * i / 8),
              .14 + .36 * math.pow(i / 8, 1.2),
              .08 + .12 * i / 8,
            ),
        ]);
        sleeve(false, false, short: true);
        sleeve(true, false, short: true);
      case TryOnFilterCategory.pants:
        tube([
          const _Ring(Offset(.5, .03), .38, .14),
          const _Ring(Offset(.5, .12), .39, .15),
          const _Ring(Offset(.5, .23), .40, .15),
          const _Ring(Offset(.5, .34), .41, .13),
        ]);
        for (final right in [false, true]) {
          tube([
            for (var i = 0; i <= 10; i++)
              _Ring(
                Offset(
                  right ? .71 + .07 * i / 10 : .29 - .07 * i / 10,
                  .32 + .66 * i / 10,
                ),
                .21 - .02 * i / 10,
                .13 - .04 * i / 10,
              ),
          ]);
        }
      case TryOnFilterCategory.shoes:
        throw ArgumentError('Shoes retain the existing 2D foot filters.');
    }
    return GarmentMesh._(List.unmodifiable(vertices), List.unmodifiable(faces));
  }
}

class _Ring {
  const _Ring(this.center, this.radius, this.depth, {this.neckDip = 0});
  final Offset center;
  final double radius;
  final double depth;
  final double neckDip;
}

class GarmentVertex {
  const GarmentVertex(this.position, this.uv);
  final MeshPoint position;
  final Offset uv;
}

class GarmentFace {
  const GarmentFace(this.a, this.b, this.c, this.textured);
  final int a;
  final int b;
  final int c;
  final bool textured;
}

class MeshPoint {
  const MeshPoint(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
  MeshPoint operator +(MeshPoint p) => MeshPoint(x + p.x, y + p.y, z + p.z);
  MeshPoint operator -(MeshPoint p) => MeshPoint(x - p.x, y - p.y, z - p.z);
  MeshPoint operator *(double s) => MeshPoint(x * s, y * s, z * s);
  double dot(MeshPoint p) => x * p.x + y * p.y + z * p.z;
  MeshPoint cross(MeshPoint p) =>
      MeshPoint(y * p.z - z * p.y, z * p.x - x * p.z, x * p.y - y * p.x);
  MeshPoint get normalized => this * (1 / math.max(math.sqrt(dot(this)), 1e-9));
}
