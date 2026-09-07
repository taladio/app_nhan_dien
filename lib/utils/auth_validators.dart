String? validateFullName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Vui lòng nhập họ và tên.';
  }
  return null;
}

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return 'Vui lòng nhập email.';
  }
  final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  if (!emailPattern.hasMatch(email)) {
    return 'Email không đúng định dạng.';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Vui lòng nhập mật khẩu.';
  }
  if (value.length < 6) {
    return 'Mật khẩu phải có ít nhất 6 ký tự.';
  }
  return null;
}

String? validatePasswordConfirmation(String? value, String password) {
  if (value == null || value.isEmpty) {
    return 'Vui lòng nhập lại mật khẩu.';
  }
  if (value != password) {
    return 'Hai mật khẩu không giống nhau.';
  }
  return null;
}
