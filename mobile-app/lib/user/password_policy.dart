/// Shared password policy used by registration and Change Password.
class PasswordPolicy {
  PasswordPolicy._();

  static final RegExp upper = RegExp(r'[A-Z]');
  static final RegExp lower = RegExp(r'[a-z]');
  static final RegExp digit = RegExp(r'\d');
  static final RegExp special = RegExp(r'[!@#$%^&*]');

  static Map<String, bool> requirementStates(String password) {
    return {
      'At least 8 characters': password.length >= 8,
      'One uppercase letter': upper.hasMatch(password),
      'One lowercase letter': lower.hasMatch(password),
      'One number': digit.hasMatch(password),
      'One special character': special.hasMatch(password),
    };
  }

  static bool isValid(String password) {
    return requirementStates(password).values.every((met) => met);
  }

  static String? validationError(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters long.';
    }
    if (!upper.hasMatch(password)) {
      return 'Password must contain at least one uppercase letter (A-Z).';
    }
    if (!lower.hasMatch(password)) {
      return 'Password must contain at least one lowercase letter (a-z).';
    }
    if (!digit.hasMatch(password)) {
      return 'Password must contain at least one number (0-9).';
    }
    if (!special.hasMatch(password)) {
      return 'Password must contain at least one special character (!@#\$%^&*).';
    }
    return null;
  }
}
