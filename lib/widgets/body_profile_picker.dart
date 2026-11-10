import 'package:flutter/material.dart';

import '../models/body_profile.dart';
import '../services/body_profile_store.dart';

class BodyProfilePicker extends StatefulWidget {
  const BodyProfilePicker({super.key, required this.store, this.dark = false});

  final BodyProfileStore store;
  final bool dark;

  @override
  State<BodyProfilePicker> createState() => _BodyProfilePickerState();
}

class _BodyProfilePickerState extends State<BodyProfilePicker> {
  BodyProfileCollection _collection = const BodyProfileCollection();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final collection = await widget.store.load();
      if (mounted) setState(() => _collection = collection);
    } catch (_) {
      _message('Không thể đọc hồ sơ cơ thể.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showChoices() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Chọn hồ sơ cho camera',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_collection.profiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Chưa có hồ sơ. Hãy tạo trong trang Thông tin cá nhân.',
                  ),
                ),
              for (final profile in _collection.profiles)
                ListTile(
                  key: Key('camera_profile_${profile.id}'),
                  leading: Icon(
                    _collection.selected?.id == profile.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(profile.name),
                  subtitle: Text(
                    '${profile.heightCm.toStringAsFixed(1)} cm · ${profile.weightKg.toStringAsFixed(1)} kg',
                  ),
                  onTap: () async {
                    try {
                      final updated = _collection.select(profile.id);
                      await widget.store.save(updated);
                      if (!mounted) return;
                      setState(() => _collection = updated);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    } catch (_) {
                      _message('Không thể lưu hồ sơ đang chọn.');
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _collection.selected;
    final label = _loading
        ? 'Đang tải hồ sơ'
        : selected?.name ?? 'Chưa có hồ sơ';
    final foreground = widget.dark ? Colors.white : null;
    return ActionChip(
      key: const Key('camera_profile_picker'),
      avatar: Icon(Icons.person_outline, color: foreground),
      backgroundColor: widget.dark ? Colors.black87 : null,
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: foreground),
      ),
      onPressed: _loading ? null : _showChoices,
    );
  }
}
