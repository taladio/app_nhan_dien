import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_nhan_dien/models/garment_mesh.dart';
import 'package:app_nhan_dien/models/body_garment_pose.dart';
import 'package:app_nhan_dien/models/garment_template.dart';
import 'package:app_nhan_dien/models/try_on_filter.dart';
import 'package:app_nhan_dien/painters/garment_mesh_painter.dart';
import 'package:app_nhan_dien/screens/garment_3d_preview_screen.dart';
import 'package:app_nhan_dien/widgets/garment_surface.dart';
import 'package:app_nhan_dien/widgets/try_on_filter_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'body_garment_pose_test.dart' show track, turnedBody;

Future<ui.Image> source(TryOnFilterCategory category) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawPath(
    GarmentTemplate(category).path(const Size(256, 320)),
    Paint()..color = const Color(0xffe94938),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(256, 320);
  } finally {
    picture.dispose();
  }
}

Future<img.Image> render(
  TryOnFilterCategory category, {
  double yaw = 0,
  double volume = 1,
  BodyGarmentPose? bodyPose,
}) async {
  final photo = await source(category);
  final shader = ui.ImageShader(
    photo,
    TileMode.clamp,
    TileMode.clamp,
    Matrix4.identity().storage,
  );
  final recorder = ui.PictureRecorder();
  GarmentMeshPainter(
    mesh: GarmentMesh.forCategory(category),
    image: photo,
    shader: shader,
    yaw: yaw,
    volume: volume,
    materialColor: const Color(0xff2277ee),
    bodyPose: bodyPose,
  ).paint(
    Canvas(recorder),
    bodyPose == null ? const Size(256, 320) : const Size(400, 600),
  );
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(
    bodyPose == null ? 256 : 400,
    bodyPose == null ? 320 : 600,
  );
  try {
    final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
    return img.decodePng(png!.buffer.asUint8List())!;
  } finally {
    rendered.dispose();
    picture.dispose();
    shader.dispose();
    photo.dispose();
  }
}

int opaqueWidth(img.Image image, int y) => [
  for (var x = 0; x < image.width; x++)
    if (image.getPixel(x, y).a > 100) x,
].length;

