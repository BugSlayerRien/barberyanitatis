/// Philippine phone number validation, shared by sign-up and the refund
/// contact prompt.
///
/// Extracted so the cancel/refund flow enforces the same rule as registration.
/// Before this, the refund field accepted any 7+ characters, so a receptionist
/// could be handed a number that cannot be dialled or sent money.
class PhPhone {
  PhPhone._();

  /// Digits only, with a leading +63 normalised to 0.
  static String digits(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\D'), '');
    if (cleaned.startsWith('63') && cleaned.length >= 12) {
      return '0${cleaned.substring(2)}';
    }
    return cleaned;
  }

  static bool isValid(String raw) {
    final cleaned = digits(raw);

    // Mobile: 09XXXXXXXXX
    if (cleaned.startsWith('09') && cleaned.length == 11) return true;

    // Landline: area codes 02-08, 8-10 digits total.
    if (RegExp(r'^0[2-8]').hasMatch(cleaned) &&
        cleaned.length >= 8 &&
        cleaned.length <= 10) {
      return true;
    }

    return false;
  }

  static const String error =
      'Enter a valid PH number, e.g. 09171234567 or 02-1234567.';
}
