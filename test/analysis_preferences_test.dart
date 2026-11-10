import 'package:app_nhan_dien/services/analysis_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'weather mode and manual values survive reopening per account',
    () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferencesAnalysisStore(userId: 'a').save(
        const AnalysisPreferencesData(
          useCurrentWeather: true,
          temperatureC: '18',
          season: 'winter',
          style: 'office',
          occasion: 'work',
        ),
      );
      final loaded = await SharedPreferencesAnalysisStore(userId: 'a').load();
      expect(loaded.useCurrentWeather, true);
      expect(loaded.temperatureC, '18');
      expect(loaded.season, 'winter');
      expect(loaded.style, 'office');
      final other = await SharedPreferencesAnalysisStore(userId: 'b').load();
      expect(other.useCurrentWeather, false);
      expect(other.style, 'casual');
    },
  );
}
