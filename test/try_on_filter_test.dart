import 'package:app_nhan_dien/models/try_on_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual filter scale is clamped to safe bounds', () {
    const transform = ManualFilterTransform();

    expect(transform.copyWith(scale: 0.1).scale, 0.5);
    expect(transform.copyWith(scale: 9).scale, 2.5);
    expect(transform.copyWith(scale: 1.4).scale, 1.4);
  });

  test('all filter categories have local metadata', () {
    for (final category in TryOnFilterCategory.values) {
      expect(
        tryOnFilters.where((filter) => filter.category == category),
        isNotEmpty,
      );
    }
    expect(
      tryOnFilters.every((filter) => filter.assetPath.startsWith('assets/')),
      isTrue,
    );
  });
}
