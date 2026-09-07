import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/auth_validators.dart';
import '../../widgets/auth_page_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.authService,
    required this.onRegisterTap,
  });

  final AuthService authService;
  final VoidCallback onRegisterTap;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      await widget.authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthServiceException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Không thể đăng nhập. Vui lòng thử lại.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    if (_isSubmitting) {
      return;
    }
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final resetFormKey = GlobalKey<FormState>();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Đặt lại mật khẩu'),
          content: Form(
            key: resetFormKey,
            child: TextFormField(
              controller: emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: validateEmail,
              onFieldSubmitted: (_) {
                if (resetFormKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(emailController.text.trim());
                }
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (resetFormKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(emailController.text.trim());
                }
              },
              child: const Text('Gửi email'),
            ),
          ],
        );
      },
    );
    emailController.dispose();
    if (!mounted || email == null) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.authService.sendPasswordResetEmail(email);
      if (mounted) {
        _showMessage('Đã gửi email đặt lại mật khẩu.');
      }
    } on AuthServiceException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Không thể gửi email đặt lại mật khẩu.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Chào mừng trở lại',
      subtitle: 'Đăng nhập để tiếp tục nhận diện trang phục cùng AI Fashion.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                key: const Key('login_email'),
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
                key: const Key('login_password'),
                controller: _passwordController,
                enabled: !_isSubmitting,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.password],
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
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('forgot_password_button'),
                  onPressed: _isSubmitting ? null : _forgotPassword,
                  child: const Text('Quên mật khẩu?'),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton(
                key: const Key('login_button'),
                onPressed: _isSubmitting ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _isSubmitting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Đăng nhập'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('go_to_register_button'),
                onPressed: _isSubmitting ? null : widget.onRegisterTap,
                child: const Text('Chưa có tài khoản? Đăng ký'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
