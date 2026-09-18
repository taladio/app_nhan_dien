import 'dart:ui';

class CameraCoordinateMapper {
  const CameraCoordinateMapper({
    required this.imageSize,
    required this.viewportSize,
    required this.rotationDegrees,
    required this.mirrored,
  }) : assert(
         rotationDegrees == 0 ||
             rotationDegrees == 90 ||
             rotationDegrees == 180 ||
             rotationDegrees == 270,
       );

  final Size imageSize;
  final Size viewportSize;
  final int rotationDegrees;
  final bool mirrored;

  Size get orientedImageSize {
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      return Size(imageSize.height, imageSize.width);
    }
    return imageSize;
  }

  double get coverScale {
    final oriented = orientedImageSize;
    return _max(
      viewportSize.width / oriented.width,
      viewportSize.height / oriented.height,
    );
  }

  Size get scaledImageSize {
    final oriented = orientedImageSize;
    return Size(oriented.width * coverScale, oriented.height * coverScale);
  }

  Offset get cropOffset {
    final scaled = scaledImageSize;
    return Offset(
      (scaled.width - viewportSize.width) / 2,
      (scaled.height - viewportSize.height) / 2,
    );
  }

  Offset orientNormalized(Offset point) {
    var oriented = switch (rotationDegrees) {
      90 => Offset(1 - point.dy, point.dx),
      180 => Offset(1 - point.dx, 1 - point.dy),
      270 => Offset(point.dy, 1 - point.dx),
      _ => point,
    };
    if (mirrored) oriented = Offset(1 - oriented.dx, oriented.dy);
    return oriented;
  }

  Offset mapNormalized(Offset point) {
    final oriented = orientNormalized(point);
    final scaled = scaledImageSize;
    final crop = cropOffset;
    return Offset(
      oriented.dx * scaled.width - crop.dx,
      oriented.dy * scaled.height - crop.dy,
    );
  }
}

double _max(double first, double second) => first > second ? first : second;
