import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../models/pose_result.dart';
import '../models/try_on_filter.dart';
import '../painters/pose_skeleton_painter.dart';
import '../services/camera_frame_service.dart';
import '../services/body_profile_store.dart';
import '../services/pose_websocket_service.dart';
import '../utils/camera_coordinate_mapper.dart';
import '../utils/camera_selection.dart';
import '../utils/pose_smoother.dart';
import '../widgets/try_on_filter_picker.dart';
import '../widgets/body_profile_picker.dart';
import '../widgets/virtual_clothing_overlay.dart';
import 'garment_cutout_screen.dart';
import 'garment_3d_preview_screen.dart';

class VirtualTryOnScreen extends StatefulWidget {
  const VirtualTryOnScreen({super.key, this.profileStore});

  final BodyProfileStore? profileStore;

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
  bool _switchingCamera = false;
  bool _editingGarment = false;
  bool _appIsActive = true;
  bool _resumeRequested = false;
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
  final List<TryOnFilter> _customFilters = [];
  bool _use3D = true;

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
      _appIsActive = true;
      if (_editingGarment) return;
      if (_initializingCamera) {
        // Android tạm pause app khi hiện hộp thoại cấp quyền. Ghi nhớ để thử
        // lại sau initialize thay vì dispose controller giữa chừng.
        _resumeRequested = true;
      } else {
        unawaited(_initializeCamera());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _appIsActive = false;
      if (!_initializingCamera && !_editingGarment) unawaited(_pauseRealtime());
    }
  }

  ImageFormatGroup get _preferredFormat {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ImageFormatGroup.bgra8888;
    }
    return ImageFormatGroup.yuv420;
  }

  Future<void> _initializeCamera({bool tryOtherCameras = true}) async {
    if (_initializingCamera || _leaving || _editingGarment) return;
    final existingController = _controller;
    if (existingController != null && existingController.value.isInitialized) {
      if (!existingController.value.isStreamingImages) {
        await _startImageStream(existingController);
      }
      return;
    }
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
      final controller = await _openFirstWorkingCamera(
        tryOtherCameras: tryOtherCameras,
      );
      if (_leaving || !_appIsActive) {
        await controller.dispose();
        if (_controller == controller) _controller = null;
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
      final shouldRetry =
          _resumeRequested &&
          _appIsActive &&
          !(_controller?.value.isInitialized ?? false) &&
          !_leaving;
      _resumeRequested = false;
      if (shouldRetry) unawaited(_initializeCamera());
    }
  }

  Future<CameraController> _openFirstWorkingCamera({
    bool tryOtherCameras = true,
  }) async {
    CameraException? lastError;
    final indexes = <int>[
      _cameraIndex,
      if (tryOtherCameras)
        for (var index = 0; index < _cameras.length; index++)
          if (index != _cameraIndex) index,
    ];
    for (final index in indexes) {
      final controller = CameraController(
        _cameras[index],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: _preferredFormat,
      );
      _controller = controller;
      try {
        await controller.initialize();
        _cameraIndex = index;
        return controller;
      } on CameraException catch (error) {
        lastError = error;
        _controller = null;
        await controller.dispose();
        if (_isCameraPermissionError(error)) rethrow;
      }
    }
    throw lastError ??
        CameraException('CameraUnavailable', 'Không có camera khả dụng.');
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
    if (_leaving ||
        _editingGarment ||
        sourceController != _controller ||
        !mounted) {
      return;
    }
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
      // 3D orientation interpolates rigid body rotations itself. EMA on the
      // landmark positions would shrink the shoulder span while turning.
      _pose = _use3D && _selectedFilter.supports3D
          ? (result.poseDetected ? result : null)
          : smoothed;
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
    if (_initializingCamera || _switchingCamera) return;
    final currentController = _controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    final targetIndex = oppositeCameraIndex(
      _cameras,
      currentController.description.lensDirection,
    );
    if (targetIndex == null) {
      _setCameraError('Thiết bị không có camera trước/sau để chuyển đổi.');
      return;
    }

    final previousIndex = _cameraIndex;
    _switchingCamera = true;
    if (mounted) setState(() => _cameraError = null);
    try {
      await _socket.disconnect();
      _socketConfig = null;
      _encodedFrameSize = null;
      _pose = null;
      _bodyVisible = false;
      _smoother.reset();

      // Nếu không giải phóng camera cũ, _initializeCamera sẽ thấy controller
      // vẫn hoạt động rồi thoát sớm mà không mở camera mới.
      await _disposeController();
      _cameraIndex = targetIndex;
      await _initializeCamera(tryOtherCameras: false);

      final switchedController = _controller;
      final switched =
          switchedController != null &&
          switchedController.value.isInitialized &&
          switchedController.description.lensDirection !=
              currentController.description.lensDirection;
      if (!switched && _appIsActive && !_leaving) {
        _cameraIndex = previousIndex;
        await _disposeController();
        await _initializeCamera(tryOtherCameras: false);
        _setCameraError(
          'Không thể mở camera còn lại. Camera ban đầu đã được khôi phục.',
        );
      }
    } finally {
      _switchingCamera = false;
      if (mounted) setState(() {});
    }
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

  Future<void> _retryCamera() async {
    if (_initializingCamera) return;
    setState(() => _cameraError = null);
    await _initializeCamera();
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

  Future<void> _importGarment() async {
    if (_editingGarment || _initializingCamera || _switchingCamera) return;
    final category = _category;
    setState(() => _editingGarment = true);
    try {
      // Gallery/editor use their own route; camera is released until returning.
      await _pauseRealtime();
      if (!mounted) return;
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      if (await picked.length() > 10 * 1024 * 1024) {
        throw const FormatException('Chọn ảnh quần áo nhỏ hơn 10 MB.');
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      var volume = 1.0;
      final png = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => GarmentCutoutScreen(
            bytes: bytes,
            category: category,
            onVolumeChanged: (value) => volume = value,
          ),
        ),
      );
      if (png == null || !mounted) return;
      final filter = TryOnFilter.fromImage(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        category: category,
        bytes: png,
        templateAligned: true,
        volume: volume,
      );
      setState(() {
        // Giới hạn RAM: giữ tối đa một ảnh nhập cho mỗi loại trong phiên này.
        for (final previous in _customFilters.where(
          (item) => item.category == category,
        )) {
          _manualTransforms.remove(previous.id);
          unawaited(MemoryImage(previous.imageBytes!).evict());
        }
        _customFilters.removeWhere((item) => item.category == category);
        _customFilters.add(filter);
        _selectedFilter = filter;
        _category = category;
        _filterEnabled = true;
        _use3D = true;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Không chọn được ảnh. Hãy thử lại.',
            ),
          ),
        );
      }
    } finally {
      _editingGarment = false;
      if (mounted && !_leaving) {
        setState(() {});
        if (_appIsActive) await _initializeCamera();
      }
    }
  }

  void _removeCustomFilter() {
    final id = _selectedFilter.id;
    final bytes = _selectedFilter.imageBytes;
    if (bytes != null) unawaited(MemoryImage(bytes).evict());
    setState(() {
      _customFilters.removeWhere((filter) => filter.id == id);
      _manualTransforms.remove(id);
      _selectedFilter = tryOnFilters.firstWhere(
        (filter) => filter.category == _category,
      );
    });
  }

  Future<void> _preview3D() async {
    if (_editingGarment ||
        _initializingCamera ||
        _switchingCamera ||
        !_selectedFilter.supports3D) {
      return;
    }
    setState(() => _editingGarment = true);
    try {
      await _pauseRealtime();
      if (!mounted) return;
      final volume = await Navigator.of(context).push<double>(
        MaterialPageRoute(
          builder: (_) => Garment3DPreviewScreen(filter: _selectedFilter),
        ),
      );
      if (mounted && volume != null) {
        setState(() {
          _use3D = true;
          _selectedFilter = _selectedFilter.withVolume(volume);
          final index = _customFilters.indexWhere(
            (f) => f.id == _selectedFilter.id,
          );
          if (index >= 0) _customFilters[index] = _selectedFilter;
        });
      }
    } finally {
      _editingGarment = false;
      if (mounted && !_leaving) {
        setState(() {});
        if (_appIsActive) await _initializeCamera();
      }
    }
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
              else if (_cameraError != null)
                TryOnCameraUnavailable(
                  message: _cameraError!,
                  onRetry: _retryCamera,
                )
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
                  use3D: _use3D,
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
                      onPressed:
                          initialized &&
                              !_initializingCamera &&
                              !_switchingCamera &&
                              hasOppositeCamera(
                                _cameras,
                                controller!.description.lensDirection,
                              )
                          ? _switchCamera
                          : null,
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
                    poseDetected: pose?.poseDetected ?? false,
                    processingFps: _processingFps,
                    errorMessage: initialized
                        ? _cameraError ?? _backendError
                        : _backendError,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom:
                    210 +
                    (_selectedFilter.supports3D ? 44 : 0) +
                    MediaQuery.paddingOf(context).bottom,
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
              if (widget.profileStore != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom:
                      250 +
                      (_selectedFilter.supports3D ? 44 : 0) +
                      MediaQuery.paddingOf(context).bottom,
                  child: Center(
                    child: BodyProfilePicker(
                      store: widget.profileStore!,
                      dark: true,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: TryOnFilterPicker(
                  category: _category,
                  selectedFilter: _selectedFilter,
                  customFilters: _customFilters,
                  use3D: _use3D,
                  on3DChanged: (value) => setState(() => _use3D = value),
                  onPreview3D:
                      _editingGarment || _initializingCamera || _switchingCamera
                      ? null
                      : _preview3D,
                  onImport:
                      _editingGarment || _initializingCamera || _switchingCamera
                      ? null
                      : _importGarment,
                  onRemoveCustom: _selectedFilter.imageBytes == null
                      ? null
                      : _removeCustomFilter,
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
    for (final filter in _customFilters) {
      unawaited(MemoryImage(filter.imageBytes!).evict());
    }
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
    'CameraAccessDenied' => 'Bạn chưa cấp quyền camera. Hãy thử lại.',
    'CameraAccessRestricted' => 'Thiết bị đang hạn chế quyền sử dụng camera.',
    'CameraAccessDeniedWithoutPrompt' =>
      'Quyền camera đã bị từ chối. Hãy bật lại trong Cài đặt ứng dụng.',
    'CameraUnavailable' =>
      'Camera đang được ứng dụng khác sử dụng hoặc thiết bị không có camera.',
    _ => 'Không thể mở camera. Vui lòng thử lại.',
  };
}

bool _isCameraPermissionError(CameraException error) {
  return error.code == 'CameraAccessDenied' ||
      error.code == 'CameraAccessDeniedWithoutPrompt' ||
      error.code == 'CameraAccessRestricted';
}
