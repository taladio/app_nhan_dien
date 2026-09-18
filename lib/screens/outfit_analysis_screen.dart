import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/outfit_analysis_result.dart';
import '../services/analysis_preferences.dart';
import '../services/outfit_analysis_service.dart';
import '../widgets/detection_image_view.dart';
import '../widgets/outfit_score_card.dart';
import '../widgets/outfit_suggestion_card.dart';
import 'realtime_detection_screen.dart';
import 'virtual_try_on_screen.dart';

typedef AnalysisImageSelector = Future<PreparedAnalysisImage?> Function(
  ImageSource source,
);

const Map<String, String> _seasons = <String, String>{
  'spring': 'Xuân',
  'summer': 'Hè',
  'autumn': 'Thu',
  'winter': 'Đông',
  'rainy': 'Mùa mưa',
};

const Map<String, String> _styles = <String, String>{
  'casual': 'Hằng ngày',
  'sporty': 'Năng động',
  'elegant': 'Thanh lịch',
  'office': 'Công sở',
  'streetwear': 'Đường phố',
  'minimal': 'Tối giản',
  'party': 'Dự tiệc',
};

const Map<String, String> _occasions = <String, String>{
  'school': 'Đi học',
  'work': 'Đi làm',
  'outing': 'Đi chơi',
  'date': 'Hẹn hò',
  'party': 'Dự tiệc',
  'sport': 'Thể thao',
  'travel': 'Du lịch',
};

class OutfitAnalysisScreen extends StatefulWidget {
  const OutfitAnalysisScreen({
    super.key,
    this.service,
    this.preferencesStore,
    this.imageSelectionCallback,
    this.onSignOut,
  });

  final OutfitAnalysisServiceContract? service;
  final AnalysisPreferencesStore? preferencesStore;
  final AnalysisImageSelector? imageSelectionCallback;
  final Future<void> Function()? onSignOut;

  @override
  State<OutfitAnalysisScreen> createState() => _OutfitAnalysisScreenState();
}

class _OutfitAnalysisScreenState extends State<OutfitAnalysisScreen> {
  final _formKey = GlobalKey<FormState>();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _temperatureController = TextEditingController(text: '28');
  final _picker = ImagePicker();

  late final OutfitAnalysisServiceContract _service;
  late final AnalysisPreferencesStore _preferencesStore;
  late final bool _ownsService;

