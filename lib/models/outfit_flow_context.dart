import 'body_profile.dart';
import 'gemini_fashion.dart';
import 'outfit_analysis_result.dart';
import 'weather_snapshot.dart';

/// Bối cảnh dùng chung giữa các tab; không chứa hay lưu bytes ảnh.
class OutfitFlowContext {
  const OutfitFlowContext({
    this.analysisResult,
    this.season = 'summer',
    this.temperature = '28',
    this.style = 'casual',
    this.occasion = 'outing',
    this.useCurrentWeather = false,
    this.weather,
    this.heightCm,
    this.weightKg,
    this.gender = BodyGender.unspecified,
  });

  final OutfitAnalysisResult? analysisResult;
  final String season;
  final String temperature;
  final String style;
  final String occasion;
  final bool useCurrentWeather;
  final WeatherSnapshot? weather;
  final double? heightCm;
  final double? weightKg;
  final BodyGender gender;

  GeminiOutfitContext get chatContext => GeminiOutfitContext(
    // Gợi ý và hỏi đáp là luồng độc lập, không kế thừa đồ nhận diện từ ảnh.
    items: const <DetectedOutfitItem>[],
    weather: useCurrentWeather ? weather : null,
    season: useCurrentWeather ? null : season,
    style: style,
    occasion: occasion,
    temperatureC: useCurrentWeather
        ? weather?.temperatureC
        : double.tryParse(temperature.trim().replaceAll(',', '.')),
    heightCm: heightCm,
    weightKg: weightKg,
    gender: gender,
  );
}
