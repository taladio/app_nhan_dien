import 'package:flutter/material.dart';

import '../models/try_on_filter.dart';

class TryOnFilterPicker extends StatelessWidget {
  const TryOnFilterPicker({
    super.key,
    required this.category,
    required this.selectedFilter,
    required this.onCategorySelected,
    required this.onFilterSelected,
  });

  final TryOnFilterCategory category;
  final TryOnFilter selectedFilter;
  final ValueChanged<TryOnFilterCategory> onCategorySelected;
  final ValueChanged<TryOnFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    final filters = tryOnFilters
        .where((filter) => filter.category == category)
        .toList(growable: false);
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
                          child: Image.asset(filter.assetPath),
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
    this.processingFps,
    this.errorMessage,
  });

  final String connectionText;
  final bool connected;
  final bool bodyVisible;
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
        if (!bodyVisible) ...<Widget>[
          const SizedBox(height: 8),
          const DecoratedBox(
            key: Key('full_body_hint'),
            decoration: BoxDecoration(
              color: Color(0xB3000000),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Hãy đứng lùi lại để nhìn thấy toàn thân',
                style: TextStyle(color: Colors.white),
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
