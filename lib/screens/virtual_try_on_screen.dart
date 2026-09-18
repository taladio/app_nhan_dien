import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/pose_result.dart';
import '../models/try_on_filter.dart';
import '../painters/pose_skeleton_painter.dart';
import '../services/camera_frame_service.dart';
import '../services/pose_websocket_service.dart';
import '../utils/camera_coordinate_mapper.dart';
import '../utils/pose_smoother.dart';
import '../widgets/try_on_filter_picker.dart';
import '../widgets/virtual_clothing_overlay.dart';

class VirtualTryOnScreen extends StatefulWidget {
  const VirtualTryOnScreen({super.key});

  @override
  State<VirtualTryOnScreen> createState() => _VirtualTryOnScreenState();
}

class _VirtualTryOnScreenState extends State<VirtualTryOnScreen>
    with WidgetsBindingObserver {
  static const Duration _frameInterval = Duration(milliseconds: 125);

  late final PoseWebSocketService _socket;
  late final StreamSubscription<PoseResult> _poseSubscription;
  late final StreamSubscription<PoseSocketState> _stateSubscription;
  final PoseSmoother _smoother = PoseSmoother();
  final Map<String, ManualFilterTransform> _manualTransforms =
      <String, ManualFilterTransform>{};

  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializingCamera = false;
  bool _encodingFrame = false;
  bool _leaving = false;
  DateTime? _lastFrameAt;
  Size? _encodedFrameSize;
  PoseSocketConfig? _socketConfig;
  PoseResult? _pose;
  DateTime? _lastPoseAt;
  double? _processingFps;
  String _connectionText = 'Đang kết nối';
  String? _cameraError;
  String? _backendError;
  bool _showSkeleton = false;
  bool _filterEnabled = true;
  bool _bodyVisible = false;
  TryOnFilterCategory _category = TryOnFilterCategory.top;
  TryOnFilter _selectedFilter = tryOnFilters.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _socket = PoseWebSocketService(ApiConfig.poseWebSocketUri());
    _poseSubscription = _socket.results.listen(_handlePoseResult);
    _stateSubscription = _socket.states.listen(_handleSocketState);
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_initializeCamera());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_pauseRealtime());
    }
  }

  ImageFormatGroup get _preferredFormat {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ImageFormatGroup.bgra8888;
    }
    return ImageFormatGroup.yuv420;
  }

  Future<void> _initializeCamera() async {
    if (_initializingCamera || _leaving) return;
    _initializingCamera = true;
    try {
      await _disposeController();
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) throw StateError('no_camera');
        final front = _cameras.indexWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
        );
        _cameraIndex = front >= 0 ? front : 0;
      }
      final controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: _preferredFormat,
      );
      _controller = controller;
      await controller.initialize();
      if (_leaving) {
        await controller.dispose();
        return;
      }
      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException {
        // Camera trước và một số thiết bị không có flash.
      }
      if (mounted) {
        setState(() {
          _cameraError = null;
          _pose = null;
          _bodyVisible = false;
        });
      }
      await _startImageStream(controller);
    } on CameraException catch (error) {
      _setCameraError(_cameraMessage(error));
    } on Object {
      _setCameraError('Không tìm thấy hoặc không thể mở camera.');
    } finally {
      _initializingCamera = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startImageStream(CameraController controller) async {
    if (controller.value.isStreamingImages) return;
    _lastFrameAt = null;
    await controller.startImageStream((image) {
      final now = DateTime.now();
      final lastFrameAt = _lastFrameAt;
      final needsInitialFrame = _socketConfig == null;
      if (_leaving ||
          _encodingFrame ||
          (!needsInitialFrame && !_socket.canSendFrame) ||
          (lastFrameAt != null &&
              now.difference(lastFrameAt) < _frameInterval)) {
        return;
      }
      _lastFrameAt = now;
      _encodingFrame = true;
      final rotation = cameraRotationDegrees(controller);
      unawaited(
        encodeCameraFrame(image, rotationDegrees: rotation)
            .then((frame) => _handleEncodedFrame(frame, controller))
            .catchError((Object _) {
              _setCameraError('Không thể chuyển đổi frame camera.');
            })
            .whenComplete(() => _encodingFrame = false),
      );
    });
  }

  Future<void> _handleEncodedFrame(
    EncodedCameraFrame frame,
    CameraController sourceController,
  ) async {
    if (_leaving || sourceController != _controller || !mounted) return;
    final newSize = Size(frame.width.toDouble(), frame.height.toDouble());
    final camera = sourceController.description.lensDirection;
    final config = PoseSocketConfig(
      camera: switch (camera) {
        CameraLensDirection.front => 'front',
        CameraLensDirection.back => 'back',
        CameraLensDirection.external => 'external',
      },
      mirrored: camera == CameraLensDirection.front,
      // JPEG đã được xoay đúng chiều trước khi gửi. Utility mapper vẫn hỗ trợ
      // đủ 0/90/180/270 cho nguồn frame chưa xoay và được unit test riêng.
      rotationDegrees: 0,
      frameWidth: frame.width,
      frameHeight: frame.height,
    );
    if (_socketConfig == null) {
      _socketConfig = config;
      setState(() => _encodedFrameSize = newSize);
      await _socket.connect(config);
      return;
    }
    if (_encodedFrameSize != newSize) {
      setState(() => _encodedFrameSize = newSize);
    }
    _socket.sendFrame(frame.bytes);
  }

  void _handlePoseResult(PoseResult result) {
    if (!mounted || _leaving) return;
    final now = DateTime.now();
    final previousAt = _lastPoseAt;
    final smoothed = _smoother.update(result, now: now);
    setState(() {
      _lastPoseAt = now;
      if (previousAt != null) {
        final elapsedMs = now.difference(previousAt).inMicroseconds / 1000;
        if (elapsedMs > 0) {
          final instantFps = 1000 / elapsedMs;
          _processingFps = _processingFps == null
              ? instantFps
              : (_processingFps! * 0.7 + instantFps * 0.3);
        }
      }
      _pose = smoothed;
      _bodyVisible = result.bodyVisible;
      if (result.poseDetected) _backendError = null;
    });
  }

  void _handleSocketState(PoseSocketState state) {
    if (!mounted || _leaving) return;
    final expectedMessage = switch (state.status) {
      PoseSocketStatus.connecting => 'Đang kết nối',
      PoseSocketStatus.reconnecting => 'Đang kết nối lại',
      PoseSocketStatus.connected => 'Đã kết nối',
      PoseSocketStatus.disconnected => 'Mất kết nối',
    };
    final isStatusOnly = state.message == expectedMessage;
    setState(() {
      _connectionText = expectedMessage;
      if (state.status == PoseSocketStatus.connected) {
        _backendError = isStatusOnly ? null : state.message;
      } else if (!isStatusOnly && _backendError == null) {
        _backendError = state.message;
      }
      if (state.status == PoseSocketStatus.disconnected) {
        _bodyVisible = false;
        _pose = null;
        _smoother.reset();
      }
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializingCamera) return;
    await _socket.disconnect();
    _socketConfig = null;
    _encodedFrameSize = null;
    _smoother.reset();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera();
  }

  Future<void> _reconnect() async {
    final config = _socketConfig;
    if (config == null) return;
    setState(() => _backendError = null);
    await _socket.disconnect();
    await _socket.connect(config, manual: true);
  }

  Future<void> _pauseRealtime() async {
    await _socket.disconnect();
    await _disposeController();
    _socketConfig = null;
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } on CameraException {
        // Stream có thể đã bị hệ điều hành dừng.
      }
    }
    await controller.dispose();
  }

  void _setCameraError(String message) {
    if (!mounted || _leaving) return;
    setState(() => _cameraError = message);
  }

  ManualFilterTransform get _manualTransform =>
      _manualTransforms[_selectedFilter.id] ?? const ManualFilterTransform();

  void _selectCategory(TryOnFilterCategory category) {
    final filter = tryOnFilters.firstWhere((item) => item.category == category);
    setState(() {
      _category = category;
      _selectedFilter = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final frameSize = _encodedFrameSize ?? _fallbackFrameSize(controller);
          final mirrored =
              controller?.description.lensDirection ==
              CameraLensDirection.front;
          final mapper = CameraCoordinateMapper(
            imageSize: frameSize,
            viewportSize: viewport,
            rotationDegrees: 0,
            mirrored: mirrored,
          );
          final pose = _pose;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (initialized)
                _buildCameraPreview(controller!, frameSize)
              else
                const Center(child: CircularProgressIndicator()),
              if (pose != null && _showSkeleton)
                IgnorePointer(
                  child: CustomPaint(
                    painter: PoseSkeletonPainter(pose: pose, mapper: mapper),
                  ),
                ),
              if (pose != null && _filterEnabled)
                VirtualClothingOverlay(
                  pose: pose,
                  filter: _selectedFilter,
                  mapper: mapper,
                  manualTransform: _manualTransform,
                  onTransformChanged: (value) {
                    if (mounted) {
                      setState(
                        () => _manualTransforms[_selectedFilter.id] = value,
                      );
                    }
                  },
                ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 8,
                right: 8,
                child: Row(
                  children: <Widget>[
                    _roundButton(
                      tooltip: 'Đóng',
                      icon: Icons.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    _roundButton(
                      tooltip: 'Hiện/ẩn khung xương',
                      icon: _showSkeleton
                          ? Icons.accessibility_new
                          : Icons.accessibility_new_outlined,
                      onPressed: () =>
                          setState(() => _showSkeleton = !_showSkeleton),
                    ),
                    _roundButton(
                      tooltip: 'Bật/tắt filter',
                      icon: _filterEnabled
                          ? Icons.checkroom
                          : Icons.checkroom_outlined,
                      onPressed: () =>
                          setState(() => _filterEnabled = !_filterEnabled),
                    ),
                    _roundButton(
                      tooltip: 'Đặt lại filter',
                      icon: Icons.center_focus_strong,
                      onPressed: () => setState(
                        () => _manualTransforms.remove(_selectedFilter.id),
                      ),
                    ),
                    _roundButton(
                      tooltip: 'Kết nối lại backend',
                      icon: Icons.sync,
                      onPressed: _reconnect,
                    ),
                    _roundButton(
                      tooltip: 'Đổi camera',
                      icon: Icons.cameraswitch_outlined,
                      onPressed: _cameras.length > 1 ? _switchCamera : null,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 64,
                left: 20,
                right: 20,
                child: Center(
                  child: TryOnStatusPanel(
                    connectionText: _connectionText,
                    connected: _socket.status == PoseSocketStatus.connected,
                    bodyVisible: _bodyVisible,
                    processingFps: _processingFps,
                    errorMessage: _cameraError ?? _backendError,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 150 + MediaQuery.paddingOf(context).bottom,
                child: const Text(
                  'Hình ảnh camera chỉ được xử lý tạm thời và không được lưu trữ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    shadows: <Shadow>[Shadow(blurRadius: 5)],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: TryOnFilterPicker(
                  category: _category,
                  selectedFilter: _selectedFilter,
                  onCategorySelected: _selectCategory,
                  onFilterSelected: (filter) =>
                      setState(() => _selectedFilter = filter),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCameraPreview(CameraController controller, Size frameSize) {
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: frameSize.width,
            height: frameSize.height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Size _fallbackFrameSize(CameraController? controller) {
    final preview = controller?.value.previewSize;
    if (preview == null || preview.isEmpty) return const Size(480, 640);
    return preview.width > preview.height
        ? Size(preview.height, preview.width)
        : preview;
  }

  Widget _roundButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.58),
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon),
      ),
    );
  }

  @override
  void dispose() {
    _leaving = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_poseSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_socket.dispose());
    unawaited(_disposeController());
    super.dispose();
  }
}

String _cameraMessage(CameraException error) {
  return switch (error.code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
      'Bạn chưa cấp quyền camera. Hãy bật quyền trong Cài đặt.',
    'CameraAccessRestricted' => 'Thiết bị đang hạn chế quyền sử dụng camera.',
    _ => 'Không thể mở camera. Vui lòng thử lại.',
  };
}
