import 'package:shared_preferences/shared_preferences.dart';

class AnalysisPreferencesData {
  const AnalysisPreferencesData({
    this.heightCm = '',
    this.weightKg = '',
    this.temperatureC = '28',
    this.season = 'summer',
    this.style = 'casual',
    this.occasion = 'outing',
    this.useCurrentWeather = false,
  });

  final String heightCm;
  final String weightKg;
  final String temperatureC;
  final String season;
  final String style;
  final String occasion;
  final bool useCurrentWeather;
}

abstract interface class AnalysisPreferencesStore {
  Future<AnalysisPreferencesData> load();
  Future<void> save(AnalysisPreferencesData data);
}

class SharedPreferencesAnalysisStore implements AnalysisPreferencesStore {
  SharedPreferencesAnalysisStore({String? userId})
    : _prefix = userId == null ? '' : 'user_${userId}_';
  final String _prefix;
  static const _heightKey = 'outfit_analysis_height_cm';
  static const _weightKey = 'outfit_analysis_weight_kg';
  static const _temperatureKey = 'outfit_analysis_temperature_c';
  static const _seasonKey = 'outfit_analysis_season';
  static const _styleKey = 'outfit_analysis_style';
  static const _occasionKey = 'outfit_analysis_occasion';
  static const _weatherModeKey = 'outfit_analysis_current_weather';

  @override
  Future<AnalysisPreferencesData> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AnalysisPreferencesData(
      heightCm: preferences.getString('$_prefix$_heightKey') ?? '',
      weightKg: preferences.getString('$_prefix$_weightKey') ?? '',
      temperatureC: preferences.getString('$_prefix$_temperatureKey') ?? '28',
      season: preferences.getString('$_prefix$_seasonKey') ?? 'summer',
      style: preferences.getString('$_prefix$_styleKey') ?? 'casual',
      occasion: preferences.getString('$_prefix$_occasionKey') ?? 'outing',
      useCurrentWeather:
          preferences.getBool('$_prefix$_weatherModeKey') ?? false,
    );
  }

  @override
  Future<void> save(AnalysisPreferencesData data) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      preferences.setString('$_prefix$_heightKey', data.heightCm),
      preferences.setString('$_prefix$_weightKey', data.weightKg),
      preferences.setString('$_prefix$_temperatureKey', data.temperatureC),
      preferences.setString('$_prefix$_seasonKey', data.season),
      preferences.setString('$_prefix$_styleKey', data.style),
      preferences.setString('$_prefix$_occasionKey', data.occasion),
      preferences.setBool('$_prefix$_weatherModeKey', data.useCurrentWeather),
    ]);
  }
}
