import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_nhan_dien/models/garment_template.dart';
import 'package:app_nhan_dien/models/try_on_filter.dart';
import 'package:app_nhan_dien/screens/garment_cutout_screen.dart';
import 'package:app_nhan_dien/screens/garment_3d_preview_screen.dart';
import 'package:app_nhan_dien/widgets/garment_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List photo() {
  final image = img.Image(width: 120, height: 160, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(220, 40, 40, 255));
  img.fillRect(
    image,
    x1: 60,
    y1: 0,
    x2: 119,
    y2: 159,
    color: img.ColorRgba8(30, 70, 220, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

Future<void> imageWork(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  await tester.runAsync(() async {
    await action();
    // Finish route entry before looking for progress; a newly pushed route is
    // initially offstage and its native image decoder needs real async time.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  await tester.pumpAndSettle();
}

Future<void> openEditor(
  WidgetTester tester,
  TryOnFilterCategory category,
  ValueChanged<Uint8List> onDone, {
  ValueChanged<double>? onVolumeChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () async {
              final result = await Navigator.of(context).push<Uint8List>(
                MaterialPageRoute(
                  builder: (_) => GarmentCutoutScreen(
                    bytes: photo(),
                    category: category,
                    onVolumeChanged: onVolumeChanged,
                  ),
                ),
              );
              if (result != null) onDone(result);
            },
          ),
        ),
      ),
    ),
  );
  await imageWork(tester, () => tester.tap(find.text('Open')));
}

