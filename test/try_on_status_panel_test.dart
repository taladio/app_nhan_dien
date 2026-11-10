import 'package:app_nhan_dien/widgets/try_on_filter_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows backend connection status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TryOnStatusPanel(
            connectionText: 'Đã kết nối',
            connected: true,
            bodyVisible: true,
            processingFps: 8,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('try_on_connection_status')), findsOneWidget);
    expect(find.textContaining('Đã kết nối'), findsOneWidget);
    expect(find.textContaining('8.0 FPS'), findsOneWidget);
  });

  testWidgets('shows instruction when full body is not visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TryOnStatusPanel(
            connectionText: 'Đã kết nối',
            connected: true,
            bodyVisible: false,
            poseDetected: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('full_body_hint')), findsOneWidget);
    expect(find.textContaining('Đang theo dõi phần cơ thể'), findsOneWidget);
  });

  testWidgets('does not claim partial tracking when no person is detected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TryOnStatusPanel(
            connectionText: 'Đã kết nối',
            connected: true,
            bodyVisible: false,
          ),
        ),
      ),
    );
    expect(find.textContaining('Chưa thấy cơ thể'), findsOneWidget);
    expect(find.textContaining('Đang theo dõi'), findsNothing);
  });

  testWidgets('does not show body hint while backend is disconnected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TryOnStatusPanel(
            connectionText: 'Mất kết nối',
            connected: false,
            bodyVisible: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('full_body_hint')), findsNothing);
  });

  testWidgets('camera error has a visible retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TryOnCameraUnavailable(
            message: 'Không thể mở camera.',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('try_on_camera_error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry_camera_button')));
    expect(retried, isTrue);
  });
}
