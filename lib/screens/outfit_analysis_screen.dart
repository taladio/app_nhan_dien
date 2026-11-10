import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/outfit_analysis_result.dart';
import '../models/outfit_context_options.dart';
import '../models/outfit_flow_context.dart';
import '../models/weather_snapshot.dart';
import '../models/body_profile.dart';
import '../services/analysis_preferences.dart';
import '../services/body_profile_store.dart';
import '../services/outfit_analysis_service.dart';
import '../services/weather_service.dart';
import '../widgets/detection_image_view.dart';
import '../widgets/outfit_score_card.dart';
import '../widgets/outfit_suggestion_card.dart';
import 'realtime_detection_screen.dart';
import 'virtual_try_on_screen.dart';
import 'personal_info_screen.dart';
import 'outfit_suggestion_screen.dart';

typedef AnalysisImageSelector = Future<PreparedAnalysisImage?> Function(
  ImageSource source,
);

class OutfitAnalysisScreen extends StatefulWidget {
  const OutfitAnalysisScreen({
    super.key,
    this.service,
    this.preferencesStore,
    this.imageSelectionCallback,
    this.onSignOut,
    this.profileStore,
    this.accountName,
    this.accountEmail,
    this.onChangePassword,
    this.weatherService,
    this.locationService,
    this.onAnalysisCompleted,
    this.onSuggestionRequested,
    this.onPersonalRequested,
    this.profileRevision = 0,
  });

  final OutfitAnalysisServiceContract? service;
  final AnalysisPreferencesStore? preferencesStore;
  final AnalysisImageSelector? imageSelectionCallback;
  final Future<void> Function()? onSignOut;
  final BodyProfileStore? profileStore;
  final String? accountName;
  final String? accountEmail;
  final Future<void> Function(String, String)? onChangePassword;
  final WeatherService? weatherService;
  final CurrentLocationService? locationService;
  final ValueChanged<OutfitFlowContext>? onAnalysisCompleted;
  final ValueChanged<OutfitFlowContext>? onSuggestionRequested;
  final VoidCallback? onPersonalRequested;
  final int profileRevision;

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
  late final WeatherService _weatherService;
  late final CurrentLocationService _locationService;
  late final bool _ownsWeatherService;

  PreparedAnalysisImage? _selectedImage;
  OutfitAnalysisResult? _result;
  String? _errorMessage;
  String _season = 'summer';
  String _style = 'casual';
  String _occasion = 'outing';
  double _confidence = 0.25;
  bool _isLoading = false;
  int _analysisRequestId = 0;
  int _profileLoadId = 0;
  bool _profilesLoading = false;
  BodyProfileCollection _profiles = const BodyProfileCollection();
  WeatherSnapshot? _weather;
  DateTime? _weatherFetchedAt;
  SuggestionMode _contextMode = SuggestionMode.manual;
  bool _weatherLoading = false;
  String? _weatherError;
  String? _weatherPlace;
  String? _selectedCityId;
  int _weatherRequestId = 0;
  Future<void> _preferenceWrites = Future.value();

