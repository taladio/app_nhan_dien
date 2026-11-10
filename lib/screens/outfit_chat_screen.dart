import 'dart:async';

import 'package:flutter/material.dart';

import '../models/gemini_fashion.dart';
import '../services/gemini_fashion_service.dart';
import '../services/chat_history_store.dart';

class OutfitChatScreen extends StatefulWidget {
  const OutfitChatScreen({
    super.key,
    required this.contextData,
    this.service,
    this.historyStore,
  });

  final GeminiOutfitContext contextData;
  final GeminiFashionServiceContract? service;
  final ChatHistoryStore? historyStore;

  @override
  State<OutfitChatScreen> createState() => _OutfitChatScreenState();
}

class _OutfitChatScreenState extends State<OutfitChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final GeminiFashionServiceContract _service;
  late final bool _ownsService;
  final _turns = <GeminiChatTurn>[];
  bool _loading = false;
  String? _error;
  String? _pendingMessage;
  bool _restoring = false;
  bool _restoreFailed = false;
  bool _closing = false;
  String? _storageError;
  Timer? _draftTimer;
  Future<void> _saveQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsService = widget.service == null;
    _service = widget.service ?? GeminiFashionService();
    _controller.addListener(_draftChanged);
    if (widget.historyStore != null) _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _storageError = null;
    });
    try {
      final history = await widget.historyStore!.load();
      if (!mounted) return;
      setState(() {
        _turns
          ..clear()
          ..addAll(history.turns);
        _controller.text = history.draft;
        _pendingMessage = history.pendingMessage;
        _error = _pendingMessage == null
            ? null
            : 'Câu hỏi trước chưa nhận được trả lời. Bấm Thử lại để gửi tiếp.';
        _restoreFailed = false;
      });
      _scrollToLatest();
    } catch (_) {
      if (mounted) {
        setState(() {
          _restoreFailed = true;
          _storageError =
              'Chưa đọc được lịch sử. Hãy thử tải lại trước khi gửi câu hỏi.';
        });
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _draftChanged() {
    if (_restoring || _restoreFailed) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), _persist);
  }

  Future<void> _persist() {
    final store = widget.historyStore;
    if (store == null || _restoring || _restoreFailed) return Future.value();
    _draftTimer?.cancel();
    final snapshot = ChatHistory(
      turns: List.of(_turns),
      draft: _controller.text,
      pendingMessage: _pendingMessage,
    );
    // Serialize disk writes so a slow draft write cannot replace a newer reply.
    _saveQueue = _saveQueue
        .then((_) => store.save(snapshot))
        .then((_) {
          if (mounted && !_closing && _storageError != null) {
            setState(() => _storageError = null);
          }
        })
        .catchError((Object _) {
          if (mounted && !_closing) {
            setState(
              () => _storageError = 'Chưa lưu được hội thoại trên máy. Bấm Lưu lại trước khi đóng app.',
            );
          }
        });
    return _saveQueue;
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _newConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bắt đầu cuộc trò chuyện mới?'),
        content: const Text(
          'Lịch sử hỏi đáp trên thiết bị này sẽ được xóa. Hồ sơ cơ thể vẫn được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa và bắt đầu'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _turns.clear();
      _controller.clear();
      _pendingMessage = null;
      _error = null;
      _restoreFailed = false;
    });
    await _persist();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_persist());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closing = true;
    _draftTimer?.cancel();
    unawaited(_persist());
    _controller.removeListener(_draftChanged);
    _controller.dispose();
    _scrollController.dispose();
    if (_ownsService) _service.close();
    super.dispose();
  }

  Future<void> _send([String? retryMessage]) async {
    final message = (retryMessage ?? _controller.text).trim();
    if (_loading || _restoring || _restoreFailed || message.isEmpty) return;
    if (message.length > 500) {
      setState(() => _error = 'Câu hỏi tối đa 500 ký tự.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _pendingMessage = message;
    });
    unawaited(_persist());
    _scrollToLatest();
    try {
      final start = _turns.length > 6 ? _turns.length - 6 : 0;
      final reply = await _service.chat(
        widget.contextData,
        message,
        _turns.sublist(start),
      );
      if (!mounted) return;
      setState(() {
        _turns.add(GeminiChatTurn(role: 'user', content: message));
        _turns.add(GeminiChatTurn(role: 'assistant', content: reply));
        // Giữ lịch sử hiển thị; chỉ giới hạn phần gửi lên AI ở phía trên.
        _controller.clear();
        _pendingMessage = null;
        if (_turns.length > ChatHistory.maxTurns) {
          _turns.removeRange(0, _turns.length - ChatHistory.maxTurns);
        }
      });
    } on GeminiFashionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Chatbot tạm thời không hoạt động.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        unawaited(_persist());
        _scrollToLatest();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hỏi đáp phối đồ'),
        actions: [
          IconButton(
            key: const Key('chat_new_button'),
            tooltip: 'Cuộc trò chuyện mới',
            onPressed: _loading || _restoring ? null : _newConversation,
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_restoring) const LinearProgressIndicator(),
            if (_storageError != null)
              MaterialBanner(
                content: Text(_storageError!),
                actions: [
                  TextButton(
                    onPressed: _restoring
                        ? null
                        : (_restoreFailed ? _restore : _persist),
                    child: Text(_restoreFailed ? 'Tải lại' : 'Lưu lại'),
                  ),
                ],
              ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Text(
                    widget.contextData.items.isEmpty
                        ? 'Bạn có thể hỏi phối đồ ngay cả khi chưa chụp ảnh.'
                        : 'Hỏi tiếp về bộ đồ YOLO vừa nhận diện; thời tiết chỉ được dùng khi có dữ liệu.',
                  ),
                  const SizedBox(height: 12),
                  if (_turns.isEmpty && !_restoring && !_restoreFailed)
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        for (final question in const <String>[
                          'Hôm nay nên mặc gì?',
                          'Nếu trời mưa thì sao?',
                          'Phối màu thế nào?',
                        ])
                          ActionChip(
                            label: Text(question),
                            onPressed: _loading ? null : () => _send(question),
                          ),
                      ],
                    ),
                  for (final turn in <GeminiChatTurn>[
                    ..._turns,
                    if (_pendingMessage != null)
                      GeminiChatTurn(role: 'user', content: _pendingMessage!),
                  ])
                    Align(
                      alignment: turn.role == 'user'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Card(
                        color: turn.role == 'user'
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(turn.content),
                        ),
                      ),
                    ),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null) ...<Widget>[
                    Text(_error!, style: TextStyle(color: scheme.error)),
                    TextButton.icon(
                      key: const Key('chat_retry_button'),
                      onPressed: _pendingMessage == null
                          ? null
                          : () => _send(_pendingMessage),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('chat_message_field'),
                      controller: _controller,
                      enabled: !_loading && !_restoring && !_restoreFailed,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Ví dụ: Nếu trời mưa thì thay giày nào?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('chat_send_button'),
                    tooltip: 'Gửi câu hỏi',
                    onPressed: _loading || _restoring || _restoreFailed
                        ? null
                        : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
