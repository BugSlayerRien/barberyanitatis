// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

Future<XFile?> pickWebCameraImageImpl() async {
  final input = html.FileUploadInputElement();
  input.accept = 'image/*';
  input.setAttribute('capture', 'environment');
  input.click();

  await input.onChange.first;
  if (input.files == null || input.files!.isEmpty) {
    return null;
  }

  final file = input.files!.first;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;

  final buffer = reader.result as ByteBuffer;
  return XFile.fromData(
    buffer.asUint8List(),
    name: file.name,
    mimeType: file.type,
  );
}

Future<bool> isWebCameraSupportedImpl() async {
  return html.window.isSecureContext && html.window.navigator.mediaDevices != null;
}
