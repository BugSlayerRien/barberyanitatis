import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App-wide cache of the real device orientation reported by the camera plugin.
///
/// Why this exists: `CameraController.value.deviceOrientation` cannot be
/// trusted. `CameraValue.uninitialized()` seeds it to
/// [DeviceOrientation.portraitUp], and the Android plugin only pushes an
/// orientation event when the orientation *changes* — `handleOrientationChange`
/// compares against a `lastOrientation` field that lives on the plugin's
/// DeviceOrientationManager for the life of the activity, not per controller.
///
/// So a controller created while the device is already landscape, in a session
/// where a camera has been opened before, never receives an event and keeps
/// reporting `portraitUp` forever. Feeding that into the ML Kit rotation maths
/// puts the input image 90° out and face detection returns nothing — which is
/// exactly why the landscape kiosk scanner found no faces while the
/// portrait-locked customer scanner worked: portrait's stale default happened
/// to be the correct answer.
///
/// Subscribing once at startup means the first camera open of the session — the
/// one broadcast that is always delivered, because `lastOrientation` starts
/// null — is captured and retained for every controller afterwards.
class DeviceOrientationTracker {
  DeviceOrientationTracker._();

  static StreamSubscription<DeviceOrientationChangedEvent>? _subscription;
  static DeviceOrientation? _latest;

  /// Last orientation the platform actually reported, or null if it never has.
  static DeviceOrientation? get latest => _latest;

  /// Safe to call more than once; later calls are no-ops.
  static void start() {
    if (kIsWeb || _subscription != null) {
      return;
    }
    try {
      _subscription =
          CameraPlatform.instance.onDeviceOrientationChanged().listen((event) {
        _latest = event.orientation;
        debugPrint('[DeviceOrientation] platform reported ${event.orientation}');
      }, onError: (Object error) {
        debugPrint('[DeviceOrientation] stream error: $error');
      });
    } catch (e) {
      // Desktop and unsupported platforms have no camera implementation; the
      // scanner falls back to the controller's own value there.
      debugPrint('[DeviceOrientation] tracker unavailable: $e');
    }
  }

  @visibleForTesting
  static void debugSet(DeviceOrientation? orientation) {
    _latest = orientation;
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
