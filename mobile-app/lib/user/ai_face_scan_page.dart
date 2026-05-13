import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'api_config.dart';
import 'ai_funnel_service.dart';
import '../services/calibration_api.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'suggested_appointment_page.dart';
import 'ai_chatbot_page.dart';
import 'dashboard_page.dart';
import 'booking_guard.dart';
import 'haircuts_list_page.dart';
import '../main.dart';
import 'scanner/overlay_models.dart';
import 'scanner/attachment_engine.dart';
import 'scanner/face_detector_service_stub.dart'
    if (dart.library.io) 'scanner/face_detector_service_mobile.dart';
import 'user_session.dart';
import 'web_camera_view_stub.dart'
    if (dart.library.html) 'web_camera_view.dart';
import 'widgets/app_top_bar.dart';

class AiFaceScanPage extends StatefulWidget {
  final Map<String, dynamic>? presetRecommendation;
  final bool previewOnly;

  const AiFaceScanPage({super.key, this.presetRecommendation, this.previewOnly = false});

  @override
  State<AiFaceScanPage> createState() => _AiFaceScanPageState();
}

class _AiFaceScanPageState extends State<AiFaceScanPage>
    with WidgetsBindingObserver, RouteAware {
  final FaceDetectorService _detector = FaceDetectorService();
  final WebCameraController _webCamera = WebCameraController();
  late final AttachmentEngine _attachmentEngine;

  CameraController? _camera;
  bool _busy = false;
  bool _loadingRecommendations = false;
  bool _initialized = false;
  bool _webCameraReady = false;
  Rect? _normalizedFaceRect;
  double? _headYaw;
  double? _headRoll;
  double? _foreheadAnchorY;
  double? _eyeMidX;
  double? _eyeDistanceNorm;
  double? _webVideoAspect;
  List<double>? _faceTransformMatrix;
  bool _showCalibrationMode = false;
  bool _controlsSheetExpanded = false;
  final ScrollController _pageScrollController = ScrollController();
  UserCalibration _activeCalibration = UserCalibration.defaults();
  UserCalibration _tempCalibration = UserCalibration.defaults();
  Rect? _smoothedFaceRect;
  double? _smoothedHeadYaw;
  double? _smoothedHeadRoll;
  double? _smoothedForeheadAnchorY;
  double? _smoothedEyeMidX;
  double? _smoothedEyeDistanceNorm;
  Rect? _lastStableFaceRect;
  Rect? _lastCenteredFaceRect;
  DateTime? _overlayHoldUntil;

  String _faceShape = 'Oval';
  String _hairTexture = 'Straight';
  String _status = 'Center your face in the guide.';

  final List<Map<String, dynamic>> _recommendations = [];
  int _selectedIndex = 0;
  bool _webTrackingAttached = false;
  bool _autoProcessingStarted = false;
  bool _isSettingUp = false;
  bool _isRouteSubscribed = false;
  DateTime? _lastRecommendationFetchAt;
  DateTime? _faceSeenAt;
  DateTime? _faceMissingAt;
  int _stableFaceFrames = 0;
  bool _faceSessionReady = false;
  bool _calibrationSyncInFlight = false;
  DateTime? _lastCalibrationSyncAt;
  bool _bookingInFlight = false;

  static const double _rectSmoothingAlpha = 0.58;
  static const double _angleSmoothingAlpha = 0.28;
  static const double _anchorSmoothingAlpha = 0.52;
  static const Duration _faceStableDuration = Duration(milliseconds: 700);
  static const Duration _faceMissingGrace = Duration(milliseconds: 1200);
  static const Duration _overlayHoldDuration = Duration(milliseconds: 800);
  static const Duration _overlayHoldAfterProcessDuration =
      Duration(milliseconds: 2200);
  static const Duration _recommendationCooldown = Duration(seconds: 10);
  static const Duration _calibrationSyncCooldown = Duration(seconds: 2);
  static const int _minimumStableFrames = 4;
  static const bool _deterministicTestingMode = false;
  static const double _trackingJumpThreshold = 0.13;
  static const double _minFaceAreaForOverlay = 0.042;
  static const double _maxFaceAreaForOverlayMobile = 0.28;
  static const double _maxFaceAreaForOverlayWeb = 0.20;
  static const double _overlayBaseOpacity = 1.0;
  static const double _hairBlurSigma = 5.0;
  static const double _hairCoverTopOpacity = 0.34;
  static const double _hairCoverMidOpacity = 0.20;
  static const double _hairCoverBottomOpacity = 0.08;
  static const double _hairCoverRadialOpacity = 0.14;
  static const double _hairEdgeOpacity = 0.12;
  static const bool _showOverlayDebug = false;
  static const OverlayImageSet _sampleImageOverlay = OverlayImageSet(
    front: 'assets/images/overlays/blowout_taper/blowout_taper_front.png',
    left: 'assets/images/overlays/blowout_taper/blowout_taper_left.png',
    right: 'assets/images/overlays/blowout_taper/blowout_taper_right.png',
  );
  static const String _sampleHairModel3d = 'assets/models/blowouttaper.glb';
  static const bool _enable3DHairOverlay = false;

  static const Map<String, OverlayImageSet> _styleOverlayImages = {
    'blowout taper': OverlayImageSet(
      front: 'assets/images/overlays/blowout_taper/blowout_taper_front.png',
      left: 'assets/images/overlays/blowout_taper/blowout_taper_left.png',
      right: 'assets/images/overlays/blowout_taper/blowout_taper_right.png',
    ),
    'buzz cut': OverlayImageSet(
      front: 'assets/images/overlays/buzz_cut/buzz_cut_front.png',
      left: 'assets/images/overlays/buzz_cut/buzz_cut_left.png',
      right: 'assets/images/overlays/buzz_cut/buzz_cut_right.png',
    ),
    'curly taper fade': OverlayImageSet(
      front: 'assets/images/overlays/curly_taper/curly_taper_fade_front.png',
      left: 'assets/images/overlays/curly_taper/curly_taper_fade_left.png',
      right: 'assets/images/overlays/curly_taper/curly_taper_fade_right.png',
    ),
    'low fade': OverlayImageSet(
      front: 'assets/images/overlays/low_fade/low_fade_front.png',
      left: 'assets/images/overlays/low_fade/low_fade_left.png',
      right: 'assets/images/overlays/low_fade/low_fade_right.png',
    ),
    'french crop': OverlayImageSet(
      front: 'assets/images/overlays/french_crop/french_crop_front.png',
      left: 'assets/images/overlays/french_crop/french_crop_left.png',
      right: 'assets/images/overlays/french_crop/french_crop_right.png',
    ),
    'textured crop': OverlayImageSet(
      front: 'assets/images/overlays/textured_crop/textured_crop_front.png',
      left: 'assets/images/overlays/textured_crop/textured_crop_left.png',
      right: 'assets/images/overlays/textured_crop/textured_crop_right.png',
    ),
    'curly modern mullet': OverlayImageSet(
      front: 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_front.png',
      left: 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_left.png',
      right: 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_right.png',
    ),
  };

  static const Map<String, OverlayCalibration> _styleCalibration = {
    'blowout taper': OverlayCalibration(
      widthScale: 1.18,
      heightScale: 1.28,
      xOffset: 0.00,
      yOffset: -0.22,
      hairClipFactor: 0.76,
      visualScale: 1.18,
      yawShiftFactor: 0.06),
    'buzz cut': OverlayCalibration(
      widthScale: 0.96,
      heightScale: 0.94,
      xOffset: 0.00,
      yOffset: -0.08,
      hairClipFactor: 0.85,
      visualScale: 0.98,
      yawShiftFactor: 0.03),
    'low fade': OverlayCalibration(
      widthScale: 1.04,
      heightScale: 1.06,
      xOffset: 0.00,
      yOffset: -0.16,
      hairClipFactor: 0.80,
      visualScale: 1.04,
      yawShiftFactor: 0.05),
    'french crop': OverlayCalibration(
      widthScale: 1.06,
      heightScale: 1.08,
      xOffset: 0.00,
      yOffset: -0.18,
      hairClipFactor: 0.78,
      visualScale: 1.06,
      yawShiftFactor: 0.05),
    'curly taper fade': OverlayCalibration(
      widthScale: 1.10,
      heightScale: 1.12,
      xOffset: 0.00,
      yOffset: -0.14,
      hairClipFactor: 0.80,
      visualScale: 1.06,
      yawShiftFactor: 0.04),
    'textured crop': OverlayCalibration(
      widthScale: 1.02,
      heightScale: 1.04,
      xOffset: 0.00,
      yOffset: -0.12,
      hairClipFactor: 0.82,
      visualScale: 1.03,
      yawShiftFactor: 0.04),
    'curly modern mullet': OverlayCalibration(
      widthScale: 1.12,
      heightScale: 1.18,
      xOffset: 0.00,
      yOffset: -0.16,
      hairClipFactor: 0.79,
      visualScale: 1.08,
      yawShiftFactor: 0.05),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachmentEngine = createAttachmentEngine(AttachmentEngineMode.auto);
    _applyPresetRecommendation();
    _loadCalibration();
    _setup();
  }

  Future<void> _loadCalibration() async {
    final loaded = await UserSession.loadUserCalibration();
    if (!mounted) return;
    setState(() {
      _activeCalibration = loaded ?? UserCalibration.defaults();
      _tempCalibration = _activeCalibration;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isRouteSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
      _isRouteSubscribed = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _releaseScannerResources();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _resumeScannerResources();
    }
  }

  @override
  void didPushNext() {
    _releaseScannerResources();
  }

  @override
  void didPopNext() {
    _resumeScannerResources();
  }

  Future<void> _releaseScannerResources() async {
    if (kIsWeb) {
      await _webCamera.stop();
      if (mounted) {
        setState(() {
          _webCameraReady = false;
        });
      }
      return;
    }

    final camera = _camera;
    if (camera == null) {
      return;
    }

    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } catch (_) {}

    await camera.dispose();
    if (mounted) {
      setState(() {
        _camera = null;
      });
    } else {
      _camera = null;
    }
  }

  void _resumeScannerResources() {
    if (_isSettingUp) {
      return;
    }
    _setup();
  }

  Future<void> _setup() async {
    if (_isSettingUp) {
      return;
    }
    _isSettingUp = true;

    try {
      debugPrint('[AiFaceScan] Initializing face detector...');
      await _detector.initialize();
      debugPrint('[AiFaceScan] Face detector initialized successfully');
      
      if (kIsWeb) {
        if (_webCameraReady) {
          return;
        }
        final started = await _webCamera.start();
        if (!_webTrackingAttached) {
          _webCamera.tracking.addListener(_onWebTrackingChanged);
          _webTrackingAttached = true;
        }
        if (!mounted) return;
        setState(() {
          _initialized = true;
          _webCameraReady = started;
          _status = started
              ? 'Camera is ready. We are tracking your face live.'
              : 'Camera is blocked. Please allow browser camera access.';
        });
        return;
      }

      if (_camera != null && _camera!.value.isInitialized) {
        debugPrint('[AiFaceScan] Camera already initialized, skipping...');
        return;
      }

      debugPrint('[AiFaceScan] Getting available cameras...');
      final cameras = await availableCameras();
      debugPrint('[AiFaceScan] Found ${cameras.length} cameras');
      
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      debugPrint('[AiFaceScan] Initializing camera controller...');
      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      debugPrint('[AiFaceScan] Camera controller initialized successfully');
      
      debugPrint('[AiFaceScan] Starting image stream...');
      await controller.startImageStream((image) async {
        if (_busy || !mounted) return;
        _busy = true;
        try {
          final frame = await _detector.processFrame(
            image,
            sensorOrientation: controller.description.sensorOrientation,
          );
          if (!mounted) return;
          if (frame == null) {
            final now = DateTime.now();
            _faceMissingAt ??= now;
            final shouldReset =
                now.difference(_faceMissingAt!) >= _faceMissingGrace;

            setState(() {
              if (shouldReset) {
                _normalizedFaceRect = null;
                _smoothedFaceRect = null;
                _smoothedHeadYaw = null;
                _smoothedHeadRoll = null;
                _headYaw = null;
                _headRoll = null;
                _foreheadAnchorY = null;
                _eyeMidX = null;
                _eyeDistanceNorm = null;
                _webVideoAspect = null;
                _faceTransformMatrix = null;
                _autoProcessingStarted = false;
                _faceSeenAt = null;
                _stableFaceFrames = 0;
                _faceSessionReady = false;
                _smoothedForeheadAnchorY = null;
                _smoothedEyeMidX = null;
                _smoothedEyeDistanceNorm = null;
                _lastStableFaceRect = null;
                _overlayHoldUntil = null;
                _status =
                    'We cannot see your face yet. Face the camera in good light.';
              } else {
                _status = 'Hold still. We are finding your face again.';
              }
            });
          } else {
            final now = DateTime.now();
            _faceSeenAt ??= now;
            _faceMissingAt = null;
            _stableFaceFrames += 1;
            final normalized = Rect.fromLTWH(
              (frame.boundingBox.left / frame.imageSize.width).clamp(0.0, 1.0),
              (frame.boundingBox.top / frame.imageSize.height).clamp(0.0, 1.0),
              (frame.boundingBox.width / frame.imageSize.width).clamp(0.0, 1.0),
              (frame.boundingBox.height / frame.imageSize.height)
                  .clamp(0.0, 1.0),
            );
            final stableWindowReached =
              now.difference(_faceSeenAt!) >= _faceStableDuration;
            final centeredInGuide = _isFaceInsideScanGuide(normalized);
            _faceSessionReady = stableWindowReached &&
              _stableFaceFrames >= _minimumStableFrames &&
              centeredInGuide;
            final stabilizedInput =
              _stabilizeIncomingRect(_smoothedFaceRect, normalized);
            final smoothedRect =
              _smoothRect(_smoothedFaceRect, stabilizedInput, _rectSmoothingAlpha);
            final smoothedYaw = _smoothValue(
                _smoothedHeadYaw, frame.headEulerAngleY, _angleSmoothingAlpha);
            final smoothedRoll = _smoothValue(
                _smoothedHeadRoll, frame.headEulerAngleZ, _angleSmoothingAlpha);
            final inferredForeheadAnchor =
                (smoothedRect.top + (smoothedRect.height * 0.18))
                    .clamp(0.0, 1.0);
            final smoothedForehead = _smoothValue(_smoothedForeheadAnchorY,
                inferredForeheadAnchor, _anchorSmoothingAlpha);
            final inferredEyeMidX =
              (smoothedRect.left + (smoothedRect.width * 0.5)).clamp(0.0, 1.0);
            final inferredEyeDistance =
              (smoothedRect.width * 0.42).clamp(0.04, 0.65);
            final smoothedEyeMidX = _smoothValue(
              _smoothedEyeMidX, inferredEyeMidX, _anchorSmoothingAlpha);
            final smoothedEyeDistance = _smoothValue(_smoothedEyeDistanceNorm,
              inferredEyeDistance, _anchorSmoothingAlpha);
            final inferred =
                _inferFaceShape(smoothedRect.width, smoothedRect.height);
            setState(() {
              _normalizedFaceRect = smoothedRect;
              _headYaw = smoothedYaw;
              _headRoll = smoothedRoll;
              _foreheadAnchorY = smoothedForehead;
              _eyeMidX = smoothedEyeMidX;
              _eyeDistanceNorm = smoothedEyeDistance;
              _smoothedFaceRect = smoothedRect;
              _smoothedHeadYaw = smoothedYaw;
              _smoothedHeadRoll = smoothedRoll;
              _smoothedForeheadAnchorY = smoothedForehead;
              _smoothedEyeMidX = smoothedEyeMidX;
              _smoothedEyeDistanceNorm = smoothedEyeDistance;
              _faceShape = inferred;
              if (_isLikelyStableFace(smoothedRect)) {
                _lastStableFaceRect = smoothedRect;
                _overlayHoldUntil = now.add(_overlayHoldDuration);
                if (smoothedYaw.abs() < 8 && centeredInGuide) {
                  _lastCenteredFaceRect = smoothedRect;
                }
              }
                _status = _faceSessionReady
                  ? 'Face is centered and steady. Starting automatically...'
                  : (centeredInGuide
                      ? 'Keep still inside the guide...'
                      : 'Move your face into the guide marks.');
            });

            if (_shouldAutoFetchRecommendations()) {
              _triggerAutoFetch(isWeb: false);
            }
            _maybeSyncServerCalibration();
          }
        } catch (e, st) {
          debugPrint('[Face Detector Error] $e\nStackTrace: $st');
          if (!mounted) return;
          setState(() {
            _status = 'Camera stream error. Retrying...';
          });
        } finally {
          _busy = false;
        }
      });

      if (!mounted) return;
      setState(() {
        _camera = controller;
        _initialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _status = 'Failed to initialize camera scanner: $e';
      });
    } finally {
      _isSettingUp = false;
    }
  }

  void _onWebTrackingChanged() {
    if (!mounted) return;

    final t = _webCamera.tracking.value;
    final rect = t.faceRect;
    if (rect == null) {
      final now = DateTime.now();
      _faceMissingAt ??= now;
      final shouldReset = now.difference(_faceMissingAt!) >= _faceMissingGrace;

      setState(() {
        if (shouldReset) {
          _normalizedFaceRect = null;
          _smoothedFaceRect = null;
          _smoothedHeadYaw = null;
          _smoothedHeadRoll = null;
          _autoProcessingStarted = false;
          _headYaw = null;
          _headRoll = null;
          _foreheadAnchorY = null;
          _eyeMidX = null;
          _eyeDistanceNorm = null;
          _webVideoAspect = null;
          _faceTransformMatrix = null;
          _faceSeenAt = null;
          _stableFaceFrames = 0;
          _faceSessionReady = false;
          _smoothedForeheadAnchorY = null;
          _smoothedEyeMidX = null;
          _smoothedEyeDistanceNorm = null;
          _lastStableFaceRect = null;
          _overlayHoldUntil = null;
          _status = 'We cannot see your face yet. Center your face in the guide.';
        } else {
          _status = 'Hold still. We are finding your face again.';
        }
      });
      return;
    }

    final now = DateTime.now();
    _faceSeenAt ??= now;
    _faceMissingAt = null;
    _stableFaceFrames += 1;
    final stableWindowReached =
      now.difference(_faceSeenAt!) >= _faceStableDuration;
    final centeredInGuide = _isFaceInsideScanGuide(rect);
    _faceSessionReady = stableWindowReached &&
      _stableFaceFrames >= _minimumStableFrames &&
      centeredInGuide;

    final smoothedRect = _smoothRect(_smoothedFaceRect,
      _stabilizeIncomingRect(_smoothedFaceRect, rect), _rectSmoothingAlpha);
    final smoothedYaw =
        _smoothValue(_smoothedHeadYaw, t.headYaw, _angleSmoothingAlpha);
    final smoothedRoll =
        _smoothValue(_smoothedHeadRoll, t.headRoll, _angleSmoothingAlpha);
    final eyeAnchor = ((t.eyeMidY ?? (rect.top + (rect.height * 0.36))) -
        (rect.height * 0.16))
      .clamp(0.0, 1.0);
    final smoothedForehead = _smoothValue(
        _smoothedForeheadAnchorY, eyeAnchor, _anchorSmoothingAlpha);
    final eyeMidX =
      (t.eyeMidX ?? (rect.left + (rect.width * 0.5))).clamp(0.0, 1.0);
    final eyeDistance =
      (t.eyeDistanceNorm ?? (rect.width * 0.42)).clamp(0.04, 0.65);
    final smoothedEyeMidX =
      _smoothValue(_smoothedEyeMidX, eyeMidX, _anchorSmoothingAlpha);
    final smoothedEyeDistance = _smoothValue(
      _smoothedEyeDistanceNorm, eyeDistance, _anchorSmoothingAlpha);
    final videoAspect = t.videoAspect;
    final transformMatrix = t.faceTransformMatrix;
    final inferred = _inferFaceShape(smoothedRect.width, smoothedRect.height);

    setState(() {
      _normalizedFaceRect = smoothedRect;
      _headYaw = smoothedYaw;
      _headRoll = smoothedRoll;
      _foreheadAnchorY = smoothedForehead;
      _eyeMidX = smoothedEyeMidX;
      _eyeDistanceNorm = smoothedEyeDistance;
      _webVideoAspect = videoAspect;
      _faceTransformMatrix = transformMatrix;
      _smoothedFaceRect = smoothedRect;
      _smoothedHeadYaw = smoothedYaw;
      _smoothedHeadRoll = smoothedRoll;
      _smoothedForeheadAnchorY = smoothedForehead;
      _smoothedEyeMidX = smoothedEyeMidX;
      _smoothedEyeDistanceNorm = smoothedEyeDistance;
      _faceShape = inferred;
      if (_isLikelyStableFace(smoothedRect)) {
        _lastStableFaceRect = smoothedRect;
        _overlayHoldUntil = now.add(_overlayHoldDuration);
        if (smoothedYaw.abs() < 8 && centeredInGuide) {
          _lastCenteredFaceRect = smoothedRect;
        }
      }
        _status = _faceSessionReady
          ? 'Face is centered and steady. Starting automatically...'
          : (centeredInGuide
              ? 'Keep still inside the guide...'
              : 'Move your face into the guide marks.');
    });

    if (_shouldAutoFetchRecommendations()) {
      _triggerAutoFetch(isWeb: true);
    }
    _maybeSyncServerCalibration();
  }

  bool _shouldAutoFetchRecommendations() {
    if (widget.previewOnly) {
      return false;
    }
    if (_normalizedFaceRect == null || !_faceSessionReady) {
      if (_normalizedFaceRect == null) {
        return false;
      }
      if (!_isLikelyStableFace(_normalizedFaceRect!)) {
        return false;
      }
    }
    if (!_isFaceInsideScanGuide(_normalizedFaceRect!)) {
      if (!_isLikelyStableFace(_normalizedFaceRect!)) {
        return false;
      }
    }
    if (_loadingRecommendations || _autoProcessingStarted) {
      return false;
    }
    final lastFetch = _lastRecommendationFetchAt;
    if (lastFetch == null) {
      return true;
    }
    return DateTime.now().difference(lastFetch) >= _recommendationCooldown;
  }

  void _triggerAutoFetch({required bool isWeb}) {
    _autoProcessingStarted = true;
    if (isWeb) {
      _fetchRecommendationsWeb(showToastOnError: false, autoTriggered: true);
    } else {
      _fetchRecommendations(autoTriggered: true);
    }
  }

  bool _isFaceInsideScanGuide(Rect face) {
    final center = face.center;
    final centerOffsetX = (center.dx - 0.5).abs();
    final centerOffsetY = (center.dy - 0.5).abs();
    final area = face.width * face.height;
    return centerOffsetX <= 0.14 &&
        centerOffsetY <= 0.16 &&
        area >= 0.05 &&
        area <= 0.24;
  }

  void _maybeSyncServerCalibration() {
    if (!_faceSessionReady || _normalizedFaceRect == null || !mounted) {
      return;
    }
    if (_calibrationSyncInFlight) {
      return;
    }
    final lastSync = _lastCalibrationSyncAt;
    if (lastSync != null &&
        DateTime.now().difference(lastSync) < _calibrationSyncCooldown) {
      return;
    }

    _syncCalibrationWithServer();
  }

  Future<void> _syncCalibrationWithServer() async {
    final face = _normalizedFaceRect;
    if (face == null || !mounted) {
      return;
    }

    _calibrationSyncInFlight = true;
    try {
      final selected = _recommendations.isNotEmpty
          ? _recommendations[
              _selectedIndex.clamp(0, _recommendations.length - 1)]
          : null;

      final styleId = (selected?['style_code']?.toString() ??
              selected?['variant_id']?.toString() ??
              selected?['style_name']?.toString() ??
              selected?['styleName']?.toString() ??
              'default')
          .trim();

      final styleFamily = _inferStyleFamily(selected);
      final platform = kIsWeb
          ? 'web'
          : switch (defaultTargetPlatform) {
              TargetPlatform.iOS => 'ios',
              _ => 'android',
            };

      final calibration = await CalibrationApi.computeCalibration(
        faceData: {
          'faceRect': {
            'x': face.left,
            'y': face.top,
            'width': face.width,
            'height': face.height,
          },
          'headYaw': _headYaw ?? 0,
          'headRoll': _headRoll ?? 0,
          'eyeMidX': _eyeMidX ?? (face.left + (face.width * 0.5)),
          'eyeDistanceNorm': _eyeDistanceNorm ?? (face.width * 0.42),
          'foreheadAnchorY': _foreheadAnchorY ??
              (face.top + (face.height * 0.18)),
          'videoAspect': _webVideoAspect ??
              (MediaQuery.of(context).size.width /
                  MediaQuery.of(context).size.height),
          'platform': platform,
        },
        styleId: styleId,
        styleFamily: styleFamily,
      );

      if (calibration == null || !mounted) {
        return;
      }

      final confidence =
          (calibration['confidence'] as num?)?.toDouble() ?? 1.0;
      if (confidence < 0.55) {
        return;
      }

      double toDouble(dynamic value, double fallback) {
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString() ?? '') ?? fallback;
      }

      final merged = await UserSession.mergeServerCalibration(
        offsetX: toDouble(calibration['offsetX'], _activeCalibration.offsetX),
        offsetY: toDouble(calibration['offsetY'], _activeCalibration.offsetY),
        scale: toDouble(calibration['scale'], _activeCalibration.scale),
        foreheadOffset: toDouble(
          calibration['foreheadOffset'],
          _activeCalibration.foreheadOffset,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _activeCalibration = merged;
        if (!_showCalibrationMode) {
          _tempCalibration = merged;
        }
      });

    } catch (_) {
    } finally {
      _calibrationSyncInFlight = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _inferStyleFamily(Map<String, dynamic>? recommendation) {

        _lastCalibrationSyncAt = DateTime.now();
    final styleName = (recommendation?['style_name']?.toString() ??
            recommendation?['styleName']?.toString() ??
            '')
        .toLowerCase();
    if (styleName.contains('undercut')) {
      return 'undercut';
    }
    if (styleName.contains('fade')) {
      return 'fade';
    }
    if (styleName.contains('long')) {
      return 'long_hair';
    }
    return 'default';
  }

  String _inferFaceShape(double w, double h) {
    if (h <= 0) return 'Oval';
    final ratio = w / h;
    if (ratio > 0.95) return 'Round';
    if (ratio < 0.70) return 'Oblong';
    if (ratio > 0.84) return 'Square';
    return 'Oval';
  }

  Future<void> _fetchRecommendations({bool autoTriggered = false}) async {
    if (autoTriggered) {
      _autoProcessingStarted = true;
    }

    if (widget.presetRecommendation != null && autoTriggered) {
      return;
    }

    if (kIsWeb) {
      await _fetchRecommendationsWeb(autoTriggered: autoTriggered);
      return;
    }

    if (_normalizedFaceRect == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please center your face first.')),
      );
      return;
    }

    if (_deterministicTestingMode) {
      await _applyDeterministicRecommendation();
      return;
    }

    setState(() => _loadingRecommendations = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'rankByFeatures',
          'faceShape': _faceShape,
          'hairTexture': _hairTexture,
          'hairDensity': UserSession.lastScan?['hairDensity']?.toString(),
        }),
      );

      final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        throw Exception(
            data['error']?.toString() ?? 'Failed to fetch recommendations');
      }

      var recommendations = (data['recommendations'] as List<dynamic>? ??
              data['variants'] as List<dynamic>? ??
              [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final libraryFallback = await _loadLibraryFallback();
      recommendations = _mergeRecommendations(recommendations, libraryFallback);

      final ranked = _rankRecommendations(recommendations);
      if (!mounted) return;
      setState(() {
        _recommendations
          ..clear()
          ..addAll(_topThreeRecommendations(ranked));
        _selectedIndex = 0;
        _markOverlayReadyAfterProcessing();
        _status = 'Suggestions are ready. Pick one to preview.';
      });

      UserSession.lastScan = {
        'faceShape': _faceShape,
        'hairTexture': _hairTexture,
        'headYaw': _headYaw,
      };
      UserSession.lastRecommendations = _recommendations;
      UserSession.hasRecentRecommendations = true;

      UserSession.activeScanSessionId = null;

      await AiFunnelService.trackScan(
        scanSessionId: UserSession.ensureScanSessionId(),
        userId: UserSession.userId,
        faceShape: _faceShape,
        hairTexture: _hairTexture,
        hairDensity: null,
        hairLength: null,
        recommendationCount: _recommendations.length,
      );

      _lastRecommendationFetchAt = DateTime.now();
    } catch (e) {
      if (autoTriggered) {
        _autoProcessingStarted = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load recommendations: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingRecommendations = false);
      }
    }
  }

  Future<void> _fetchRecommendationsWeb(
      {bool showToastOnError = true, bool autoTriggered = false}) async {
    if (autoTriggered) {
      _autoProcessingStarted = true;
    }

    if (widget.presetRecommendation != null && autoTriggered) {
      return;
    }

    if (_normalizedFaceRect == null) {
      if (showToastOnError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Center your face first so we can continue.')),
        );
      }
      return;
    }

    if (!_webCameraReady) {
      if (showToastOnError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Camera is not ready yet. Please allow camera access.')),
        );
      }
      return;
    }

    if (_deterministicTestingMode) {
      await _applyDeterministicRecommendation();
      return;
    }

    setState(() => _loadingRecommendations = true);
    try {
      if (mounted) {
        setState(() {
          _status = 'Updating haircut suggestions...';
        });
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'rankByFeatures',
          'faceShape': _faceShape,
          'hairTexture': _hairTexture,
          'hairDensity': UserSession.lastScan?['hairDensity']?.toString(),
        }),
      );

      final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        throw Exception(data['error']?.toString() ??
            'Failed to fetch live recommendations');
      }

      var recommendations = (data['recommendations'] as List<dynamic>? ??
              data['variants'] as List<dynamic>? ??
              [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final libraryFallback = await _loadLibraryFallback();
      recommendations = _mergeRecommendations(recommendations, libraryFallback);

      if (recommendations.isEmpty) {
        throw Exception('No available hairstyle variants yet');
      }

      final ranked = _rankRecommendations(recommendations);

      if (!mounted) return;
      setState(() {
        _recommendations
          ..clear()
          ..addAll(_topThreeRecommendations(ranked));
        _selectedIndex = 0;
        _markOverlayReadyAfterProcessing();
        _status =
          'Suggestions are ready. Hair preview now uses your selected style.';
      });

      UserSession.lastScan = {
        'faceShape': _faceShape,
        'hairTexture': _hairTexture,
      };
      UserSession.lastRecommendations = _recommendations;
      UserSession.hasRecentRecommendations = true;

      UserSession.activeScanSessionId = null;

      await AiFunnelService.trackScan(
        scanSessionId: UserSession.ensureScanSessionId(),
        userId: UserSession.userId,
        faceShape: _faceShape,
        hairTexture: _hairTexture,
        hairDensity: null,
        hairLength: null,
        recommendationCount: _recommendations.length,
      );

      _lastRecommendationFetchAt = DateTime.now();
    } catch (e) {
      if (autoTriggered) {
        _autoProcessingStarted = false;
      }
      if (!mounted) return;
      setState(() {
        _status = 'Could not update suggestions. Please try again.';
      });
      if (showToastOnError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Live sync failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingRecommendations = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadLibraryFallback() async {
    debugPrint('[AiFaceScan] Loading hairstyle library from ${ApiConfig.baseUrl}/haircuts.php');
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/haircuts.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'listLibrary'}),
    );

    debugPrint('[AiFaceScan] Library response status=${response.statusCode} bytes=${response.bodyBytes.length}');

    if (response.statusCode != 200 || response.body.isEmpty) {
      debugPrint('[AiFaceScan] Library API failed or returned empty payload (API-only mode)');
      return <Map<String, dynamic>>[];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final styles = (data['hairstyles'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (styles.isEmpty) {
      debugPrint('[AiFaceScan] Library API returned 0 hairstyles (API-only mode)');
      return <Map<String, dynamic>>[];
    }

    debugPrint('[AiFaceScan] Library API returned ${styles.length} hairstyles: ${styles.map((style) => style['style_name'] ?? style['styleName'] ?? 'unknown').take(12).join(', ')}');
    return styles;
  }

  Widget _buildHairOnlyOverlayModel(
      {required OverlayCalibration calibration,
      required Map<String, dynamic>? recommendation}) {
    if (_shouldUse3DModel(recommendation)) {
      return _buildHair3DOverlayModel(calibration: calibration);
    }

    final yaw = (_headYaw ?? 0).clamp(-60.0, 60.0);
    final yawAbsNorm = (yaw.abs() / 34.0).clamp(0.0, 1.0);
    final frontOpacity = (1.0 - (yawAbsNorm * 0.45)).clamp(0.60, 1.0);
    final sideOpacity = ((yawAbsNorm - 0.12) / 0.38).clamp(0.0, 1.0);
    final styleName = (recommendation?['style_name']?.toString() ??
            recommendation?['styleName']?.toString() ??
            '')
        .trim();

    // Resolve overlay images based on style name from recommendation
    final overlayImageSet = _resolveOverlayImageSet(recommendation);
    final frontImage = overlayImageSet.front;
    final sideImage = yaw >= 0 ? overlayImageSet.right : overlayImageSet.left;
    final frontAsset = _assetPath(frontImage);
    final sideAsset = _assetPath(sideImage);
    
    debugPrint('[AiFaceScan] === Overlay Rendering Debug ===');
    debugPrint('[AiFaceScan] Recommendation keys: ${recommendation?.keys.toList()}');
    debugPrint('[AiFaceScan] Full recommendation: $recommendation');
    debugPrint('[AiFaceScan] styleName="$styleName" yaw=${yaw.toStringAsFixed(1)}');
    debugPrint('[AiFaceScan] frontImage=$frontImage');
    debugPrint('[AiFaceScan] sideImage=$sideImage');
    debugPrint('[AiFaceScan] frontOpacity=$frontOpacity sideOpacity=$sideOpacity');
    debugPrint('[AiFaceScan] === End Debug ===');
    final sideAlignment = Alignment.center;
    final sideInset = (0.50 - (yawAbsNorm * 0.06)).clamp(0.40, 0.52).toDouble();
    final sideStretchX = (1.0 + (yawAbsNorm * 0.20)).clamp(1.0, 1.24).toDouble();
    final sideStretchY = (1.0 + (yawAbsNorm * 0.06)).clamp(1.0, 1.10).toDouble();
    const sideNudgeX = 0.0;
    const sideFadeBegin = Alignment.centerLeft;
    const sideFadeEnd = Alignment.centerRight;

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: calibration.hairClipFactor,
        child: SizedBox.expand(
          child: Transform.scale(
            scale: calibration.visualScale,
            alignment: Alignment.topCenter,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: frontOpacity,
                  child: Image.asset(
                    frontAsset,
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('[AiFaceScan] Failed to load front overlay asset: $frontImage | $error');
                      return const ColoredBox(color: Colors.transparent);
                    },
                  ),
                ),
                Opacity(
                  opacity: sideOpacity,
                  child: Align(
                    alignment: sideAlignment,
                    child: ClipRect(
                      child: Align(
                        alignment: sideAlignment,
                        widthFactor: sideInset,
                        child: ShaderMask(
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: sideFadeBegin,
                              end: sideFadeEnd,
                              colors: const [
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.62, 1.0],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: Transform.translate(
                            offset: Offset(sideNudgeX, 0),
                            child: Transform.scale(
                              scaleX: sideStretchX,
                              scaleY: sideStretchY,
                              alignment: sideAlignment,
                              child: Image.asset(
                                sideAsset,
                                fit: BoxFit.cover,
                                alignment: sideAlignment,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (context, error, stackTrace) {
                                  debugPrint('[AiFaceScan] Failed to load side overlay asset: $sideImage | $error');
                                  return const ColoredBox(color: Colors.transparent);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (yawAbsNorm > 0.08)
                  Align(
                    alignment: sideAlignment,
                    child: ClipRect(
                      child: Align(
                        alignment: sideAlignment,
                        widthFactor: 0.46,
                        child: Opacity(
                          opacity: (yawAbsNorm * 0.48 * sideOpacity).clamp(0.0, 0.48),
                          child: Transform.scale(
                            scaleX: 1.14,
                            scaleY: 1.03,
                            alignment: sideAlignment,
                            child: Image.asset(
                              sideAsset,
                              fit: BoxFit.cover,
                              alignment: sideAlignment,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stackTrace) {
                                debugPrint('[AiFaceScan] Failed to load side overlay asset: $sideImage | $error');
                                return const ColoredBox(
                                    color: Colors.transparent);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _shouldUse3DModel(Map<String, dynamic>? recommendation) {
    if (!_enable3DHairOverlay) {
      return false;
    }
    if (recommendation == null) {
      return false;
    }
    final styleName = (recommendation['style_name']?.toString() ??
            recommendation['styleName']?.toString() ??
            '')
        .toLowerCase();

    // Initial 3D integration targets the provided blowout taper sample model.
    return styleName.contains('blowout taper');
  }

  Widget _buildHair3DOverlayModel({required OverlayCalibration calibration}) {
    final yaw = (_headYaw ?? 0).clamp(-60.0, 60.0);
    final pitch = ((_headRoll ?? 0) * 0.2).clamp(-15.0, 15.0);
    final orbit = '${yaw.toStringAsFixed(1)}deg ${pitch.toStringAsFixed(1)}deg 86%';

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: calibration.hairClipFactor,
        child: SizedBox.expand(
          child: Transform.scale(
            scale: calibration.visualScale,
            alignment: Alignment.topCenter,
            child: IgnorePointer(
              child: ModelViewer(
                src: _sampleHairModel3d,
                alt: '3D hair overlay',
                cameraControls: false,
                disableZoom: true,
                autoRotate: false,
                cameraOrbit: orbit,
                interactionPrompt: InteractionPrompt.none,
                backgroundColor: const Color.fromARGB(0, 0, 0, 0),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyDeterministicRecommendation() async {
    if (!mounted) {
      return;
    }

    List<Map<String, dynamic>> fallback;
    try {
      fallback = await _loadLibraryFallback();
    } catch (_) {
      fallback = <Map<String, dynamic>>[];
    }
    if (fallback.isEmpty || !mounted) {
      setState(() {
        _loadingRecommendations = false;
        _recommendations.clear();
        _status = 'Deterministic mode: no hairstyles registered in the database yet.';
      });
      return;
    }

    final defaultStyle = fallback.first;
    setState(() {
      _loadingRecommendations = false;
      _recommendations
        ..clear()
        ..add(defaultStyle);
      _selectedIndex = 0;
      _status = 'Deterministic mode: default haircut applied for testing.';
    });

    UserSession.lastScan = {
      'faceShape': _faceShape,
      'hairTexture': _hairTexture,
      'headYaw': _headYaw,
    };
    UserSession.lastRecommendations = [defaultStyle];
  }

  void _applyPresetRecommendation() {
    final preset = widget.presetRecommendation;
    if (preset == null) {
      return;
    }

    final normalized = _normalizePresetRecommendation(preset);
    _recommendations
      ..clear()
      ..add(normalized);
    _selectedIndex = 0;
    _status = 'Previewing your selected haircut. Tap Get Top 3 to update.';
    if (!widget.previewOnly) {
      UserSession.lastRecommendations = [normalized];
      UserSession.hasRecentRecommendations = true;
    }
  }

  Map<String, dynamic> _normalizePresetRecommendation(Map<String, dynamic> preset) {
    final name = preset['style_name'] ?? preset['styleName'] ?? preset['name'];
    final front = preset['front_view_url'] ?? preset['frontViewUrl'] ?? preset['image'];
    final side = preset['side_view_url'] ?? preset['sideViewUrl'] ?? preset['side'];
    final back = preset['back_view_url'] ?? preset['backViewUrl'] ?? preset['back'];
    return {
      'style_name': name?.toString() ?? 'Style',
      'style_code': preset['style_code'] ?? preset['styleCode'],
      'face_shape': preset['face_shape'] ?? preset['faceShape'],
      'hair_texture': preset['hair_texture'] ?? preset['hairTexture'],
      'front_view_url': front?.toString() ?? '',
      'side_view_url': side?.toString() ?? '',
      'back_view_url': back?.toString() ?? '',
      'confidence_score': preset['confidence_score'] ?? preset['confidenceScore'] ?? 0,
      'description': preset['description'] ?? 'Selected from library',
      'variant_id': preset['variant_id'] ?? preset['variantId'],
      'service_id': preset['service_id'] ?? preset['serviceId'] ?? preset['serviceID'],
      'estimated_minutes': preset['estimated_minutes'] ?? preset['estimatedMinutes'],
    };
  }

  void _markOverlayReadyAfterProcessing() {
    final now = DateTime.now();
    final bestFace = _normalizedFaceRect ?? _smoothedFaceRect;
    if (bestFace == null) {
      return;
    }
    _lastStableFaceRect = bestFace;
    _overlayHoldUntil = now.add(_overlayHoldAfterProcessDuration);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isRouteSubscribed) {
      routeObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
    if (_webTrackingAttached) {
      _webCamera.tracking.removeListener(_onWebTrackingChanged);
      _webTrackingAttached = false;
    }
    _pageScrollController.dispose();
    _releaseScannerResources();
    _detector.dispose();
    super.dispose();
  }

  double _scannerHeightForLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final isPortrait = media.orientation == Orientation.portrait;
    if (isPortrait) {
      return (media.size.height * 0.62).clamp(360.0, 640.0);
    }
    return (media.size.height * 0.72).clamp(280.0, 480.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppTopBar(
        showBack: true,
        onBack: () {
          if (widget.previewOnly) {
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const DashboardPage()),
            );
          }
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: FloatingActionButton(
          heroTag: 'scanner_ai_chat_fab',
          backgroundColor: const Color(0xFFA99941),
          foregroundColor: Colors.black,
          tooltip: 'Open AI Barber Chat',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiChatbotPage()),
            );
          },
          child: const Icon(Icons.support_agent_rounded),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: !_initialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _pageScrollController,
                      padding: const EdgeInsets.fromLTRB(10, 16, 10, 98),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Live Hair Preview',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _status,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        _buildStatusIndicators(),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _chip(
                                label: 'Detected face: $_faceShape',
                                icon: Icons.face_retouching_natural,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _chip(
                                label:
                                    'Head turn: ${(_headYaw ?? 0).toStringAsFixed(1)} deg',
                                icon: Icons.threed_rotation,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildScannerCard(),
                        const SizedBox(height: 10),
                        if (widget.previewOnly) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _recommendations.isEmpty || _bookingInFlight
                                      ? null
                                      : () => _useSelectedStyle(),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFFA99941),
                                foregroundColor: Colors.black,
                              ),
                              child: _bookingInFlight
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Text('Confirm and Proceed'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const HaircutsListPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.folder_open, color: Colors.white),
                              label: const Text(
                                'Choose Another Haircut',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                backgroundColor: const Color(0xFF121212),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _recommendations.isEmpty || _bookingInFlight
                                      ? null
                                      : () => _useSelectedStyle(),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFFA99941),
                                foregroundColor: Colors.black,
                              ),
                              child: _bookingInFlight
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Text('Proceed to Booking'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_loadingRecommendations)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: LinearProgressIndicator(
                                minHeight: 3,
                                backgroundColor: Color(0xFF1A1A1A),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white70),
                              ),
                            ),
                          const Text(
                            'Top 3 results',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildTopThreePanel(),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const HaircutsListPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.folder_open, color: Colors.white),
                              label: const Text(
                                'Haircut Library',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                backgroundColor: const Color(0xFF121212),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Open the bottom panel for quick actions and booking.',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
                    _buildSlidingControlsSheet(constraints),
                if (_showCalibrationMode) _buildCalibrationOverlay(),
              ],
            );
              },
            ),
    );
  }

  Widget _buildSlidingControlsSheet(BoxConstraints viewport) {
    final expandedHeight =
        (viewport.maxHeight * 0.74).clamp(320.0, 620.0).toDouble();
    const collapsedHeight = 64.0;
    final currentHeight = _controlsSheetExpanded ? expandedHeight : collapsedHeight;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          height: currentHeight,
          child: Material(
            color: const Color(0xFF090909),
            elevation: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 4,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _controlsSheetExpanded
                                ? 'Quick Actions'
                                : 'Quick actions',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              height: 1.0,
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                          tooltip: _controlsSheetExpanded
                              ? 'Slide down (hide controls)'
                              : 'Slide up (show controls)',
                          onPressed: () {
                            setState(() {
                              _controlsSheetExpanded = !_controlsSheetExpanded;
                            });
                          },
                          iconSize: 24,
                          splashRadius: 18,
                          icon: Icon(
                            _controlsSheetExpanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_up_rounded,
                            color: const Color(0xFFE8D27D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_controlsSheetExpanded) ...[
                    const SizedBox(height: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              _buildRecommendationSection(),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildControls(),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _hairTexture,
          items: const ['Straight', 'Wavy', 'Curly', 'Coily']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _hairTexture = v);
          },
          dropdownColor: const Color(0xFF121212),
          decoration: InputDecoration(
            labelText: 'Hair type',
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: const Color(0xFF121212),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _tempCalibration = _activeCalibration;
              _showCalibrationMode = true;
            });
          },
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Fine-tune Hair Fit'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            backgroundColor: const Color(0xFF2A2A2A),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildCalibrationOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.70),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFA99941)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Adjust Hair Position',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  _buildCalibrationSlider(
                    label: 'Left ↔ Right',
                    value: _tempCalibration.offsetX,
                    min: -0.2,
                    max: 0.2,
                    onChanged: (v) {
                      setState(() {
                        _tempCalibration = _tempCalibration.copyWith(
                          offsetX: v,
                          lastUpdated: DateTime.now(),
                        );
                        _activeCalibration = _tempCalibration;
                      });
                    },
                  ),
                  _buildCalibrationSlider(
                    label: 'Up ↓ Down ↑',
                    value: _tempCalibration.offsetY,
                    min: -0.15,
                    max: 0.15,
                    onChanged: (v) {
                      setState(() {
                        _tempCalibration = _tempCalibration.copyWith(
                          offsetY: v,
                          lastUpdated: DateTime.now(),
                        );
                        _activeCalibration = _tempCalibration;
                      });
                    },
                  ),
                  _buildCalibrationSlider(
                    label: 'Size',
                    value: _tempCalibration.scale,
                    min: 0.7,
                    max: 1.3,
                    onChanged: (v) {
                      setState(() {
                        _tempCalibration = _tempCalibration.copyWith(
                          scale: v,
                          lastUpdated: DateTime.now(),
                        );
                        _activeCalibration = _tempCalibration;
                      });
                    },
                  ),
                  _buildCalibrationSlider(
                    label: 'Hairline Height',
                    value: _tempCalibration.foreheadOffset,
                    min: -0.1,
                    max: 0.1,
                    onChanged: (v) {
                      setState(() {
                        _tempCalibration = _tempCalibration.copyWith(
                          foreheadOffset: v,
                          lastUpdated: DateTime.now(),
                        );
                        _activeCalibration = _tempCalibration;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _activeCalibration = UserSession.userCalibration ??
                                  UserCalibration.defaults();
                              _tempCalibration = _activeCalibration;
                              _showCalibrationMode = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await UserSession.saveUserCalibration(
                                _tempCalibration);
                            if (!mounted) return;
                            setState(() {
                              _activeCalibration = _tempCalibration;
                              _showCalibrationMode = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFA99941),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      await UserSession.clearUserCalibration();
                      if (!mounted) return;
                      setState(() {
                        _activeCalibration = UserCalibration.defaults();
                        _tempCalibration = _activeCalibration;
                      });
                    },
                    child: const Text('Reset to defaults'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalibrationSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label  ${value.toStringAsFixed(3)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildScannerCard() {
    final scannerHeight = _scannerHeightForLayout(context);
    final recommendation = _recommendations.isNotEmpty
        ? _recommendations[_selectedIndex.clamp(0, _recommendations.length - 1)]
        : null;
    final overlayFace = _effectiveOverlayFaceRect();
    final overlayOpacity = _currentOverlayOpacity();

    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: scannerHeight,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_webCameraReady)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final videoAspect = (_webVideoAspect != null && _webVideoAspect! > 0)
                        ? _webVideoAspect!
                        : (9 / 16);
                    final boxAspect = constraints.maxWidth / constraints.maxHeight;
                    late final double width;
                    late final double height;
                    if (boxAspect > videoAspect) {
                      width = constraints.maxWidth;
                      height = width / videoAspect;
                    } else {
                      height = constraints.maxHeight;
                      width = height * videoAspect;
                    }

                    return Center(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: WebCameraView(controller: _webCamera),
                      ),
                    );
                  },
                )
              else
                const Center(
                  child: Text('Web camera unavailable on this platform',
                      style: TextStyle(color: Colors.white70)),
                ),
              if (_webCameraReady)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return _buildScanGuideOverlay(constraints);
                  },
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final blurLayer = _hairBlurLayer(
                    constraints: constraints,
                    overlayFace: overlayFace,
                    recommendation: recommendation,
                    overlayOpacity: overlayOpacity,
                  );
                  final coverLayer = _hairCoverLayer(
                    constraints: constraints,
                    overlayFace: overlayFace,
                    recommendation: recommendation,
                    overlayOpacity: overlayOpacity,
                  );
                  final featherLayer = _hairEdgeFeatherLayer(
                    constraints: constraints,
                    overlayFace: overlayFace,
                    recommendation: recommendation,
                    overlayOpacity: overlayOpacity,
                  );
                  final layer = _overlayLayer(
                    constraints: constraints,
                    overlayFace: overlayFace,
                    recommendation: recommendation,
                    overlayOpacity: overlayOpacity,
                  );
                  final debugLayer = _debugAttachmentLayer(
                    constraints: constraints,
                    overlayFace: overlayFace,
                    recommendation: recommendation,
                    overlayOpacity: overlayOpacity,
                  );
                  if (blurLayer == null &&
                      coverLayer == null &&
                      featherLayer == null &&
                      layer == null &&
                      debugLayer == null) {
                    return const SizedBox.shrink();
                  }
                  return Stack(
                    children: [
                      if (blurLayer != null) blurLayer,
                      if (coverLayer != null) coverLayer,
                      if (featherLayer != null) featherLayer,
                      if (layer != null) layer,
                      if (debugLayer != null) debugLayer,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    if (_camera == null || !_camera!.value.isInitialized) {
      return Container(
        height: scannerHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Text('Camera unavailable on this platform',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: scannerHeight,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final previewSize = _camera!.value.previewSize;
                final previewWidth = previewSize?.height ?? constraints.maxWidth;
                final previewHeight = previewSize?.width ?? constraints.maxHeight;

                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: constraints.maxWidth,
                    minHeight: constraints.maxHeight,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: previewWidth,
                        height: previewHeight,
                        child: CameraPreview(_camera!),
                      ),
                    ),
                  ),
                );
              },
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                return _buildScanGuideOverlay(constraints);
              },
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final blurLayer = _hairBlurLayer(
                  constraints: constraints,
                  overlayFace: overlayFace,
                  recommendation: recommendation,
                  overlayOpacity: overlayOpacity,
                );
                final coverLayer = _hairCoverLayer(
                  constraints: constraints,
                  overlayFace: overlayFace,
                  recommendation: recommendation,
                  overlayOpacity: overlayOpacity,
                );
                final featherLayer = _hairEdgeFeatherLayer(
                  constraints: constraints,
                  overlayFace: overlayFace,
                  recommendation: recommendation,
                  overlayOpacity: overlayOpacity,
                );
                final layer = _overlayLayer(
                  constraints: constraints,
                  overlayFace: overlayFace,
                  recommendation: recommendation,
                  overlayOpacity: overlayOpacity,
                );
                final debugLayer = _debugAttachmentLayer(
                  constraints: constraints,
                  overlayFace: overlayFace,
                  recommendation: recommendation,
                  overlayOpacity: overlayOpacity,
                );
                if (blurLayer == null &&
                    coverLayer == null &&
                    featherLayer == null &&
                    layer == null &&
                    debugLayer == null) {
                  return const SizedBox.shrink();
                }
                return Stack(
                  children: [
                    if (blurLayer != null) blurLayer,
                    if (coverLayer != null) coverLayer,
                    if (featherLayer != null) featherLayer,
                    if (layer != null) layer,
                    if (debugLayer != null) debugLayer,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget? _overlayLayer({
    required BoxConstraints constraints,
    required Rect? overlayFace,
    required Map<String, dynamic>? recommendation,
    required double overlayOpacity,
  }) {
    if (overlayFace == null || recommendation == null || overlayOpacity <= 0.01) {
      if (recommendation == null) {
        debugPrint('[AiFaceScan] _overlayLayer: Skipping - no recommendation');
      } else if (overlayFace == null) {
        debugPrint('[AiFaceScan] _overlayLayer: Skipping - no overlayFace');
      } else {
        debugPrint('[AiFaceScan] _overlayLayer: Skipping - opacity too low ($overlayOpacity)');
      }
      return null;
    }

    debugPrint('[AiFaceScan] _overlayLayer: Building with recommendation style_name=${recommendation['style_name']}');

    final calibration = _overlayCalibration(recommendation);
    final yawAbsNorm = ((_headYaw ?? 0).abs() / 34.0).clamp(0.0, 1.0);
    final anchorFace = (yawAbsNorm > 0.12 && _lastCenteredFaceRect != null)
        ? _anchorRectToCenter(overlayFace, _lastCenteredFaceRect!)
        : overlayFace;
    final box = _computeAttachmentBox(
      face: anchorFace,
      constraints: constraints,
      calibration: calibration,
    );
    return Positioned(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        child: Opacity(
          opacity: overlayOpacity,
          child: Transform(
            alignment: (_headYaw ?? 0) >= 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            transform: Matrix4.identity()
              ..rotateZ((_headRoll ?? 0) * math.pi / 180)
              ..scale(box.yawScale, 1.0),
            child: _buildHairOnlyOverlayModel(
              calibration: calibration,
              recommendation: recommendation,
            ),
          ),
        ),
      ),
    );
  }

  Widget? _hairBlurLayer({
    required BoxConstraints constraints,
    required Rect? overlayFace,
    required Map<String, dynamic>? recommendation,
    required double overlayOpacity,
  }) {
    if (overlayFace == null || recommendation == null || overlayOpacity <= 0.01) {
      return null;
    }

    if (kIsWeb) {
      return null;
    }

    final calibration = _overlayCalibration(recommendation);
    final box = _computeAttachmentBox(
      face: overlayFace,
      constraints: constraints,
      calibration: calibration,
    );

    // tighten blur area to avoid covering the face
    final blurLeft =
      (box.left + (box.width * 0.14)).clamp(0.0, constraints.maxWidth).toDouble();
    final blurTop =
      (box.top + (box.height * 0.06)).clamp(0.0, constraints.maxHeight).toDouble();
    final blurWidth =
      (box.width * 0.60).clamp(0.0, constraints.maxWidth - blurLeft).toDouble();
    final blurHeight =
      (box.height * 0.34).clamp(0.0, constraints.maxHeight - blurTop).toDouble();

    if (blurWidth <= 1 || blurHeight <= 1) {
      return null;
    }

    return Positioned(
      left: blurLeft,
      top: blurTop,
      width: blurWidth,
      height: blurHeight,
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
                sigmaX: _hairBlurSigma, sigmaY: _hairBlurSigma),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
    );
  }

  Widget? _hairCoverLayer({
    required BoxConstraints constraints,
    required Rect? overlayFace,
    required Map<String, dynamic>? recommendation,
    required double overlayOpacity,
  }) {
    if (overlayFace == null || recommendation == null || overlayOpacity <= 0.01) {
      return null;
    }

    if (kIsWeb) {
      return null;
    }

    final calibration = _overlayCalibration(recommendation);
    final box = _computeAttachmentBox(
      face: overlayFace,
      constraints: constraints,
      calibration: calibration,
    );

    // slightly reduce cover region to sit more on the hairline
    final coverLeft =
      (box.left + (box.width * 0.10)).clamp(0.0, constraints.maxWidth).toDouble();
    final coverTop =
      (box.top + (box.height * 0.06)).clamp(0.0, constraints.maxHeight).toDouble();
    final coverWidth =
      (box.width * 0.78).clamp(0.0, constraints.maxWidth - coverLeft).toDouble();
    final coverHeight =
      (box.height * 0.40).clamp(0.0, constraints.maxHeight - coverTop).toDouble();

    if (coverWidth <= 1 || coverHeight <= 1) {
      return null;
    }

    return Positioned(
      left: coverLeft,
      top: coverTop,
      width: coverWidth,
      height: coverHeight,
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(_hairCoverTopOpacity),
                      Colors.black.withOpacity(_hairCoverMidOpacity),
                      Colors.black.withOpacity(_hairCoverBottomOpacity),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 1.05,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(_hairCoverRadialOpacity),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _hairEdgeFeatherLayer({
    required BoxConstraints constraints,
    required Rect? overlayFace,
    required Map<String, dynamic>? recommendation,
    required double overlayOpacity,
  }) {
    if (overlayFace == null || recommendation == null || overlayOpacity <= 0.01) {
      return null;
    }

    if (kIsWeb) {
      return null;
    }

    final calibration = _overlayCalibration(recommendation);
    final box = _computeAttachmentBox(
      face: overlayFace,
      constraints: constraints,
      calibration: calibration,
    );

    // edge feather slightly smaller to match reduced cover
    final featherLeft =
      (box.left + (box.width * 0.08)).clamp(0.0, constraints.maxWidth).toDouble();
    final featherTop =
      (box.top + (box.height * 0.06)).clamp(0.0, constraints.maxHeight).toDouble();
    final featherWidth =
      (box.width * 0.80).clamp(0.0, constraints.maxWidth - featherLeft).toDouble();
    final featherHeight =
      (box.height * 0.46).clamp(0.0, constraints.maxHeight - featherTop).toDouble();

    if (featherWidth <= 1 || featherHeight <= 1) {
      return null;
    }

    return Positioned(
      left: featherLeft,
      top: featherTop,
      width: featherWidth,
      height: featherHeight,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.black.withOpacity(_hairEdgeOpacity),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget? _debugAttachmentLayer({
    required BoxConstraints constraints,
    required Rect? overlayFace,
    required Map<String, dynamic>? recommendation,
    required double overlayOpacity,
  }) {
    if (!_showOverlayDebug ||
        overlayFace == null ||
        recommendation == null ||
        overlayOpacity <= 0.01) {
      return null;
    }

    final calibration = _overlayCalibration(recommendation);
    final box = _computeAttachmentBox(
      face: overlayFace,
      constraints: constraints,
      calibration: calibration,
    );

    final anchorXNorm = (_eyeMidX ?? (overlayFace.left + (overlayFace.width * 0.5)))
        .clamp(0.0, 1.0);
    final anchorYNorm =
        (_foreheadAnchorY ?? (overlayFace.top + (overlayFace.height * 0.12)))
            .clamp(0.0, 1.0);
    final anchorX = anchorXNorm * constraints.maxWidth;
    final anchorY = anchorYNorm * constraints.maxHeight;

    return IgnorePointer(
      child: Stack(
        children: [
          // Raw ML face rectangle (normalized coordinates) - red border
          Positioned(
            left: overlayFace.left * constraints.maxWidth,
            top: overlayFace.top * constraints.maxHeight,
            width: overlayFace.width * constraints.maxWidth,
            height: overlayFace.height * constraints.maxHeight,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withOpacity(0.85),
                  width: 1.6,
                ),
              ),
            ),
          ),
          Positioned(
            left: box.left,
            top: box.top,
            width: box.width,
            height: box.height,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF16E3FF).withOpacity(0.85),
                  width: 1.2,
                ),
              ),
            ),
          ),
          Positioned(
            left: anchorX - 5,
            top: anchorY - 5,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4D6D),
                border: Border.all(color: Colors.white70, width: 1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                'DBG box(${box.width.toStringAsFixed(0)}x${box.height.toStringAsFixed(0)}) yaw:${(_headYaw ?? 0).toStringAsFixed(1)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    const guidance = 'Center your face and keep still for cleaner matching.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              guidance,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanGuideOverlay(BoxConstraints constraints) {
    final guideHeight = (constraints.maxHeight * 0.72).clamp(250.0, 430.0);
    final guideWidth = (guideHeight * 0.78).clamp(200.0, 340.0);
    final guideRect = Rect.fromCenter(
      center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
      width: guideWidth,
      height: guideHeight,
    );

    final ready = _faceSessionReady;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanGuidePainter(
                guideRect: guideRect,
                ready: ready,
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ready ? Colors.greenAccent.shade200 : Colors.white24,
                  ),
                ),
                child: Text(
                  ready
                      ? 'Ready - scan will start automatically'
                      : 'Place your face inside the guide marks',
                  style: TextStyle(
                    color: ready ? Colors.greenAccent.shade100 : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicators() {
    final hasFace = _normalizedFaceRect != null;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusPill(
          icon: Icons.videocam,
          label: _webCameraReady || (_camera?.value.isInitialized ?? false)
              ? 'Camera on'
              : 'Camera off',
          active: _webCameraReady || (_camera?.value.isInitialized ?? false),
        ),
        _StatusPill(
          icon: Icons.tune,
          label: 'Live preview',
          active: true,
        ),
        _StatusPill(
          icon: Icons.face,
          label: kIsWeb
              ? (_recommendations.isNotEmpty
                  ? 'Hair preview on'
                  : 'Waiting for suggestions')
              : (hasFace ? 'Face found' : 'Find your face'),
          active: kIsWeb ? (_recommendations.isNotEmpty && hasFace) : hasFace,
        ),
        _StatusPill(
          icon: Icons.auto_awesome,
          label: _loadingRecommendations ? 'Loading suggestions...' : 'Ready',
          active: !_loadingRecommendations,
        ),
      ],
    );
  }

  Widget _chip({required String label, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopThreePanel() {
    if (_recommendations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          'No haircut suggestions yet. Center your face, then tap Get Top 3 Haircuts.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Best 3 Matches',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...List.generate(_recommendations.length, (index) {
            final item = _recommendations[index];
            final selected = index == _selectedIndex;
            final name = item['style_name']?.toString() ??
                item['styleName']?.toString() ??
                'Style';
            final texture = item['hair_texture']?.toString() ??
                item['hairTexture']?.toString() ??
                '';

            return Padding(
              padding: EdgeInsets.only(
                  bottom: index == _recommendations.length - 1 ? 0 : 8),
              child: InkWell(
                onTap: () => setState(() => _selectedIndex = index),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF1D1D1D)
                        : const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: selected ? Colors.white60 : Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: Center(
                          child: Text('${index + 1}',
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                            if (texture.isNotEmpty)
                              Text(texture,
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _rankRecommendations(
      List<Map<String, dynamic>> input) {
    final ranked = _dedupeRecommendations(input);

    double score(Map<String, dynamic> item) {
      final confidence = double.tryParse(
              '${item['confidence_score'] ?? item['confidenceScore'] ?? 0}') ??
          0;
      final styleName = (item['style_name']?.toString() ??
              item['styleName']?.toString() ??
              '')
          .toLowerCase();
      final face = (item['face_shape']?.toString() ??
              item['faceShape']?.toString() ??
              '')
          .toLowerCase();
      final texture = (item['hair_texture']?.toString() ??
              item['hairTexture']?.toString() ??
              '')
          .toLowerCase();

      var s = confidence;
      if (face.isNotEmpty && face == _faceShape.toLowerCase()) {
        s += 0.20;
      }
      if (texture.isNotEmpty && texture == _hairTexture.toLowerCase()) {
        s += 0.25;
      } else if (texture.isNotEmpty && texture != _hairTexture.toLowerCase()) {
        s -= 0.25;
      }

      final likelyCoilyStyle = styleName.contains('afro') ||
          styleName.contains('dread') ||
          styleName.contains('twist');
      if (_hairTexture.toLowerCase() != 'coily' && likelyCoilyStyle) {
        s -= 0.55;
      }

      return s;
    }

    ranked.sort((a, b) => score(b).compareTo(score(a)));
    return ranked;
  }

  String _recommendationIdentity(Map<String, dynamic> item) {
    final variantId = item['variant_id']?.toString() ?? item['variantId']?.toString() ?? '';
    if (variantId.isNotEmpty) {
      return 'variant:$variantId';
    }
    final styleCode = item['style_code']?.toString() ?? item['styleCode']?.toString() ?? '';
    if (styleCode.isNotEmpty) {
      return 'stylecode:$styleCode';
    }
    final styleName = item['style_name']?.toString() ?? item['styleName']?.toString() ?? '';
    return 'style:$styleName'.toLowerCase();
  }

  List<Map<String, dynamic>> _dedupeRecommendations(List<Map<String, dynamic>> input) {
    final seen = <String>{};
    final output = <Map<String, dynamic>>[];
    for (final item in input) {
      final key = _recommendationIdentity(item);
      if (seen.add(key)) {
        output.add(Map<String, dynamic>.from(item));
      }
    }
    return output;
  }

  List<Map<String, dynamic>> _mergeRecommendations(
      List<Map<String, dynamic>> base,
      List<Map<String, dynamic>> extras) {
    final seen = <String>{};
    final output = <Map<String, dynamic>>[];

    for (final item in base) {
      final key = _recommendationIdentity(item);
      if (seen.add(key)) {
        output.add(item);
      }
    }

    for (final item in extras) {
      final key = _recommendationIdentity(item);
      if (seen.add(key)) {
        output.add(item);
      }
    }

    return output;
  }

  List<Map<String, dynamic>> _topThreeRecommendations(
      List<Map<String, dynamic>> ranked) {
    // ranked is already deduped and sorted by _rankRecommendations, just take top 3
    return ranked.take(3).toList();
  }

  Future<void> _useSelectedStyle() async {
    if (_recommendations.isEmpty) {
      return;
    }

    final selected = _recommendations[_selectedIndex.clamp(0, _recommendations.length - 1)];
    final style = _toStyleMap(selected);
    final variantId = style['variantId'] as int?;
    if (variantId == null || variantId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This style cannot be booked yet.')),
      );
      return;
    }

    final userId = UserSession.userId;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again.')),
      );
      return;
    }

    if (await BookingGuard.hasActiveAppointment(userId: userId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AppointmentsPage()),
      );
      return;
    }

    UserSession.selectedVariantId = variantId;
    UserSession.selectedServiceId = int.tryParse(style['serviceId']?.toString() ?? '');
    UserSession.selectedStyleName = style['name']?.toString();
    UserSession.selectedEstimatedMinutes = style['estimatedMinutes'] as int?;
    UserSession.selectedPreviewImages = {
      'frontViewUrl': style['frontViewUrl']?.toString() ?? '',
      'sideViewUrl': style['sideViewUrl']?.toString() ?? '',
      'backViewUrl': style['backViewUrl']?.toString() ?? '',
    };

    await AiFunnelService.saveSelection(
      scanSessionId: UserSession.ensureScanSessionId(),
      userId: userId,
      variantId: variantId,
      styleName: UserSession.selectedStyleName ?? 'Style',
      faceShape: UserSession.lastScan?['faceShape']?.toString(),
      hairTexture: UserSession.lastScan?['hairTexture']?.toString(),
      hairDensity: UserSession.lastScan?['hairDensity']?.toString(),
      hairLength: UserSession.lastScan?['hairLength']?.toString(),
      estimatedMinutes: UserSession.selectedEstimatedMinutes,
      frontViewUrl: UserSession.selectedPreviewImages?['frontViewUrl'],
      sideViewUrl: UserSession.selectedPreviewImages?['sideViewUrl'],
      backViewUrl: UserSession.selectedPreviewImages?['backViewUrl'],
    );

    setState(() => _bookingInFlight = true);
    final suggestion = await _fetchSuggestedSlot();
    if (!mounted) {
      return;
    }
    setState(() => _bookingInFlight = false);

    if (suggestion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available slots found. Please choose manually.')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuggestedAppointmentPage(suggestion: suggestion),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchSuggestedSlot() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'suggestBestSlot'}),
      );
      if (response.statusCode != 200 || response.body.isEmpty) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['suggestion'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _toStyleMap(Map<String, dynamic> recommendation) {
    return {
      'name': recommendation['style_name']?.toString() ?? recommendation['styleName']?.toString() ?? 'Style',
      'description': recommendation['description']?.toString() ?? 'AI recommended style',
      'image': _resolveImage(recommendation['front_view_url'] ?? recommendation['frontViewUrl']) ?? '',
      'details': 'Face shape: ${recommendation['face_shape'] ?? 'N/A'}\nHair texture: ${recommendation['hair_texture'] ?? 'N/A'}',
      'rating': _asDouble(recommendation['confidence_score']) ?? 4.0,
      'frontViewUrl': _resolveImage(recommendation['front_view_url'] ?? recommendation['frontViewUrl']) ?? '',
      'sideViewUrl': _resolveImage(recommendation['side_view_url'] ?? recommendation['sideViewUrl']) ?? '',
      'backViewUrl': _resolveImage(recommendation['back_view_url'] ?? recommendation['backViewUrl']) ?? '',
      'variantId': recommendation['variant_id'] ?? recommendation['variantId'],
      'serviceId': recommendation['service_id'] ?? recommendation['serviceID'],
      'estimatedMinutes': _asInt(recommendation['estimated_minutes'] ?? recommendation['estimatedMinutes']),
    };
  }

  String? _resolveImage(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('assets/')) {
      return raw;
    }
    return ApiConfig.resolveImageUrl(raw);
  }

  String _assetPath(String raw) {
    return raw;
  }

  double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value.toString());
  }

  int? _asInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  Rect _smoothRect(Rect? previous, Rect next, double alpha) {
    if (previous == null) {
      return next;
    }
    return Rect.fromLTWH(
      _smoothValue(previous.left, next.left, alpha),
      _smoothValue(previous.top, next.top, alpha),
      _smoothValue(previous.width, next.width, alpha),
      _smoothValue(previous.height, next.height, alpha),
    );
  }

  double _smoothValue(double? previous, double? next, double alpha) {
    final target = next ?? 0;
    if (previous == null) {
      return target;
    }
    final value = previous + ((target - previous) * alpha);
    return value;
  }

  Rect _stabilizeIncomingRect(Rect? previous, Rect next) {
    if (previous == null) {
      return next;
    }

    final prevCenter = previous.center;
    final nextCenter = next.center;
    final centerJump = (nextCenter - prevCenter).distance;
    final areaJump = ((_rectArea(next) - _rectArea(previous)).abs() /
            (_rectArea(previous).clamp(0.001, 1.0)))
        .clamp(0.0, 2.0);

    if (centerJump > _trackingJumpThreshold || areaJump > 0.40) {
      return Rect.lerp(previous, next, 0.22) ?? next;
    }
    return next;
  }

  bool _isLikelyStableFace(Rect rect) {
    final area = _rectArea(rect);
    if (area < _minFaceAreaForOverlay) {
      return false;
    }
    const maxArea =
        kIsWeb ? _maxFaceAreaForOverlayWeb : _maxFaceAreaForOverlayMobile;
    if (area > maxArea) {
      return false;
    }
    if (rect.left <= 0.01 ||
        rect.top <= 0.01 ||
        rect.right >= 0.99 ||
        rect.bottom >= 0.99) {
      return false;
    }
    return true;
  }

  double _rectArea(Rect rect) => (rect.width * rect.height).clamp(0.0, 1.0);

  Rect? _effectiveOverlayFaceRect() {
    final current = _normalizedFaceRect;
    if (current != null && _recommendations.isNotEmpty) {
      final yawAbsNorm = ((_headYaw ?? 0).abs() / 34.0).clamp(0.0, 1.0);
      final centered = _lastCenteredFaceRect;
      if (yawAbsNorm > 0.12 && centered != null) {
        return _recenterRectX(current, centered.center.dx);
      }
      if (_isLikelyStableFace(current)) {
        _lastStableFaceRect = current;
        _overlayHoldUntil = DateTime.now().add(_overlayHoldDuration);
        return current;
      }

      final holdUntil = _overlayHoldUntil;
      final fallback = _lastStableFaceRect;
      if (holdUntil != null && fallback != null && DateTime.now().isBefore(holdUntil)) {
        return fallback;
      }
      return current;
    }
    if (current != null && _isLikelyStableFace(current)) {
      return current;
    }
    final holdUntil = _overlayHoldUntil;
    final fallback = _lastStableFaceRect;
    if (holdUntil == null || fallback == null) {
      return null;
    }
    if (DateTime.now().isAfter(holdUntil)) {
      return null;
    }
    return fallback;
  }

  Rect _recenterRectX(Rect current, double centerX) {
    final width = current.width;
    final left = (centerX - (width * 0.5)).clamp(0.0, 1.0 - width);
    return Rect.fromLTWH(left, current.top, width, current.height);
  }

  Rect _anchorRectToCenter(Rect current, Rect anchor) {
    final width = current.width;
    final height = current.height;
    final left = (anchor.center.dx - (width * 0.5)).clamp(0.0, 1.0 - width);
    final top = (anchor.center.dy - (height * 0.5)).clamp(0.0, 1.0 - height);
    return Rect.fromLTWH(left, top, width, height);
  }

  double _currentOverlayOpacity() {
    if (_normalizedFaceRect != null) {
      return _overlayBaseOpacity;
    }
    final holdUntil = _overlayHoldUntil;
    if (holdUntil == null) {
      return 0;
    }
    final remainingMs = holdUntil.difference(DateTime.now()).inMilliseconds;
    if (remainingMs <= 0) {
      return 0;
    }
    final t =
        (remainingMs / _overlayHoldDuration.inMilliseconds).clamp(0.0, 1.0);
    return _overlayBaseOpacity * t;
  }

  OverlayImageSet _resolveOverlayImageSet(Map<String, dynamic>? recommendation) {
    if (recommendation == null) {
      debugPrint('[AiFaceScan] No recommendation available, using sample overlay');
      return _sampleImageOverlay;
    }

    final styleName = (recommendation['style_name']?.toString() ??
            recommendation['styleName']?.toString() ??
            '')
        .trim()
        .toLowerCase();
    if (styleName.isEmpty) {
      debugPrint('[AiFaceScan] Recommendation missing style name, using sample overlay');
      return _sampleImageOverlay;
    }

    final normalizedStyleName = styleName == 'curly top fade' ? 'curly taper fade' : styleName;

    // Try exact match first
    if (_styleOverlayImages.containsKey(normalizedStyleName)) {
      debugPrint('[AiFaceScan] Matched overlay style="$styleName" via exact match');
      return _styleOverlayImages[normalizedStyleName]!;
    }

    // Try substring match (in case style name has variations)
    for (final entry in _styleOverlayImages.entries) {
      if (normalizedStyleName.contains(entry.key)) {
        debugPrint('[AiFaceScan] Matched overlay style="$styleName" via substring match -> ${entry.key}');
        return entry.value;
      }
    }

    debugPrint('[AiFaceScan] No overlay match for style="$styleName", using sample overlay');
    return _sampleImageOverlay;
  }

  OverlayCalibration _overlayCalibration(
      Map<String, dynamic>? recommendation) {
    OverlayCalibration base = OverlayCalibration.defaults;

    if (recommendation == null) {
      return _adaptCalibrationToFace(base);
    }

    final styleName = (recommendation['style_name']?.toString() ??
            recommendation['styleName']?.toString() ??
            '')
        .trim()
        .toLowerCase();
    if (styleName.isEmpty) {
      return _adaptCalibrationToFace(base);
    }

    for (final entry in _styleCalibration.entries) {
      if (styleName.contains(entry.key)) {
        base = entry.value;
        break;
      }
    }

    return _adaptCalibrationToFace(base);
  }

  OverlayBox _computeAttachmentBox({
    required Rect face,
    required BoxConstraints constraints,
    required OverlayCalibration calibration,
  }) {
    final yawAbsNorm = ((_headYaw ?? 0).abs() / 34.0).clamp(0.0, 1.0);
    final anchorX = yawAbsNorm > 0.12 && _lastCenteredFaceRect != null
        ? _lastCenteredFaceRect!.center.dx
        : (face.left + (face.width * 0.5));
    return _attachmentEngine.compute(
      AttachmentInput(
        face: face,
        constraints: constraints,
        calibration: calibration,
        isWeb: kIsWeb,
        headYaw: _headYaw,
        headRoll: _headRoll,
        foreheadAnchorY: _foreheadAnchorY,
        eyeMidX: anchorX,
        eyeDistanceNorm: _eyeDistanceNorm,
        videoAspect: _webVideoAspect,
        faceTransformMatrix: _faceTransformMatrix,
        calibrationOffsets: AttachmentCalibrationOffsets(
          offsetX: _activeCalibration.offsetX,
          offsetY: _activeCalibration.offsetY,
          scale: _activeCalibration.scale,
          foreheadOffset: _activeCalibration.foreheadOffset,
        ),
      ),
    );
  }

  OverlayCalibration _adaptCalibrationToFace(OverlayCalibration base) {
    final face = _effectiveOverlayFaceRect() ?? _smoothedFaceRect ?? _normalizedFaceRect;
    if (face == null) {
      return base;
    }

    final area = (face.width * face.height).clamp(0.03, 0.40);
    final aspect = (face.width / face.height).clamp(0.58, 1.15);

    final slimFaceNorm = ((0.88 - aspect) / 0.30).clamp(0.0, 1.0);
    final wideFaceNorm = ((aspect - 0.84) / 0.24).clamp(0.0, 1.0);
    final nearNorm = ((area - 0.15) / 0.18).clamp(0.0, 1.0);
    final farNorm = ((0.15 - area) / 0.12).clamp(0.0, 1.0);
    final eyeDistance =
      (_eyeDistanceNorm ?? (face.width * 0.42)).clamp(0.05, 0.70);
    final expectedEye = (face.width * 0.42).clamp(0.05, 0.70);
    final eyeScaleNorm =
      ((expectedEye - eyeDistance).abs() / expectedEye).clamp(0.0, 1.0);
    final eyeIsWider = (eyeDistance > expectedEye) ? 1.0 : 0.0;

    final widthScale = (base.widthScale *
            (1.0 + (slimFaceNorm * 0.18) - (wideFaceNorm * 0.08)) *
        (1.0 + (farNorm * 0.10) - (nearNorm * 0.06)) *
        (1.0 - (eyeScaleNorm * 0.06 * eyeIsWider)))
        .clamp(0.96, 1.58)
        .toDouble();

    final heightScale = (base.heightScale *
            (1.0 + (wideFaceNorm * 0.16) + (slimFaceNorm * 0.05)) *
        (1.0 + (nearNorm * 0.08) + (farNorm * 0.04)) *
        (1.0 + (eyeScaleNorm * 0.05 * (1.0 - eyeIsWider))))
        .clamp(1.04, 1.78)
        .toDouble();

    final yOffset = (base.yOffset +
            (nearNorm * 0.04) -
            (farNorm * 0.03) -
            (slimFaceNorm * 0.02))
      .clamp(-0.30, -0.08)
        .toDouble();

    final clipFactor =
        (base.hairClipFactor + (wideFaceNorm * 0.03) - (slimFaceNorm * 0.02))
            .clamp(0.80, 0.92)
            .toDouble();

    final visualScale =
        (base.visualScale + (farNorm * 0.06) - (nearNorm * 0.04))
        .clamp(1.00, 1.22)
            .toDouble();

    return OverlayCalibration(
      widthScale: widthScale,
      heightScale: heightScale,
      xOffset: base.xOffset,
      yOffset: yOffset,
      hairClipFactor: clipFactor,
      visualScale: visualScale,
      yawShiftFactor: base.yawShiftFactor,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _StatusPill(
      {required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF17301D) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: active ? const Color(0xFF3E7A4A) : Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: active ? Colors.greenAccent.shade100 : Colors.white60),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.greenAccent.shade100 : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final String label;
  final bool isLive;

  const _LiveBadge({required this.label, required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fiber_manual_record,
            size: 11,
            color: isLive ? Colors.redAccent : Colors.white54,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  final Rect guideRect;
  final bool ready;

  const _ScanGuidePainter({required this.guideRect, required this.ready});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = guideRect;
    final paint = Paint()
      ..color = ready
          ? Colors.greenAccent.withOpacity(0.72)
          : Colors.white.withOpacity(0.68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(999));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter oldDelegate) {
    return oldDelegate.guideRect != guideRect || oldDelegate.ready != ready;
  }
}

class _FaceGuidePainter extends CustomPainter {
  final Rect face;

  const _FaceGuidePainter({required this.face});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      face.left * size.width,
      face.top * size.height,
      face.width * size.width,
      face.height * size.height,
    );

    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) =>
      oldDelegate.face != face;
}