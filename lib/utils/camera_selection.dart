import 'package:camera/camera.dart';

/// Finds a camera that faces the opposite way from [currentDirection].
///
/// Some Android phones expose several physical cameras with the same lens
/// direction. Selecting the next raw entry can therefore appear to do nothing.
int? oppositeCameraIndex(
  List<CameraDescription> cameras,
  CameraLensDirection currentDirection,
) {
  final preferredDirection = switch (currentDirection) {
    CameraLensDirection.front => CameraLensDirection.back,
    CameraLensDirection.back => CameraLensDirection.front,
    CameraLensDirection.external => CameraLensDirection.back,
  };

  final preferredIndex = cameras.indexWhere(
    (camera) => camera.lensDirection == preferredDirection,
  );
  if (preferredIndex >= 0) return preferredIndex;

  final alternativeIndex = cameras.indexWhere(
    (camera) => camera.lensDirection != currentDirection,
  );
  return alternativeIndex >= 0 ? alternativeIndex : null;
}

bool hasOppositeCamera(
  List<CameraDescription> cameras,
  CameraLensDirection currentDirection,
) => oppositeCameraIndex(cameras, currentDirection) != null;
