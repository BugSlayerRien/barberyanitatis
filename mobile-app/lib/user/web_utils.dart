// Conditional export to provide `clearUrlFragment()` on web only.
export 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils_web.dart';
