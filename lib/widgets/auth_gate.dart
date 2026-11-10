import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/login_page.dart';
import '../screens/auth/register_page.dart';
import '../services/auth_service.dart';
import '../services/body_profile_store.dart';
import '../services/chat_history_store.dart';
import '../services/analysis_preferences.dart';
import 'app_home.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService;
  bool _showRegisterPage = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  Future<void> _signOut() async {
    if (mounted && _showRegisterPage) {
      setState(() => _showRegisterPage = false);
    }
    await _authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges(),
      initialData: _authService.currentUser,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _AuthGateError();
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const _AuthGateLoading();
        }

        final user = snapshot.data;
        if (user != null) {
          return AppHome(
            key: ValueKey<String>(user.uid),
            onSignOut: _signOut,
            accountName: user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : (user.email?.split('@').first ?? 'Người dùng'),
            accountEmail: user.email ?? '',
            onChangePassword: (current, next) => _authService.changePassword(
              currentPassword: current,
              newPassword: next,
            ),
            profileStore: FirestoreBodyProfileStore(user.uid),
            chatHistoryStore: SharedPreferencesChatHistoryStore(user.uid),
            preferencesStore: SharedPreferencesAnalysisStore(userId: user.uid),
          );
        }
        if (_showRegisterPage) {
          return RegisterPage(
            authService: _authService,
            onLoginTap: () => setState(() => _showRegisterPage = false),
          );
        }
        return LoginPage(
          authService: _authService,
          onRegisterTap: () => setState(() => _showRegisterPage = true),
        );
      },
    );
  }
}

class _AuthGateLoading extends StatelessWidget {
  const _AuthGateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang kiểm tra phiên đăng nhập...'),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthGateError extends StatelessWidget {
  const _AuthGateError();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.cloud_off_outlined,
                  size: 52,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Không thể kiểm tra phiên đăng nhập. Vui lòng mở lại ứng dụng.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
