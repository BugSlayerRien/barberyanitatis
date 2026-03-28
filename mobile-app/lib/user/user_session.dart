class UserSession {
  static int? userId;
  static String? fullName;
  static String? email;
  static List<String> roles = [];

  static String? selectedStyleName;
  static int? selectedVariantId;

  static Map<String, dynamic>? lastScan;
  static List<Map<String, dynamic>> lastRecommendations = [];

  static void clear() {
    userId = null;
    fullName = null;
    email = null;
    roles = [];
    selectedStyleName = null;
    selectedVariantId = null;
    lastScan = null;
    lastRecommendations = [];
  }
}
