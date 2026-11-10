import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/body_profile.dart';
import '../models/gemini_fashion.dart';
import '../models/outfit_context_options.dart';
import '../models/weather_snapshot.dart';
import '../services/body_profile_store.dart';
import '../services/gemini_fashion_service.dart';
import '../services/weather_service.dart';
import 'outfit_chat_screen.dart';

enum SuggestionMode { manual, currentWeather }

class OutfitSuggestionScreen extends StatefulWidget {
  const OutfitSuggestionScreen({
    super.key,
    required this.profileStore,
    required this.initialSeason,
    required this.initialTemperatureC,
    this.initialStyle = 'casual',
    this.initialOccasion = 'outing',
    this.initialMode = SuggestionMode.manual,
    this.initialWeather,
    this.onWeatherChanged,
    this.weatherService,
    this.locationService,
    this.geminiService,
    this.initialHeightCm,
    this.initialWeightKg,
    this.initialGender = BodyGender.unspecified,
    this.onAdviceReady,
    this.onContextChanged,
    this.onOpenChat,
    this.profileRevision = 0,
  });

  final BodyProfileStore profileStore;
  final String initialSeason;
  final String initialTemperatureC;
  final String initialStyle;
  final String initialOccasion;
  final SuggestionMode initialMode;
  final WeatherSnapshot? initialWeather;
  final ValueChanged<WeatherSnapshot?>? onWeatherChanged;
  final WeatherService? weatherService;
  final CurrentLocationService? locationService;
  final GeminiFashionServiceContract? geminiService;
  final double? initialHeightCm;
  final double? initialWeightKg;
  final BodyGender initialGender;
  final void Function(GeminiOutfitContext, GeminiSuggestion)? onAdviceReady;
  final ValueChanged<GeminiOutfitContext>? onContextChanged;
  final VoidCallback? onOpenChat;
  final int profileRevision;

  @override
  State<OutfitSuggestionScreen> createState() => _OutfitSuggestionScreenState();
}

class _OutfitSuggestionScreenState extends State<OutfitSuggestionScreen> {
  final _manualFormKey = GlobalKey<FormState>();
  late final TextEditingController _temperatureController;
  late final WeatherService _weatherService;
  late final CurrentLocationService _locationService;
  late final bool _ownsWeatherService;
  late final GeminiFashionServiceContract _geminiService;
  late final bool _ownsGeminiService;

  BodyProfileCollection _profiles = const BodyProfileCollection();
  SuggestionMode _mode = SuggestionMode.manual;
  late String _season;
  late String _style;
  late String _occasion;
  WeatherSnapshot? _weather;
  GeminiSuggestion? _aiSuggestion;
  GeminiOutfitContext? _aiContext;
  bool _loadingAdvice = false;
  int _adviceRequestId = 0;
  String? _adviceError;
  String? _error;
  bool _loadingProfiles = true;
  bool _profilesLoaded = false;
  int _profileLoadId = 0;
  bool _loadingWeather = false;
  int _weatherRequestId = 0;
  String? _selectedCityId;
  String? _placeLabel;

