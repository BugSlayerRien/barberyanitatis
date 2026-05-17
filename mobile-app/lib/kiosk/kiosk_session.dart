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

  static String? guestName;
  static KioskEntryPath? entryPath;
  static KioskScanMode? scanMode;
  static int? selectedServiceId;
  static int? selectedBarberId;
  static String? selectedStyleName;
  static int? selectedVariantId;

  static void reset() {
    guestName = null;
    entryPath = null;
    scanMode = null;
    selectedServiceId = null;
    selectedBarberId = null;
    selectedStyleName = null;
    selectedVariantId = null;
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
