class BoundingBox {
  const BoundingBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x1: _asDouble(json['x1']),
      y1: _asDouble(json['y1']),
      x2: _asDouble(json['x2']),
      y2: _asDouble(json['y2']),
    );
  }

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  bool get isValid =>
      x1.isFinite &&
      y1.isFinite &&
      x2.isFinite &&
      y2.isFinite &&
      x2 > x1 &&
      y2 > y1;

  BoundingBox clamped({required double width, required double height}) {
    return BoundingBox(
      x1: x1.clamp(0, width).toDouble(),
      y1: y1.clamp(0, height).toDouble(),
      x2: x2.clamp(0, width).toDouble(),
      y2: y2.clamp(0, height).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BoundingBox &&
        other.x1 == x1 &&
        other.y1 == y1 &&
        other.x2 == x2 &&
        other.y2 == y2;
  }

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);
}

class NormalizedBoundingBox {
  const NormalizedBoundingBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  factory NormalizedBoundingBox.fromJson(Map<String, dynamic> json) {
    return NormalizedBoundingBox(
      x1: _asDouble(json['x1']).clamp(0, 1).toDouble(),
      y1: _asDouble(json['y1']).clamp(0, 1).toDouble(),
      x2: _asDouble(json['x2']).clamp(0, 1).toDouble(),
      y2: _asDouble(json['y2']).clamp(0, 1).toDouble(),
    );
  }

  factory NormalizedBoundingBox.fromBoundingBox(
    BoundingBox box, {
    required int imageWidth,
    required int imageHeight,
  }) {
    final clamped = box.clamped(
      width: imageWidth.toDouble(),
      height: imageHeight.toDouble(),
    );
    return NormalizedBoundingBox(
      x1: clamped.x1 / imageWidth,
      y1: clamped.y1 / imageHeight,
      x2: clamped.x2 / imageWidth,
      y2: clamped.y2 / imageHeight,
    );
  }

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  @override
  bool operator ==(Object other) {
    return other is NormalizedBoundingBox &&
        other.x1 == x1 &&
        other.y1 == y1 &&
        other.x2 == x2 &&
        other.y2 == y2;
  }

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);
}

class ClothingDetection {
  const ClothingDetection({
    required this.classId,
    required this.rawClassName,
    required this.className,
    required this.classNameVi,
    required this.color,
    required this.confidence,
    required this.boundingBox,
    this.normalizedBoundingBox,
  });

  factory ClothingDetection.fromJson(Map<String, dynamic> json) {
    final normalizedJson = _asMap(json['bbox_normalized']);
    return ClothingDetection(
      classId: _asInt(json['class_id'], fallback: -1),
      rawClassName: _asString(json['raw_class_name']),
      className: _asString(json['class_name'], fallback: 'unknown'),
      classNameVi: _asString(json['class_name_vi'], fallback: 'Không xác định'),
      color: _asString(json['color'], fallback: 'Không xác định'),
      confidence: _asDouble(json['confidence']),
      boundingBox: BoundingBox.fromJson(_asMap(json['bbox'])),
      normalizedBoundingBox: normalizedJson.isEmpty
          ? null
          : NormalizedBoundingBox.fromJson(normalizedJson),
    );
  }

  final int classId;
  final String rawClassName;
  final String className;
  final String classNameVi;
  final String color;
  final double confidence;
  final BoundingBox boundingBox;
  final NormalizedBoundingBox? normalizedBoundingBox;

  double get safeConfidence {
    if (!confidence.isFinite) {
      return 0;
    }
    return confidence.clamp(0, 1).toDouble();
  }

  double get confidencePercent => safeConfidence * 100;

  NormalizedBoundingBox normalizedBoxFor({
    required int imageWidth,
    required int imageHeight,
  }) {
    return normalizedBoundingBox ??
        NormalizedBoundingBox.fromBoundingBox(
          boundingBox,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );
  }

