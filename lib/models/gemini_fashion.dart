import 'body_profile.dart';
import 'outfit_analysis_result.dart';
import 'weather_snapshot.dart';

class GeminiOutfitContext {
  GeminiOutfitContext({
    required this.items,
    this.weather,
    this.season,
    this.style,
    this.occasion,
    this.temperatureC,
    this.heightCm,
    this.weightKg,
    this.gender = BodyGender.unspecified,
  });

  final List<DetectedOutfitItem> items;
  final WeatherSnapshot? weather;
  final String? season;
  final String? style;
  final String? occasion;
  final double? temperatureC;
  final double? heightCm;
  final double? weightKg;
  final BodyGender gender;

  bool get hasColorData =>
      items.any((item) => _knownColor(item.primaryColor) != null);

  Map<String, Object?> toJson() => <String, Object?>{
    'items': items
        .take(30)
        .map(
          (item) => <String, Object?>{
            // Keep the exact YOLO model label, not only the eight UI categories.
            'label': item.rawClassName,
            'confidence': item.confidence,
            'color': _knownColor(item.primaryColor),
          },
        )
        .toList(),
    'weather': weather?.toAnalysisJson(),
    'season': weather == null ? season : null,
    'style': style,
    'occasion': occasion,
    'temperature_c': weather?.temperatureC ?? temperatureC,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    if (gender.adviceValue != null) 'gender': gender.adviceValue,
  };

  static String? _knownColor(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        <String>{
          'không xác định',
          'khong xac dinh',
          'unknown',
          'n/a',
        }.contains(normalized.toLowerCase())) {
      return null;
    }
    return normalized;
  }
}

class GeminiSuggestion {
  const GeminiSuggestion({
    required this.assessment,
    required this.reason,
    required this.adjustments,
    required this.colorScore,
  });

  final String assessment;
  final String reason;
  final List<String> adjustments;
  final int? colorScore;

  factory GeminiSuggestion.fromJson(Map<String, dynamic> json) {
    final assessment = json['assessment'];
    final reason = json['reason'];
    final adjustments = json['adjustments'];
    final colorScore = json['color_score'];
    if (assessment is! String ||
        assessment.trim().isEmpty ||
        reason is! String ||
        reason.trim().isEmpty ||
        adjustments is! List ||
        adjustments.isEmpty ||
        adjustments.any((item) => item is! String || item.trim().isEmpty) ||
        (colorScore != null &&
            (colorScore is! int || colorScore < 0 || colorScore > 100))) {
      throw const FormatException('Dữ liệu gợi ý AI không hợp lệ.');
    }
    return GeminiSuggestion(
      assessment: assessment,
      reason: reason,
      adjustments: adjustments.cast<String>(),
      colorScore: colorScore,
    );
  }
}

class GeminiChatTurn {
  const GeminiChatTurn({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, String> toJson() => <String, String>{
    'role': role,
    'content': content,
  };
}
