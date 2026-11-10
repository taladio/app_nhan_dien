class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.precipitationMmCurrentInterval,
    required this.precipitationIntervalMinutes,
    required this.weatherCode,
    required this.temperatureMaxCToday,
    required this.temperatureMinCToday,
    required this.precipitationProbabilityMaxPercentToday,
    required this.observedAtLocal,
    required this.todayDate,
    required this.timezone,
    required this.latitude,
    required this.longitude,
  });

  final double temperatureC;
  final double apparentTemperatureC;
  final double precipitationMmCurrentInterval;
  final double precipitationIntervalMinutes;
  final int weatherCode;
  final double temperatureMaxCToday;
  final double temperatureMinCToday;
  final int precipitationProbabilityMaxPercentToday;
  final String observedAtLocal;
  final String todayDate;
  final String timezone;
  final double latitude;
  final double longitude;

  bool get isRainingNow =>
      precipitationMmCurrentInterval > 0 ||
      <int>{
        51,
        53,
        55,
        56,
        57,
        61,
        63,
        65,
        66,
        67,
        80,
        81,
        82,
        95,
        96,
        99,
      }.contains(weatherCode);

  bool get rainLikelyToday => precipitationProbabilityMaxPercentToday >= 60;

  String get conditionLabel => switch (weatherCode) {
    0 => 'Trời quang',
    1 || 2 || 3 => 'Có mây',
    45 || 48 => 'Sương mù',
    51 || 53 || 55 || 56 || 57 => 'Mưa phùn',
    61 || 63 || 65 || 66 || 67 => 'Mưa',
    71 || 73 || 75 || 77 => 'Tuyết',
    80 || 81 || 82 => 'Mưa rào',
    95 || 96 || 99 => 'Dông',
    _ => 'Điều kiện thời tiết khác',
  };

  Map<String, Object> toAnalysisJson() => <String, Object>{
    'source': 'Open-Meteo',
    'temperature_c': temperatureC,
    'apparent_temperature_c': apparentTemperatureC,
    'precipitation_mm_current_interval': precipitationMmCurrentInterval,
    'precipitation_interval_minutes': precipitationIntervalMinutes,
    'weather_code': weatherCode,
    'temperature_max_c_today': temperatureMaxCToday,
    'temperature_min_c_today': temperatureMinCToday,
    'precipitation_probability_max_percent_today':
        precipitationProbabilityMaxPercentToday,
    'observed_at_local': observedAtLocal,
    'today_date': todayDate,
    'timezone': timezone,
  };

  static WeatherSnapshot fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite) {
        throw const FormatException('Dữ liệu thời tiết không hợp lệ.');
      }
      return value.toDouble();
    }

    String string(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw const FormatException('Dữ liệu thời tiết không hợp lệ.');
      }
      return value;
    }

    final code = number('weather_code');
    final probability = number('precipitation_probability_max_percent_today');
    final interval = number('precipitation_interval_minutes');
    final precipitation = number('precipitation_mm_current_interval');
    if (code != code.roundToDouble() ||
        probability != probability.roundToDouble() ||
        code < 0 ||
        code > 99 ||
        probability < 0 ||
        probability > 100 ||
        interval <= 0 ||
        precipitation < 0) {
      throw const FormatException('Dữ liệu thời tiết không hợp lệ.');
    }
    return WeatherSnapshot(
      temperatureC: number('temperature_c'),
      apparentTemperatureC: number('apparent_temperature_c'),
      precipitationMmCurrentInterval: precipitation,
      precipitationIntervalMinutes: interval,
      weatherCode: code.toInt(),
      temperatureMaxCToday: number('temperature_max_c_today'),
      temperatureMinCToday: number('temperature_min_c_today'),
      precipitationProbabilityMaxPercentToday: probability.toInt(),
      observedAtLocal: string('observed_at_local'),
      todayDate: string('today_date'),
      timezone: string('timezone'),
      latitude: number('latitude'),
      longitude: number('longitude'),
    );
  }
}