Future<Uint8List> photoBytes() async {
  final photo = await source(TryOnFilterCategory.top);
  try {
    return (await photo.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    photo.dispose();
  }
}

void main() {
  testWidgets(
    'camera body rotation actually renders front then back for both cameras',
    (tester) async {
      await tester.runAsync(() async {
        for (final mirrored in [false, true]) {
          final front = await render(
            TryOnFilterCategory.top,
            bodyPose: track(turnedBody(0), mirrored: mirrored),
          );
          final back = await render(
            TryOnFilterCategory.top,
            bodyPose: track(turnedBody(math.pi), mirrored: mirrored),
          );
          final side = await render(
            TryOnFilterCategory.top,
            bodyPose: track(turnedBody(math.pi / 2), mirrored: mirrored),
          );
          expect(
            front.getPixel(200, 340).r,
            greaterThan(front.getPixel(200, 340).b),
          );
          expect(
            back.getPixel(200, 340).b,
            greaterThan(back.getPixel(200, 340).r),
          );
          expect(opaqueWidth(side, 340), greaterThan(20));
          expect(opaqueWidth(side, 340), lessThan(opaqueWidth(front, 340)));
          expect(front.getPixel(0, 0).a, 0);
        }
      });
    },
  );
  test(
    'five garment meshes have real depth, valid faces and bounded complexity',
    () {
      for (final category in TryOnFilterCategory.values.where(
        (c) => c != TryOnFilterCategory.shoes,
      )) {
        final mesh = GarmentMesh.forCategory(category);
        expect(identical(mesh, GarmentMesh.forCategory(category)), isTrue);
        expect(mesh.faces.length, lessThan(2300));
        expect(mesh.vertices.any((v) => v.position.z > .07), isTrue);
        expect(mesh.vertices.any((v) => v.position.z < -.07), isTrue);
        expect(mesh.faces.any((f) => f.textured), isTrue);
        expect(mesh.faces.any((f) => !f.textured), isTrue);
        for (final face in mesh.faces) {
          expect({face.a, face.b, face.c}.length, 3);
          for (final i in [face.a, face.b, face.c]) {
            expect(i, inInclusiveRange(0, mesh.vertices.length - 1));
          }
        }
      }
    },
  );

  testWidgets(
    'front uses photo; side and back have volume and plain material',
    (tester) async {
      await tester.runAsync(() async {
        final front = await render(TryOnFilterCategory.top);
        final side = await render(TryOnFilterCategory.top, yaw: math.pi / 2);
        final back = await render(TryOnFilterCategory.top, yaw: math.pi);
        expect(
          front.getPixel(128, 160).r,
          greaterThan(front.getPixel(128, 160).b),
        );
        expect(
          back.getPixel(128, 160).b,
          greaterThan(back.getPixel(128, 160).r),
        );
        expect(
          side.getPixel(128, 160).b,
          greaterThan(side.getPixel(128, 160).r),
        );
        expect(opaqueWidth(side, 160), greaterThan(40));
        expect(opaqueWidth(side, 160), lessThan(opaqueWidth(front, 160)));
        for (final image in [front, side, back]) {
          expect(image.getPixel(0, 0).a, 0);
        }
        final thin = await render(
          TryOnFilterCategory.top,
          yaw: math.pi / 2,
          volume: .4,
        );
        expect(opaqueWidth(thin, 160), lessThan(opaqueWidth(side, 160)));
      });
    },
  );

  testWidgets('pants retain two legs and a visible gap in front and rear', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final yaw in [0.0, math.pi]) {
        final pants = await render(TryOnFilterCategory.pants, yaw: yaw);
        expect(pants.getPixel(128, 260).a, 0);
        expect(pants.getPixel(64, 260).a, greaterThan(200));
        expect(pants.getPixel(192, 260).a, greaterThan(200));
      }
    });
  });

  test(
    '3D is available only for aligned clothes, shoes and old images keep 2D',
    () {
      final bytes = Uint8List(0);
      for (final category in TryOnFilterCategory.values) {
        final filter = TryOnFilter.fromImage(
          id: 'x',
          category: category,
          bytes: bytes,
          templateAligned: true,
        );
        expect(filter.supports3D, category != TryOnFilterCategory.shoes);
      }
      expect(tryOnFilters.any((f) => f.supports3D), isFalse);
      expect(
        TryOnFilter.fromImage(
          id: 'old',
          category: TryOnFilterCategory.top,
          bytes: bytes,
        ).supports3D,
        isFalse,
      );
    },
  );

  testWidgets(
    'preview rotates, resets, changes volume and fits a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(photoBytes);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Garment3DPreviewScreen(
            filter: TryOnFilter.fromImage(
              id: 'test',
              category: TryOnFilterCategory.top,
              bytes: bytes!,
              templateAligned: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Mặt sau'));
      await tester.pump();
      expect(
        tester.widget<GarmentSurface>(find.byType(GarmentSurface)).yaw,
        math.pi,
      );
      await tester.tap(find.text('Mặt trước'));
      await tester.pump();
      expect(tester.widget<GarmentSurface>(find.byType(GarmentSurface)).yaw, 0);
      final orbit = find.byKey(const Key('garment_3d_orbit'));
      final gesture = await tester.startGesture(tester.getCenter(orbit));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      await gesture.up();
      expect(
        tester.widget<GarmentSurface>(find.byType(GarmentSurface)).yaw,
        isNot(0),
      );
      await tester.ensureVisible(find.byKey(const Key('garment_3d_volume')));
      await tester.tapAt(
        tester.getTopRight(find.byKey(const Key('garment_3d_volume'))) +
            const Offset(-25, 20),
      );
      await tester.pump();
      expect(
        tester.widget<GarmentSurface>(find.byType(GarmentSurface)).volume,
        greaterThan(1),
      );
      await tester.ensureVisible(find.byKey(const Key('use_3d_filter')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
  );

  testWidgets('picker can switch 3D off without discarding the photo', (
    tester,
  ) async {
    final bytes = await tester.runAsync(photoBytes);
    final filter = TryOnFilter.fromImage(
      id: 'test',
      category: TryOnFilterCategory.top,
      bytes: bytes!,
      templateAligned: true,
    );
    bool? selected;
    var preview = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TryOnFilterPicker(
            category: filter.category,
            selectedFilter: filter,
            customFilters: [filter],
            onCategorySelected: (_) {},
            onFilterSelected: (_) {},
            on3DChanged: (value) => selected = value,
            onPreview3D: () => preview = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('2D'));
    expect(selected, false);
    await tester.tap(find.text('Xem 360°'));
    expect(preview, true);
    expect(find.byType(Image), findsNWidgets(2));
  });
}
