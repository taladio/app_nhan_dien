import 'package:app_nhan_dien/utils/camera_selection.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CameraDescription camera(String name, CameraLensDirection direction) {
    return CameraDescription(
      name: name,
      lensDirection: direction,
      sensorOrientation: 90,
    );
  }

  test('front camera switches to the first back camera', () {
    final cameras = <CameraDescription>[
      camera('front-main', CameraLensDirection.front),
      camera('front-depth', CameraLensDirection.front),
      camera('back-main', CameraLensDirection.back),
    ];

    expect(oppositeCameraIndex(cameras, CameraLensDirection.front), 2);
  });

  test('back camera switches to front instead of another back camera', () {
    final cameras = <CameraDescription>[
      camera('back-main', CameraLensDirection.back),
      camera('back-wide', CameraLensDirection.back),
      camera('front-main', CameraLensDirection.front),
    ];

    expect(oppositeCameraIndex(cameras, CameraLensDirection.back), 2);
  });

  test('returns null when all physical cameras face the same way', () {
    final cameras = <CameraDescription>[
      camera('back-main', CameraLensDirection.back),
      camera('back-wide', CameraLensDirection.back),
    ];

    expect(oppositeCameraIndex(cameras, CameraLensDirection.back), isNull);
    expect(hasOppositeCamera(cameras, CameraLensDirection.back), isFalse);
  });
}
