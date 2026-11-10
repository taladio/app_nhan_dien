import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/garment_template.dart';
import '../models/try_on_filter.dart';
import '../widgets/garment_surface.dart';

class Garment3DPreviewScreen extends StatefulWidget {
  const Garment3DPreviewScreen({super.key, required this.filter});
  final TryOnFilter filter;

  @override
  State<Garment3DPreviewScreen> createState() => _Garment3DPreviewScreenState();
}

class _Garment3DPreviewScreenState extends State<Garment3DPreviewScreen> {
  double _yaw = -.35, _pitch = -.08, _zoom = 1, _startZoom = 1;
  late double _volume;
  bool _wireframe = false;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _volume = widget.filter.volume;
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff83edda),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101c21),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Xem đồ 3D')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, bounds) {
              return SingleChildScrollView(
                physics: _pointers > 0
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Kéo để xoay 360° • Chụm hai ngón để phóng/thu',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: (bounds.maxHeight - 340).clamp(200.0, 500.0),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const RadialGradient(
                          colors: [Color(0xff30484c), Color(0xff14242b)],
                          radius: .9,
                        ),
                      ),
                      child: Listener(
                        onPointerDown: (_) => setState(() => _pointers++),
                        onPointerUp: (_) => setState(
                          () => _pointers = math.max(0, _pointers - 1),
                        ),
                        onPointerCancel: (_) => setState(
                          () => _pointers = math.max(0, _pointers - 1),
                        ),
                        child: GestureDetector(
                          key: const Key('garment_3d_orbit'),
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: (_) => _startZoom = _zoom,
                          onScaleUpdate: (details) => setState(() {
                            _zoom = (_startZoom * details.scale).clamp(.6, 1.8);
                            _yaw =
                                (_yaw + details.focalPointDelta.dx * .015) %
                                (math.pi * 2);
                            _pitch = (_pitch - details.focalPointDelta.dy * .01)
                                .clamp(-.8, .8);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: GarmentTemplate(filter.category)
                                    .outputSize
                                    .aspectRatio,
                                child: Transform.scale(
                                  scale: _zoom,
                                  child: GarmentSurface(
                                    image: MemoryImage(filter.imageBytes!),
                                    meshCategory: filter.category,
                                    yaw: _yaw,
                                    pitch: _pitch,
                                    volume: _volume,
                                    wireframe: _wireframe,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _yaw = 0;
                            _pitch = 0;
                            _zoom = 1;
                          }),
                          child: const Text('Mặt trước'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _yaw = math.pi / 2;
                            _pitch = 0;
                          }),
                          child: const Text('Mặt bên'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _yaw = math.pi;
                            _pitch = 0;
                          }),
                          child: const Text('Mặt sau'),
                        ),
                        FilterChip(
                          label: const Text('Lưới 3D'),
                          selected: _wireframe,
                          onSelected: (value) =>
                              setState(() => _wireframe = value),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Độ phồng'),
                        Expanded(
                          child: Slider(
                            key: const Key('garment_3d_volume'),
                            value: _volume,
                            min: .4,
                            max: 1.8,
                            onChanged: (value) =>
                                setState(() => _volume = value),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '3D thử nghiệm. Ảnh phủ mặt trước; mặt bên và sau dùng màu trơn minh họa. Chưa mô phỏng vải hay độ vừa thực tế.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('use_3d_filter'),
                      onPressed: () => Navigator.of(context).pop(_volume),
                      icon: const Icon(Icons.checkroom),
                      label: const Text('Dùng filter này'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
