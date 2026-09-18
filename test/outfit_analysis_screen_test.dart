import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:app_nhan_dien/models/outfit_analysis_result.dart';
import 'package:app_nhan_dien/screens/outfit_analysis_screen.dart';
import 'package:app_nhan_dien/services/analysis_preferences.dart';
import 'package:app_nhan_dien/services/outfit_analysis_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class FakeAnalysisPreferences implements AnalysisPreferencesStore {
  AnalysisPreferencesData data = const AnalysisPreferencesData(
    heightCm: '170',
    weightKg: '65',
    temperatureC: '32',
  );

  @override
  Future<AnalysisPreferencesData> load() async => data;

  @override
  Future<void> save(AnalysisPreferencesData newData) async => data = newData;
}

class FakeAnalysisService implements OutfitAnalysisServiceContract {
  FakeAnalysisService(this.handler);

  final Future<OutfitAnalysisResult> Function() handler;
  int callCount = 0;

  @override
  Future<OutfitAnalysisResult> analyze({
    required PreparedAnalysisImage image,
    required double heightCm,
    required double weightKg,
    required String season,
    required double temperatureC,
    required String style,
    required String occasion,
    required double confidence,
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

PreparedAnalysisImage get _selectedImage => PreparedAnalysisImage(
  bytes: _validPng,
  filename: 'outfit.png',
  mimeType: 'image/png',
);

OutfitAnalysisResult _result() => OutfitAnalysisResult(
  filename: 'outfit.png',
  imageWidth: 100,
  imageHeight: 100,
  source: OutfitAnalysisSource.fallback,
  detectedItems: <DetectedOutfitItem>[
    DetectedOutfitItem(
      detectionId: 'det_1',
      classId: 0,
      rawClassName: 'T-Shirt',
      className: 'tshirt',
      classNameVi: 'Áo thun',
      primaryColor: 'Trắng',
      secondaryColors: const <String>[],
      confidence: 0.9,
      boundingBox: const BoundingBox(x1: 10, y1: 10, x2: 90, y2: 90),
    ),
  ],
  evaluation: OutfitEvaluation(
    overallScore: 80,
    rating: 'Phù hợp',
    colorScore: 80,
    seasonTemperatureScore: 80,
    bodyProportionScore: 80,
    styleScore: 80,
    occasionScore: 80,
    summary: 'Đánh giá cơ bản.',
    strengths: <String>['Màu dễ phối.'],
    problems: <String>[],
    recommendations: <String>['Giữ cách phối.'],
    suggestedOutfit: SuggestedOutfit(
      top: 'Áo trắng',
      bottom: 'Quần be',
      outerwear: null,
      shoes: 'Giày trắng',
      reason: 'Phù hợp.',
    ),
  ),
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required OutfitAnalysisServiceContract service,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: OutfitAnalysisScreen(
        service: service,
        preferencesStore: FakeAnalysisPreferences(),
        imageSelectionCallback: (ImageSource _) async => _selectedImage,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectAndAnalyze(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('gallery_button')));
  await tester.pumpAndSettle();
  final button = find.byKey(const Key('analyze_button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  testWidgets('khóa nút và hiển thị loading khi request đang chạy', (
    tester,
  ) async {
    final completer = Completer<OutfitAnalysisResult>();
    final service = FakeAnalysisService(() => completer.future);
    await _pumpScreen(tester, service: service);

    await _selectAndAnalyze(tester);

    expect(find.byKey(const Key('loading_panel')), findsOneWidget);
    expect(service.callCount, 1);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('analyze_button')),
    );
    expect(button.onPressed, isNull);

    completer.complete(_result());
    await tester.pumpAndSettle();
    expect(find.text('Đánh giá cơ bản'), findsWidgets);
    expect(find.byKey(const Key('analyze_again_button')), findsOneWidget);
  });

  testWidgets('hiển thị lỗi tiếng Việt khi service thất bại', (tester) async {
    final service = FakeAnalysisService(
      () async => throw const OutfitAnalysisException(
        'Không thể kết nối backend. Hãy kiểm tra máy chủ và mạng.',
      ),
    );
    await _pumpScreen(tester, service: service);

    await _selectAndAnalyze(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error_panel')), findsOneWidget);
    expect(find.textContaining('Không thể kết nối backend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
