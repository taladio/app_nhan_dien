import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/screens/personal_info_screen.dart';
import 'package:app_nhan_dien/services/body_profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements BodyProfileStore {
  BodyProfileCollection data = const BodyProfileCollection();

  @override
  Future<BodyProfileCollection> load() async => data;

  @override
  Future<void> save(BodyProfileCollection collection) async =>
      data = collection;
}

void main() {
  testWidgets('shows account and can add and rename a body profile', (
    tester,
  ) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalInfoScreen(
          accountName: 'Hoàng',
          email: 'hoang@gmail.com',
          profileStore: store,
          onChangePassword: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hoàng'), findsOneWidget);
    expect(find.text('hoang@gmail.com'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_profile_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile_name_field')),
      'Hồ sơ A',
    );
    await tester.enterText(
      find.byKey(const Key('profile_height_field')),
      '175',
    );
    await tester.enterText(find.byKey(const Key('profile_weight_field')), '70');
    await tester.tap(find.byKey(const Key('profile_gender_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nam').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pumpAndSettle();
    expect(store.data.selected?.name, 'Hồ sơ A');
    expect(store.data.selected?.gender, BodyGender.male);

    await tester.tap(find.byTooltip('Tùy chọn Hồ sơ A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi tên / sửa hồ sơ'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile_name_field')),
      'Hồ sơ B',
    );
    await tester.tap(find.byKey(const Key('save_profile_button')));
    await tester.pumpAndSettle();
    expect(store.data.selected?.name, 'Hồ sơ B');
    expect(store.data.selected?.gender, BodyGender.male);
  });

  testWidgets('change password validates then calls secure handler', (
    tester,
  ) async {
    final store = _MemoryStore();
    String? current;
    String? next;
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalInfoScreen(
          accountName: 'Hoàng',
          email: 'hoang@gmail.com',
          profileStore: store,
          onChangePassword: (oldPassword, newPassword) async {
            current = oldPassword;
            next = newPassword;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change_password_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('current_password_field')),
      'old123',
    );
    await tester.enterText(
      find.byKey(const Key('new_password_field')),
      'new123',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_password_field')),
      'new123',
    );
    await tester.tap(find.byKey(const Key('confirm_change_password_button')));
    await tester.pumpAndSettle();
    expect(current, 'old123');
    expect(next, 'new123');
  });
}
