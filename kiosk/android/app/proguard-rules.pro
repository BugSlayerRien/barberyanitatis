# R8 keep rules for the AI face scanner.
#
# Flutter's Gradle plugin turns on R8 shrinking for --release builds by itself,
# so these rules apply to every production APK whether or not minifyEnabled is
# written out. Without them the scanner fails on every frame in release while
# working fine under `flutter run`.

# --- ML Kit face detection -------------------------------------------------
#
# InputImageConverter is only ever reached over the Flutter method channel, so
# R8 sees no Java caller, inlines it into FaceDetector.handleDetection and
# strips the class (it shows up as R8$$REMOVED$$CLASS in mapping.txt). In doing
# so it rewrites Objects.requireNonNull(x) into the cheaper x.getClass() null
# check -- which is exactly the
#   "Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()'
#    on a null object reference"
# NullPointerException that surfaced as InputImageConverterError on every frame.
# The Flutter plugin side (commons holds InputImageConverter; face_detection
# holds the MethodCallHandler both are reached through).
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }

# The ML Kit SDK and the bundled native face pipeline underneath it. The
# gms.vision.face tree is the detector itself -- without this R8 removes
# classes like com.google.android.gms.vision.face.mlkit.zze.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.vision.**

# --- camera_android ---------------------------------------------------------
#
# ImageStreamReader.latestImageBufferHardReference is assigned but never read,
# so R8 removes it as dead. The plugin's own comment says that field is the
# only thing keeping a frame alive between handler.post() and run() -- without
# it frames hang off a bare WeakReference and can be collected mid-flight.
-keep class io.flutter.plugins.camera.** { *; }
-keepclassmembers class io.flutter.plugins.camera.media.ImageStreamReader { *; }

# --- Platform-channel surface ----------------------------------------------
# Plugin registration is reflective; Flutter's bundled rules allow shrinking of
# these, which is fine for most plugins but not for ones we call every frame.
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel$MethodCallHandler *;
}
