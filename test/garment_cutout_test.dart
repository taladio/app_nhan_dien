import 'dart:convert';
import 'dart:typed_data';

import 'package:app_nhan_dien/models/try_on_filter.dart';
import 'package:app_nhan_dien/screens/garment_cutout_screen.dart';
import 'package:app_nhan_dien/services/garment_cutout_service.dart';
import 'package:app_nhan_dien/widgets/try_on_filter_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

Uint8List garmentPng() {
  final image = img.Image(width: 80, height: 100, numChannels: 4);
  img.fillRect(
    image,
    x1: 20,
    y1: 10,
    x2: 60,
    y2: 90,
    color: img.ColorRgba8(0, 130, 130, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

// Image codecs and PNG export execute outside Flutter's fake async clock.
Future<void> finishImageWork(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  await tester.runAsync(() async {
    await action();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  await tester.pumpAndSettle();
}

void main() {
  test('cutout uses configured backend, uploads one image and crop', () async {
    final bytes = garmentPng();
    final service = GarmentCutoutService(
      baseUrl: 'https://example.test/base',
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://example.test/base/api/v1/try-on/cutout',
        );
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        final body = utf8.decode(request.bodyBytes, allowMalformed: true);
        expect(body, contains('name="x"\r\n\r\n0.1'));
        expect(body, contains('name="width"\r\n\r\n0.8'));
        expect(body, contains('name="file"'));
        return http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    expect(
      await service.cutout(bytes, const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)),
      bytes,
    );
  });

  test('invalid upload and invalid response do not become filters', () async {
    var calls = 0;
    final service = GarmentCutoutService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.cutout(Uint8List(2), const Rect.fromLTWH(0, 0, 1, 1)),
      throwsA(isA<GarmentCutoutException>()),
    );
    expect(calls, 0);
    await expectLater(
      service.cutout(garmentPng(), const Rect.fromLTWH(0, 0, 1, 1)),
      throwsA(isA<GarmentCutoutException>()),
    );
  });

  testWidgets('template creates transparent PNG locally without segmentation', (
    tester,
  ) async {
    final photo = img.Image(width: 80, height: 100, numChannels: 4);
    img.fill(photo, color: img.ColorRgba8(0, 130, 130, 255));
    final bytes = Uint8List.fromList(img.encodePng(photo));
    Uint8List? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                applied = await Navigator.of(context).push<Uint8List>(
                  MaterialPageRoute(
                    builder: (_) => GarmentCutoutScreen(
                      bytes: bytes,
                      category: TryOnFilterCategory.top,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await finishImageWork(tester, () => tester.tap(find.text('Open')));
    expect(find.text('Tách nền & xem trước'), findsNothing);
    await tester.tap(find.text('Xem trước'));
    await tester.pumpAndSettle();
    expect(find.text('Hiện viền'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('garment_edit_canvas')),
      const Offset(20, 20),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đặt lại'));
    await tester.pumpAndSettle();
    await finishImageWork(
      tester,
      () => tester.tap(find.byKey(const Key('apply_garment_button'))),
    );
    expect(applied, isNotNull);
    final decoded = img.decodePng(applied!);
    expect(decoded!.getPixel(0, 0).a, 0);
    expect(decoded.width, 720);
    expect(decoded.height, 800);
    expect(decoded.getPixel(360, 16).a, 0); // Neck opening.
    expect(decoded.getPixel(360, 400).a, 255);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreadable photo stays in editor with creation disabled', (
    tester,
  ) async {
    await finishImageWork(
      tester,
      () => tester.pumpWidget(
        MaterialApp(
          home: GarmentCutoutScreen(
            bytes: Uint8List.fromList([1, 2, 3]),
            category: TryOnFilterCategory.top,
          ),
        ),
      ),
    );
    expect(find.textContaining('Không đọc được ảnh'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('apply_garment_button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('picker shows imported image and import/remove controls', (
    tester,
  ) async {
    final filter = TryOnFilter.fromImage(
      id: 'custom',
      category: TryOnFilterCategory.top,
      bytes: garmentPng(),
    );
    var imports = 0;
    var removals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TryOnFilterPicker(
              category: TryOnFilterCategory.top,
              selectedFilter: filter,
              customFilters: [filter],
              onCategorySelected: (_) {},
              onFilterSelected: (_) {},
              onImport: () => imports++,
              onRemoveCustom: () => removals++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Thêm ảnh đồ'));
    await tester.tap(find.byTooltip('Bỏ ảnh đồ này'));
    expect(imports, 1);
    expect(removals, 1);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
