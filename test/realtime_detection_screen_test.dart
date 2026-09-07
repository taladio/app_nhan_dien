import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/screens/realtime_detection_screen.dart';
import 'package:app_nhan_dien/services/fashion_api_service.dart';
import 'package:app_nhan_dien/services/realtime_camera_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRealtimeCameraSession implements RealtimeCameraSession {
  bool initialized = false;
  bool streaming = false;
  ValueChanged<RealtimeCameraFrame>? _onFrame;

  @override
  bool get canSwitchCamera => true;

  @override
  bool get isInitialized => initialized;

  @override
  Widget buildPreview({Widget? overlay}) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[overlay ?? const SizedBox.shrink()],
        ),
      ),
    );
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> startFrameStream({
    required ValueChanged<RealtimeCameraFrame> onFrame,
    required ValueChanged<Object> onError,
  }) async {
    streaming = true;
    _onFrame = onFrame;
  }

  @override
  Future<void> stopFrameStream() async {
    streaming = false;
  }

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> dispose() async {
    initialized = false;
    streaming = false;
  }

  void emit(RealtimeCameraFrame frame) {
    if (streaming) {
      _onFrame?.call(frame);
    }
  }
}

class FakeRealtimeFashionService implements FashionDetectionService {
  FakeRealtimeFashionService(this.handler);

  final Future<DetectionResponse> Function() handler;
  int callCount = 0;

  @override
  Future<DetectionResponse> detectClothing({
    required Uint8List imageBytes,
    required String filename,
    required double confidence,
    double iou = 0.45,
  }) {
    callCount += 1;
    return handler();
  }

  @override
  void close() {}
}

final Uint8List _validFrame = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

RealtimeCameraFrame get _frame =>
    RealtimeCameraFrame(bytes: _validFrame, filename: 'realtime.jpg');

DetectionResponse _response({bool hasDetection = true}) => DetectionResponse(
  filename: 'realtime.jpg',
  imageWidth: 480,
  imageHeight: 640,
  detections: hasDetection
      ? const <ClothingDetection>[
          ClothingDetection(
            classId: 1,
            rawClassName: 'T-Shirt',
            className: 'tshirt',
            classNameVi: 'Áo thun',
            color: 'Trắng',
            confidence: 0.88,
            boundingBox: BoundingBox(x1: 40, y1: 50, x2: 420, y2: 590),
          ),
        ]
      : const <ClothingDetection>[],
  ignoredDetectionCount: 0,
);

Future<void> _pumpRealtimeScreen(
  WidgetTester tester, {
  required FakeRealtimeCameraSession camera,
  required FashionDetectionService service,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RealtimeDetectionScreen(cameraSession: camera, service: service),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('khởi tạo preview realtime không overflow trên điện thoại', (
    tester,
  ) async {
    final camera = FakeRealtimeCameraSession();
    final service = FakeRealtimeFashionService(() async => _response());

    await _pumpRealtimeScreen(tester, camera: camera, service: service);

    expect(find.text('Nhận diện realtime'), findsOneWidget);
    expect(find.byKey(const Key('realtime_preview')), findsOneWidget);
    expect(find.text('Bắt đầu realtime'), findsOneWidget);
    expect(find.text('Đổi camera'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gửi frame và hiển thị kết quả realtime', (tester) async {
    final camera = FakeRealtimeCameraSession();
    final service = FakeRealtimeFashionService(() async => _response());
    await _pumpRealtimeScreen(tester, camera: camera, service: service);

    await tester.ensureVisible(find.byKey(const Key('realtime_start_button')));
    await tester.tap(find.byKey(const Key('realtime_start_button')));
    await tester.pump();
    camera.emit(_frame);
    await tester.pumpAndSettle();

    expect(service.callCount, 1);
    expect(find.text('Dừng nhận diện'), findsOneWidget);
    expect(find.byKey(const Key('realtime_result')), findsOneWidget);
    expect(find.text('Áo thun: 1'), findsOneWidget);
    expect(find.text('Màu: Trắng'), findsOneWidget);
    expect(find.text('Frame: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('không gửi chồng nhiều frame khi YOLO đang xử lý', (
    tester,
  ) async {
    final completer = Completer<DetectionResponse>();
    final camera = FakeRealtimeCameraSession();
    final service = FakeRealtimeFashionService(() => completer.future);
    await _pumpRealtimeScreen(tester, camera: camera, service: service);

    await tester.ensureVisible(find.byKey(const Key('realtime_start_button')));
    await tester.tap(find.byKey(const Key('realtime_start_button')));
    await tester.pump();
    camera
      ..emit(_frame)
      ..emit(_frame);
    await tester.pump();

    expect(service.callCount, 1);
    completer.complete(_response(hasDetection: false));
    await tester.pumpAndSettle();
    expect(find.text('Không phát hiện được quần áo'), findsOneWidget);
  });

  testWidgets('dừng realtime và giữ thông báo lỗi API để thử lại', (
    tester,
  ) async {
    final camera = FakeRealtimeCameraSession();
    final service = FakeRealtimeFashionService(
      () async =>
          throw const FashionApiException('Không thể kết nối đến máy chủ.'),
    );
    await _pumpRealtimeScreen(tester, camera: camera, service: service);

    await tester.ensureVisible(find.byKey(const Key('realtime_start_button')));
    await tester.tap(find.byKey(const Key('realtime_start_button')));
    await tester.pump();
    camera.emit(_frame);
    await tester.pumpAndSettle();

    expect(camera.streaming, isFalse);
    expect(find.byKey(const Key('realtime_error')), findsOneWidget);
    expect(find.text('Không thể kết nối đến máy chủ.'), findsOneWidget);
    expect(find.text('Bắt đầu realtime'), findsOneWidget);
  });
}
