import 'package:app_nhan_dien/services/auth_service.dart';
import 'package:app_nhan_dien/utils/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chuẩn hóa dữ liệu đăng ký', () {
    test('loại bỏ khoảng trắng thừa trong họ tên', () {
      expect(normalizeFullName('  Nguyễn   Văn   An  '), 'Nguyễn Văn An');
    });
  });

  group('kiểm tra biểu mẫu xác thực', () {
    test('kiểm tra email đúng định dạng', () {
      expect(validateEmail('ban@example.com'), isNull);
      expect(validateEmail('email-sai'), isNotNull);
      expect(validateEmail('  '), isNotNull);
    });

    test('mật khẩu cần ít nhất 6 ký tự và xác nhận phải trùng', () {
      expect(validatePassword('123456'), isNull);
      expect(validatePassword('12345'), isNotNull);
      expect(validatePasswordConfirmation('123456', '123456'), isNull);
      expect(validatePasswordConfirmation('654321', '123456'), isNotNull);
    });
  });

  test('dịch các lỗi Firebase chính sang tiếng Việt', () {
    expect(authErrorMessage('invalid-email'), 'Địa chỉ email không hợp lệ.');
    expect(
      authErrorMessage('email-already-in-use'),
      'Email này đã được sử dụng.',
    );
    expect(
      authErrorMessage('invalid-credential'),
      'Email hoặc mật khẩu không đúng.',
    );
    expect(
      authErrorMessage('network-request-failed'),
      contains('kiểm tra Internet'),
    );
  });
}
