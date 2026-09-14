import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'api_config.dart';
import 'app_brand.dart';
import 'ai_funnel_service.dart';
import '../services/calibration_api.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'suggested_appointment_page.dart';
import 'widgets/ai_chatbot_fab.dart';
import 'customer_navigation.dart';
import 'dashboard_page.dart';
import 'booking_guard.dart';
import 'customer_api.dart';
import 'haircuts_list_page.dart';
import '../main.dart';
import 'scanner/overlay_models.dart';
import 'scanner/overlay_registry.dart';
import 'scanner/overlay_asset_cache.dart';
import 'scanner/scanner_layout.dart';
import 'scanner/camera_preview_cover.dart';
import 'scanner/camera_frame_orientation.dart';
import 'scanner/device_orientation_tracker.dart';
import 'scanner/face_preview_mapping.dart';
import 'scanner/staging_face_validation.dart';
import 'scanner/attachment_engine.dart';
import 'scanner/face_detector_service_stub.dart'
    if (dart.library.io) 'scanner/face_detector_service_mobile.dart';
import 'face_scan_results_page.dart';
import 'feature_flags.dart';
import 'services/booking_slots_service.dart';
import 'services/face_scan_service.dart';
import 'user_session.dart';
import 'web_camera_view_stub.dart'
    if (dart.library.html) 'web_camera_view.dart';
import 'saved_haircuts_page.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/menu_sheet.dart';
import '../kiosk/kiosk_barber_page.dart';
import '../kiosk/kiosk_session.dart';
import '../app_orientation.dart';

class AiFaceScanPage extends StatefulWidget {
  final Map<String, dynamic>? presetRecommendation;
  final bool previewOnly;
  final Map<String, dynamic>? captureSummary;
  /// Opens live camera overlay only (skips 3-angle capture). Use after static scan.
  final bool livePreviewOnly;
  /// Walk-in kiosk: no bottom nav; routes to kiosk queue after style pick.
  final bool kioskMode;
  /// When true, clears working scan state and starts a fresh capture session.
  /// Completed scan snapshot is kept until a new scan is committed.
  final bool startFresh;

  const AiFaceScanPage({
    super.key,
    this.presetRecommendation,
    this.previewOnly = false,
    this.captureSummary,
    this.livePreviewOnly = false,
    this.kioskMode = false,
    this.startFresh = false,
  });

  @override
  State<AiFaceScanPage> createState() => _AiFaceScanPageState();
}

