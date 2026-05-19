import 'package:image_picker/image_picker.dart';

import 'web_camera_picker_stub.dart'
    if (dart.library.html) 'web_camera_picker_web.dart';

Future<XFile?> pickWebCameraImage() => pickWebCameraImageImpl();

Future<bool> isWebCameraSupported() => isWebCameraSupportedImpl();
