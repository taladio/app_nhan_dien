import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/detection_result.dart';
import '../services/fashion_api_service.dart';
import '../widgets/detection_image_view.dart';
import '../widgets/detection_result_card.dart';

enum DetectionScreenStatus {
  noImage,
  imageSelected,
  loading,
  success,
  empty,
  error,
}

@immutable
class SelectedImageData {
  const SelectedImageData({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

typedef ImageSelectionCallback = Future<SelectedImageData?> Function(
  ImageSource source,
);

class ClothingDetectionScreen extends StatefulWidget {
  const ClothingDetectionScreen({
    super.key,
    this.service,
    this.imageSelectionCallback,
  });

  final FashionDetectionService? service;
  final ImageSelectionCallback? imageSelectionCallback;

  @override
  State<ClothingDetectionScreen> createState() =>
      _ClothingDetectionScreenState();
}

class _ClothingDetectionScreenState extends State<ClothingDetectionScreen> {
  late final FashionDetectionService _service;
  late final bool _ownsService;
  final ImagePicker _imagePicker = ImagePicker();

  SelectedImageData? _selectedImage;
  DetectionResponse? _response;
  DetectionScreenStatus _status = DetectionScreenStatus.noImage;
  String? _errorMessage;
  double _confidence = 0.25;
  bool _showBoundingBoxes = true;
  int? _highlightedIndex;

  bool get _isLoading => _status == DetectionScreenStatus.loading;

  bool get _cameraSupported {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? FashionApiService();
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.close();
    }
    super.dispose();
  }

  Future<SelectedImageData?> _pickWithImagePicker(ImageSource source) async {
    final pickedFile = await _imagePicker.pickImage(source: source);
    if (pickedFile == null) {
      return null;
    }
    // Đọc đúng một lần, sau đó dùng lại bytes cho preview và request API.
    final bytes = await pickedFile.readAsBytes();
    return SelectedImageData(bytes: bytes, filename: pickedFile.name);
  }

  Future<void> _selectImage(ImageSource source) async {
    if (_isLoading) {
      return;
    }

    try {
      final selection = await (widget.imageSelectionCallback != null
          ? widget.imageSelectionCallback!(source)
          : _pickWithImagePicker(source));
      if (!mounted || selection == null) {
        return;
      }

      final mimeType = detectSupportedImageMimeType(
        selection.filename,
        selection.bytes,
      );
      if (selection.bytes.isEmpty || mimeType == null) {
        setState(() {
          _status = DetectionScreenStatus.error;
          _errorMessage = 'Chỉ chấp nhận ảnh JPEG, PNG hoặc WebP hợp lệ.';
        });
        return;
      }

      setState(() {
        _selectedImage = selection;
        _response = null;
        _errorMessage = null;
        _highlightedIndex = null;
        _showBoundingBoxes = true;
        _status = DetectionScreenStatus.imageSelected;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = DetectionScreenStatus.error;
        _errorMessage = 'Không thể mở ảnh. Vui lòng chọn một ảnh khác.';
      });
    }
  }

  Future<void> _startDetection() async {
    final selectedImage = _selectedImage;
    if (selectedImage == null || _isLoading) {
      return;
    }

    setState(() {
      _status = DetectionScreenStatus.loading;
      _response = null;
      _errorMessage = null;
      _highlightedIndex = null;
    });

    try {
      final result = await _service.detectClothing(
        imageBytes: selectedImage.bytes,
        filename: selectedImage.filename,
        confidence: _confidence,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _response = result;
        _status = result.hasDetections
            ? DetectionScreenStatus.success
            : DetectionScreenStatus.empty;
      });
    } on FashionApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = DetectionScreenStatus.error;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = DetectionScreenStatus.error;
        _errorMessage = 'Không thể xử lý ảnh. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedImage = _selectedImage;
    return Scaffold(
      appBar: AppBar(title: const Text('Nhận diện trang phục')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (selectedImage == null) _buildEmptyImageArea(context),
                      if (selectedImage != null) ...<Widget>[
                        DetectionImageView(
                          imageBytes: selectedImage.bytes,
                          response: _response,
                          showBoundingBoxes: _showBoundingBoxes,
                          highlightedIndex: _highlightedIndex,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selectedImage.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _buildImageActions(selectedImage != null),
                      if (!_cameraSupported) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Chụp ảnh khả dụng trên Android và iOS. '
                          'Trên nền tảng này, hãy chọn ảnh có sẵn.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (selectedImage != null) ...<Widget>[
                        const SizedBox(height: 20),
                        _buildConfidenceControl(context),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('detect_button'),
                          onPressed: _isLoading ? null : _startDetection,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Bắt đầu nhận diện'),
                        ),
                      ],
                      if (_isLoading) ...<Widget>[
                        const SizedBox(height: 20),
                        const _LoadingPanel(),
                      ],
                      if (_status == DetectionScreenStatus.error) ...<Widget>[
                        const SizedBox(height: 20),
                        _ErrorPanel(
                          message: _errorMessage ?? 'Không thể xử lý yêu cầu.',
                          canRetry: selectedImage != null,
                          onRetry: _startDetection,
                        ),
                      ],
                      if (_status == DetectionScreenStatus.empty) ...<Widget>[
                        const SizedBox(height: 20),
                        _EmptyResultPanel(onRetry: _startDetection),
                      ],
                      if (_status == DetectionScreenStatus.success &&
                          _response != null) ...<Widget>[
                        const SizedBox(height: 20),
                        _buildResults(context, _response!),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyImageArea(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Chọn ảnh trang phục',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ảnh sẽ được xem trước trước khi gửi đến hệ thống nhận diện.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageActions(bool hasImage) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        OutlinedButton.icon(
          key: const Key('gallery_button'),
          onPressed: _isLoading
              ? null
              : () => _selectImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(hasImage ? 'Chọn ảnh khác' : 'Chọn ảnh từ thư viện'),
        ),
        if (_cameraSupported)
          OutlinedButton.icon(
            key: const Key('camera_button'),
            onPressed: _isLoading
                ? null
                : () => _selectImage(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Chụp ảnh'),
          ),
      ],
    );
  }

  Widget _buildConfidenceControl(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Ngưỡng tin cậy: ${_confidence.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Slider(
              key: const Key('confidence_slider'),
              min: 0.10,
              max: 0.90,
              divisions: 16,
              label: _confidence.toStringAsFixed(2),
              value: _confidence,
              onChanged: _isLoading
                  ? null
                  : (value) => setState(() => _confidence = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, DetectionResponse result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Kết quả nhận diện',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text('Tổng: ${result.detectionCount}'),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hiển thị bounding box'),
          value: _showBoundingBoxes,
          onChanged: (value) => setState(() => _showBoundingBoxes = value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: result.summary
              .map(
                (item) =>
                    Chip(label: Text('${item.classNameVi}: ${item.count}')),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 8),
        ...List<Widget>.generate(result.detections.length, (index) {
          final detection = result.detections[index];
          return DetectionResultCard(
            detection: detection,
            index: index,
            isHighlighted: _highlightedIndex == index,
            onTap: () {
              setState(() {
                _highlightedIndex = _highlightedIndex == index ? null : index;
              });
            },
          );
        }),
      ],
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Card(
      key: Key('loading_panel'),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 14),
            Flexible(child: Text('Đang phân tích ảnh...')),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('error_panel'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (canRetry) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyResultPanel extends StatelessWidget {
  const _EmptyResultPanel({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('empty_result_panel'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.search_off,
              size: 42,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 10),
            Text(
              'Không phát hiện được quần áo',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
