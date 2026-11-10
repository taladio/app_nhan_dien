import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthServiceException implements Exception {
  const AuthServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final normalizedName = normalizeFullName(fullName);
    final normalizedEmail = email.trim();

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthServiceException(
          'Không thể tạo tài khoản. Vui lòng thử lại.',
        );
      }

      await user.updateDisplayName(normalizedName);
      await _firestore.collection('users').doc(user.uid).set(<String, Object?>{
        'uid': user.uid,
        'fullName': normalizedName,
        'email': user.email ?? normalizedEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return credential;
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(
        authErrorMessage(error.code),
        code: error.code,
      );
    } on FirebaseException catch (error) {
      throw AuthServiceException(
        firestoreErrorMessage(error.code),
        code: error.code,
      );
    }
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(
        authErrorMessage(error.code),
        code: error.code,
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(
        authErrorMessage(error.code),
        code: error.code,
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(
        authErrorMessage(error.code),
        code: error.code,
      );
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw const AuthServiceException(
        'Vui lòng đăng nhập lại để đổi mật khẩu.',
      );
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(switch (error.code) {
        'wrong-password' ||
        'invalid-credential' => 'Mật khẩu hiện tại không đúng.',
        'requires-recent-login' =>
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        _ => authErrorMessage(error.code),
      }, code: error.code);
    }
  }
}

String normalizeFullName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String authErrorMessage(String code) {
  return switch (code) {
    'invalid-email' => 'Địa chỉ email không hợp lệ.',
    'weak-password' => 'Mật khẩu quá yếu. Vui lòng dùng ít nhất 6 ký tự.',
    'email-already-in-use' => 'Email này đã được sử dụng.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'Email hoặc mật khẩu không đúng.',
    'network-request-failed' =>
      'Không thể kết nối Firebase. Vui lòng kiểm tra Internet.',
    'too-many-requests' => 'Bạn thao tác quá nhiều lần. Vui lòng thử lại sau.',
    'user-disabled' => 'Tài khoản này đã bị vô hiệu hóa.',
    'operation-not-allowed' =>
      'Đăng nhập Email/Mật khẩu chưa được bật trên Firebase.',
    _ => 'Không thể xác thực tài khoản. Vui lòng thử lại.',
  };
}

String firestoreErrorMessage(String code) {
  return switch (code) {
    'permission-denied' =>
      'Không thể lưu hồ sơ người dùng. Vui lòng kiểm tra quyền Firestore.',
    'unavailable' => 'Dịch vụ lưu hồ sơ đang tạm gián đoạn. Vui lòng thử lại.',
    _ => 'Không thể lưu hồ sơ người dùng. Vui lòng thử lại.',
  };
}