  PreparedAnalysisImage? _selectedImage;
  OutfitAnalysisResult? _result;
  String? _errorMessage;
  String _season = 'summer';
  String _style = 'casual';
  String _occasion = 'outing';
  double _confidence = 0.25;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? OutfitAnalysisService();
    _preferencesStore =
        widget.preferencesStore ?? SharedPreferencesAnalysisStore();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final data = await _preferencesStore.load();
      if (!mounted) return;
      setState(() {
        _heightController.text = data.heightCm;
        _weightController.text = data.weightKg;
        _temperatureController.text = data.temperatureC;
        if (_seasons.containsKey(data.season)) _season = data.season;
        if (_styles.containsKey(data.style)) _style = data.style;
        if (_occasions.containsKey(data.occasion)) {
          _occasion = data.occasion;
        }
      });
    } catch (_) {
      // Lỗi lưu cục bộ không được chặn tính năng phân tích.
    }
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _temperatureController.dispose();
    if (_ownsService) _service.close();
    super.dispose();
  }

  Future<void> _selectImage(ImageSource source) async {
    if (_isLoading) return;
    try {
      PreparedAnalysisImage? prepared;
      if (widget.imageSelectionCallback != null) {
        prepared = await widget.imageSelectionCallback!(source);
      } else {
        final picked = await _picker.pickImage(
          source: source,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 88,
        );
        if (picked == null) return;
        prepared = prepareAnalysisImage(
          bytes: await picked.readAsBytes(),
          filename: picked.name,
        );
      }
      if (!mounted || prepared == null) return;
      setState(() {
        _selectedImage = prepared;
        _result = null;
        _errorMessage = null;
      });
    } on OutfitAnalysisException catch (error) {
      _showError(error.message);
    } on PlatformException catch (error) {
      final denied =
          error.code.contains('denied') ||
          error.code.contains('access') ||
          error.code.contains('permission');
      _showError(
        denied
            ? 'Bạn chưa cấp quyền camera hoặc thư viện ảnh. Hãy bật quyền trong Cài đặt.'
            : 'Không thể mở camera hoặc thư viện ảnh trên thiết bị này.',
      );
    } catch (_) {
      _showError('Không thể đọc ảnh đã chọn. Vui lòng thử ảnh khác.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  double? _parseNumber(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  String? _positiveNumberValidator(String? value, String label, double max) {
    final number = _parseNumber(value ?? '');
    if (number == null) return 'Vui lòng nhập $label.';
    if (!number.isFinite || number <= 0 || number > max) {
      return '$label không hợp lệ.';
    }
    return null;
  }

  String? _temperatureValidator(String? value) {
    final number = _parseNumber(value ?? '');
    if (number == null || !number.isFinite || number < -100 || number > 100) {
      return 'Nhiệt độ không hợp lệ.';
    }
    return null;
  }

  Future<void> _analyze() async {
    if (_isLoading) return;
    final image = _selectedImage;
    if (image == null) {
      _showError('Vui lòng chụp hoặc chọn một ảnh trang phục.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final height = _parseNumber(_heightController.text)!;
    final weight = _parseNumber(_weightController.text)!;
    final temperature = _parseNumber(_temperatureController.text)!;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      await _preferencesStore.save(
        AnalysisPreferencesData(
          heightCm: _heightController.text.trim(),
          weightKg: _weightController.text.trim(),
          temperatureC: _temperatureController.text.trim(),
          season: _season,
          style: _style,
          occasion: _occasion,
        ),
      );
    } catch (_) {
      // Không lưu được preference vẫn tiếp tục request.
    }

    try {
      final result = await _service.analyze(
        image: image,
        heightCm: height,
        weightKg: weight,
        season: _season,
        temperatureC: temperature,
        style: _style,
        occasion: _occasion,
        confidence: _confidence,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on OutfitAnalysisException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Đã xảy ra lỗi khi phân tích. Vui lòng thử lại.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _analyzeAgain() {
    if (_isLoading) return;
    setState(() {
      _result = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _selectedImage;
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phân tích trang phục AI'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Nhận diện realtime',
            onPressed: _isLoading
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RealtimeDetectionScreen(),
                    ),
                  ),
            icon: const Icon(Icons.videocam_outlined),
          ),
          if (widget.onSignOut != null)
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: _isLoading ? null : widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (image == null)
                      const _ImagePlaceholder()
                    else
                      DetectionImageView(
                        imageBytes: image.bytes,
                        response: result?.asDetectionResponse(),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          key: const Key('virtual_try_on_button'),
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const VirtualTryOnScreen(),
                                  ),
                                ),
                          icon: const Icon(Icons.checkroom),
                          label: const Text('Thử đồ ảo'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('camera_button'),
                          onPressed: _isLoading
                              ? null
                              : () => _selectImage(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Chụp ảnh'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('gallery_button'),
                          onPressed: _isLoading
                              ? null
                              : () => _selectImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Chọn từ thư viện'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildProfileCard(context),
                    const SizedBox(height: 12),
                    _buildContextCard(context),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Ngưỡng nhận diện: ${_confidence.toStringAsFixed(2)}',
                            ),
                            Slider(
                              value: _confidence,
                              min: 0.1,
                              max: 0.9,
                              divisions: 16,
                              onChanged: _isLoading
                                  ? null
                                  : (value) =>
                                        setState(() => _confidence = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('analyze_button'),
                      onPressed: _isLoading ? null : _analyze,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 13),
                        child: Text('Phân tích trang phục'),
                      ),
                    ),
                    if (_isLoading) ...<Widget>[
                      const SizedBox(height: 16),
                      const _LoadingPanel(),
                    ],
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 16),
                      _ErrorPanel(message: _errorMessage!),
                    ],
                    if (result != null) ...<Widget>[
                      const SizedBox(height: 20),
                      _buildResult(context, result),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Thông tin chung',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: const Key('height_field'),
                    controller: _heightController,
                    enabled: !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Chiều cao (cm)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _positiveNumberValidator(value, 'chiều cao', 300),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('weight_field'),
                    controller: _weightController,
                    enabled: !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cân nặng (kg)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _positiveNumberValidator(value, 'cân nặng', 500),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Bối cảnh mong muốn',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _dropdown(
              key: const Key('season_dropdown'),
              label: 'Mùa',
              value: _season,
              options: _seasons,
              onChanged: (value) => setState(() => _season = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('temperature_field'),
              controller: _temperatureController,
              enabled: !_isLoading,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Nhiệt độ (°C)',
                border: OutlineInputBorder(),
              ),
              validator: _temperatureValidator,
            ),
            const SizedBox(height: 12),
            _dropdown(
              key: const Key('style_dropdown'),
              label: 'Phong cách',
              value: _style,
              options: _styles,
              onChanged: (value) => setState(() => _style = value),
            ),
            const SizedBox(height: 12),
            _dropdown(
              key: const Key('occasion_dropdown'),
              label: 'Hoàn cảnh',
              value: _occasion,
              options: _occasions,
              onChanged: (value) => setState(() => _occasion = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required Key key,
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(growable: false),
      onChanged: _isLoading
          ? null
          : (newValue) {
              if (newValue != null) onChanged(newValue);
            },
    );
  }

  Widget _buildResult(BuildContext context, OutfitAnalysisResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Kết quả đánh giá',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Chip(
              avatar: Icon(
                result.source == OutfitAnalysisSource.openai
                    ? Icons.auto_awesome
                    : Icons.rule,
                size: 18,
              ),
              label: Text(result.source.displayName),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...result.detectedItems.map(
          (item) => Card(
            child: ListTile(
              title: Text('${item.classNameVi} · ${item.primaryColor}'),
              subtitle: Text(
                <String>[
                  if (item.secondaryColors.isNotEmpty)
                    'Màu phụ: ${item.secondaryColors.join(', ')}',
                  'Độ tin cậy: ${(item.confidence * 100).toStringAsFixed(1)}%',
                ].join('\n'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutfitScoreCard(evaluation: result.evaluation),
        OutfitSuggestionCard(evaluation: result.evaluation),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('analyze_again_button'),
          onPressed: _analyzeAgain,
          icon: const Icon(Icons.refresh),
          label: const Text('Phân tích lại'),
        ),
      ],
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('image_placeholder'),
      height: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.add_a_photo_outlined, size: 52),
          SizedBox(height: 12),
          Text('Chụp hoặc chọn ảnh trang phục toàn thân'),
        ],
      ),
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
        padding: EdgeInsets.all(18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 12),
            Flexible(child: Text('Đang nhận diện và đánh giá trang phục...')),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('error_panel'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
