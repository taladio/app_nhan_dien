import 'package:flutter/material.dart';

import '../models/body_profile.dart';
import '../services/body_profile_store.dart';
import '../utils/auth_validators.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({
    super.key,
    required this.accountName,
    required this.email,
    required this.profileStore,
    required this.onChangePassword,
    this.onProfilesChanged,
    this.onSignOut,
    this.profileRevision = 0,
  });

  final String accountName;
  final String email;
  final BodyProfileStore profileStore;
  final Future<void> Function(String currentPassword, String newPassword)
  onChangePassword;
  final ValueChanged<BodyProfileCollection>? onProfilesChanged;
  final VoidCallback? onSignOut;
  final int profileRevision;

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  BodyProfileCollection _collection = const BodyProfileCollection();
  bool _loading = true;
  int _loadId = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final collection = await widget.profileStore.load();
      if (mounted && loadId == _loadId) {
        setState(() => _collection = collection);
      }
    } catch (_) {
      if (mounted && loadId == _loadId) {
        setState(
          () => _loadError =
              'Không thể tải hồ sơ từ Firebase. Kiểm tra Internet và thử lại.',
        );
      }
    } finally {
      if (mounted && loadId == _loadId) setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant PersonalInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileRevision != widget.profileRevision) _load();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _save(BodyProfileCollection collection) async {
    try {
      await widget.profileStore.save(collection);
      if (mounted) setState(() => _collection = collection);
      widget.onProfilesChanged?.call(collection);
      return true;
    } catch (_) {
      _message(
        'Không thể lưu hồ sơ lên Firebase. Kiểm tra Internet và thử lại.',
      );
      return false;
    }
  }

  double? _number(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  String? _validateNumber(String? value, String label, double max) {
    final number = _number(value ?? '');
    if (number == null || !number.isFinite || number <= 0 || number > max) {
      return '$label phải lớn hơn 0 và không vượt quá ${max.toInt()}.';
    }
    return null;
  }

  Future<void> _editProfile([BodyProfile? profile]) async {
    var name = profile?.name ?? '';
    var height = profile == null ? '' : _format(profile.heightCm);
    var weight = profile == null ? '' : _format(profile.weightKg);
    var gender = profile?.gender ?? BodyGender.unspecified;
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(profile == null ? 'Thêm hồ sơ cơ thể' : 'Sửa hồ sơ'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  key: const Key('profile_name_field'),
                  initialValue: name,
                  onChanged: (value) => name = value,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Tên hồ sơ'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng đặt tên hồ sơ.'
                      : null,
                ),
                TextFormField(
                  key: const Key('profile_height_field'),
                  initialValue: height,
                  onChanged: (value) => height = value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Chiều cao (cm)',
                  ),
                  validator: (value) =>
                      _validateNumber(value, 'Chiều cao', 300),
                ),
                TextFormField(
                  key: const Key('profile_weight_field'),
                  initialValue: weight,
                  onChanged: (value) => weight = value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Cân nặng (kg)'),
                  validator: (value) => _validateNumber(value, 'Cân nặng', 500),
                ),
                DropdownButtonFormField<BodyGender>(
                  key: const Key('profile_gender_field'),
                  initialValue: gender,
                  decoration: const InputDecoration(labelText: 'Giới tính'),
                  items: BodyGender.values
                      .map(
                        (option) => DropdownMenuItem<BodyGender>(
                          value: option,
                          child: Text(option.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      gender = value ?? BodyGender.unspecified,
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('save_profile_button'),
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final updated = BodyProfile(
                id:
                    profile?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                name: name.trim(),
                heightCm: _number(height)!,
                weightKg: _number(weight)!,
                gender: gender,
              );
              if (await _save(_collection.upsert(updated)) &&
                  dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProfile(BodyProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa hồ sơ?'),
        content: Text('Xóa “${profile.name}” khỏi tài khoản Firebase?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _save(_collection.remove(profile.id));
  }

  Future<void> _changePassword() async {
    var current = '';
    var next = '';
    final formKey = GlobalKey<FormState>();
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Đổi mật khẩu'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextFormField(
                    key: const Key('current_password_field'),
                    onChanged: (value) => current = value,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu hiện tại',
                    ),
                    validator: validatePassword,
                  ),
                  TextFormField(
                    key: const Key('new_password_field'),
                    onChanged: (value) => next = value,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới',
                    ),
                    validator: validatePassword,
                  ),
                  TextFormField(
                    key: const Key('confirm_password_field'),
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nhập lại mật khẩu mới',
                    ),
                    validator: (value) =>
                        validatePasswordConfirmation(value, next),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('confirm_change_password_button'),
              onPressed: busy
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        await widget.onChangePassword(current, next);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        _message('Đã đổi mật khẩu.');
                      } catch (error) {
                        _message(error.toString());
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => busy = false);
                        }
                      }
                    },
              child: const Text('Đổi mật khẩu'),
            ),
          ],
        ),
      ),
    );
  }

  String _format(double number) => number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toString();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông tin cá nhân'),
        actions: <Widget>[
          if (widget.onSignOut != null)
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Tải lại hồ sơ'),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: <Widget>[
                  Card(
                    color: color.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 30,
                            child: Text(
                              widget.accountName.isEmpty
                                  ? '?'
                                  : widget.accountName[0].toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  widget.accountName,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  widget.email,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: <Widget>[
                        const ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text('Mật khẩu'),
                          subtitle: Text(
                            '••••••••  ·  Không thể xem mật khẩu cũ',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              key: const Key('change_password_button'),
                              onPressed: _changePassword,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Đổi mật khẩu'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Hồ sơ cơ thể',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('add_profile_button'),
                        onPressed: () => _editProfile(),
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lưu trên Firebase theo tài khoản này. Chọn một hồ sơ để dùng khi chụp ảnh hoặc quay video.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_collection.profiles.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Chưa có hồ sơ. Hãy thêm chiều cao và cân nặng của bạn.',
                        ),
                      ),
                    ),
                  for (final profile in _collection.profiles)
                    Card(
                      child: ListTile(
                        key: Key('body_profile_${profile.id}'),
                        leading: Icon(
                          _collection.selected?.id == profile.id
                              ? Icons.check_circle
                              : Icons.person_outline,
                          color: _collection.selected?.id == profile.id
                              ? color.primary
                              : null,
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          '${_format(profile.heightCm)} cm · ${_format(profile.weightKg)} kg · ${profile.gender.label}',
                        ),
                        onTap: () => _save(_collection.select(profile.id)),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Tùy chọn ${profile.name}',
                          onSelected: (action) => action == 'edit'
                              ? _editProfile(profile)
                              : _deleteProfile(profile),
                          itemBuilder: (_) => const <PopupMenuEntry<String>>[
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Đổi tên / sửa hồ sơ'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Xóa hồ sơ'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
