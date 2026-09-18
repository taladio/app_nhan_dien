import 'detection_result.dart';

enum OutfitAnalysisSource {
  openai,
  fallback;

  String get displayName => this == openai ? 'AI' : 'Đánh giá cơ bản';
}

class DetectedOutfitItem {
  DetectedOutfitItem({
    required this.detectionId,
    required this.classId,
    required this.rawClassName,
    required this.className,
    required this.classNameVi,
    required this.primaryColor,
    required List<String> secondaryColors,
    required this.confidence,
    required this.boundingBox,
  }) : secondaryColors = List<String>.unmodifiable(secondaryColors) {
    if (detectionId.isEmpty || className.isEmpty || classNameVi.isEmpty) {
      throw const FormatException('Detection thiếu thông tin bắt buộc.');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const FormatException('Confidence không hợp lệ.');
    }
    if (!boundingBox.isValid || secondaryColors.length > 2) {
      throw const FormatException('Bounding box hoặc màu phụ không hợp lệ.');
    }
  }

  factory DetectedOutfitItem.fromJson(Map<String, dynamic> json) {
    return DetectedOutfitItem(
      detectionId: _requiredString(json, 'detection_id'),
      classId: _requiredInt(json, 'class_id'),
      rawClassName: _requiredString(json, 'raw_class_name'),
      className: _requiredString(json, 'class_name'),
      classNameVi: _requiredString(json, 'class_name_vi'),
      primaryColor: _requiredString(json, 'primary_color'),
      secondaryColors: _stringList(json['secondary_colors']),
      confidence: _requiredDouble(json, 'confidence'),
      boundingBox: BoundingBox.fromJson(_requiredMap(json, 'bbox')),
    );
  }

  final String detectionId;
  final int classId;
  final String rawClassName;
  final String className;
  final String classNameVi;
  final String primaryColor;
  final List<String> secondaryColors;
  final double confidence;
  final BoundingBox boundingBox;
}

class SuggestedOutfit {
  const SuggestedOutfit({
    required this.top,
    required this.bottom,
    required this.outerwear,
    required this.shoes,
    required this.reason,
  });

  factory SuggestedOutfit.fromJson(Map<String, dynamic> json) {
    return SuggestedOutfit(
      top: _nullableString(json, 'top'),
      bottom: _nullableString(json, 'bottom'),
      outerwear: _nullableString(json, 'outerwear'),
      shoes: _nullableString(json, 'shoes'),
      reason: _requiredString(json, 'reason'),
    );
  }

  final String? top;
  final String? bottom;
  final String? outerwear;
  final String? shoes;
  final String reason;
}

class OutfitEvaluation {
  OutfitEvaluation({
    required this.overallScore,
    required this.rating,
    required this.colorScore,
    required this.seasonTemperatureScore,
    required this.bodyProportionScore,
    required this.styleScore,
    required this.occasionScore,
    required this.summary,
    required List<String> strengths,
    required List<String> problems,
    required List<String> recommendations,
    required this.suggestedOutfit,
  }) : strengths = List<String>.unmodifiable(strengths),
       problems = List<String>.unmodifiable(problems),
       recommendations = List<String>.unmodifiable(recommendations) {
    for (final score in scores.values) {
      if (!score.isFinite || score < 0 || score > 100) {
        throw const FormatException('Điểm đánh giá không hợp lệ.');
      }
    }
  }

  factory OutfitEvaluation.fromJson(Map<String, dynamic> json) {
    return OutfitEvaluation(
      overallScore: _requiredDouble(json, 'overall_score'),
      rating: _requiredString(json, 'rating'),
      colorScore: _requiredDouble(json, 'color_score'),
      seasonTemperatureScore: _requiredDouble(json, 'season_temperature_score'),
      bodyProportionScore: _requiredDouble(json, 'body_proportion_score'),
      styleScore: _requiredDouble(json, 'style_score'),
      occasionScore: _requiredDouble(json, 'occasion_score'),
      summary: _requiredString(json, 'summary'),
      strengths: _stringList(json['strengths']),
      problems: _stringList(json['problems']),
      recommendations: _stringList(json['recommendations']),
      suggestedOutfit: SuggestedOutfit.fromJson(
        _requiredMap(json, 'suggested_outfit'),
      ),
    );
  }

