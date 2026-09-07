import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/auth_validators.dart';
import '../../widgets/auth_page_shell.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.authService,
    required this.onLoginTap,
  });

  final AuthService authService;
  final VoidCallback onLoginTap;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      await widget.authService.register(
        fullName: _fullNameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthServiceException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showError('Không thể đăng ký tài khoản. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Tạo tài khoản',
      subtitle: 'Lưu hồ sơ của bạn và bắt đầu khám phá trang phục cùng AI.',
      icon: Icons.person_add_alt_1_outlined,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                key: const Key('register_full_name'),
                controller: _fullNameController,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.name],
                decoration: const InputDecoration(
                  labelText: 'Họ và tên',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: validateFullName,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('register_email'),
                controller: _emailController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('register_password'),
                controller: _passwordController,
                enabled: !_isSubmitting,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: validatePassword,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('register_password_confirmation'),
                controller: _confirmPasswordController,
                enabled: !_isSubmitting,
                obscureText: _obscureConfirmation,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Nhập lại mật khẩu',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirmation
                        ? 'Hiện mật khẩu'
                        : 'Ẩn mật khẩu',
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            setState(
                              () =>
                                  _obscureConfirmation = !_obscureConfirmation,
                            );
                          },
                    icon: Icon(
                      _obscureConfirmation
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => validatePasswordConfirmation(
                  value,
                  _passwordController.text,
                ),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 22),
              FilledButton(
                key: const Key('register_button'),
                onPressed: _isSubmitting ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _isSubmitting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Đăng ký'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('go_to_login_button'),
                onPressed: _isSubmitting ? null : widget.onLoginTap,
                child: const Text('Đã có tài khoản? Đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
