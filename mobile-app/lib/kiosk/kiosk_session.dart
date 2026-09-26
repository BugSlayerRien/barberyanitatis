/// Walk-in kiosk flow state (no customer login).
enum KioskScanMode {
  threeAngle,
  liveOnly,
}

enum KioskEntryPath {
  scanFace,
  browseCatalog,
  knownStyle,
}

class KioskSession {
  KioskSession._();

  /// Upper bound on a walk-in guest name.
  ///
  /// Mirrored server-side in `api/kiosk_guest_name.php`. `walkin_queue.
  /// guest_name` is VARCHAR(120), so this stays well inside the column and a
  /// long entry is rejected at the screen instead of failing on insert.
  static const int guestNameMaxLength = 70;

  static const String guestNameHint = 'Your name (letters and spaces)';
  static const String guestNameError =
      'Enter at least 2 letters. Letters and spaces only.';
  static const String guestNameTooLongError =
      'Name must be $guestNameMaxLength characters or fewer.';

  static bool isValidGuestName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return false;
    if (name.length > guestNameMaxLength) return false;
    final allowed = RegExp(r'^[\p{L} ]+$', unicode: true);
    if (!allowed.hasMatch(name)) return false;
    return RegExp(r'\p{L}', unicode: true).allMatches(name).length >= 2;
  }

  /// Which rule the entry breaks, so the kiosk can say the useful thing rather
  /// than one generic message.
  static String? guestNameErrorFor(String raw) {
    final name = raw.trim();
    if (name.length > guestNameMaxLength) return guestNameTooLongError;
    return isValidGuestName(name) ? null : guestNameError;
  }

  static String? guestName;
  static KioskEntryPath? entryPath;
  static KioskScanMode? scanMode;
  static int? selectedServiceId;
  static int? selectedBarberId;
  static String? selectedStyleName;
  static int? selectedVariantId;

  /// Terms accepted for THIS walk-in. Deliberately not persisted: a kiosk is
  /// used by a different person each time, so a remembered "already agreed"
  /// would be someone else's agreement. reset() clears it with everything else.
  static bool consentAccepted = false;

  /// How the guest says they will pay: 'counter' or 'gcash'. An intention
  /// only -- the kiosk never talks to the payment gateway; staff collect the
  /// money and completing the visit is what records the payment.
  static String paymentMode = 'counter';

  static void reset() {
    guestName = null;
    entryPath = null;
    scanMode = null;
    selectedServiceId = null;
    selectedBarberId = null;
    selectedStyleName = null;
    selectedVariantId = null;
    consentAccepted = false;
    paymentMode = 'counter';
  }

  static bool get isThreeAngle => scanMode == KioskScanMode.threeAngle;
  static bool get isLiveOnly => scanMode == KioskScanMode.liveOnly;

  static String get scanModeLabel {
    switch (scanMode) {
      case KioskScanMode.threeAngle:
        return '3-angle capture';
      case KioskScanMode.liveOnly:
        return 'Live preview';
      default:
        return '';
    }
  }

  static String get entryPathLabel {
    switch (entryPath) {
      case KioskEntryPath.scanFace:
        return 'face_scan';
      case KioskEntryPath.browseCatalog:
        return 'catalog';
      case KioskEntryPath.knownStyle:
        return 'known_style';
      default:
        return '';
    }
  }
}
