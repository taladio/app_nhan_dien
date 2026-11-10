import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/services/body_profile_store.dart';
import 'package:app_nhan_dien/widgets/body_profile_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements BodyProfileStore {
  BodyProfileCollection data = const BodyProfileCollection(
    profiles: <BodyProfile>[
      BodyProfile(id: 'a', name: 'Hồ sơ A', heightCm: 170, weightKg: 65),
      BodyProfile(id: 'b', name: 'Hồ sơ B', heightCm: 180, weightKg: 75),
    ],
    selectedId: 'a',
  );

  @override
  Future<BodyProfileCollection> load() async => data;

  @override
  Future<void> save(BodyProfileCollection collection) async =>
      data = collection;
}

void main() {
  testWidgets('camera picker shows and saves the named profile', (
    tester,
  ) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: BodyProfilePicker(store: store)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ A'), findsOneWidget);

    await tester.tap(find.byKey(const Key('camera_profile_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('camera_profile_b')));
    await tester.pumpAndSettle();
    expect(store.data.selected?.name, 'Hồ sơ B');
    expect(find.text('Hồ sơ B'), findsOneWidget);
  });
}
