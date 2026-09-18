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
            connectionText: 'Đang kết nối',
            connected: false,
            bodyVisible: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('full_body_hint')), findsOneWidget);
    expect(find.textContaining('đứng lùi lại'), findsOneWidget);
  });
}
