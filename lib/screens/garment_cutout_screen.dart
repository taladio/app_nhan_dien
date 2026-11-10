import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/garment_template.dart';
import '../models/try_on_filter.dart';
import 'garment_3d_preview_screen.dart';

/// Fits an image into a clothing silhouette entirely on the device.
class GarmentCutoutScreen extends StatefulWidget {
  const GarmentCutoutScreen({
    super.key,
    required this.bytes,
    required this.category,
    this.onVolumeChanged,
  });
  final Uint8List bytes;
  final TryOnFilterCategory category;
  final ValueChanged<double>? onVolumeChanged;

  @override
  State<GarmentCutoutScreen> createState() => _GarmentCutoutScreenState();
}

class _GarmentCutoutScreenState extends State<GarmentCutoutScreen> {
  ui.Image? _image;
  bool _busy = true;
  bool _preview = false;
  bool _flipped = false;
  String? _error;
  double _zoom = 1;
  double _rotation = 0;
  Offset _offset = Offset.zero;
  double _startZoom = 1;
  double _startRotation = 0;
  Offset _gestureAnchor = Offset.zero;
  int _photoPointers = 0;
  static const _accent = Color(0xff83edda);
  static const _minZoom = .35;
  static const _maxZoom = 4.0;
  GarmentTemplate get _template => GarmentTemplate(widget.category);

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      if (widget.bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Chọn ảnh nhỏ hơn 10 MB.');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final ui.Image image;
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width * descriptor.height > 20000000) {
            throw const FormatException('Chọn ảnh dưới 20 megapixel.');
          }
          final ratio = math.min(
            1.0,
            1600 / math.max(descriptor.width, descriptor.height),
          );
          final codec = await descriptor.instantiateCodec(
            targetWidth: math.max(1, (descriptor.width * ratio).round()),
            targetHeight: math.max(1, (descriptor.height * ratio).round()),
          );
          try {
            image = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Không đọc được ảnh. Hãy chọn ảnh JPG, PNG hoặc WebP khác.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
    _zoom = 1;
    _offset = Offset.zero;
    _rotation = 0;
    _flipped = false;
    _error = null;
  });

  Future<void> _apply({bool preview3D = false}) async {
    final image = _image;
    if (image == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final size = _template.outputSize;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.clipPath(_template.path(size));
      _paintPhoto(canvas, size, image, _zoom, _offset, _rotation, _flipped);
      final picture = recorder.endRecording();
      final ui.Image rendered;
      try {
        rendered = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
      } finally {
        picture.dispose();
      }
      final ByteData? png;
      try {
        final rgba = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        var visiblePixels = 0;
        if (rgba != null) {
          for (var i = 3; i < rgba.lengthInBytes; i += 4) {
            if (rgba.getUint8(i) > 8) visiblePixels++;
          }
        }
        if (visiblePixels < size.width * size.height * .01) {
          throw const FormatException(
            'Ảnh đang nằm ngoài khung. Kéo ảnh vào lại hoặc bấm Đặt lại.',
          );
        }
        png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        rendered.dispose();
      }
      if (png == null) throw StateError('empty_png');
      if (!mounted) return;
      final bytes = png.buffer.asUint8List();
      if (preview3D) {
        final volume = await Navigator.of(context).push<double>(
          MaterialPageRoute(
            builder: (_) => Garment3DPreviewScreen(
              filter: TryOnFilter.fromImage(
                id: 'preview',
                category: widget.category,
                bytes: bytes,
                templateAligned: true,
              ),
            ),
          ),
        );
        // Preview images are temporary, including when returning to edit again.
        await MemoryImage(bytes).evict();
        if (volume == null || !mounted) return;
        widget.onVolumeChanged?.call(volume);
      }
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Chưa tạo được filter. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _canvas(Size size) {
    final image = _image;
    return Listener(
      onPointerDown: (_) => setState(() => _photoPointers++),
      onPointerUp: (_) =>
          setState(() => _photoPointers = math.max(0, _photoPointers - 1)),
      onPointerCancel: (_) =>
          setState(() => _photoPointers = math.max(0, _photoPointers - 1)),
      child: GestureDetector(
        key: const Key('garment_edit_canvas'),
        behavior: HitTestBehavior.opaque,
        onScaleStart: _busy || image == null
            ? null
            : (details) {
                _startZoom = _zoom;
                _startRotation = _rotation;
                final translation = Offset(
                  _offset.dx * size.width,
                  _offset.dy * size.height,
                );
                _gestureAnchor =
                    _rotate(
                      details.localFocalPoint -
                          size.center(Offset.zero) -
                          translation,
                      -_rotation,
                    ) /
                    _zoom;
              },
        onScaleUpdate: _busy || image == null
            ? null
            : (details) {
                final zoom = (_startZoom * details.scale).clamp(
                  _minZoom,
                  _maxZoom,
                );
                final rotation = _startRotation + details.rotation;
                final translation =
                    details.localFocalPoint -
                    size.center(Offset.zero) -
                    _rotate(_gestureAnchor * zoom, rotation);
                setState(() {
                  _zoom = zoom;
                  _rotation = rotation;
                  _offset = Offset(
                    translation.dx / size.width,
                    translation.dy / size.height,
                  );
                });
              },
        child: CustomPaint(
          painter: _TemplatePainter(
            template: _template,
            image: image,
            zoom: _zoom,
            offset: _offset,
            rotation: _rotation,
            flipped: _flipped,
            preview: _preview,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && _image != null;
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101c21),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Căn ảnh vào khung'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canvasHeight = (constraints.maxHeight - 300).clamp(
                180.0,
                460.0,
              );
              return SingleChildScrollView(
                physics: _photoPointers > 0
                    ? const NeverScrollableScrollPhysics()
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.checkroom, color: _accent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Khung ${widget.category.label.toLowerCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.pinch_outlined,
                            color: Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '2 ngón',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Kéo ảnh, chụm hai ngón để phóng/thu và xoay cho vừa viền. Phần trong viền sẽ thành filter.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      Container(
                        height: canvasHeight,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xff1b2a30),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _template.outputSize.aspectRatio,
                              child: LayoutBuilder(
                                builder: (_, bounds) => _canvas(bounds.biggest),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Color(0xffffb4ab)),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.photo_size_select_small, size: 20),
                          Expanded(
                            child: Slider(
                              key: const Key('garment_zoom_slider'),
                              min: _minZoom,
                              max: _maxZoom,
                              value: _zoom,
                              label: '${(_zoom * 100).round()}%',
                              onChanged: enabled
                                  ? (value) => setState(() => _zoom = value)
                                  : null,
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text('${(_zoom * 100).round()}%'),
                          ),
                        ],
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: enabled ? _reset : null,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Đặt lại'),
                          ),
                          TextButton.icon(
                            onPressed: enabled
                                ? () => setState(() => _flipped = !_flipped)
                                : null,
                            icon: const Icon(Icons.flip),
                            label: const Text('Lật ảnh'),
                          ),
                          TextButton.icon(
                            onPressed: enabled
                                ? () => setState(() => _preview = !_preview)
                                : null,
                            icon: Icon(
                              _preview
                                  ? Icons.crop_free
                                  : Icons.visibility_outlined,
                            ),
                            label: Text(_preview ? 'Hiện viền' : 'Xem trước'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (widget.category != TryOnFilterCategory.shoes)
                        OutlinedButton.icon(
                          key: const Key('preview_garment_3d'),
                          onPressed: enabled
                              ? () => _apply(preview3D: true)
                              : null,
                          icon: const Icon(Icons.view_in_ar),
                          label: const Text('Xem thử 3D'),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('apply_garment_button'),
                          onPressed: enabled ? _apply : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: const Color(0xff102b28),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.checkroom),
                          label: const Text('Tạo filter'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Ảnh chỉ dùng trong phiên thử đồ này.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }
}

Offset _rotate(Offset p, double angle) => Offset(
  p.dx * math.cos(angle) - p.dy * math.sin(angle),
  p.dx * math.sin(angle) + p.dy * math.cos(angle),
);

void _paintPhoto(
  Canvas canvas,
  Size size,
  ui.Image image,
  double zoom,
  Offset offset,
  double rotation,
  bool flipped, {
  double opacity = 1,
}) {
  final fit = math.max(size.width / image.width, size.height / image.height);
  canvas.save();
  canvas.translate(
    size.width * (.5 + offset.dx),
    size.height * (.5 + offset.dy),
  );
  canvas.rotate(rotation);
  canvas.scale(fit * zoom * (flipped ? -1 : 1), fit * zoom);
  canvas.drawImage(
    image,
    Offset(-image.width / 2, -image.height / 2),
    Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..filterQuality = FilterQuality.high,
  );
  canvas.restore();
}

class _TemplatePainter extends CustomPainter {
  const _TemplatePainter({
    required this.template,
    required this.image,
    required this.zoom,
    required this.offset,
    required this.rotation,
    required this.flipped,
    required this.preview,
  });
  final GarmentTemplate template;
  final ui.Image? image;
  final double zoom;
  final Offset offset;
  final double rotation;
  final bool flipped;
  final bool preview;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final path = template.path(size);
    if (!preview && image != null) {
      _paintPhoto(
        canvas,
        size,
        image!,
        zoom,
        offset,
        rotation,
        flipped,
        opacity: .20,
      );
    }
    canvas.save();
    canvas.clipPath(path);
    for (var y = 0.0; y < size.height; y += 14) {
      for (var x = 0.0; x < size.width; x += 14) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 14, 14),
          Paint()
            ..color = ((x / 14 + y / 14).round().isEven
                ? const Color(0xff304047)
                : const Color(0xff26353c)),
        );
      }
    }
    if (image != null) {
      _paintPhoto(canvas, size, image!, zoom, offset, rotation, flipped);
    }
    canvas.restore();
    if (!preview) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x3083edda)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff83edda)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.save();
      canvas.clipPath(path);
      final guide = Paint()
        ..color = const Color(0x80ffffff)
        ..strokeWidth = 1;
      for (var y = 0.0; y < size.height; y += 12) {
        canvas.drawLine(
          Offset(size.width / 2, y),
          Offset(size.width / 2, y + 5),
          guide,
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TemplatePainter old) =>
      image != old.image ||
      zoom != old.zoom ||
      offset != old.offset ||
      rotation != old.rotation ||
      flipped != old.flipped ||
      preview != old.preview ||
      template.category != old.template.category;
}
