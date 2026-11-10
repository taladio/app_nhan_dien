import 'package:app_nhan_dien/models/outfit_analysis_result.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload() => <String, dynamic>{
  'filename': 'outfit.jpg',
  'image_width': 1080,
  'image_height': 1920,
  'source': 'gemini',
  'detected_items': <Object?>[
    <String, dynamic>{
      'detection_id': 'det_1',
      'class_id': 0,
      'raw_class_name': 'T-Shirt',
      'class_name': 'tshirt',
      'class_name_vi': 'Áo thun',
      'primary_color': 'Trắng',
      'secondary_colors': <String>['Xám'],
      'confidence': 0.91,
      'bbox': <String, dynamic>{'x1': 220, 'y1': 300, 'x2': 820, 'y2': 950},
    },
  ],
  'evaluation': <String, dynamic>{
    'overall_score': 82.5,
    'rating': 'Phù hợp',
    'color_score': 90,
    'season_temperature_score': 85,
    'body_proportion_score': 75,
    'style_score': 80,
    'occasion_score': 80,
    'summary': 'Bộ đồ hài hòa.',
    'strengths': <String>['Màu tương phản cân bằng.'],
    'problems': <String>[],
    'recommendations': <String>['Giữ bảng màu gọn.'],
    'suggested_outfit': <String, dynamic>{
      'top': 'Áo thun trắng',
      'bottom': 'Quần short màu be',
      'outerwear': null,
      'shoes': 'Giày trắng',
      'reason': 'Phù hợp mùa hè.',
    },
  },
};

void main() {
  test('parse response null-safe và chuyển sang detection overlay', () {
    final result = OutfitAnalysisResult.fromJson(_payload());

    expect(result.source, OutfitAnalysisSource.gemini);
    expect(result.source.displayName, 'Gemini AI');
    expect(result.detectedItems.single.primaryColor, 'Trắng');
    expect(result.detectedItems.single.secondaryColors, <String>['Xám']);
    expect(result.evaluation?.overallScore, 82.5);
    expect(result.evaluation?.suggestedOutfit.outerwear, isNull);

    final detectionResponse = result.asDetectionResponse();
    expect(detectionResponse.imageWidth, 1080);
    expect(detectionResponse.detections.single.color, 'Trắng');
    expect(detectionResponse.detections.single.boundingBox.x1, 220);
  });

  test('từ chối source lạ và score ngoài 0-100', () {
    final invalidSource = _payload()..['source'] = 'unknown';
    expect(
      () => OutfitAnalysisResult.fromJson(invalidSource),
      throwsFormatException,
    );

    final invalidScore = _payload();
    (invalidScore['evaluation'] as Map<String, dynamic>)['color_score'] = 101;
    expect(
      () => OutfitAnalysisResult.fromJson(invalidScore),
      throwsFormatException,
    );
  });

  test('Gemini lỗi vẫn giữ nhãn YOLO và không có gợi ý giả', () {
    final payload = _payload()
      ..['source'] = 'unavailable'
      ..['evaluation'] = null
      ..['ai_error'] = 'Gemini tạm thời không phản hồi.';
    final result = OutfitAnalysisResult.fromJson(payload);
    expect(result.source, OutfitAnalysisSource.unavailable);
    expect(result.detectedItems, hasLength(1));
    expect(result.evaluation, isNull);
    expect(result.aiError, contains('Gemini'));
  });
}