void main() {
  testWidgets(
    '3D preview returns to editing or applies the same cropped photo',
    (tester) async {
      Uint8List? result;
      double? chosenVolume;
      await openEditor(
        tester,
        TryOnFilterCategory.top,
        (bytes) => result = bytes,
        onVolumeChanged: (value) => chosenVolume = value,
      );
      await tester.ensureVisible(find.byKey(const Key('preview_garment_3d')));
      await imageWork(
        tester,
        () => tester.tap(find.byKey(const Key('preview_garment_3d'))),
      );
      expect(find.byType(Garment3DPreviewScreen), findsOneWidget);
      expect(result, isNull);
      await imageWork(tester, () => tester.pageBack());
      expect(find.byType(GarmentCutoutScreen), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('preview_garment_3d')));
      await imageWork(
        tester,
        () => tester.tap(find.byKey(const Key('preview_garment_3d'))),
      );
      await tester.ensureVisible(find.byKey(const Key('use_3d_filter')));
      await imageWork(
        tester,
        () => tester.tap(find.byKey(const Key('use_3d_filter'))),
      );
      expect(find.byType(GarmentCutoutScreen), findsNothing);
      final image = img.decodePng(result!)!;
      expect(chosenVolume, 1);
      expect(image.getPixel(0, 0).a, 0);
      expect(image.getPixel(360, 400).a, greaterThan(200));
    },
  );

  test('silhouettes preserve the neck and the space between legs', () {
    const size = Size(100, 100);
    final shirt = const GarmentTemplate(TryOnFilterCategory.top).path(size);
    expect(shirt.contains(const Offset(50, 3)), isFalse);
    expect(shirt.contains(const Offset(50, 50)), isTrue);
    final pants = const GarmentTemplate(TryOnFilterCategory.pants).path(size);
    expect(pants.contains(const Offset(50, 80)), isFalse);
    expect(pants.contains(const Offset(25, 80)), isTrue);
    expect(pants.contains(const Offset(75, 80)), isTrue);
    for (final category in TryOnFilterCategory.values) {
      final template = GarmentTemplate(category);
      expect(template.outputSize.longestSide, lessThanOrEqualTo(900));
      expect(template.path(template.outputSize).getBounds().isEmpty, isFalse);
    }
  });

  testWidgets('pinch zooms, reset restores, and flip changes exported photo', (
    tester,
  ) async {
    Uint8List? result;
    await openEditor(
      tester,
      TryOnFilterCategory.top,
      (bytes) => result = bytes,
    );
    final center = tester.getCenter(
      find.byKey(const Key('garment_edit_canvas')),
    );
    final first = await tester.startGesture(
      center - const Offset(25, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(25, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(50, 0));
    await second.moveTo(center + const Offset(50, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(75, 0));
    await second.moveTo(center + const Offset(75, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Slider>(find.byKey(const Key('garment_zoom_slider'))).value,
      greaterThan(1),
    );
    await tester.tap(find.text('Đặt lại'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Slider>(find.byKey(const Key('garment_zoom_slider'))).value,
      1,
    );
    await tester.tap(find.text('Lật ảnh'));
    await tester.pump();
    await imageWork(
      tester,
      () => tester.tap(find.byKey(const Key('apply_garment_button'))),
    );
    final image = img.decodePng(result!)!;
    expect(image.getPixel(250, 400).b, greaterThan(image.getPixel(250, 400).r));
    expect(image.getPixel(470, 400).r, greaterThan(image.getPixel(470, 400).b));
  });

  testWidgets('pants export keeps both legs and a transparent gap', (
    tester,
  ) async {
    Uint8List? result;
    await openEditor(
      tester,
      TryOnFilterCategory.pants,
      (bytes) => result = bytes,
    );
    await imageWork(
      tester,
      () => tester.tap(find.byKey(const Key('apply_garment_button'))),
    );
    final image = img.decodePng(result!)!;
    expect(image.getPixel(300, 720).a, 0);
    expect(image.getPixel(150, 720).a, 255);
    expect(image.getPixel(450, 720).a, 255);
  });

  testWidgets('moving the image out of frame can be reset and retried', (
    tester,
  ) async {
    Uint8List? result;
    await openEditor(
      tester,
      TryOnFilterCategory.top,
      (bytes) => result = bytes,
    );
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('garment_edit_canvas'))),
    );
    await drag.moveBy(const Offset(25, 0));
    await tester.pump();
    await drag.moveBy(const Offset(100, 0));
    await tester.pump();
    await drag.moveBy(const Offset(1000, 1000));
    await drag.up();
    await tester.pumpAndSettle();
    await imageWork(
      tester,
      () => tester.tap(find.byKey(const Key('apply_garment_button'))),
    );
    expect(result, isNull);
    expect(find.textContaining('Ảnh đang nằm ngoài khung'), findsOneWidget);
    await tester.tap(find.text('Đặt lại'));
    await tester.pumpAndSettle();
    await imageWork(
      tester,
      () => tester.tap(find.byKey(const Key('apply_garment_button'))),
    );
    expect(result, isNotNull);
  });

  testWidgets('small phone and larger text keep controls accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await imageWork(
      tester,
      () => tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: GarmentCutoutScreen(
            bytes: photo(),
            category: TryOnFilterCategory.jacket,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('apply_garment_button')));
  });

  testWidgets('mesh preserves alpha and shades cloth without a rectangle', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = img.Image(width: 160, height: 200, numChannels: 4);
      img.fillRect(
        source,
        x1: 16,
        y1: 20,
        x2: 144,
        y2: 180,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(img.encodePng(source)),
      );
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      );
      final recorder = ui.PictureRecorder();
      GarmentSurfacePainter(
        image: image,
        shader: shader,
        yaw: .5,
      ).paint(Canvas(recorder), const Size(160, 200));
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(160, 200);
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final pixels = img.decodePng(data!.buffer.asUint8List())!;
      expect(pixels.getPixel(0, 0).a, 0);
      expect(pixels.getPixel(80, 100).a, 255);
      expect(
        pixels.getPixel(80, 100).r,
        greaterThan(pixels.getPixel(130, 100).r),
      );
      rendered.dispose();
      picture.dispose();
      shader.dispose();
      image.dispose();
    });
  });
}
