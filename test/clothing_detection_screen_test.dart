import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/screens/clothing_detection_screen.dart';
import 'package:app_nhan_dien/services/fashion_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFashionService implements FashionDetectionService {
  FakeFashionService(this.handler);

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

final Uint8List _validPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

SelectedImageData get _selectedImage =>
    SelectedImageData(bytes: _validPng, filename: 'trang-phuc.png');

DetectionResponse _emptyResponse() => DetectionResponse(
  filename: 'trang-phuc.png',
  imageWidth: 100,
  imageHeight: 100,
  detections: const <ClothingDetection>[],
  ignoredDetectionCount: 0,
);

DetectionResponse _successfulResponse() => DetectionResponse(
  filename: 'trang-phuc.png',
  imageWidth: 100,
  imageHeight: 100,
  detections: const <ClothingDetection>[
    ClothingDetection(
      classId: 19,
      rawClassName: 'tshirt',
      className: 'tshirt',
      classNameVi: 'Áo thun',
      color: 'Trắng',
      confidence: 0.9321,
      boundingBox: BoundingBox(x1: 10, y1: 15, x2: 80, y2: 90),
    ),
  ],
  ignoredDetectionCount: 0,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FashionDetectionService service,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ClothingDetectionScreen(
        service: service,
        imageSelectionCallback: (_) async => _selectedImage,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _selectImageAndDetect(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('gallery_button')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('detect_button')));
  await tester.tap(find.byKey(const Key('detect_button')));
}

void main() {
  testWidgets('trạng thái chưa chọn ảnh không overflow trên điện thoại', (
    tester,
  ) async {
    final service = FakeFashionService(() async => _emptyResponse());

    await _pumpScreen(tester, service: service);

    expect(find.text('Nhận diện trang phục'), findsOneWidget);
    expect(find.text('Chọn ảnh trang phục'), findsOneWidget);
    expect(find.text('Chọn ảnh từ thư viện'), findsOneWidget);
    expect(find.byKey(const Key('detect_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiển thị và khóa thao tác trong trạng thái đang tải', (
    tester,
  ) async {
    final completer = Completer<DetectionResponse>();
    final service = FakeFashionService(() => completer.future);
    await _pumpScreen(tester, service: service);

    await _selectImageAndDetect(tester);
    await tester.pump();

    expect(find.text('Đang phân tích ảnh...'), findsOneWidget);
    final detectButton = tester.widget<FilledButton>(
      find.byKey(const Key('detect_button')),
    );
    expect(detectButton.onPressed, isNull);
    expect(service.callCount, 1);

    completer.complete(_emptyResponse());
    await tester.pumpAndSettle();
  });

  testWidgets('hiển thị trạng thái không có detection', (tester) async {
    final service = FakeFashionService(() async => _emptyResponse());
    await _pumpScreen(tester, service: service);

    await _selectImageAndDetect(tester);
    await tester.pumpAndSettle();

    expect(find.text('Không phát hiện được quần áo'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Chọn ảnh khác'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiển thị kết quả, summary và confidence', (tester) async {
    final service = FakeFashionService(() async => _successfulResponse());
    await _pumpScreen(tester, service: service);

    await _selectImageAndDetect(tester);
    await tester.pumpAndSettle();

    expect(find.text('Kết quả nhận diện'), findsOneWidget);
    expect(find.text('Tổng: 1'), findsOneWidget);
    expect(find.text('Áo thun: 1'), findsOneWidget);
    expect(find.text('Áo thun'), findsWidgets);
    expect(find.text('Màu: Trắng'), findsOneWidget);
    expect(find.text('Độ tin cậy: 93.21%'), findsOneWidget);
    expect(find.text('Lớp: tshirt'), findsOneWidget);
    expect(find.text('Hiển thị bounding box'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