  @override
  bool operator ==(Object other) {
    return other is ClothingDetection &&
        other.classId == classId &&
        other.rawClassName == rawClassName &&
        other.className == className &&
        other.classNameVi == classNameVi &&
        other.color == color &&
        other.confidence == confidence &&
        other.boundingBox == boundingBox &&
        other.normalizedBoundingBox == normalizedBoundingBox;
  }

  @override
  int get hashCode => Object.hash(
    classId,
    rawClassName,
    className,
    classNameVi,
    color,
    confidence,
    boundingBox,
    normalizedBoundingBox,
  );
}

class DetectionSummary {
  const DetectionSummary({
    required this.className,
    required this.classNameVi,
    required this.count,
  });

  factory DetectionSummary.fromJson(Map<String, dynamic> json) {
    return DetectionSummary(
      className: _asString(json['class_name'], fallback: 'unknown'),
      classNameVi: _asString(json['class_name_vi'], fallback: 'Không xác định'),
      count: _asInt(json['count']).clamp(0, 1 << 31),
    );
  }

  final String className;
  final String classNameVi;
  final int count;
}

class DetectionResponse {
  DetectionResponse({
    required this.filename,
    required this.imageWidth,
    required this.imageHeight,
    required List<ClothingDetection> detections,
    required this.ignoredDetectionCount,
    List<DetectionSummary>? summary,
  }) : detections = List<ClothingDetection>.unmodifiable(
         List<ClothingDetection>.of(detections)..sort(
           (first, second) =>
               second.safeConfidence.compareTo(first.safeConfidence),
         ),
       ),
       summary = List<DetectionSummary>.unmodifiable(
         summary == null || (summary.isEmpty && detections.isNotEmpty)
             ? buildSummary(detections)
             : summary,
       ) {
    if (imageWidth <= 0 || imageHeight <= 0) {
      throw const FormatException('Kích thước ảnh từ máy chủ không hợp lệ.');
    }
  }

  factory DetectionResponse.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    final detections = <ClothingDetection>[];
    if (rawDetections is List) {
      for (final item in rawDetections) {
        final map = _asMap(item);
        if (map.isNotEmpty) {
          detections.add(ClothingDetection.fromJson(map));
        }
      }
    }

    final rawSummary = json['summary'];
    final parsedSummary = <DetectionSummary>[];
    if (rawSummary is List) {
      for (final item in rawSummary) {
        final map = _asMap(item);
        if (map.isNotEmpty) {
          parsedSummary.add(DetectionSummary.fromJson(map));
        }
      }
    }

    return DetectionResponse(
      filename: _asString(json['filename'], fallback: 'image'),
      imageWidth: _asInt(json['image_width']),
      imageHeight: _asInt(json['image_height']),
      detections: detections,
      ignoredDetectionCount: _asInt(json['ignored_detection_count'])
          .clamp(0, 1 << 31),
      summary: parsedSummary,
    );
  }

  final String filename;
  final int imageWidth;
  final int imageHeight;
  final List<ClothingDetection> detections;
  final int ignoredDetectionCount;
  final List<DetectionSummary> summary;

  int get detectionCount => detections.length;
  bool get hasDetections => detections.isNotEmpty;

  static List<DetectionSummary> buildSummary(
    Iterable<ClothingDetection> detections,
  ) {
    final grouped = <String, DetectionSummary>{};
    for (final detection in detections) {
      final current = grouped[detection.className];
      grouped[detection.className] = DetectionSummary(
        className: detection.className,
        classNameVi: detection.classNameVi,
        count: (current?.count ?? 0) + 1,
      );
    }
    return grouped.values.toList(growable: false);
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

String _asString(Object? value, {String fallback = ''}) {
  return value is String && value.trim().isNotEmpty ? value : fallback;
}

int _asInt(Object? value, {int fallback = 0}) {
  return value is num && value.isFinite ? value.toInt() : fallback;
}

double _asDouble(Object? value, {double fallback = 0}) {
  return value is num && value.isFinite ? value.toDouble() : fallback;
}