  final double overallScore;
  final String rating;
  final double colorScore;
  final double seasonTemperatureScore;
  final double bodyProportionScore;
  final double styleScore;
  final double occasionScore;
  final String summary;
  final List<String> strengths;
  final List<String> problems;
  final List<String> recommendations;
  final SuggestedOutfit suggestedOutfit;

  Map<String, double> get scores => <String, double>{
    'overall': overallScore,
    'color': colorScore,
    'season': seasonTemperatureScore,
    'body': bodyProportionScore,
    'style': styleScore,
    'occasion': occasionScore,
  };
}

class OutfitAnalysisResult {
  OutfitAnalysisResult({
    required this.filename,
    required this.imageWidth,
    required this.imageHeight,
    required this.source,
    required List<DetectedOutfitItem> detectedItems,
    required this.evaluation,
  }) : detectedItems = List<DetectedOutfitItem>.unmodifiable(detectedItems) {
    if (imageWidth <= 0 || imageHeight <= 0 || detectedItems.isEmpty) {
      throw const FormatException('Kết quả phân tích thiếu dữ liệu.');
    }
  }

  factory OutfitAnalysisResult.fromJson(Map<String, dynamic> json) {
    final sourceValue = _requiredString(json, 'source');
    final source = switch (sourceValue) {
      'openai' => OutfitAnalysisSource.openai,
      'fallback' => OutfitAnalysisSource.fallback,
      _ => throw const FormatException('Nguồn đánh giá không hợp lệ.'),
    };
    final items = _requiredList(json, 'detected_items')
        .map((item) => DetectedOutfitItem.fromJson(_asMap(item)))
        .toList(growable: false);

    return OutfitAnalysisResult(
      filename: _requiredString(json, 'filename'),
      imageWidth: _requiredInt(json, 'image_width'),
      imageHeight: _requiredInt(json, 'image_height'),
      source: source,
      detectedItems: items,
      evaluation: OutfitEvaluation.fromJson(_requiredMap(json, 'evaluation')),
    );
  }

  final String filename;
  final int imageWidth;
  final int imageHeight;
  final OutfitAnalysisSource source;
  final List<DetectedOutfitItem> detectedItems;
  final OutfitEvaluation evaluation;

  DetectionResponse asDetectionResponse() {
    return DetectionResponse(
      filename: filename,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      ignoredDetectionCount: 0,
      detections: detectedItems
          .map(
            (item) => ClothingDetection(
              classId: item.classId,
              rawClassName: item.rawClassName,
              className: item.className,
              classNameVi: item.classNameVi,
              color: item.primaryColor,
              confidence: item.confidence,
              boundingBox: item.boundingBox,
            ),
          )
          .toList(growable: false),
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw const FormatException('Dữ liệu JSON không đúng cấu trúc.');
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Thiếu trường $key.');
  return _asMap(json[key]);
}

List<Object?> _requiredList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('Trường $key phải là danh sách.');
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    throw const FormatException('Danh sách văn bản không hợp lệ.');
  }
  return value
      .map((item) {
        if (item is! String || item.trim().isEmpty) {
          throw const FormatException('Danh sách chứa văn bản không hợp lệ.');
        }
        return item.trim();
      })
      .toList(growable: false);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Trường $key không hợp lệ.');
  }
  return value.trim();
}

String? _nullableString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Thiếu trường $key.');
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Trường $key không hợp lệ.');
  }
  return value.trim();
}

double _requiredDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('Trường $key không phải số hợp lệ.');
  }
  return value.toDouble();
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    throw FormatException('Trường $key không phải số nguyên hợp lệ.');
  }
  return value.toInt();
}
