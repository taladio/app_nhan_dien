import 'dart:async';

import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import '../services/fashion_api_service.dart';
import '../services/body_profile_store.dart';
import '../services/realtime_camera_service.dart';
import '../widgets/body_profile_picker.dart';
import '../widgets/detection_painter.dart';
import '../widgets/detection_result_card.dart';

class RealtimeDetectionScreen extends StatefulWidget {
  const RealtimeDetectionScreen({
    super.key,
    this.service,
    this.cameraSession,
    this.profileStore,
  });

  final FashionDetectionService? service;
  final RealtimeCameraSession? cameraSession;
  final BodyProfileStore? profileStore;

  @override
  State<RealtimeDetectionScreen> createState() =>
      _RealtimeDetectionScreenState();
}

class _RealtimeDetectionScreenState extends State<RealtimeDetectionScreen>
    with WidgetsBindingObserver {
  late final FashionDetectionService _service;
  late final RealtimeCameraSession _cameraSession;
  late final bool _ownsService;
  late final bool _ownsCameraSession;

  bool _isInitializing = true;
  bool _isRunning = false;
  bool _frameInFlight = false;
  bool _showBoundingBoxes = true;
  bool _restartAfterResume = false;
  int _runGeneration = 0;
  int _analyzedFrameCount = 0;
  double _confidence = 0.25;
  Duration? _lastAnalysisDuration;
  DetectionResponse? _response;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsService = widget.service == null;
    _ownsCameraSession = widget.cameraSession == null;
    _service = widget.service ?? FashionApiService();
    _cameraSession = widget.cameraSession ?? PluginRealtimeCameraSession();
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Không dispose ở trạng thái inactive: hộp thoại xin quyền camera cũng làm
    // app tạm inactive và sẽ gây race với CameraController.initialize().
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _restartAfterResume = _isRunning;
      if (!_isInitializing) {
        unawaited(_suspendCamera());
      }
    } else if (state == AppLifecycleState.resumed &&
        !_cameraSession.isInitialized) {
      final shouldRestart = _restartAfterResume;
      _restartAfterResume = false;
      unawaited(_initializeCamera(startAfterInitialization: shouldRestart));
    }
  }

  Future<void> _initializeCamera({
    bool startAfterInitialization = false,
  }) async {
    final generation = ++_runGeneration;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _isRunning = false;
        _errorMessage = null;
      });
    }

    try {
      await _cameraSession.initialize();
      if (!mounted || generation != _runGeneration) {
        return;
      }
      setState(() => _isInitializing = false);
      if (startAfterInitialization) {
        await _startRealtime();
      }
    } on RealtimeCameraException catch (error) {
      _showInitializationError(generation, error.message);
    } catch (_) {
      _showInitializationError(
        generation,
        'Không thể khởi tạo camera. Vui lòng thử lại.',
      );
    }
  }

  void _showInitializationError(int generation, String message) {
    if (!mounted || generation != _runGeneration) {
      return;
    }
    setState(() {
      _isInitializing = false;
      _isRunning = false;
      _errorMessage = message;
    });
  }

  Future<void> _startRealtime() async {
    if (_isRunning || _isInitializing || !_cameraSession.isInitialized) {
      return;
    }
    final generation = ++_runGeneration;
    setState(() {
      _isRunning = true;
      _errorMessage = null;
    });

    try {
      await _cameraSession.startFrameStream(
        onFrame: (frame) => _handleFrame(frame, generation),
        onError: (error) =>
            _stopWithError(generation, 'Không thể đọc hình ảnh từ camera.'),
      );
    } on RealtimeCameraException catch (error) {
      _stopWithError(generation, error.message);
    } catch (_) {
      _stopWithError(generation, 'Không thể bắt đầu nhận diện realtime.');
    }
  }

  void _handleFrame(RealtimeCameraFrame frame, int generation) {
    if (!_isRunning || _frameInFlight || generation != _runGeneration) {
      return;
    }
    _frameInFlight = true;
    unawaited(_analyzeFrame(frame, generation));
  }

  Future<void> _analyzeFrame(RealtimeCameraFrame frame, int generation) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _service.detectClothing(
        imageBytes: frame.bytes,
        filename: frame.filename,
        confidence: _confidence,
      );
      stopwatch.stop();
      if (!mounted || !_isRunning || generation != _runGeneration) {
        return;
      }
      setState(() {
        _response = response;
        _lastAnalysisDuration = stopwatch.elapsed;
        _analyzedFrameCount += 1;
        _errorMessage = null;
      });
    } on FashionApiException catch (error) {
      _stopWithError(generation, error.message);
    } catch (_) {
      _stopWithError(
        generation,
        'Không thể xử lý khung hình. Vui lòng thử lại.',
      );
    } finally {
      _frameInFlight = false;
    }
  }

  void _stopWithError(int generation, String message) {
    if (!mounted || generation != _runGeneration) {
      return;
    }
    _runGeneration += 1;
    setState(() {
      _isRunning = false;
      _errorMessage = message;
    });
    unawaited(_cameraSession.stopFrameStream());
  }

  Future<void> _stopRealtime() async {
    if (!_isRunning) {
      return;
    }
    _runGeneration += 1;
    setState(() => _isRunning = false);
    await _cameraSession.stopFrameStream();
  }

  Future<void> _switchCamera() async {
    if (_isInitializing) {
      return;
    }
    final wasRunning = _isRunning;
    if (wasRunning) {
      await _stopRealtime();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isInitializing = true;
      _response = null;
      _errorMessage = null;
    });
    try {
      await _cameraSession.switchCamera();
      if (!mounted) {
        return;
      }
      setState(() => _isInitializing = false);
      if (wasRunning) {
        await _startRealtime();
      }
    } on RealtimeCameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _suspendCamera() async {
    _runGeneration += 1;
    if (mounted) {
      setState(() {
        _isRunning = false;
        _isInitializing = true;
      });
    }
    await _cameraSession.stopFrameStream();
    await _cameraSession.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runGeneration += 1;
    if (_ownsService) {
      _service.close();
    }
    if (_ownsCameraSession) {
      unawaited(_cameraSession.dispose());
    } else {
      unawaited(_cameraSession.stopFrameStream());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nhận diện realtime')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (widget.profileStore != null) ...<Widget>[
                    BodyProfilePicker(store: widget.profileStore!),
                    const SizedBox(height: 8),
                  ],
                  _buildCameraArea(context),
                  const SizedBox(height: 12),
                  _buildStatus(context),
                  const SizedBox(height: 12),
                  _buildControls(context),
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _buildErrorPanel(context),
                  ],
                  if (_response != null) ...<Widget>[
                    const SizedBox(height: 16),
                    _buildResults(context, _response!),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Ứng dụng không lưu video và không thu âm. Các khung hình '
                    'được gửi tuần tự đến máy chủ để tránh quá tải YOLO.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea(BuildContext context) {
    if (_isInitializing) {
      return const AspectRatio(
        aspectRatio: 3 / 4,
        child: Card(
          key: Key('realtime_initializing'),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!_cameraSession.isInitialized) {
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: Card(
          child: Center(
            child: Icon(
              Icons.no_photography_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      );
    }

    final response = _response;
    return Card(
      key: const Key('realtime_preview'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: _cameraSession.buildPreview(
        overlay: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (response != null)
              IgnorePointer(
                child: CustomPaint(
                  painter: DetectionPainter(
                    detections: response.detections,
                    imageSize: Size(
                      response.imageWidth.toDouble(),
                      response.imageHeight.toDouble(),
                    ),
                    showBoundingBoxes: _showBoundingBoxes,
                  ),
                ),
              ),
            Positioned(
              left: 10,
              top: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _isRunning ? Icons.fiber_manual_record : Icons.pause,
                        color: _isRunning ? Colors.redAccent : Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isRunning ? 'Đang nhận diện' : 'Đã tạm dừng',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final duration = _lastAnalysisDuration;
    final objectCount = _response?.detectionCount ?? 0;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        Chip(
          avatar: const Icon(Icons.center_focus_strong, size: 18),
          label: Text('Vật thể: $objectCount'),
        ),
        Chip(
          avatar: const Icon(Icons.photo_camera_back_outlined, size: 18),
          label: Text('Frame: $_analyzedFrameCount'),
        ),
        if (duration != null)
          Chip(
            avatar: const Icon(Icons.speed, size: 18),
            label: Text('${duration.inMilliseconds} ms'),
          ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Ngưỡng tin cậy: ${_confidence.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Slider(
              key: const Key('realtime_confidence_slider'),
              min: 0.10,
              max: 0.90,
              divisions: 16,
              value: _confidence,
              label: _confidence.toStringAsFixed(2),
              onChanged: (value) => setState(() => _confidence = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hiển thị bounding box'),
              value: _showBoundingBoxes,
              onChanged: (value) {
                setState(() => _showBoundingBoxes = value);
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('realtime_start_button'),
                  onPressed: _isInitializing || !_cameraSession.isInitialized
                      ? null
                      : (_isRunning ? _stopRealtime : _startRealtime),
                  icon: Icon(_isRunning ? Icons.stop : Icons.videocam),
                  label: Text(
                    _isRunning ? 'Dừng nhận diện' : 'Bắt đầu realtime',
                  ),
                ),
                if (_cameraSession.canSwitchCamera)
                  OutlinedButton.icon(
                    key: const Key('switch_camera_button'),
                    onPressed: _isInitializing || !_cameraSession.isInitialized
                        ? null
                        : _switchCamera,
                    icon: const Icon(Icons.cameraswitch_outlined),
                    label: const Text('Đổi camera'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorPanel(BuildContext context) {
    return Card(
      key: const Key('realtime_error'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _cameraSession.isInitialized
                  ? _startRealtime
                  : _initializeCamera,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, DetectionResponse response) {
    return Column(
      key: const Key('realtime_result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          response.hasDetections
              ? 'Kết quả realtime'
              : 'Không phát hiện được quần áo',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (response.summary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: response.summary
                .map(
                  (item) =>
                      Chip(label: Text('${item.classNameVi}: ${item.count}')),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 8),
        ...List<Widget>.generate(response.detections.length, (index) {
          return DetectionResultCard(
            detection: response.detections[index],
            index: index,
          );
        }),
      ],
    );
  }
}