  WeatherSnapshot? get _freshWeather {
    if (_contextMode != SuggestionMode.currentWeather) return null;
    final fetchedAt = _weatherFetchedAt;
    if (fetchedAt == null ||
        DateTime.now().difference(fetchedAt) > const Duration(minutes: 30)) {
      return null;
    }
    return _weather;
  }

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? OutfitAnalysisService();
    _ownsWeatherService = widget.weatherService == null;
    _weatherService = widget.weatherService ?? BackendWeatherService();
    _locationService = widget.locationService ?? DeviceLocationService();
    _preferencesStore =
        widget.preferencesStore ?? SharedPreferencesAnalysisStore();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant OutfitAnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileRevision != widget.profileRevision) {
      _result = null;
      _loadProfiles();
    }
  }

  OutfitFlowContext _flowContext(OutfitAnalysisResult? result) =>
      OutfitFlowContext(
        analysisResult: result,
        season: _season,
        temperature: _temperatureController.text,
        style: _style,
        occasion: _occasion,
        useCurrentWeather: _contextMode == SuggestionMode.currentWeather,
        weather: _freshWeather,
        heightCm: _parseNumber(_heightController.text),
        weightKg: _parseNumber(_weightController.text),
        gender: _profiles.selected?.gender ?? BodyGender.unspecified,
      );

  Future<void> _initialize() async {
    await _loadPreferences();
    await _loadProfiles();
    if (mounted && _contextMode == SuggestionMode.currentWeather) {
      unawaited(_refreshWeather());
    }
  }

  Future<void> _loadProfiles() async {
    final store = widget.profileStore;
    if (store == null) return;
    final loadId = ++_profileLoadId;
    _analysisRequestId++;
    if (mounted) {
      setState(() {
        _profilesLoading = true;
        _isLoading = false;
        _result = null;
      });
    }
    try {
      final collection = await store.load();
      if (!mounted || loadId != _profileLoadId) return;
      setState(() {
        _profiles = collection;
        final selected = collection.selected;
        _heightController.text = selected?.heightCm.toString() ?? '';
        _weightController.text = selected?.weightKg.toString() ?? '';
      });
      widget.onAnalysisCompleted?.call(_flowContext(null));
    } catch (_) {
      if (!mounted || loadId != _profileLoadId) return;
      _showError(
        'Không thể tải hồ sơ cơ thể từ Firebase. Kiểm tra Internet và quyền Firestore.',
      );
    } finally {
      if (mounted && loadId == _profileLoadId) {
        setState(() => _profilesLoading = false);
      }
    }
  }

  Future<void> _selectProfile(String id) async {
    final updated = _profiles.select(id);
    try {
      await widget.profileStore!.save(updated);
      if (!mounted) return;
      setState(() {
        _profiles = updated;
        _heightController.text = updated.selected!.heightCm.toString();
        _weightController.text = updated.selected!.weightKg.toString();
        _result = null;
        _analysisRequestId++;
        _isLoading = false;
      });
      widget.onAnalysisCompleted?.call(_flowContext(null));
    } catch (_) {
      _showError('Không thể lưu hồ sơ đang chọn.');
    }
  }

  Future<void> _openPersonalInfo() async {
    if (widget.onPersonalRequested != null) {
      widget.onPersonalRequested!();
      return;
    }
    if (widget.profileStore == null || widget.onChangePassword == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PersonalInfoScreen(
          accountName: widget.accountName ?? 'Người dùng',
          email: widget.accountEmail ?? '',
          profileStore: widget.profileStore!,
          onChangePassword: widget.onChangePassword!,
        ),
      ),
    );
    if (mounted) await _loadProfiles();
  }

  Future<void> _openRealtime() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            RealtimeDetectionScreen(profileStore: widget.profileStore),
      ),
    );
    if (mounted) await _loadProfiles();
  }

  Future<void> _openTryOn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VirtualTryOnScreen(profileStore: widget.profileStore),
      ),
    );
    if (mounted) await _loadProfiles();
  }

  Future<void> _openSuggestions() async {
    final store = widget.profileStore;
    if (store == null) return;
    final flow = _flowContext(_result);
    if (widget.onSuggestionRequested != null) {
      widget.onSuggestionRequested!(flow);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OutfitSuggestionScreen(
          profileStore: store,
          initialSeason: _season,
          initialTemperatureC: _temperatureController.text,
          initialStyle: _style,
          initialOccasion: _occasion,
          initialMode: _contextMode,
          initialWeather: _freshWeather,
          initialHeightCm: flow.heightCm,
          initialWeightKg: flow.weightKg,
          initialGender: flow.gender,
          onWeatherChanged: (weather) {
            if (!mounted) return;
            setState(() {
              _weather = weather;
              _weatherFetchedAt = weather == null ? null : DateTime.now();
              if (weather != null) _contextMode = SuggestionMode.currentWeather;
            });
            widget.onAnalysisCompleted?.call(_flowContext(null));
          },
        ),
      ),
    );
    if (mounted) await _loadProfiles();
  }

  Future<void> _loadPreferences() async {
    try {
      final data = await _preferencesStore.load();
      if (!mounted) return;
      setState(() {
        _heightController.text = data.heightCm;
        _weightController.text = data.weightKg;
        _temperatureController.text = data.temperatureC;
        _contextMode = data.useCurrentWeather
            ? SuggestionMode.currentWeather
            : SuggestionMode.manual;
        if (seasonLabels.containsKey(data.season)) _season = data.season;
        if (styleLabels.containsKey(data.style)) _style = data.style;
        if (occasionLabels.containsKey(data.occasion)) {
          _occasion = data.occasion;
        }
      });
      widget.onAnalysisCompleted?.call(_flowContext(null));
    } catch (_) {
      // Lỗi lưu cục bộ không được chặn tính năng phân tích.
    }
  }

  @override
  void dispose() {
    _weatherRequestId++;
    _heightController.dispose();
    _weightController.dispose();
    _temperatureController.dispose();
    if (_ownsService) _service.close();
    if (_ownsWeatherService && _weatherService is BackendWeatherService) {
      _weatherService.close();
    }
    super.dispose();
  }

  void _changeContextMode(SuggestionMode mode) {
    if (_contextMode == mode || _isLoading) return;
    setState(() {
      _contextMode = mode;
      _weatherError = null;
      _result = null;
      if (mode == SuggestionMode.manual) {
        _weatherRequestId++;
        _weatherLoading = false;
        _weather = null;
        _weatherFetchedAt = null;
        _weatherPlace = null;
      }
    });
    widget.onAnalysisCompleted?.call(_flowContext(null));
    unawaited(_savePreferences());
    if (mode == SuggestionMode.currentWeather) _refreshWeather();
  }

  void _updateContext(VoidCallback update) {
    setState(() {
      update();
      _result = null;
      _errorMessage = null;
    });
    widget.onAnalysisCompleted?.call(_flowContext(null));
    unawaited(_savePreferences());
  }

  Future<void> _savePreferences() {
    final data = AnalysisPreferencesData(
      heightCm: widget.profileStore == null
          ? _heightController.text.trim()
          : '',
      weightKg: widget.profileStore == null
          ? _weightController.text.trim()
          : '',
      temperatureC: _temperatureController.text.trim(),
      season: _season,
      style: _style,
      occasion: _occasion,
      useCurrentWeather: _contextMode == SuggestionMode.currentWeather,
    );
    _preferenceWrites = _preferenceWrites
        .then((_) => _preferencesStore.save(data))
        .catchError((Object _) {});
    return _preferenceWrites;
  }

  Future<void> _refreshWeather() =>
      _loadWeather(_locationService.current, 'Vị trí hiện tại');

  Future<void> _loadSelectedCityWeather() async {
    WeatherCity? selected;
    for (final city in weatherCities) {
      if (city.id == _selectedCityId) selected = city;
    }
    if (selected == null) {
      setState(() => _weatherError = 'Hãy chọn một thành phố.');
      return;
    }
    final city = selected;
    await _loadWeather(() async => city.location, city.name);
  }

  Future<void> _loadWeather(
    Future<CurrentLocation> Function() getLocation,
    String place,
  ) async {
    if (_weatherLoading || _contextMode != SuggestionMode.currentWeather) {
      return;
    }
    final requestId = ++_weatherRequestId;
    setState(() {
      _weatherLoading = true;
      _weatherError = null;
      _weather = null;
      _weatherFetchedAt = null;
      _result = null;
    });
    widget.onAnalysisCompleted?.call(_flowContext(null));
    try {
      final location = await getLocation();
      if (!mounted || requestId != _weatherRequestId) return;
      final weather = await _weatherService.currentAt(location);
      if (!mounted || requestId != _weatherRequestId) return;
      setState(() {
        _weather = weather;
        _weatherFetchedAt = DateTime.now();
        _weatherPlace = place;
      });
      widget.onAnalysisCompleted?.call(_flowContext(null));
    } on WeatherException catch (error) {
      if (mounted && requestId == _weatherRequestId) {
        setState(() => _weatherError = error.message);
      }
    } catch (_) {
      if (mounted && requestId == _weatherRequestId) {
        setState(
          () => _weatherError =
              'Không lấy được thời tiết. Hãy thử lại hoặc chọn thành phố.',
        );
      }
    } finally {
      if (mounted && requestId == _weatherRequestId) {
        setState(() => _weatherLoading = false);
      }
    }
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
        prepared = await prepareAnalysisImageInBackground(
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
      widget.onAnalysisCompleted?.call(_flowContext(null));
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
    if ((value ?? '').trim().isEmpty) return null;
    final number = _parseNumber(value ?? '');
    if (number == null) return 'Vui lòng nhập $label.';
    if (!number.isFinite || number <= 0 || number > max) {
      return '$label không hợp lệ.';
    }
    return null;
  }

  String? _temperatureValidator(String? value) {
    if (_contextMode == SuggestionMode.currentWeather) return null;
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

    final height = _parseNumber(_heightController.text);
    final weight = _parseNumber(_weightController.text);
    final gender = _profiles.selected?.gender ?? BodyGender.unspecified;
    final requestId = ++_analysisRequestId;
    final weather = _freshWeather;
    final temperature = _contextMode == SuggestionMode.currentWeather
        ? weather?.temperatureC
        : _parseNumber(_temperatureController.text);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    await _savePreferences();

    if (!mounted || requestId != _analysisRequestId) return;
    try {
      final result = await _service.analyze(
        image: image,
        heightCm: height,
        weightKg: weight,
        gender: gender,
        season: _contextMode == SuggestionMode.manual ? _season : null,
        temperatureC: temperature,
        style: _style,
        occasion: _occasion,
        confidence: _confidence,
        weather: weather,
      );
      if (!mounted || requestId != _analysisRequestId) return;
      setState(() => _result = result);
      widget.onAnalysisCompleted?.call(_flowContext(result));
    } on OutfitAnalysisException catch (error) {
      if (!mounted || requestId != _analysisRequestId) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted || requestId != _analysisRequestId) return;
      setState(() {
        _errorMessage = 'Đã xảy ra lỗi khi phân tích. Vui lòng thử lại.';
      });
    } finally {
      if (mounted && requestId == _analysisRequestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _analyzeAgain() {
    if (_isLoading) return;
    setState(() {
      _result = null;
      _errorMessage = null;
    });
    widget.onAnalysisCompleted?.call(_flowContext(null));
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
            onPressed: _isLoading ? null : _openRealtime,
            icon: const Icon(Icons.videocam_outlined),
          ),
          if (widget.profileStore != null && widget.onChangePassword != null)
            IconButton(
              tooltip: 'Thông tin cá nhân',
              onPressed: _isLoading ? null : _openPersonalInfo,
              icon: const Icon(Icons.account_circle_outlined),
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
                        if (widget.profileStore != null)
                          FilledButton.tonalIcon(
                            key: const Key('outfit_suggestion_button'),
                            onPressed: _isLoading ? null : _openSuggestions,
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: const Text('Gợi ý phối đồ'),
                          ),
                        FilledButton.tonalIcon(
                          key: const Key('virtual_try_on_button'),
                          onPressed: _isLoading ? null : _openTryOn,
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
                      onPressed: _isLoading || _profilesLoading
                          ? null
                          : _analyze,
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
    if (widget.profileStore != null) {
      final selected = _profiles.selected;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Hồ sơ cơ thể',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_profilesLoading)
                const LinearProgressIndicator()
              else if (selected == null)
                const Text('Chưa có hồ sơ chiều cao/cân nặng.')
              else ...<Widget>[
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('profile_dropdown_${selected.id}'),
                  initialValue: selected.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Chọn hồ sơ cho ảnh này',
                    border: OutlineInputBorder(),
                  ),
                  items: _profiles.profiles
                      .map(
                        (profile) => DropdownMenuItem<String>(
                          value: profile.id,
                          child: Text(
                            profile.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isLoading
                      ? null
                      : (id) {
                          if (id != null) _selectProfile(id);
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  '${selected.heightCm.toStringAsFixed(1)} cm · ${selected.weightKg.toStringAsFixed(1)} kg · ${selected.gender.label}',
                ),
              ],
              if (widget.onChangePassword != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _openPersonalInfo,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(
                      selected == null ? 'Tạo hồ sơ' : 'Quản lý hồ sơ',
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
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
            SegmentedButton<SuggestionMode>(
              key: const Key('analysis_weather_mode_switch'),
              segments: const <ButtonSegment<SuggestionMode>>[
                ButtonSegment(
                  value: SuggestionMode.manual,
                  icon: Icon(Icons.tune),
                  label: Text('Thủ công'),
                ),
                ButtonSegment(
                  value: SuggestionMode.currentWeather,
                  icon: Icon(Icons.cloud_outlined),
                  label: Text('Thời tiết hiện tại'),
                ),
              ],
              selected: <SuggestionMode>{_contextMode},
              onSelectionChanged: _isLoading
                  ? null
                  : (selection) => _changeContextMode(selection.first),
            ),
            const SizedBox(height: 12),
            if (_contextMode == SuggestionMode.manual) ...<Widget>[
              _dropdown(
                key: const Key('season_dropdown'),
                label: 'Mùa (bạn chọn)',
                value: _season,
                options: seasonLabels,
                onChanged: (value) => _updateContext(() => _season = value),
              ),
              const SizedBox(height: 12),
            ],
            if (_contextMode == SuggestionMode.manual)
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
                onChanged: (_) => _updateContext(() {}),
              )
            else
              _buildCurrentWeatherControls(context),
            const SizedBox(height: 12),
            _dropdown(
              key: const Key('style_dropdown'),
              label: 'Phong cách',
              value: _style,
              options: styleLabels,
              onChanged: (value) => _updateContext(() => _style = value),
            ),
            const SizedBox(height: 12),
            _dropdown(
              key: const Key('occasion_dropdown'),
              label: 'Hoàn cảnh',
              value: _occasion,
              options: occasionLabels,
              onChanged: (value) => _updateContext(() => _occasion = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentWeatherControls(BuildContext context) {
    final weather = _freshWeather;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_weatherLoading) const LinearProgressIndicator(),
        if (weather != null) ...<Widget>[
          Text(
            '${weather.temperatureC.toStringAsFixed(1)}°C · Cảm nhận ${weather.apparentTemperatureC.toStringAsFixed(1)}°C',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Nguồn: ${_weatherPlace ?? 'Vị trí hiện tại'} · Open-Meteo'),
          Text(
            'Xác suất mưa cao nhất hôm nay: ${weather.precipitationProbabilityMaxPercentToday}%',
          ),
        ] else if (!_weatherLoading) ...<Widget>[
          Text(
            _weatherError ??
                'Chưa có thời tiết. Có thể làm mới hoặc chọn thành phố.',
          ),
          const Text(
            'Vẫn có thể phân tích trang phục; AI sẽ không đánh giá thời tiết khi chưa có dữ liệu.',
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('analysis_refresh_weather_button'),
          onPressed: _weatherLoading || _isLoading ? null : _refreshWeather,
          icon: const Icon(Icons.refresh),
          label: const Text('Lấy thời tiết vị trí hiện tại'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('analysis_city_dropdown'),
          initialValue: _selectedCityId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Không dùng GPS? Chọn thành phố',
            border: OutlineInputBorder(),
          ),
          items: weatherCities
              .map(
                (city) => DropdownMenuItem<String>(
                  value: city.id,
                  child: Text(city.name),
                ),
              )
              .toList(),
          onChanged: _weatherLoading || _isLoading
              ? null
              : (value) => setState(() => _selectedCityId = value),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('analysis_load_city_weather_button'),
          onPressed: _weatherLoading || _isLoading || _selectedCityId == null
              ? null
              : _loadSelectedCityWeather,
          icon: const Icon(Icons.location_city_outlined),
          label: const Text('Dùng thời tiết thành phố'),
        ),
        const Text(
          'Dữ liệu thời tiết: Open-Meteo',
          style: TextStyle(fontSize: 12),
        ),
      ],
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
                result.source == OutfitAnalysisSource.gemini
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
        if (result.evaluation != null) ...<Widget>[
          OutfitScoreCard(evaluation: result.evaluation!),
          OutfitSuggestionCard(evaluation: result.evaluation!),
        ] else
          _ErrorPanel(
            message: result.aiError ?? 'Gemini chưa trả được đánh giá. Bạn vẫn có thể xem kết quả YOLO và thử lại.',
          ),
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
