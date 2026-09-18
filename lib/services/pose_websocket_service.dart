import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/status.dart' as socket_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/pose_result.dart';

enum PoseSocketStatus { disconnected, connecting, connected, reconnecting }

class PoseSocketState {
  const PoseSocketState(this.status, this.message);

  final PoseSocketStatus status;
  final String message;
}

class PoseSocketConfig {
  const PoseSocketConfig({
    required this.camera,
    required this.mirrored,
    required this.rotationDegrees,
    required this.frameWidth,
    required this.frameHeight,
  });

  final String camera;
  final bool mirrored;
  final int rotationDegrees;
  final int frameWidth;
  final int frameHeight;

  Map<String, Object> toJson() => <String, Object>{
    'type': 'config',
    'camera': camera,
    'mirrored': mirrored,
    'rotation_degrees': rotationDegrees,
    'frame_width': frameWidth,
    'frame_height': frameHeight,
  };
}

class PoseWebSocketService {
  PoseWebSocketService(
    this.uri, {
    this.connectionTimeout = const Duration(seconds: 5),
    this.responseTimeout = const Duration(seconds: 4),
    this.maximumReconnectAttempts = 3,
  });

  final Uri uri;
  final Duration connectionTimeout;
  final Duration responseTimeout;
  final int maximumReconnectAttempts;
  final StreamController<PoseResult> _results =
      StreamController<PoseResult>.broadcast();
  final StreamController<PoseSocketState> _states =
      StreamController<PoseSocketState>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _responseTimer;
  PoseSocketConfig? _config;
  PoseSocketStatus _status = PoseSocketStatus.disconnected;
  int _reconnectAttempts = 0;
  int _generation = 0;
  bool _awaitingResult = false;
  bool _allowReconnect = true;
  bool _disposed = false;

  Stream<PoseResult> get results => _results.stream;
  Stream<PoseSocketState> get states => _states.stream;
  PoseSocketStatus get status => _status;
  bool get canSendFrame =>
      _status == PoseSocketStatus.connected && !_awaitingResult;

  Future<void> connect(PoseSocketConfig config, {bool manual = false}) async {
    if (_disposed) return;
    _config = config;
    _allowReconnect = true;
    if (manual) _reconnectAttempts = 0;
    if (_status == PoseSocketStatus.connecting ||
        _status == PoseSocketStatus.connected) {
      return;
    }
    await _open(isReconnect: _reconnectAttempts > 0);
  }

  Future<void> _open({required bool isReconnect}) async {
    final config = _config;
    if (_disposed || config == null) return;
    final generation = ++_generation;
    _setState(
      isReconnect ? PoseSocketStatus.reconnecting : PoseSocketStatus.connecting,
      isReconnect ? 'Đang kết nối lại' : 'Đang kết nối',
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(connectionTimeout);
      if (_disposed || generation != _generation) {
        await channel.sink.close(socket_status.goingAway);
        return;
      }
      _subscription = channel.stream.listen(
        (message) => _handleMessage(message, generation),
        onError: (_) => _handleDisconnect(generation, 'Mất kết nối backend'),
        onDone: () => _handleDisconnect(generation, 'Mất kết nối backend'),
        cancelOnError: true,
      );
      channel.sink.add(jsonEncode(config.toJson()));
      _reconnectAttempts = 0;
      _setState(PoseSocketStatus.connected, 'Đã kết nối');
    } on Object {
      _handleDisconnect(generation, 'Không thể kết nối backend');
    }
  }

  bool sendFrame(Uint8List bytes) {
    final channel = _channel;
    if (!canSendFrame || channel == null || bytes.isEmpty) return false;
    _awaitingResult = true;
    _responseTimer?.cancel();
    _responseTimer = Timer(responseTimeout, () {
      _awaitingResult = false;
      _handleDisconnect(_generation, 'Backend phản hồi quá chậm');
    });
    channel.sink.add(bytes);
    return true;
  }

  void _handleMessage(dynamic message, int generation) {
    if (generation != _generation || message is! String) return;
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      _awaitingResult = false;
      _responseTimer?.cancel();
      if (json['type'] == 'pose_result') {
        _results.add(PoseResult.fromJson(json));
      } else if (json['type'] == 'error') {
        _states.add(
          PoseSocketState(
            _status,
            json['message'] as String? ?? 'Backend không thể xử lý frame.',
          ),
        );
      }
    } on Object {
      _awaitingResult = false;
      _responseTimer?.cancel();
      _states.add(
        PoseSocketState(_status, 'Backend trả dữ liệu không hợp lệ.'),
      );
    }
  }

  void _handleDisconnect(int generation, String message) {
    if (generation != _generation || _disposed) return;
    _generation += 1;
    _awaitingResult = false;
    _responseTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close(socket_status.goingAway);
    _channel = null;
    _setState(PoseSocketStatus.disconnected, message);
    if (!_allowReconnect || _config == null) return;
    if (_reconnectAttempts >= maximumReconnectAttempts) return;
    _reconnectAttempts += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(milliseconds: 500 * (1 << (_reconnectAttempts - 1))),
      () => _open(isReconnect: true),
    );
  }

  void _setState(PoseSocketStatus status, String message) {
    _status = status;
    if (!_states.isClosed) _states.add(PoseSocketState(status, message));
  }

  Future<void> disconnect() async {
    _allowReconnect = false;
    _generation += 1;
    _reconnectTimer?.cancel();
    _responseTimer?.cancel();
    _awaitingResult = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(socket_status.goingAway);
    _channel = null;
    _setState(PoseSocketStatus.disconnected, 'Mất kết nối');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _results.close();
    await _states.close();
  }
}
