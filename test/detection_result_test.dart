import 'package:app_nhan_dien/models/detection_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> fullJson() => <String, dynamic>{
    'filename': 'outfit.jpg',
    'image_width': 1080,
    'image_height': 1920,
    'detection_count': 1,
    'ignored_detection_count': 2,
    'detections': <Map<String, dynamic>>[
      <String, dynamic>{
        'class_id': 19,
        'raw_class_name': 'tshirt',
        'class_name': 'tshirt',
        'class_name_vi': 'Áo thun',
        'color': 'Trắng',
        'confidence': 0.9321,
        'bbox': <String, dynamic>{'x1': 245, 'y1': 218, 'x2': 816, 'y2': 905},
        'bbox_normalized': <String, dynamic>{
          'x1': 0.2269,
          'y1': 0.1135,
          'x2': 0.7556,
          'y2': 0.4714,
        },
      },
    ],
    'summary': <Map<String, dynamic>>[
      <String, dynamic>{
        'class_name': 'tshirt',
        'class_name_vi': 'Áo thun',
        'count': 1,
      },
    ],
  };

  test('parse JSON đầy đủ', () {
    final result = DetectionResponse.fromJson(fullJson());

    expect(result.filename, 'outfit.jpg');
    expect(result.imageWidth, 1080);
    expect(result.imageHeight, 1920);
    expect(result.detectionCount, 1);
    expect(result.ignoredDetectionCount, 2);
    expect(result.summary.single.classNameVi, 'Áo thun');
    expect(result.detections.single.rawClassName, 'tshirt');
    expect(result.detections.single.normalizedBoundingBox?.x1, 0.2269);
  });

  test('tự tạo summary khi JSON thiếu summary', () {
    final json = fullJson()..remove('summary');
    final detections =
        List<Map<String, dynamic>>.from(json['detections']! as List)
          ..add(<String, dynamic>{
            ...Map<String, dynamic>.from(
              (json['detections']! as List).first as Map,
            ),
            'confidence': 0.8,
          });
    json['detections'] = detections;

    final result = DetectionResponse.fromJson(json);

    expect(result.summary, hasLength(1));
    expect(result.summary.single.className, 'tshirt');
    expect(result.summary.single.count, 2);
  });

  test('hoạt động khi thiếu bbox_normalized', () {
    final json = fullJson();
    final detection = Map<String, dynamic>.from(
      (json['detections']! as List).first as Map,
    )..remove('bbox_normalized');
    json['detections'] = <Map<String, dynamic>>[detection];

    final result = DetectionResponse.fromJson(json);
    final parsed = result.detections.single;
    final normalized = parsed.normalizedBoxFor(
      imageWidth: result.imageWidth,
      imageHeight: result.imageHeight,
    );

    expect(parsed.normalizedBoundingBox, isNull);
    expect(normalized.x1, closeTo(245 / 1080, 0.000001));
    expect(normalized.y2, closeTo(905 / 1920, 0.000001));
  });

  test('confidence được giới hạn và chuyển sang phần trăm', () {
    const tooHigh = ClothingDetection(
      classId: 1,
      rawClassName: 'shirt',
      className: 'shirt',
      classNameVi: 'Áo sơ mi',
      color: 'Xanh',
      confidence: 1.4,
      boundingBox: BoundingBox(x1: 0, y1: 0, x2: 10, y2: 10),
    );
    const normal = ClothingDetection(
      classId: 2,
      rawClassName: 'shoe',
      className: 'shoes',
      classNameVi: 'Giày',
      color: 'Đen',
      confidence: 0.9321,
      boundingBox: BoundingBox(x1: 0, y1: 0, x2: 10, y2: 10),
    );

    expect(tooHigh.confidencePercent, 100);
    expect(normal.confidencePercent, closeTo(93.21, 0.0001));
  });

  test('từ chối kích thước ảnh không hợp lệ', () {
    final json = fullJson()..['image_width'] = 0;

    expect(
      () => DetectionResponse.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