class _AiFaceScanPageState extends State<AiFaceScanPage>
    with WidgetsBindingObserver, RouteAware {
  // Check if we need staging or can go straight to live preview
  late bool _needsStaging;
  int _stageIndex = 0;
  bool _stagingComplete = false;
  int _goodPositionFrames = 0;
  bool _isGoodPosition = false;
  Map<String, String> _capturedImages = {};
  final Map<String, Rect> _capturedFaceRects = {};
  bool _consentAccepted = false;
  bool _consentFormAgreed = false;
  bool _consentLoading = true;
  bool _finishingStaging = false;
  
  double? _currentHeadYaw;
  Rect? _currentFaceRect;
  Size? _stagingViewSize;
  String? _lastStagingLog;

  static const List<_CaptureStage> _stages = [
    _CaptureStage(
      keyName: 'front',
      label: 'Front view',
      hint: 'Face the camera straight ahead and keep still.',
      icon: Icons.face,
      requiredYaw: 0,
      yawTolerance: 22,
    ),
    _CaptureStage(
      keyName: 'right',
      label: 'Right view',
      hint: 'Turn your face to the right (about 45 degrees).',
      icon: Icons.turn_right,
      requiredYaw: -45,
      yawTolerance: 28,
    ),
    _CaptureStage(
      keyName: 'left',
      label: 'Left view',
      hint: 'Turn your face to the left (about 45 degrees).',
      icon: Icons.turn_left,
      requiredYaw: 45,
      yawTolerance: 28,
    ),
  ];

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
    // Minimal-smoothing overlay tracking for real-time responsiveness (low lag).
    Rect? _minSmoothFaceRect;
    double? _minSmoothHeadYaw;
    double? _minSmoothHeadRoll;
    static const double _minSmoothRectAlpha = 0.82;
    static const double _minSmoothAngleAlpha = 0.75;
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
  Map<String, dynamic>? _overlayPresetOnly;

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
  static const String _sampleHairModel3d = 'assets/models/blowouttaper.glb';
  static const bool _enable3DHairOverlay = false;

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
    // Reinforce mode orientation when entering the scanner.
    // Awaited inside _setup() before the camera is built: creating the
    // controller while the UI is still rotating is what left its cached
    // deviceOrientation stale in the first place.
    DeviceOrientationTracker.start();
    _attachmentEngine = createAttachmentEngine(AttachmentEngineMode.auto);
    if (widget.livePreviewOnly && !kEnableLiveScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_exitBlockedLivePreview());
      });
      return;
    }

    _loadConsentAndStaging();
    _seedRecommendationsForLivePreview();
    _loadCalibration();
    _setup();
  }

  Future<void> _exitBlockedLivePreview() async {
    if (!mounted) return;
    final captures = UserSession.capturedFaceImages;
    if (captures != null && captures.isNotEmpty) {
      final scan = UserSession.lastScan;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FaceScanResultsPage(
            captures: Map.from(captures),
            faceShape: scan?['faceShape']?.toString() ?? 'oval',
            hairTexture: scan?['hairTexture']?.toString() ?? 'Wavy',
            hairLengthLevel: int.tryParse('${scan?['hairLengthLevel']}') ?? 1,
            hairLengthLabel: scan?['hairLength']?.toString() ?? 'short',
            analysisProvider: scan?['analysisProvider']?.toString(),
            hairTextureScore: (scan?['hairTextureScore'] as num?)?.toDouble(),
            noHairDetected: scan?['noHairDetected'] == true,
            hairColorLabel: scan?['hairColor']?.toString(),
            presetRecommendation: widget.presetRecommendation,
            kioskMode: widget.kioskMode,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _loadConsentAndStaging() async {
    if (widget.kioskMode && !widget.livePreviewOnly) {
      UserSession.resetScanState();
      if (!mounted) return;
      setState(() {
        _consentAccepted = true;
        _consentLoading = false;
        _needsStaging = true;
        _stagingComplete = false;
        _stageIndex = 0;
        _capturedImages = {};
        _capturedFaceRects.clear();
        _hairTexture = 'Wavy';
      });
      return;
    }

    final consented = await FaceScanService.hasConsent();
    if (!mounted) return;

    if (widget.livePreviewOnly) {
      setState(() {
        _consentAccepted = true;
        _consentLoading = false;
        _needsStaging = false;
        _stagingComplete = true;
        _capturedImages = Map.from(UserSession.capturedFaceImages ?? {});
      });
      return;
    }

    if (widget.startFresh) {
      UserSession.beginNewScanWorkingState();
    } else {
      final existing = UserSession.capturedFaceImages;
      final resumePartial =
          existing != null && existing.isNotEmpty && existing.length < 3;

      if (resumePartial) {
        await _primeHairTextureHint();
        if (!mounted) return;
        const angles = ['front', 'right', 'left'];
        var stage = 0;
        for (var i = 0; i < angles.length; i++) {
          if (!existing.containsKey(angles[i])) {
            stage = i;
            break;
          }
          stage = i + 1;
        }
        if (stage >= angles.length) {
          stage = angles.length - 1;
        }
        setState(() {
          _consentAccepted = true;
          _consentLoading = false;
          _needsStaging = true;
          _stagingComplete = false;
          _stageIndex = stage;
          _capturedImages = Map<String, String>.from(existing);
        });
        return;
      }
      // Opening AI Scan with a completed session: do not wipe it.
    }

    await _primeHairTextureHint();

    if (!mounted) return;
    setState(() {
      _consentAccepted = consented;
      _consentLoading = false;
      _needsStaging = true;
      _stagingComplete = false;
      _stageIndex = 0;
      _capturedImages = {};
      _capturedFaceRects.clear();
    });
    if (consented) {
      _prepareWorkingSessionForCapture();
    }
  }

  /// When the customer proceeds into capture after browsing entry, start a new
  /// working session without destroying the completed snapshot.
  void _prepareWorkingSessionForCapture() {
    if (widget.livePreviewOnly || widget.previewOnly || widget.kioskMode) {
      return;
    }
    if (widget.startFresh) {
      return;
    }
    final completedId = UserSession.completedScanSessionId;
    final liveId = UserSession.activeScanSessionId;
    final liveIsCompleted = UserSession.hasCompletedScanResults &&
        liveId != null &&
        completedId != null &&
        liveId == completedId;
    final liveHasCompletedCaptures = UserSession.capturedFaceImages != null &&
        UserSession.capturedFaceImages!.length >= 3 &&
        UserSession.lastScan != null;
    if (liveIsCompleted || liveHasCompletedCaptures || liveId == completedId) {
      UserSession.prepareNewCaptureSessionKeepingCompleted();
    } else if (UserSession.activeScanSessionId == null &&
        UserSession.hasCompletedScanResults) {
      UserSession.prepareNewCaptureSessionKeepingCompleted();
    }
  }

  Future<void> _primeHairTextureHint() async {
    final preferred = await UserSession.loadPreferredHairTexture();
    if (!mounted) return;
    final hint = UserSession.normalizeHairTextureLabel(preferred, fallback: 'Wavy');
    setState(() => _hairTexture = hint);
  }

  String _hairTextureFromAnalysis(Map<String, dynamic> analysis) {
    return UserSession.normalizeHairTextureLabel(
      analysis['hairTexture']?.toString() ?? analysis['hair_texture']?.toString(),
      fallback: _hairTexture,
    );
  }

  Future<void> _openResultsPage() async {
    if (!mounted || widget.livePreviewOnly) return;
    final validation = FaceScanService.validateCaptures(_capturedImages);
    if (!validation.ok) {
      setState(() {
        _needsStaging = true;
        _stagingComplete = false;
        _stageIndex = 0;
        _capturedImages = {};
        UserSession.capturedFaceImages = null;
      });
      _resumeScannerResources();
      return;
    }
    await _releaseScannerResources();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FaceScanResultsPage(
          captures: Map.from(_capturedImages),
          faceShape: _faceShape,
          hairTexture: _hairTexture,
          presetRecommendation: widget.presetRecommendation,
        ),
      ),
    );
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
      unawaited(OverlayAssetCache.preload());
      // Awaited, not fire-and-forget: the camera controller caches the device
      // orientation it sees at construction, so it must be built after the UI
      // has settled into its final rotation, not during the rotation.
      if (widget.kioskMode) {
        await AppOrientation.lockForKiosk();
      } else {
        await AppOrientation.lockForCustomer();
      }
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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      debugPrint('[AiFaceScan] Camera controller initialized successfully');
      if (widget.kioskMode && AppOrientation.kioskShouldLockCaptureToLandscape()) {
        final lockTo = CameraFrameOrientation.landscapeLockTarget(controller);
        await controller.lockCaptureOrientation(lockTo);
        debugPrint('[AiFaceScan] Locked capture orientation to $lockTo');
      }
      
      debugPrint(
        '[AiFaceScan] Starting image stream... '
        'sensor=${controller.description.sensorOrientation} '
        'lens=${controller.description.lensDirection.name} '
        'trackedOrientation=${DeviceOrientationTracker.latest} '
        'controllerOrientation=${controller.value.deviceOrientation} '
        'mlKitRotation=${CameraFrameOrientation.mlKitRotationDegreesFor(controller)}',
      );
      await controller.startImageStream((image) async {
        if (_busy || !mounted) return;
        _busy = true;
        try {
          final frame = await _detector.processFrame(
            image,
            sensorOrientation: controller.description.sensorOrientation,
            deviceOrientation:
                CameraFrameOrientation.frameOrientation(controller),
            lensDirection: controller.description.lensDirection,
          );
          if (!mounted) {
            _busy = false;
            return;
          }

          // Route to staging or live preview based on phase
          if (!_stagingComplete && _needsStaging) {
            await _processStagingFrame(frame, image);
            _busy = false;
            return;
          }

          // Live preview processing (existing logic)
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
            final noseBase = frame.landmarks?[FaceLandmarkType.noseBase.index];
            final leftEye = frame.landmarks?[FaceLandmarkType.leftEye.index];
            final rightEye = frame.landmarks?[FaceLandmarkType.rightEye.index];
            final leftEar = frame.landmarks?[FaceLandmarkType.leftEar.index];
            final rightEar = frame.landmarks?[FaceLandmarkType.rightEar.index];
            final noseBaseX = noseBase?['x'];
            final noseBaseY = noseBase?['y'];
            final leftEarX = leftEar?['x'];
            final rightEarX = rightEar?['x'];
            final stabilizedInput =
              _stabilizeIncomingRect(_smoothedFaceRect, normalized);
            final smoothedRect =
              _smoothRect(_smoothedFaceRect, stabilizedInput, _rectSmoothingAlpha);
            final smoothedYaw = _smoothValue(
                _smoothedHeadYaw, frame.headEulerAngleY, _angleSmoothingAlpha);
            final smoothedRoll = _smoothValue(
                _smoothedHeadRoll, frame.headEulerAngleZ, _angleSmoothingAlpha);
            double inferredForeheadAnchor;
            if (leftEye != null &&
                rightEye != null &&
                leftEye['y'] != null &&
                rightEye['y'] != null) {
              final eyeY = (leftEye['y']! + rightEye['y']!) / 2;
              final eyeToNose = noseBaseY != null
                  ? (noseBaseY - eyeY).abs().clamp(0.03, 0.18)
                  : smoothedRect.height * 0.14;
              inferredForeheadAnchor =
                  (eyeY - eyeToNose * 1.35).clamp(smoothedRect.top, eyeY);
            } else if (noseBaseY != null) {
              inferredForeheadAnchor =
                  (noseBaseY - (smoothedRect.height * 0.40)).clamp(0.0, 1.0);
            } else {
              inferredForeheadAnchor =
                  (smoothedRect.top + (smoothedRect.height * 0.05)).clamp(0.0, 1.0);
            }
            final smoothedForehead = _smoothValue(_smoothedForeheadAnchorY,
                inferredForeheadAnchor, _anchorSmoothingAlpha);
            final inferredEyeMidX = noseBaseX != null
              ? noseBaseX.clamp(0.0, 1.0)
              : (smoothedRect.left + (smoothedRect.width * 0.5)).clamp(0.0, 1.0);
            final inferredEyeDistance = (leftEarX != null && rightEarX != null)
              ? ((rightEarX - leftEarX).abs() * 0.55).clamp(0.04, 0.65)
              : (smoothedRect.width * 0.42).clamp(0.04, 0.65);
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

            // Update minimal-smoothing overlay tracking for low-lag real-time response.
            final minSmoothRect = _smoothRect(
              _minSmoothFaceRect,
              stabilizedInput,
              _minSmoothRectAlpha,
            );
            final minSmoothYaw = _smoothValue(
              _minSmoothHeadYaw,
              frame.headEulerAngleY,
              _minSmoothAngleAlpha,
            );
            final minSmoothRoll = _smoothValue(
              _minSmoothHeadRoll,
              frame.headEulerAngleZ,
              _minSmoothAngleAlpha,
            );
            if (mounted) {
              setState(() {
                _minSmoothFaceRect = minSmoothRect;
                _minSmoothHeadYaw = minSmoothYaw;
                _minSmoothHeadRoll = minSmoothRoll;
              });
            }

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

    // Route to staging or live preview based on phase
    if (!_stagingComplete && _needsStaging) {
      _processStagingFrameWeb();
      return;
    }

    // Live preview processing (existing logic)
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
    final eyeY = (t.eyeMidY ?? (rect.top + (rect.height * 0.36))).clamp(0.0, 1.0);
    final eyeToNose = rect.height * 0.14;
    final eyeAnchor =
        (eyeY - eyeToNose * 1.35).clamp(rect.top, eyeY);
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

  /// Live overlay try-on only — no PHP ranking on this screen.
  bool get _overlayOnlyMode => widget.livePreviewOnly || widget.previewOnly;

  bool _shouldAutoFetchRecommendations() {
    if (_overlayOnlyMode) {
      return false;
    }
    if (!widget.livePreviewOnly && !widget.previewOnly) {
      return false;
    }
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
    if (ratio < 0.70) return 'Oval';
    if (ratio > 0.84) return 'Square';
    return 'Oval';
  }

  Future<void> _fetchRecommendations({bool autoTriggered = false}) async {
    if (_overlayOnlyMode || (!widget.livePreviewOnly && !widget.previewOnly)) {
      return;
    }

    if (autoTriggered) {
      _autoProcessingStarted = true;
    }

    if (widget.presetRecommendation != null &&
        autoTriggered &&
        _recommendations.length >= 3) {
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
        headers: await CustomerApi.headers(),
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
    if (_overlayOnlyMode || (!widget.livePreviewOnly && !widget.previewOnly)) {
      return;
    }

    if (autoTriggered) {
      _autoProcessingStarted = true;
    }

    if (widget.presetRecommendation != null &&
        autoTriggered &&
        _recommendations.length >= 3) {
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
        headers: await CustomerApi.headers(),
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

  // DEPRECATED: Use _buildHairOverlay instead. Kept for reference.
  // Widget _buildHairOnlyOverlayModel(...) { ... }

  /// Main overlay builder that determines which view (front/side) to render based on yaw.
  Widget _buildHairOverlay({
    required OverlayCalibration calibration,
    required Map<String, dynamic>? recommendation,
  }) {
    if (_shouldUse3DModel(recommendation)) {
      return _buildHair3DOverlayModel(calibration: calibration);
    }

    final yaw = (_headYaw ?? 0).clamp(-60.0, 60.0);
    final yawAbs = yaw.abs();

    // Determine which view to show based on yaw angle
    if (yawAbs <= 15) {
      // FRONT VIEW ONLY: facing forward
      return _buildFrontOverlay(
        calibration: calibration,
        recommendation: recommendation,
      );
    } else if (yawAbs >= 25) {
      // SIDE VIEW ONLY: turned significantly
      return _buildSideOverlay(
        calibration: calibration,
        recommendation: recommendation,
        yaw: yaw,
        opacity: 1.0,
      );
    } else {
      // TRANSITION ZONE (15-25°): crossfade between front and side
      final t = ((yawAbs - 15) / 10).clamp(0.0, 1.0); // 0 at 15°, 1 at 25°
      return Stack(
        children: [
          Opacity(
            opacity: 1.0 - t,
            child: _buildFrontOverlay(
              calibration: calibration,
              recommendation: recommendation,
            ),
          ),
          Opacity(
            opacity: t,
            child: _buildSideOverlay(
              calibration: calibration,
              recommendation: recommendation,
              yaw: yaw,
              opacity: t,
            ),
          ),
        ],
      );
    }
  }

  /// Front view overlay: shows only the front image, centered and at full size.
  Widget _buildFrontOverlay({
    required OverlayCalibration calibration,
    required Map<String, dynamic>? recommendation,
  }) {
    final overlayImageSet = _resolveOverlayImageSet(recommendation);
    final frontImage = overlayImageSet.front;
    final frontAsset = _assetPath(frontImage);

    return Transform.scale(
      scale: calibration.visualScale,
      alignment: Alignment.bottomCenter,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Image.asset(
          frontAsset,
          fit: BoxFit.fitWidth,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('[AiFaceScan] Failed to load front overlay: $frontImage');
            return const ColoredBox(color: Colors.transparent);
          },
        ),
      ),
    );
  }

  /// Side view overlay: shows only the side image, anchored to the ear/temple.
  Widget _buildSideOverlay({
    required OverlayCalibration calibration,
    required Map<String, dynamic>? recommendation,
    required double yaw,
    required double opacity,
  }) {
    final overlayImageSet = _resolveOverlayImageSet(recommendation);
    final isRightTurn = yaw >= 0;
    // Asset filenames were swapped: use opposite file for head turn direction.
    final sideImage = isRightTurn ? overlayImageSet.left : overlayImageSet.right;
    final sideAsset = _assetPath(sideImage);
    final yawAbsNorm = (yaw.abs() / 34.0).clamp(0.0, 1.0);

    // Side image anchors to the ear side, not the nose
    final sideAlignment = isRightTurn ? Alignment.centerRight : Alignment.centerLeft;

    return Transform.scale(
      scale: calibration.visualScale,
      alignment: Alignment.topCenter,
      child: Align(
        alignment: sideAlignment,
        widthFactor: (0.72 + (yawAbsNorm * 0.22)).clamp(0.72, 0.94),
        child: Transform.translate(
          offset: Offset(
            (isRightTurn ? 1.0 : -1.0) * yawAbsNorm * 12.0,
            0,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              sideAsset,
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('[AiFaceScan] Failed to load side overlay: $sideImage');
                return const ColoredBox(color: Colors.transparent);
              },
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
  }

  void _seedRecommendationsForLivePreview() {
    final preset = widget.presetRecommendation;

    _recommendations.clear();
    _selectedIndex = 0;

    if (widget.livePreviewOnly) {
      _loadingRecommendations = false;
      _status = 'Live preview — move your head to see the selected style.';
      if (preset != null) {
        final normalized = _normalizePresetRecommendation(preset);
        _recommendations.add(normalized);
        _overlayPresetOnly = normalized;
      } else {
        _overlayPresetOnly = null;
      }
      return;
    }

    _loadingRecommendations = false;
    _status =
        'Complete the 3-angle capture to open your personalized recommendations.';
    if (preset != null) {
      _overlayPresetOnly = _normalizePresetRecommendation(preset);
    } else {
      _overlayPresetOnly = null;
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

  bool get _stagingUsesFrontCamera =>
      _camera?.description.lensDirection == CameraLensDirection.front;

  Rect _normalizeStagingFace(DetectedFaceFrame frame) {
    final camera = _camera;
    final rotated = FacePreviewMapping.normalizeBoundingBox(
      boundingBox: frame.boundingBox,
      imageSize: frame.imageSize,
      rotationDegrees: camera == null
          ? 90
          : CameraFrameOrientation.mlKitRotationDegreesFor(camera),
      mirrorX: _stagingUsesFrontCamera,
    );
    return _stagingViewportFace(rotated);
  }

  Rect _stagingViewportFace(Rect sourceNorm) {
    final view = _stagingViewSize;
    final camera = _camera;
    if (view == null || camera == null || !camera.value.isInitialized) {
      return sourceNorm;
    }
    final layout = CameraFrameOrientation.previewLayoutSizeFor(camera);
    if (layout.width <= 0 || layout.height <= 0) {
      return sourceNorm;
    }
    return FacePreviewMapping.sourceToCoverViewport(
      face: sourceNorm,
      sourceAspect: layout.width / layout.height,
      viewport: view,
    );
  }

  void _logStaging(String message) {
    if (_lastStagingLog == message) {
      return;
    }
    _lastStagingLog = message;
    debugPrint('[ScanStaging] $message');
  }

  Future<void> _processStagingFrame(DetectedFaceFrame? frame, CameraImage image) async {
    if (frame == null) {
      _logStaging('no_face');
      setState(() {
        _currentFaceRect = null;
        _isGoodPosition = false;
        _goodPositionFrames =
            (_goodPositionFrames - StagingFaceValidation.missDecay)
                .clamp(0, StagingFaceValidation.holdFrames);
        _status = 'Face not detected. Keep your face visible.';
      });
      return;
    }

    final normalized = _normalizeStagingFace(frame);
    // Pose uses raw ML Kit yaw. BBox is mirrored to match CameraPreview.
    final yaw = frame.headEulerAngleY;
    final stage = _stages[_stageIndex.clamp(0, _stages.length - 1)];
    final isGood = StagingFaceValidation.isWellPositioned(
      face: normalized,
      yaw: yaw,
      requiredYaw: stage.requiredYaw,
      tolerance: stage.yawTolerance,
      kioskMode: widget.kioskMode,
    );
    final rejectReason = isGood
        ? ''
        : StagingFaceValidation.rejectReason(
            face: normalized,
            yaw: yaw,
            requiredYaw: stage.requiredYaw,
            tolerance: stage.yawTolerance,
            fallbackHint: stage.hint,
            kioskMode: widget.kioskMode,
          );

    _logStaging(
      isGood
          ? 'accepted yaw=${yaw?.toStringAsFixed(1)} area=${(normalized.width * normalized.height).toStringAsFixed(3)}'
          : 'rejected $rejectReason yaw=${yaw?.toStringAsFixed(1)} '
              'area=${(normalized.width * normalized.height).toStringAsFixed(3)} '
              'c=${normalized.center.dx.toStringAsFixed(2)},${normalized.center.dy.toStringAsFixed(2)}',
    );

    setState(() {
      _currentFaceRect = normalized;
      _isGoodPosition = isGood;
      _currentHeadYaw = yaw;

      if (isGood) {
        _goodPositionFrames++;
        _status =
            '${stage.label} - Hold still ${(StagingFaceValidation.holdFrames - _goodPositionFrames).clamp(0, StagingFaceValidation.holdFrames)}';
      } else {
        _goodPositionFrames =
            (_goodPositionFrames - StagingFaceValidation.missDecay)
                .clamp(0, StagingFaceValidation.holdFrames);
        _status = rejectReason.isNotEmpty ? rejectReason : stage.hint;
      }
    });

    if (_goodPositionFrames >= StagingFaceValidation.holdFrames) {
      await _captureCurrent(image);
    }
  }

  Future<void> _processStagingFrameWeb() async {
    // Web staging uses the web camera controller to capture frames
    final tracked = _webCamera.tracking.value;
    if (tracked.faceRect == null) {
      _logStaging('no_face');
      setState(() {
        _currentFaceRect = null;
        _isGoodPosition = false;
        _goodPositionFrames =
            (_goodPositionFrames - StagingFaceValidation.missDecay)
                .clamp(0, StagingFaceValidation.holdFrames);
        _status = 'Face not detected. Keep your face visible.';
      });
      return;
    }

    final stage = _stages[_stageIndex.clamp(0, _stages.length - 1)];
    final isGood = StagingFaceValidation.isWellPositioned(
      face: tracked.faceRect!,
      yaw: tracked.headYaw,
      requiredYaw: stage.requiredYaw,
      tolerance: stage.yawTolerance,
      kioskMode: widget.kioskMode,
    );
    final rejectReason = isGood
        ? ''
        : StagingFaceValidation.rejectReason(
            face: tracked.faceRect!,
            yaw: tracked.headYaw,
            requiredYaw: stage.requiredYaw,
            tolerance: stage.yawTolerance,
            fallbackHint: stage.hint,
            kioskMode: widget.kioskMode,
          );

    _logStaging(
      isGood
          ? 'accepted yaw=${tracked.headYaw?.toStringAsFixed(1)}'
          : 'rejected $rejectReason yaw=${tracked.headYaw?.toStringAsFixed(1)}',
    );

    setState(() {
      _currentFaceRect = tracked.faceRect;
      _isGoodPosition = isGood;
      _currentHeadYaw = tracked.headYaw;

      if (isGood) {
        _goodPositionFrames++;
        _status =
            '${stage.label} - Hold still ${(StagingFaceValidation.holdFrames - _goodPositionFrames).clamp(0, StagingFaceValidation.holdFrames)}';
      } else {
        _goodPositionFrames =
            (_goodPositionFrames - StagingFaceValidation.missDecay)
                .clamp(0, StagingFaceValidation.holdFrames);
        _status = rejectReason.isNotEmpty ? rejectReason : stage.hint;
      }
    });

    if (_goodPositionFrames >= StagingFaceValidation.holdFrames) {
      await _captureCurrentWeb();
    }
  }

  Future<void> _captureCurrent(CameraImage image) async {
    if (_camera == null || !_camera!.value.isInitialized || _finishingStaging) {
      return;
    }
    try {
      final stage = _stages[_stageIndex];
      await _camera!.stopImageStream();
      final file = await _camera!.takePicture();
      final bytes = await file.readAsBytes();
      if (!FaceScanService.isValidJpeg(bytes)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid ${stage.label} capture. Hold steady and try again.')),
          );
        }
        await _restartStagingStream();
        return;
      }
      final base64Image = base64Encode(bytes);
      if (_currentFaceRect != null) {
        _capturedFaceRects[stage.keyName] = _currentFaceRect!;
      }
      setState(() {
        _capturedImages[stage.keyName] = base64Image;
        _goodPositionFrames = 0;
      });

      if (_stageIndex < _stages.length - 1) {
        setState(() => _stageIndex++);
        await _restartStagingStream();
      } else {
        UserSession.capturedFaceImages = Map.from(_capturedImages);
        UserSession.captureFaceRects = Map.from(_capturedFaceRects);
        await _finishStagingCapture();
      }
    } catch (e) {
      debugPrint('[AiFaceScan] Capture error: $e');
      await _restartStagingStream();
    }
  }

  Future<void> _restartStagingStream() async {
    if (_camera == null || !_camera!.value.isInitialized || _stagingComplete) {
      return;
    }
    if (_camera!.value.isStreamingImages) {
      return;
    }
    await _camera!.startImageStream((image) async {
      if (_busy || !mounted) return;
      _busy = true;
      try {
        final frame = await _detector.processFrame(
          image,
          sensorOrientation: _camera!.description.sensorOrientation,
          deviceOrientation:
              CameraFrameOrientation.frameOrientation(_camera!),
          lensDirection: _camera!.description.lensDirection,
        );
        if (!mounted) {
          _busy = false;
          return;
        }
        if (!_stagingComplete && _needsStaging) {
          await _processStagingFrame(frame, image);
        }
      } finally {
        _busy = false;
      }
    });
  }

  Future<void> _captureCurrentWeb() async {
    try {
      final stage = _stages[_stageIndex];
      final frameBytes = await _webCamera.capture();
      if (frameBytes == null) {
        debugPrint('[AiFaceScan] Web capture failed');
        return;
      }
      
      if (!FaceScanService.isValidJpeg(frameBytes)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid ${stage.label} capture. Please try again.')),
          );
        }
        return;
      }
      final base64Image = base64Encode(frameBytes);
      if (_currentFaceRect != null) {
        _capturedFaceRects[stage.keyName] = _currentFaceRect!;
      }
      
      setState(() {
        _capturedImages[stage.keyName] = base64Image;
        _goodPositionFrames = 0;
      });

      if (_stageIndex < _stages.length - 1) {
        setState(() => _stageIndex++);
      } else {
        UserSession.capturedFaceImages = Map.from(_capturedImages);
        UserSession.captureFaceRects = Map.from(_capturedFaceRects);
        await _finishStagingCapture();
      }
    } catch (e) {
      debugPrint('[AiFaceScan] Web capture error: $e');
    }
  }

  Future<void> _finishStagingCapture() async {
    if (_finishingStaging) return;
    _finishingStaging = true;

    // Stop camera immediately — staging is done; avoid stream running on results route.
    await _releaseScannerResources();

    final validation = FaceScanService.validateCaptures(_capturedImages);
    if (!validation.ok) {
      _finishingStaging = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(validation.error ?? 'Invalid captures')),
        );
        _resumeScannerResources();
      }
      return;
    }

    if (_currentFaceRect != null) {
      _faceShape = _inferFaceShape(_currentFaceRect!.width, _currentFaceRect!.height);
    }

    if (mounted) {
      setState(() => _stagingComplete = true);
    }

    // Ensure uploads go to a fresh session when leaving a completed one behind.
    _prepareWorkingSessionForCapture();
    final scanSessionId = UserSession.ensureScanSessionId();
    try {
      await FaceScanService.uploadCaptures(
        scanSessionId: scanSessionId,
        userId: UserSession.userId,
        captures: _capturedImages,
        faceShape: _faceShape,
        hairTexture: _hairTexture,
        hairDensity: UserSession.lastScan?['hairDensity']?.toString(),
      );
    } catch (e) {
      _finishingStaging = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
        setState(() => _stagingComplete = false);
        _resumeScannerResources();
      }
      return;
    }

    var analyzedFaceShape = _faceShape;
    var analyzedHairTexture = _hairTexture;
    var hairLengthLevel = 1;
    var hairLengthLabel = 'short';
    var analysisProvider = 'fallback';
    var hairTextureScore = 0.0;
    var noHairDetected = false;
    var hairColorLabel = '';
    List<dynamic> pythonTopStyles = [];
    try {
      final analysis = await FaceScanService.analyzeCaptures(scanSessionId: scanSessionId);
      analyzedFaceShape = analysis['faceShape']?.toString() ?? _faceShape;
      analyzedHairTexture = _hairTextureFromAnalysis(analysis);
      hairLengthLevel = int.tryParse('${analysis['hairLengthLevel']}') ?? 1;
      hairLengthLabel = analysis['hairLength']?.toString() ?? 'short';
      analysisProvider = analysis['provider']?.toString() ?? 'ai-service';
      hairTextureScore =
          double.tryParse('${analysis['hairTextureScore']}') ?? 0.0;
      noHairDetected = analysis['noHairDetected'] == true;
      hairColorLabel = analysis['hairColor']?.toString() ?? '';
      pythonTopStyles = analysis['topStyles'] as List<dynamic>? ?? [];
      // A degraded response is HTTP 200 but carries placeholder values, not a
      // real measurement. Treat it as a failed scan so hair-texture guidance
      // does not present fabricated data as confirmed.
      final degraded = analysis['degraded'] == true;
      if (mounted) {
        setState(() => _hairTexture = analyzedHairTexture);
        if (degraded) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'AI analysis could not read your photos this time. Showing an '
                'estimate only — style suitability will not be checked.',
              ),
            ),
          );
        }
      }
      UserSession.lastScan = {
        'userId': UserSession.userId,
        'scanSessionId': scanSessionId,
        'faceShape': analyzedFaceShape,
        'hairTexture': analyzedHairTexture,
        'hairLength': hairLengthLabel,
        'hairLengthLevel': hairLengthLevel,
        'analysisProvider': analysisProvider,
        'hairTextureScore': hairTextureScore,
        'scanSucceeded': !degraded,
        'noHairDetected': noHairDetected,
        'hairColor': hairColorLabel,
        'pythonTopStyles': pythonTopStyles,
        'achievableStyles': analysis['achievableStyles'] ?? [],
      };
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'AI analysis unavailable (${e.toString()}). Using profile hair type estimate.',
            ),
          ),
        );
      }
      UserSession.lastScan = {
        'userId': UserSession.userId,
        'scanSessionId': scanSessionId,
        'faceShape': analyzedFaceShape,
        'hairTexture': analyzedHairTexture,
        'hairLength': hairLengthLabel,
        'hairLengthLevel': hairLengthLevel,
        'analysisProvider': 'fallback',
        'hairTextureScore': 0.0,
        'scanSucceeded': false,
        'noHairDetected': false,
        'hairColor': '',
        'pythonTopStyles': <dynamic>[],
      };
    }

    _finishingStaging = false;
    if (!mounted) return;
    await _releaseScannerResources();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FaceScanResultsPage(
          captures: Map.from(_capturedImages),
          faceShape: analyzedFaceShape,
          hairTexture: analyzedHairTexture,
          hairLengthLevel: hairLengthLevel,
          hairLengthLabel: hairLengthLabel,
          analysisProvider: UserSession.lastScan?['analysisProvider']?.toString(),
          hairTextureScore: (UserSession.lastScan?['hairTextureScore'] as num?)?.toDouble(),
          noHairDetected: UserSession.lastScan?['noHairDetected'] == true,
          hairColorLabel: UserSession.lastScan?['hairColor']?.toString(),
          presetRecommendation: widget.presetRecommendation,
          kioskMode: widget.kioskMode,
        ),
      ),
    );
  }

  void _continueKioskFromLivePreview() {
    final variantId = widget.presetRecommendation?['variant_id'] ??
        widget.presetRecommendation?['variantId'];
    if (variantId != null) {
      KioskSession.selectedVariantId = int.tryParse('$variantId');
      UserSession.selectedVariantId = KioskSession.selectedVariantId;
    }
    final styleName = widget.presetRecommendation?['style_name'] ??
        widget.presetRecommendation?['styleName'];
    if (styleName != null) {
      KioskSession.selectedStyleName = styleName.toString();
      UserSession.selectedStyleName = KioskSession.selectedStyleName;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskBarberPage()),
    );
  }

  String _stagingPositionLabel() {
    if (_isGoodPosition) {
      final left = (StagingFaceValidation.holdFrames - _goodPositionFrames)
          .clamp(0, StagingFaceValidation.holdFrames);
      return 'Position good! Hold still $left';
    }
    return _status.isNotEmpty ? _status : 'Adjust position';
  }

  Future<void> _popScanner() async {
    await _releaseScannerResources();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmExitScanner() async {
    if (widget.kioskMode) {
      return true;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Leave scan?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your current capture session will be discarded. You will need to scan again for fresh recommendations.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _exitScannerFlow() async {
    final leave = await _confirmExitScanner();
    if (!leave || !mounted) {
      return;
    }
    UserSession.discardInProgressAndRestoreCompleted();
    unawaited(_releaseScannerResources());
    // Always return to dashboard so back never leaves an empty navigator route.
    navigateToCustomerHome(context);
  }

  void _onScannerBottomNav(int index) {
    if (index == 0) {
      if (widget.kioskMode) {
        unawaited(_exitScannerFlow());
      } else {
        unawaited(_popScanner());
      }
    } else if (index == 1) {
      openCustomerTab(context, CustomerTab.appointments);
    } else if (index == 2) {
      return;
    } else if (index == 3) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SavedHaircutsPage()),
      );
    } else if (index == 4) {
      showAppMenuSheet(context);
    }
  }

  Widget _buildStagingUI() {
    final currentStage = _stages[_stageIndex.clamp(0, _stages.length - 1)];
    final progress = (_stageIndex + (_goodPositionFrames / StagingFaceValidation.holdFrames)) / _stages.length;
    final camera = kIsWeb
        ? _buildStagingWebCamera(currentStage)
        : _buildStagingCameraView(currentStage);

    return PopScope(
      canPop: widget.kioskMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_popScanner());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppTopBar(
          showBack: true,
          showCustomerActions: !widget.kioskMode,
          onBack: () => unawaited(_popScanner()),
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(widget.kioskMode ? 16 : 20),
            child: widget.kioskMode
                ? _buildKioskLandscapeStaging(
                    camera: camera,
                    progress: progress,
                  )
                : _buildPortraitStaging(
                    camera: camera,
                    progress: progress,
                  ),
          ),
        ),
        bottomNavigationBar: widget.kioskMode
            ? null
            : AppBottomNavBar(
                currentIndex: 2,
                onTap: _onScannerBottomNav,
              ),
      ),
    );
  }

  Widget _buildPortraitStaging({
    required Widget camera,
    required double progress,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'We will capture three angles of your face for the best preview.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 18),
        LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 8,
          backgroundColor: Colors.white12,
          color: Colors.white,
        ),
        const SizedBox(height: 18),
        Expanded(child: camera),
        const SizedBox(height: 14),
        _stageStatusRow(vertical: false),
      ],
    );
  }

  /// Landscape kiosk: camera on the left, stage checklist on the right.
  Widget _buildKioskLandscapeStaging({
    required Widget camera,
    required double progress,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: camera,
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'We will capture three angles of your face for the best preview.',
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppBrand.goldTint,
                color: AppBrand.gold,
              ),
              const SizedBox(height: 16),
              Expanded(child: _stageStatusRow(vertical: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _kioskLivePreviewBottomBar() {
    if (!widget.kioskMode || !widget.livePreviewOnly) return null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _continueKioskFromLivePreview,
            style: AppBrand.primaryButton,
            child: const Text('Continue to barber selection', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _buildStagingWebCamera(_CaptureStage stage) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isGoodPosition ? const Color(0xFF4CAF50) : Colors.white24,
          width: 3,
        ),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: _webCameraReady
              ? WebCameraView(controller: _webCamera)
              : Center(
                  child: Text(
                    _webCamera.tracking.value.trackerSupported
                        ? 'Starting camera...'
                        : 'Camera or face tracking unavailable. Allow camera access and reload the page.',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.label,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  stage.hint,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      _isGoodPosition ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _isGoodPosition ? const Color(0xFF4CAF50) : Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _stagingPositionLabel(),
                        style: TextStyle(
                          color: _isGoodPosition ? const Color(0xFF4CAF50) : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStagingCameraView(_CaptureStage stage) {
    if (_camera == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Text('Camera not available', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isGoodPosition ? const Color(0xFF4CAF50) : Colors.white24,
          width: 3,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: CameraPreviewCover(controller: _camera!),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _stagingViewSize = constraints.biggest;
                return const SizedBox.expand();
              },
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.label,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  stage.hint,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      _isGoodPosition ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _isGoodPosition ? const Color(0xFF4CAF50) : Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _stagingPositionLabel(),
                        style: TextStyle(
                          color: _isGoodPosition ? const Color(0xFF4CAF50) : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageStatusRow({bool vertical = false}) {
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _stages.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Expanded(
              child: _stageLandscapeTile(
                stage: _stages[i],
                index: i,
              ),
            ),
          ],
        ],
      );
    }

    // Portrait: always reserve three equal columns so capturing Front cannot
    // shrink the status cards or leave a gap on the right.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final count = _stages.length;
        final slotWidth = (constraints.maxWidth - gap * (count - 1)) / count;

        Widget slot({required Widget child, required double height}) {
          return SizedBox(
            width: slotWidth,
            height: height,
            child: child,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  slot(
                    height: 72,
                    child: _stageThumbnailSlot(_stages[i]),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  slot(
                    height: 78,
                    child: _stageStatusCard(
                      stage: _stages[i],
                      index: i,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _stageLandscapeTile({
    required _CaptureStage stage,
    required int index,
  }) {
    final captured = _capturedImages.containsKey(stage.keyName);
    final active = index == _stageIndex;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: captured
            ? const Color(0xFF1B1B1B)
            : active
                ? const Color(0xFF18120A)
                : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: captured
              ? Colors.white.withOpacity(0.6)
              : active
                  ? Colors.white24
                  : Colors.white12,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: _stageThumbnailSlot(stage),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        stage.icon,
                        size: 20,
                        color: captured ? Colors.white : Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stage.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    captured
                        ? 'Captured'
                        : active
                            ? stage.hint
                            : 'Pending',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: captured
                          ? const Color(0xFF8FD49A)
                          : active
                              ? Colors.white70
                              : Colors.white54,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              captured
                  ? '✓'
                  : active
                      ? '...'
                      : '',
              style: TextStyle(
                color: captured ? Colors.white : Colors.white54,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stageThumbnailSlot(_CaptureStage stage) {
    final b64 = _capturedImages[stage.keyName];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: b64 != null
            ? Image.memory(
                base64Decode(b64),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.center,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => Icon(
                  stage.icon,
                  size: 22,
                  color: Colors.white24,
                ),
              )
            : Center(
                child: Icon(stage.icon, size: 22, color: Colors.white24),
              ),
      ),
    );
  }

  Widget _stageStatusCard({
    required _CaptureStage stage,
    required int index,
  }) {
    final captured = _capturedImages.containsKey(stage.keyName);
    final active = index == _stageIndex;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: captured
            ? const Color(0xFF1B1B1B)
            : active
                ? const Color(0xFF18120A)
                : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: captured
              ? Colors.white.withOpacity(0.6)
              : active
                  ? Colors.white24
                  : Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              stage.icon,
              size: 18,
              color: captured ? Colors.white : Colors.white54,
            ),
            const SizedBox(height: 4),
            Text(
              stage.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              captured
                  ? '✓'
                  : active
                      ? '...'
                      : 'Pending',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: captured ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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

  double _scannerHeightForLayout(BuildContext context) =>
      ScannerLayout.previewHeight(context);

  Widget _buildConsentUI() {
    return PopScope(
      canPop: widget.kioskMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_popScanner());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppTopBar(
          showBack: true,
          showCustomerActions: !widget.kioskMode,
          onBack: () => unawaited(_popScanner()),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Before we capture your face for haircut recommendations, please confirm:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  '• We capture front, left, and right photos once per session.\n'
                  '• Images are stored securely for AI styling and your appointment preview.\n'
                  '• You can delete data by contacting the shop or signing out.\n'
                  '• Live camera preview is optional after static capture.',
                  style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.45),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _consentFormAgreed = !_consentFormAgreed),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _consentFormAgreed,
                            onChanged: (v) => setState(() => _consentFormAgreed = v ?? false),
                            activeColor: widget.kioskMode ? AppBrand.gold : Colors.white,
                            checkColor: Colors.black,
                            side: BorderSide(
                              color: widget.kioskMode ? AppBrand.gold : Colors.white54,
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12, right: 4),
                              child: Text(
                                'I consent to face capture and AI-powered haircut recommendations.',
                                style: TextStyle(
                                  color: _consentFormAgreed ? Colors.white : Colors.white70,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _consentFormAgreed
                        ? () async {
                            await FaceScanService.saveConsent();
                            if (!mounted) return;
                            _prepareWorkingSessionForCapture();
                            setState(() => _consentAccepted = true);
                          }
                        : null,
                    style: widget.kioskMode
                        ? AppBrand.primaryButton
                        : ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.white24,
                            disabledForegroundColor: Colors.white38,
                            minimumSize: const Size.fromHeight(48),
                          ),
                    child: const Text('Continue to capture', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: widget.kioskMode
            ? null
            : AppBottomNavBar(
                currentIndex: 2,
                onTap: _onScannerBottomNav,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_consentLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (!_consentAccepted && !widget.livePreviewOnly) {
      return _buildConsentUI();
    }

    if (_finishingStaging) {
      return const Scaffold(
        backgroundColor: Color(0xFF090909),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 14),
              Text('Saving your captures...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    // Show staging UI if needed and not complete
    if (_needsStaging && !_stagingComplete && !_initialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF090909),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_needsStaging && !_stagingComplete) {
      return _buildStagingUI();
    }

    if (!widget.livePreviewOnly && !widget.previewOnly) {
      return const Scaffold(
        backgroundColor: Color(0xFF090909),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    // Live preview (optional path)
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        showCustomerActions: !widget.kioskMode,
        onBack: () {
          if (widget.kioskMode) {
            unawaited(_exitScannerFlow());
          } else {
            unawaited(_popScanner());
          }
        },
      ),
      bottomNavigationBar: widget.kioskMode
          ? _kioskLivePreviewBottomBar()
          : AppBottomNavBar(
              currentIndex: 2,
              onTap: _onScannerBottomNav,
            ),
      floatingActionButton:
          widget.kioskMode ? null : const AiChatbotFab(heroTag: 'scanner_ai_chat_fab'),
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
                        Text(
                          widget.livePreviewOnly
                              ? 'Live style preview'
                              : 'Live Hair Preview',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700),
                        ),
                        if (UserSession.lastScan?['noHairDetected'] == true) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Text(
                              'Little or no visible hair detected — you can still preview styles.',
                              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                        if (widget.previewOnly && widget.captureSummary != null) ...[
                          const SizedBox(height: 10),
                          _buildCaptureSummaryCard(widget.captureSummary!),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _status,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        if (!_overlayOnlyMode) ...[
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
                        ] else ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Move your head to see how the selected cut looks. '
                            'Go back for your full AI recommendations.',
                            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                          ),
                        ],
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
                                backgroundColor: Colors.white,
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
                        ] else if (widget.livePreviewOnly) ...[
                          const SizedBox(height: 8),
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
                                backgroundColor: Colors.white,
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
                    if (!_overlayOnlyMode) _buildSlidingControlsSheet(constraints),
                if (_showCalibrationMode && !_overlayOnlyMode) _buildCalibrationOverlay(),
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
          items: const ['Straight', 'Wavy', 'Curly']
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
                border: Border.all(color: Colors.white),
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
                            backgroundColor: Colors.white,
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
        : _overlayPresetOnly;
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
                    final sourceAspect = (_webVideoAspect != null && _webVideoAspect! > 0)
                        ? _webVideoAspect!
                        : (9 / 16);
                    return ClipRect(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxWidth / sourceAspect,
                          child: WebCameraView(controller: _webCamera),
                        ),
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
            CameraPreviewCover(controller: _camera!),
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

  Widget _buildCaptureSummaryCard(Map<String, dynamic> summary) {
    Widget scoreRow(String label, dynamic value) {
      final text = value?.toString() ?? '-';
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Capture Analysis',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          scoreRow('Front', summary['frontScore']),
          const SizedBox(height: 6),
          scoreRow('Right', summary['rightScore']),
          const SizedBox(height: 6),
          scoreRow('Left', summary['leftScore']),
          const Divider(color: Colors.white12, height: 20),
          scoreRow('Overall', summary['overallScore']),
          const SizedBox(height: 6),
          Text(
            'Recommended style: ${summary['recommendedStyle']?.toString() ?? '-'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
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
      return null;
    }

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
    // Use minimal-smooth box for real-time, low-lag overlay transforms.
    final minSmoothBox = _computeAttachmentBoxMinSmooth(
      face: anchorFace,
      constraints: constraints,
      calibration: calibration,
    );
    // Don't render if box is invalid (face too far, etc.)
    if (minSmoothBox.width <= 0 || minSmoothBox.height <= 0) {
      return null;
    }
    // For side views, shift the box toward the ear to match the side overlay anchor
    final isSideView = (_headYaw?.abs() ?? 0) >= 15;
    final sideBox = isSideView
        ? OverlayBox(
            left: (_headYaw ?? 0) >= 0
                ? minSmoothBox.left + (minSmoothBox.width * 0.15) // Shift right for right turn
                : minSmoothBox.left - (minSmoothBox.width * 0.15), // Shift left for left turn
            top: minSmoothBox.top,
            width: minSmoothBox.width,
            height: minSmoothBox.height,
            yawScale: minSmoothBox.yawScale,
          )
        : minSmoothBox;

    return Positioned(
      left: sideBox.left,
      top: sideBox.top,
      width: sideBox.width,
      height: sideBox.height,
      child: IgnorePointer(
        child: Opacity(
          opacity: overlayOpacity,
          child: Transform(
            alignment: (_headYaw ?? 0) >= 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            transform: Matrix4.identity()
              ..rotateZ((_minSmoothHeadRoll ?? 0) * math.pi / 180)
              ..scale(sideBox.yawScale, 1.0),
            child: _buildHairOverlay(
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
    final ready = _faceSessionReady;

    return IgnorePointer(
      child: Stack(
        children: [
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
                      : 'Center your face and hold still',
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
    if (_loadingRecommendations && _recommendations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Finding your top 3 haircuts...',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

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
    ranked.sort((a, b) {
      final sa = double.tryParse('${a['match_score'] ?? a['matchScore'] ?? 0}') ?? 0;
      final sb = double.tryParse('${b['match_score'] ?? b['matchScore'] ?? 0}') ?? 0;
      if (sa != sb) return sb.compareTo(sa);
      final ca = double.tryParse(
              '${a['confidence_score'] ?? a['confidenceScore'] ?? 0}') ??
          0;
      final cb = double.tryParse(
              '${b['confidence_score'] ?? b['confidenceScore'] ?? 0}') ??
          0;
      return cb.compareTo(ca);
    });
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
    if (_bookingInFlight || _recommendations.isEmpty) {
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

    setState(() => _bookingInFlight = true);

    try {
      // 30s: same Render cold-start reason as hairstyle_detail_page.
      final hasActive = await BookingGuard.hasActiveAppointment(userId: userId)
          .timeout(const Duration(seconds: 30));
      if (!mounted) {
        return;
      }
      if (hasActive) {
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

      unawaited(
        AiFunnelService.saveSelection(
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
        ).catchError((_) {}),
      );

      final result = await BookingSlotsService.fetchBestSuggestion();
      if (!mounted) {
        return;
      }

      if (result.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage!)),
        );
        return;
      }

      if (!result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No available slots found. Please choose manually.'),
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
        builder: (_) => SuggestedAppointmentPage(
          suggestion: result.suggestion!,
          alternatives: result.alternatives,
        ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _bookingInFlight = false);
      }
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
    // Don't return a position if face isn't ready
    if (!_faceSessionReady) {
      return null;
    }
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
      // Use minimal-smoothing rect for overlay placement (low-lag real-time response).
      final minSmooth = _minSmoothFaceRect ?? current;
      if (minSmooth != null && _isLikelyStableFace(minSmooth)) {
        return minSmooth;
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
    // Don't show overlay if face isn't confirmed ready (centered, stable, enough frames)
    if (!_faceSessionReady) {
      return 0.0;
    }
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
      return OverlayRegistry.sample;
    }
    final styleName = recommendation['style_name']?.toString() ??
        recommendation['styleName']?.toString() ??
        '';
    if (styleName.trim().isEmpty) {
      return OverlayRegistry.sample;
    }
    return OverlayRegistry.resolve(styleName);
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

    var matched = false;
    for (final entry in _styleCalibration.entries) {
      if (styleName.contains(entry.key)) {
        base = entry.value;
        matched = true;
        break;
      }
    }
    if (!matched) {
      base = OverlayRegistry.calibrationFor(styleName);
    }

    return _adaptCalibrationToFace(base);
  }

  double _scannerSourceAspect() {
    if (kIsWeb) {
      return (_webVideoAspect != null && _webVideoAspect! > 0)
          ? _webVideoAspect!
          : (9 / 16);
    }
    final preview = _camera?.value.previewSize;
    if (preview != null && preview.height > 0) {
      return preview.height / preview.width;
    }
    return 3 / 4;
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
        sourceAspect: _scannerSourceAspect(),
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

    // Minimal-smoothing version for real-time overlay response (low-lag).
    OverlayBox _computeAttachmentBoxMinSmooth({
      required Rect face,
      required BoxConstraints constraints,
      required OverlayCalibration calibration,
    }) {
      final yawAbsNorm = ((_minSmoothHeadYaw ?? 0).abs() / 34.0).clamp(0.0, 1.0);
      final anchorX = yawAbsNorm > 0.12 && _lastCenteredFaceRect != null
          ? _lastCenteredFaceRect!.center.dx
          : (face.left + (face.width * 0.5));
      return _attachmentEngine.compute(
        AttachmentInput(
          face: face,
          constraints: constraints,
          calibration: calibration,
          isWeb: kIsWeb,
          headYaw: _minSmoothHeadYaw,
          headRoll: _minSmoothHeadRoll,
          foreheadAnchorY: _foreheadAnchorY,
          eyeMidX: anchorX,
          eyeDistanceNorm: _eyeDistanceNorm,
          sourceAspect: _scannerSourceAspect(),
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

class _CaptureStage {
  final String keyName;
  final String label;
  final String hint;
  final IconData icon;
  final double requiredYaw;
  final double yawTolerance;

  const _CaptureStage({
    required this.keyName,
    required this.label,
    required this.hint,
    required this.icon,
    required this.requiredYaw,
    required this.yawTolerance,
  });
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