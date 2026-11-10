import 'package:flutter/material.dart';

import '../models/try_on_filter.dart';

class TryOnFilterPicker extends StatelessWidget {
  const TryOnFilterPicker({
    super.key,
    required this.category,
    required this.selectedFilter,
    required this.onCategorySelected,
    required this.onFilterSelected,
    this.customFilters = const [],
    this.onImport,
    this.onRemoveCustom,
    this.use3D = true,
    this.on3DChanged,
    this.onPreview3D,
  });

  final TryOnFilterCategory category;
  final TryOnFilter selectedFilter;
  final ValueChanged<TryOnFilterCategory> onCategorySelected;
  final ValueChanged<TryOnFilter> onFilterSelected;
  final List<TryOnFilter> customFilters;
  final VoidCallback? onImport;
  final VoidCallback? onRemoveCustom;
  final bool use3D;
  final ValueChanged<bool>? on3DChanged;
  final VoidCallback? onPreview3D;

  @override
  Widget build(BuildContext context) {
    final filters = [
      ...tryOnFilters,
      ...customFilters,
    ].where((filter) => filter.category == category).toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selectedFilter.supports3D)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ChoiceChip(
                        label: const Text('2D'),
                        selected: !use3D,
                        onSelected: (_) => on3DChanged?.call(false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('3D bám thân'),
                        selected: use3D,
                        onSelected: (_) => on3DChanged?.call(true),
                      ),
                      TextButton.icon(
                        onPressed: onPreview3D,
                        icon: const Icon(Icons.threesixty, color: Colors.white),
                        label: const Text(
                          'Xem 360°',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kéo để căn • Chụm hai ngón để phóng/thu',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (onRemoveCustom != null)
                    IconButton(
                      tooltip: 'Bỏ ảnh đồ này',
                      onPressed: onRemoveCustom,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                  TextButton.icon(
                    key: const Key('import_garment_button'),
                    onPressed: onImport,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Thêm ảnh đồ'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ],
              ),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: TryOnFilterCategory.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = TryOnFilterCategory.values[index];
                    return ChoiceChip(
                      selected: item == category,
                      label: Text(item.label),
                      onSelected: (_) => onCategorySelected(item),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final filter = filters[index];
                    final selected = filter.id == selectedFilter.id;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: filter.name,
                      child: InkWell(
                        onTap: () => onFilterSelected(filter),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 78,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white24,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: filter.imageBytes != null
                              ? Image.memory(filter.imageBytes!)
                              : Image.asset(filter.assetPath),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TryOnStatusPanel extends StatelessWidget {
  const TryOnStatusPanel({
    super.key,
    required this.connectionText,
    required this.connected,
    required this.bodyVisible,
    this.poseDetected = false,
    this.processingFps,
    this.errorMessage,
  });

  final String connectionText;
  final bool connected;
  final bool bodyVisible;
  final bool poseDetected;
  final double? processingFps;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          key: const Key('try_on_connection_status'),
          decoration: BoxDecoration(
            color: (connected ? Colors.green : Colors.black).withValues(
              alpha: 0.72,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              processingFps == null
                  ? connectionText
                  : '$connectionText · ${processingFps!.toStringAsFixed(1)} FPS',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        if (connected && !bodyVisible) ...<Widget>[
          const SizedBox(height: 8),
          DecoratedBox(
            key: const Key('full_body_hint'),
            decoration: const BoxDecoration(
              color: Color(0xB3000000),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                poseDetected
                    ? 'Đang theo dõi phần cơ thể nhìn thấy. Đứng lùi lại để thử đồ toàn thân.'
                    : 'Chưa thấy cơ thể. Hãy vào khung hình và giữ đủ ánh sáng.',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        if (errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          DecoratedBox(
            key: const Key('try_on_error'),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class TryOnCameraUnavailable extends StatelessWidget {
  const TryOnCameraUnavailable({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.no_photography_outlined,
                  size: 54,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  key: const Key('try_on_camera_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('retry_camera_button'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử mở camera lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