  @override
  void initState() {
    super.initState();
    _season = seasonLabels.containsKey(widget.initialSeason)
        ? widget.initialSeason
        : 'summer';
    _style = styleLabels.containsKey(widget.initialStyle)
        ? widget.initialStyle
        : 'casual';
    _occasion = occasionLabels.containsKey(widget.initialOccasion)
        ? widget.initialOccasion
        : 'outing';
    _mode = widget.initialMode;
    _weather = widget.initialWeather;
    _temperatureController = TextEditingController(
      text: widget.initialTemperatureC,
    );
    _ownsWeatherService = widget.weatherService == null;
    _weatherService = widget.weatherService ?? BackendWeatherService();
    _locationService = widget.locationService ?? DeviceLocationService();
    _ownsGeminiService = widget.geminiService == null;
    _geminiService = widget.geminiService ?? GeminiFashionService();
    _loadProfiles();
    if (_mode == SuggestionMode.currentWeather && _weather == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshWeather();
      });
    }
  }

  @override
  void didUpdateWidget(covariant OutfitSuggestionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileRevision != widget.profileRevision) {
      _adviceRequestId++;
      _loadingAdvice = false;
      _loadProfiles();
      _aiSuggestion = null;
      _aiContext = null;
    }
  }

  Future<void> _loadProfiles() async {
    final loadId = ++_profileLoadId;
    setState(() => _loadingProfiles = true);
    try {
      final profiles = await widget.profileStore.load();
      if (mounted && loadId == _profileLoadId) {
        setState(() {
          _profiles = profiles;
          _profilesLoaded = true;
          if (_aiContext != null &&
              jsonEncode(_aiContext!.toJson()) !=
                  jsonEncode(_currentContext().toJson())) {
            _aiSuggestion = null;
            _aiContext = null;
            _adviceRequestId++;
            _loadingAdvice = false;
          }
        });
        _notifyContextChanged();
      }
    } catch (_) {
      if (mounted && loadId == _profileLoadId) {
        setState(() => _error = 'Không thể đọc hồ sơ cơ thể đã lưu.');
      }
    } finally {
      if (mounted && loadId == _profileLoadId) {
        setState(() => _loadingProfiles = false);
      }
    }
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    if (_ownsWeatherService && _weatherService is BackendWeatherService) {
      _weatherService.close();
    }
    if (_ownsGeminiService) _geminiService.close();
    super.dispose();
  }

  Future<void> _selectProfile(String id) async {
    final updated = _profiles.select(id);
    try {
      await widget.profileStore.save(updated);
      if (mounted) {
        setState(() {
          _profiles = updated;
          _aiSuggestion = null;
          _aiContext = null;
          _adviceRequestId++;
          _loadingAdvice = false;
        });
        _notifyContextChanged();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể lưu hồ sơ đã chọn.');
    }
  }

  void _changeMode(SuggestionMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _aiSuggestion = null;
      _aiContext = null;
      _adviceRequestId++;
      _loadingAdvice = false;
      _error = null;
      if (mode == SuggestionMode.manual) {
        _weatherRequestId++;
        _loadingWeather = false;
        _weather = null;
        _placeLabel = null;
      }
    });
    _notifyContextChanged();
    if (mode == SuggestionMode.manual) widget.onWeatherChanged?.call(null);
    if (mode == SuggestionMode.currentWeather && _weather == null) {
      _refreshWeather();
    }
  }

  GeminiOutfitContext _currentContext() {
    final weather = _mode == SuggestionMode.currentWeather ? _weather : null;
    final profile = _profiles.selected;
    return GeminiOutfitContext(
      // Tab Gợi ý không dùng ảnh hay kết quả YOLO từ tab Phân tích.
      items: const [],
      weather: weather,
      season: _mode == SuggestionMode.manual ? _season : null,
      style: _style,
      occasion: _occasion,
      temperatureC: _mode == SuggestionMode.currentWeather
          ? weather?.temperatureC
          : double.tryParse(
              _temperatureController.text.trim().replaceAll(',', '.'),
            ),
      heightCm: _profilesLoaded ? profile?.heightCm : widget.initialHeightCm,
      weightKg: _profilesLoaded ? profile?.weightKg : widget.initialWeightKg,
      gender: _profilesLoaded
          ? (profile?.gender ?? BodyGender.unspecified)
          : widget.initialGender,
    );
  }

  void _notifyContextChanged() =>
      widget.onContextChanged?.call(_currentContext());

  void _changePreference(VoidCallback update) {
    setState(() {
      update();
      _aiSuggestion = null;
      _aiContext = null;
      _adviceError = null;
      _adviceRequestId++;
      _loadingAdvice = false;
    });
    _notifyContextChanged();
  }

  Future<void> _refreshWeather() async {
    await _loadWeather(_locationService.current, 'Vị trí hiện tại');
  }

  Future<void> _loadSelectedCity() async {
    WeatherCity? city;
    for (final candidate in weatherCities) {
      if (candidate.id == _selectedCityId) city = candidate;
    }
    if (city == null) {
      setState(() => _error = 'Hãy chọn một thành phố.');
      return;
    }
    final selected = city;
    await _loadWeather(() async => selected.location, selected.name);
  }

  Future<void> _loadWeather(
    Future<CurrentLocation> Function() getLocation,
    String placeLabel,
  ) async {
    if (_loadingWeather) return;
    final requestId = ++_weatherRequestId;
    setState(() {
      _loadingWeather = true;
      _error = null;
      _aiSuggestion = null;
      _aiContext = null;
      _adviceRequestId++;
      _loadingAdvice = false;
      _weather = null;
    });
    widget.onWeatherChanged?.call(null);
    _notifyContextChanged();
    try {
      final location = await getLocation();
      if (!mounted || requestId != _weatherRequestId) return;
      final weather = await _weatherService.currentAt(location);
      if (mounted && requestId == _weatherRequestId) {
        setState(() {
          _weather = weather;
          _placeLabel = placeLabel;
        });
        widget.onWeatherChanged?.call(weather);
        _notifyContextChanged();
      }
    } on WeatherException catch (error) {
      if (mounted && requestId == _weatherRequestId) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && requestId == _weatherRequestId) {
        setState(
          () => _error = 'Không lấy được thời tiết hiện tại. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted && requestId == _weatherRequestId) {
        setState(() => _loadingWeather = false);
      }
    }
  }

  Future<void> _generateSuggestion() async {
    if (_mode == SuggestionMode.manual) {
      if (!(_manualFormKey.currentState?.validate() ?? false)) return;
    }
    final adviceRequestId = ++_adviceRequestId;
    final contextData = _currentContext();
    if (_aiSuggestion != null &&
        _aiContext != null &&
        jsonEncode(_aiContext!.toJson()) == jsonEncode(contextData.toJson())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gợi ý này đã có. Đổi bối cảnh nếu muốn gợi ý mới.'),
        ),
      );
      return;
    }
    setState(() {
      _error = null;
      _loadingAdvice = true;
      _adviceError = null;
      _aiSuggestion = null;
      _aiContext = contextData;
    });
    try {
      final advice = await _geminiService.suggest(contextData);
      if (mounted && adviceRequestId == _adviceRequestId) {
        setState(() => _aiSuggestion = advice);
        widget.onAdviceReady?.call(contextData, advice);
      }
    } on GeminiFashionException catch (error) {
      if (mounted && adviceRequestId == _adviceRequestId) {
        setState(() => _adviceError = error.message);
      }
    } catch (_) {
      if (mounted && adviceRequestId == _adviceRequestId) {
        setState(() => _adviceError = 'Không lấy được gợi ý AI. Hãy thử lại.');
      }
    } finally {
      if (mounted && adviceRequestId == _adviceRequestId) {
        setState(() => _loadingAdvice = false);
      }
    }
  }

  Future<void> _openChat() async {
    final contextData = _aiContext;
    if (contextData == null) return;
    if (widget.onOpenChat != null) {
      widget.onOpenChat!();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            OutfitChatScreen(contextData: contextData, service: _geminiService),
      ),
    );
  }

  String? _validateTemperature(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite || parsed < -100 || parsed > 100) {
      return 'Nhập nhiệt độ hợp lệ từ -100 đến 100°C.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Gợi ý phối đồ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.auto_awesome_outlined,
                      color: scheme.onPrimaryContainer,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Một bộ đồ hợp với hôm nay',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Gemini tạo một bộ đồ mới từ hồ sơ, thời tiết, phong cách và hoàn cảnh; không sử dụng ảnh đã chụp.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nguồn bối cảnh',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<SuggestionMode>(
              key: const Key('suggestion_mode_switch'),
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
              selected: <SuggestionMode>{_mode},
              onSelectionChanged: (selection) => _changeMode(selection.first),
            ),
            const SizedBox(height: 16),
            _buildProfileCard(context),
            const SizedBox(height: 12),
            if (_mode == SuggestionMode.manual)
              _buildManualCard(context)
            else
              _buildWeatherCard(context),
            const SizedBox(height: 12),
            _buildStyleAndOccasionCard(context),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('generate_suggestion_button'),
              onPressed: _loadingProfiles || _loadingWeather || _loadingAdvice
                  ? null
                  : _generateSuggestion,
              icon: const Icon(Icons.checkroom_outlined),
              label: Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('Gợi ý phối đồ bằng AI'),
              ),
            ),
            if (_loadingAdvice) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const Text('Gemini đang tạo gợi ý phối đồ...'),
            ],
            if (_mode == SuggestionMode.currentWeather && _weather == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Chưa có dữ liệu thời tiết; vẫn có thể nhận tư vấn từ hồ sơ và bối cảnh đã nhập.',
                ),
              ),
            if (_adviceError != null) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_adviceError!),
                      TextButton.icon(
                        key: const Key('retry_ai_suggestion_button'),
                        onPressed: _generateSuggestion,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ),
            ],
            if (_aiSuggestion != null) ...<Widget>[
              const SizedBox(height: 16),
              _buildAiResult(context, _aiSuggestion!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
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
            const SizedBox(height: 10),
            if (_loadingProfiles)
              const LinearProgressIndicator()
            else if (selected == null)
              const Text(
                'Chưa có hồ sơ. Hãy thêm trong trang Thông tin cá nhân.',
              )
            else ...<Widget>[
              DropdownButtonFormField<String>(
                key: ValueKey<String>('suggestion_profile_${selected.id}'),
                initialValue: selected.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Chọn hồ sơ',
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
                onChanged: (id) {
                  if (id != null) _selectProfile(id);
                },
              ),
              const SizedBox(height: 8),
              Text(
                '${selected.heightCm.toStringAsFixed(0)} cm · ${selected.weightKg.toStringAsFixed(0)} kg · ${selected.gender.label}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManualCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _manualFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Chỉnh thủ công',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Bạn có thể tự chọn mùa và nhiệt độ, không cần chụp ảnh.',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('suggestion_season_$_season'),
              initialValue: _season,
              decoration: const InputDecoration(
                labelText: 'Mùa',
                border: OutlineInputBorder(),
              ),
              items: seasonLabels.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _changePreference(() => _season = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('suggestion_temperature_field'),
              controller: _temperatureController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Nhiệt độ (°C)',
                border: OutlineInputBorder(),
              ),
              validator: _validateTemperature,
              onChanged: (_) => _changePreference(() {}),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildStyleAndOccasionCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Kiểu phối đồ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('suggestion_style_dropdown'),
            initialValue: _style,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Phong cách',
              border: OutlineInputBorder(),
            ),
            items: styleLabels.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _changePreference(() => _style = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('suggestion_occasion_dropdown'),
            initialValue: _occasion,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Hoàn cảnh',
              border: OutlineInputBorder(),
            ),
            items: occasionLabels.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _changePreference(() => _occasion = value);
            },
          ),
        ],
      ),
    ),
  );

  Widget _buildWeatherCard(BuildContext context) {
    final weather = _weather;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _placeLabel == null
                        ? 'Thời tiết hiện tại'
                        : 'Thời tiết: $_placeLabel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('refresh_weather_button'),
                  tooltip: 'Cập nhật thời tiết',
                  onPressed: _loadingWeather ? null : _refreshWeather,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loadingWeather) const LinearProgressIndicator(),
            if (weather == null && !_loadingWeather)
              const Text(
                'Cho phép vị trí để xem thời tiết gần bạn, hoặc chọn thành phố bên dưới.',
              ),
            if (weather != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '${weather.temperatureC.toStringAsFixed(0)}°C',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              Text(weather.conditionLabel),
              Text(
                'Cảm nhận: ${weather.apparentTemperatureC.toStringAsFixed(1)}°C',
              ),
              Text(
                'Cao / thấp hôm nay: ${weather.temperatureMaxCToday.toStringAsFixed(1)}°C / ${weather.temperatureMinCToday.toStringAsFixed(1)}°C',
              ),
              Text(
                'Mưa trong ${weather.precipitationIntervalMinutes.toStringAsFixed(0)} phút đo hiện tại: ${weather.precipitationMmCurrentInterval.toStringAsFixed(1)} mm',
              ),
              Text(
                'Xác suất mưa cao nhất hôm nay: ${weather.precipitationProbabilityMaxPercentToday}%',
              ),
              const SizedBox(height: 8),
              Text(
                'Cập nhật: ${weather.observedAtLocal.replaceAll('T', ' ')} · ${weather.timezone}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('weather_city_dropdown'),
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
              onChanged: _loadingWeather
                  ? null
                  : (value) => setState(() => _selectedCityId = value),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('load_city_weather_button'),
              onPressed: _loadingWeather || _selectedCityId == null
                  ? null
                  : _loadSelectedCity,
              icon: const Icon(Icons.location_city_outlined),
              label: const Text('Xem thời tiết thành phố'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dữ liệu thời tiết: Open-Meteo',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiResult(BuildContext context, GeminiSuggestion advice) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Gợi ý từ Gemini',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(advice.assessment),
          const SizedBox(height: 8),
          Text(advice.reason),
          if (advice.colorScore != null) ...<Widget>[
            const SizedBox(height: 8),
            Text('Điểm phối màu tham khảo: ${advice.colorScore}/100'),
          ],
          const SizedBox(height: 12),
          Text(
            'Cách điều chỉnh',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final adjustment in advice.adjustments)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $adjustment'),
            ),
          if (_aiContext?.weather == null) ...<Widget>[
            const SizedBox(height: 8),
            const Text('Chưa có dữ liệu thời tiết cho gợi ý này.'),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('open_outfit_chat_button'),
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Hỏi tiếp về bộ đồ'),
          ),
        ],
      ),
    ),
  );
}
