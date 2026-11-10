import 'dart:ui';
import 'dart:typed_data';

enum TryOnFilterCategory { top, jacket, pants, skirt, dress, shoes }

extension TryOnFilterCategoryLabel on TryOnFilterCategory {
  String get label => switch (this) {
    TryOnFilterCategory.top => 'Áo',
    TryOnFilterCategory.jacket => 'Áo khoác',
    TryOnFilterCategory.pants => 'Quần',
    TryOnFilterCategory.skirt => 'Chân váy',
    TryOnFilterCategory.dress => 'Váy liền',
    TryOnFilterCategory.shoes => 'Giày',
  };
}

class TryOnFilter {
  const TryOnFilter({
    required this.id,
    required this.name,
    required this.category,
    this.assetPath = '',
    this.imageBytes,
    required this.widthMultiplier,
    required this.heightMultiplier,
    this.offsetX = 0,
    this.offsetY = 0,
    this.defaultRotation = 0,
    this.templateAligned = false,
    this.volume = 1,
  }) : assert(assetPath != '' || imageBytes != null);

  factory TryOnFilter.fromImage({
    required String id,
    required TryOnFilterCategory category,
    required Uint8List bytes,
    bool templateAligned = false,
    double volume = 1,
  }) {
    final preset = tryOnFilters.firstWhere(
      (filter) => filter.category == category,
    );
    // Shoulder/hip locations in the editor silhouettes, rather than the
    // transparent margins of the built-in product photographs.
    final (width, height, offsetY) = switch (category) {
      TryOnFilterCategory.top => (1 / .52, 1 / .85, -.025),
      TryOnFilterCategory.jacket => (1 / .56, 1 / .85, -.025),
      TryOnFilterCategory.pants => (1 / .76, 1 / .92, -.02),
      TryOnFilterCategory.skirt => (2.0, 1.0, 0.0),
      TryOnFilterCategory.dress => (1 / .36, 1 / .90, -.03),
      TryOnFilterCategory.shoes => (
        preset.widthMultiplier,
        preset.heightMultiplier,
        preset.offsetY,
      ),
    };
    return TryOnFilter(
      id: id,
      name: '${category.label} từ ảnh',
      category: category,
      imageBytes: bytes,
      templateAligned: templateAligned,
      volume: volume.clamp(.4, 1.8),
      widthMultiplier: templateAligned ? width : preset.widthMultiplier,
      heightMultiplier: templateAligned ? height : preset.heightMultiplier,
      offsetY: templateAligned ? offsetY : preset.offsetY,
    );
  }

  final String id;
  final String name;
  final TryOnFilterCategory category;
  final String assetPath;

  /// Chỉ giữ trong phiên thử đồ; không ghi ảnh vào Firebase hay bộ nhớ máy.
  final Uint8List? imageBytes;
  final double widthMultiplier;
  final double heightMultiplier;
  final double offsetX;
  final double offsetY;
  final double defaultRotation;
  final bool templateAligned;
  final double volume;

  TryOnFilter withVolume(double value) => TryOnFilter(
    id: id,
    name: name,
    category: category,
    assetPath: assetPath,
    imageBytes: imageBytes,
    widthMultiplier: widthMultiplier,
    heightMultiplier: heightMultiplier,
    offsetX: offsetX,
    offsetY: offsetY,
    defaultRotation: defaultRotation,
    templateAligned: templateAligned,
    volume: value.clamp(.4, 1.8),
  );

  /// 3D UVs use the editor's pattern coordinates; legacy photos stay in 2D.
  bool get supports3D =>
      templateAligned && category != TryOnFilterCategory.shoes;
}

class ManualFilterTransform {
  const ManualFilterTransform({
    this.offset = Offset.zero,
    this.scale = 1,
    this.rotation = 0,
  });

  static const double minimumScale = 0.5;
  static const double maximumScale = 2.5;

  final Offset offset;
  final double scale;
  final double rotation;

  ManualFilterTransform copyWith({
    Offset? offset,
    double? scale,
    double? rotation,
  }) {
    return ManualFilterTransform(
      offset: offset ?? this.offset,
      scale: (scale ?? this.scale).clamp(minimumScale, maximumScale),
      rotation: rotation ?? this.rotation,
    );
  }
}

const List<TryOnFilter> tryOnFilters = <TryOnFilter>[
  TryOnFilter(
    id: 'tshirt_white_01',
    name: 'Áo thun trắng',
    category: TryOnFilterCategory.top,
    assetPath: 'assets/try_on/tops/tshirt_white_01.png',
    widthMultiplier: 1.42,
    heightMultiplier: 1.40,
    offsetY: 0.03,
  ),
  TryOnFilter(
    id: 'jacket_teal_01',
    name: 'Áo khoác xanh',
    category: TryOnFilterCategory.jacket,
    assetPath: 'assets/try_on/jackets/jacket_teal_01.png',
    widthMultiplier: 1.62,
    heightMultiplier: 1.62,
    offsetY: 0.04,
  ),
  TryOnFilter(
    id: 'pants_navy_01',
    name: 'Quần xanh navy',
    category: TryOnFilterCategory.pants,
    assetPath: 'assets/try_on/pants/pants_navy_01.png',
    widthMultiplier: 1.55,
    heightMultiplier: 1.04,
    offsetY: 0.02,
  ),
  TryOnFilter(
    id: 'skirt_coral_01',
    name: 'Chân váy san hô',
    category: TryOnFilterCategory.skirt,
    assetPath: 'assets/try_on/skirts/skirt_coral_01.png',
    widthMultiplier: 1.75,
    heightMultiplier: 0.62,
    offsetY: 0.02,
  ),
  TryOnFilter(
    id: 'dress_purple_01',
    name: 'Váy tím',
    category: TryOnFilterCategory.dress,
    assetPath: 'assets/try_on/dresses/dress_purple_01.png',
    widthMultiplier: 1.55,
    heightMultiplier: 0.90,
    offsetY: 0.02,
  ),
  TryOnFilter(
    id: 'shoes_white_01',
    name: 'Giày trắng',
    category: TryOnFilterCategory.shoes,
    assetPath: 'assets/try_on/shoes/shoes_white_01.png',
    widthMultiplier: 1.45,
    heightMultiplier: 0.52,
    offsetY: 0.02,
  ),
];
