import 'package:shared_preferences/shared_preferences.dart';

class AnalysisPreferencesData {
  const AnalysisPreferencesData({
    this.heightCm = '',
    this.weightKg = '',
    this.temperatureC = '28',
    this.season = 'summer',
    this.style = 'casual',
    this.occasion = 'outing',
  });

  final String heightCm;
  final String weightKg;
  final String temperatureC;
  final String season;
  final String style;
  final String occasion;
}

abstract interface class AnalysisPreferencesStore {
  Future<AnalysisPreferencesData> load();
  Future<void> save(AnalysisPreferencesData data);
}

class SharedPreferencesAnalysisStore implements AnalysisPreferencesStore {
  static const _heightKey = 'outfit_analysis_height_cm';
  static const _weightKey = 'outfit_analysis_weight_kg';
  static const _temperatureKey = 'outfit_analysis_temperature_c';
  static const _seasonKey = 'outfit_analysis_season';
  static const _styleKey = 'outfit_analysis_style';
  static const _occasionKey = 'outfit_analysis_occasion';

  @override
  Future<AnalysisPreferencesData> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AnalysisPreferencesData(
      heightCm: preferences.getString(_heightKey) ?? '',
      weightKg: preferences.getString(_weightKey) ?? '',
      temperatureC: preferences.getString(_temperatureKey) ?? '28',
      season: preferences.getString(_seasonKey) ?? 'summer',
      style: preferences.getString(_styleKey) ?? 'casual',
      occasion: preferences.getString(_occasionKey) ?? 'outing',
    );
  }

  @override
  Future<void> save(AnalysisPreferencesData data) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      preferences.setString(_heightKey, data.heightCm),
      preferences.setString(_weightKey, data.weightKg),
      preferences.setString(_temperatureKey, data.temperatureC),
      preferences.setString(_seasonKey, data.season),
      preferences.setString(_styleKey, data.style),
      preferences.setString(_occasionKey, data.occasion),
    ]);
  }
}
