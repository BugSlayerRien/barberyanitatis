import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'face_scan_results_page.dart';
import 'services/face_scan_service.dart';
import 'scanner/face_detector_service_stub.dart'
  if (dart.library.io) 'scanner/face_detector_service_mobile.dart';
import 'user_session.dart';

class HaircutPreviewScannerPage extends StatefulWidget {
  final Map<String, dynamic> style;

  const HaircutPreviewScannerPage({super.key, required this.style});

  @override
  State<HaircutPreviewScannerPage> createState() => _HaircutPreviewScannerPageState();
}

class _HaircutPreviewScannerPageState extends State<HaircutPreviewScannerPage>
    with WidgetsBindingObserver {
  // ===== STAGING PHASE VARIABLES =====
  static const List<_CaptureStage> _stages = [
    _CaptureStage(
      keyName: 'front',
      label: 'Front view',
      hint: 'Face the camera straight ahead and keep still.',
      icon: Icons.face,
      requiredYaw: 0,
      yawTolerance: 10,
    ),
    _CaptureStage(
      keyName: 'right',
      label: 'Right view',
      hint: 'Turn your face to the right (about 45 degrees).',
      icon: Icons.turn_right,
      requiredYaw: -45,
      yawTolerance: 15,
    ),
    _CaptureStage(
      keyName: 'left',
      label: 'Left view',
      hint: 'Turn your face to the left (about 45 degrees).',
      icon: Icons.turn_left,
      requiredYaw: 45,
      yawTolerance: 15,
    ),
  ];

  late FaceDetectorService _detector;
  CameraController? _camera;
  
  int _stageIndex = 0;
  bool _isInitialized = false;
  bool _isBusy = false;
  bool _isCompleting = false;
  bool _isGoodPosition = false;
  int _goodPositionFrames = 0;
  
  double? _currentHeadYaw;
  Rect? _currentFaceRect;
  
  Map<String, String> _capturedImages = {};

  // ===== LIVE PREVIEW PHASE VARIABLES =====
  bool _stagingComplete = false;
  
  bool _busy = false;
  bool _loadingRecommendations = false;
  Rect? _normalizedFaceRect;
  double? _headYaw;
  double? _headRoll;
  double? _foreheadAnchorY;
  double? _eyeMidX;
  double? _eyeDistanceNorm;
  List<double>? _faceTransformMatrix;
  bool _showCalibrationMode = false;
  
  String _status = 'Center your face in the guide.';
  final List<Map<String, dynamic>> _recommendations = [];
  int _selectedIndex = 0;
  DateTime? _lastRecommendationFetchAt;
  DateTime? _faceSeenAt;
  DateTime? _faceMissingAt;
  int _stableFaceFrames = 0;
  bool _faceSessionReady = false;
  
  Rect? _smoothedFaceRect;
  double? _smoothedHeadYaw;
  double? _smoothedHeadRoll;
  double? _smoothedForeheadAnchorY;
  double? _smoothedEyeMidX;
  double? _smoothedEyeDistanceNorm;

  static const double _rectSmoothingAlpha = 0.58;
  static const double _angleSmoothingAlpha = 0.45;
  static const double _anchorSmoothingAlpha = 0.52;
  static const Duration _faceStableDuration = Duration(milliseconds: 300);
  static const Duration _faceMissingGrace = Duration(milliseconds: 800);
  static const int _minimumStableFrames = 8;

  bool get _showLivePreview => _stagingComplete && _capturedImages.length >= 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseCamera();
    if (!kIsWeb) {
      _detector.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeAll() async {
    try {
      if (!kIsWeb) {
        _detector = FaceDetectorService();
        await _detector.initialize();
      }
      
      if (!mounted) return;
      
      await _initializeCamera();
      
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (!mounted) return;
      setState(() => _isInitialized = false);
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (kIsWeb) return;

      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      
      if (!mounted) return;
      setState(() => _camera = controller);

      await controller.startImageStream(_processFrame);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _releaseCamera() async {
    if (_camera != null) {
      try {
        if (_camera!.value.isStreamingImages) {
          await _camera!.stopImageStream();
        }
      } catch (_) {}
      await _camera!.dispose();
      _camera = null;
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isBusy || !mounted) return;
    _isBusy = true;

    try {
      final frame = await _detector.processFrame(
        image,
        sensorOrientation: _camera!.description.sensorOrientation,
      );

      if (!mounted) {
        _isBusy = false;
        return;
      }

      if (_showLivePreview) {
        // Live preview phase processing
        await _processLivePreviewFrame(frame);
      } else {
        // Staging phase processing
        await _processStagingFrame(frame, image);
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _processStagingFrame(
      DetectedFaceFrame? frame, CameraImage image) async {
    if (frame == null) {
      setState(() {
        _currentHeadYaw = null;
        _currentFaceRect = null;
        _isGoodPosition = false;
        _goodPositionFrames = 0;
      });
      return;
    }

    final normalized = Rect.fromLTWH(
      (frame.boundingBox.left / frame.imageSize.width).clamp(0.0, 1.0),
      (frame.boundingBox.top / frame.imageSize.height).clamp(0.0, 1.0),
      (frame.boundingBox.width / frame.imageSize.width).clamp(0.0, 1.0),
      (frame.boundingBox.height / frame.imageSize.height).clamp(0.0, 1.0),
    );

    final yaw = frame.headEulerAngleY;
    final requiredYaw = _stages[_stageIndex].requiredYaw.toDouble();
    final yawTolerance = _stages[_stageIndex].yawTolerance.toDouble();

    final isGoodPosition = _isFaceWellPositioned(normalized, yaw, requiredYaw, yawTolerance);

    setState(() {
      _currentHeadYaw = yaw;
      _currentFaceRect = normalized;
      _isGoodPosition = isGoodPosition;

      if (isGoodPosition) {
        _goodPositionFrames++;
        if (_goodPositionFrames >= 12) {
          _captureCurrent(image);
        }
      } else {
        _goodPositionFrames = 0;
      }
    });
  }

  Future<void> _processLivePreviewFrame(DetectedFaceFrame? frame) async {
    if (frame == null) {
      final now = DateTime.now();
      _faceMissingAt ??= now;
      final shouldReset = now.difference(_faceMissingAt!) >= _faceMissingGrace;

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
          _faceTransformMatrix = null;
          _faceSessionReady = false;
          _stableFaceFrames = 0;
          _smoothedForeheadAnchorY = null;
          _smoothedEyeMidX = null;
          _smoothedEyeDistanceNorm = null;
          _status = 'We cannot see your face yet. Face the camera in good light.';
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

    final normalized = Rect.fromLTWH(
      (frame.boundingBox.left / frame.imageSize.width).clamp(0.0, 1.0),
      (frame.boundingBox.top / frame.imageSize.height).clamp(0.0, 1.0),
      (frame.boundingBox.width / frame.imageSize.width).clamp(0.0, 1.0),
      (frame.boundingBox.height / frame.imageSize.height).clamp(0.0, 1.0),
    );

    final stableWindowReached = now.difference(_faceSeenAt!) >= _faceStableDuration;
    final centeredInGuide = _isFaceInsideScanGuide(normalized);
    _faceSessionReady =
        stableWindowReached && _stableFaceFrames >= _minimumStableFrames && centeredInGuide;

    final smoothedRect = _smoothRect(_smoothedFaceRect, normalized, _rectSmoothingAlpha);
    final smoothedYaw =
      _smoothValue(_smoothedHeadYaw, frame.headEulerAngleY ?? 0.0, _angleSmoothingAlpha);
    final smoothedRoll =
      _smoothValue(_smoothedHeadRoll, frame.headEulerAngleZ ?? 0.0, _angleSmoothingAlpha);

    final inferredForeheadAnchor = (smoothedRect.top + (smoothedRect.height * 0.18)).clamp(0.0, 1.0);
    final smoothedForehead =
        _smoothValue(_smoothedForeheadAnchorY, inferredForeheadAnchor, _anchorSmoothingAlpha);

    final inferredEyeMidX = (smoothedRect.left + (smoothedRect.width * 0.5)).clamp(0.0, 1.0);
    final inferredEyeDistance = (smoothedRect.width * 0.42).clamp(0.04, 0.65);
    final smoothedEyeMidX =
        _smoothValue(_smoothedEyeMidX, inferredEyeMidX, _anchorSmoothingAlpha);
    final smoothedEyeDistance =
        _smoothValue(_smoothedEyeDistanceNorm, inferredEyeDistance, _anchorSmoothingAlpha);

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
      _status = _faceSessionReady ? 'Ready! Tap "Confirm and Proceed"' : 'Position your face in the guide';
    });
  }

  bool _isFaceWellPositioned(Rect face, double? yaw, double requiredYaw, double tolerance) {
    final faceCenterX = face.left + (face.width / 2);
    final faceCenterY = face.top + (face.height / 2);
    
    final xCentered = faceCenterX >= 0.3 && faceCenterX <= 0.7;
    final yCentered = faceCenterY >= 0.2 && faceCenterY <= 0.7;
    
    final faceArea = face.width * face.height;
    const double minArea = 0.08;
    const double maxArea = 0.4;
    final bool goodSize = faceArea >= minArea && faceArea <= maxArea;
    
    final yawMatch = yaw != null && (yaw - requiredYaw).abs() <= tolerance;
    
    return xCentered && yCentered && goodSize && yawMatch;
  }

  bool _isFaceInsideScanGuide(Rect face) {
    final center = face.center;
    final centerOffsetX = (center.dx - 0.5).abs();
    final centerOffsetY = (center.dy - 0.5).abs();
    final area = face.width * face.height;
    return centerOffsetX <= 0.14 && centerOffsetY <= 0.16 && area >= 0.05 && area <= 0.24;
  }

  Rect _smoothRect(Rect? previous, Rect current, double alpha) {
    if (previous == null) return current;
    return Rect.fromLTWH(
      _smoothValue(previous.left, current.left, alpha),
      _smoothValue(previous.top, current.top, alpha),
      _smoothValue(previous.width, current.width, alpha),
      _smoothValue(previous.height, current.height, alpha),
    );
  }

  double _smoothValue(double? previous, double current, double alpha) {
    if (previous == null) return current;
    return (1 - alpha) * previous + alpha * current;
  }

  Future<void> _captureCurrent(CameraImage image) async {
    try {
      final stage = _stages[_stageIndex];
      final jpeg = image.planes[0].bytes;
      final base64Image = base64Encode(jpeg);
      
      setState(() {
        _capturedImages[stage.keyName] = base64Image;
        _goodPositionFrames = 0;
      });

      if (_stageIndex < _stages.length - 1) {
        setState(() => _stageIndex++);
      } else {
        // All 3 angles captured, transition to live preview
        setState(() => _stagingComplete = true);
        _stageIndex = 0; // Reset for any future use
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }

  Future<void> _proceedToBooking() async {
    final validation = FaceScanService.validateCaptures(_capturedImages);
    if (!validation.ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validation.error ?? 'Invalid captures')),
      );
      return;
    }

    UserSession.capturedFaceImages = Map.from(_capturedImages);
    final faceShape = UserSession.lastScan?['faceShape']?.toString() ?? 'Oval';
    final hairTexture = UserSession.lastScan?['hairTexture']?.toString() ?? 'Straight';

    try {
      await FaceScanService.uploadCaptures(
        scanSessionId: UserSession.ensureScanSessionId(),
        userId: UserSession.userId,
        captures: _capturedImages,
        faceShape: faceShape,
        hairTexture: hairTexture,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FaceScanResultsPage(
          captures: Map.from(_capturedImages),
          faceShape: faceShape,
          hairTexture: hairTexture,
          presetRecommendation: widget.style,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: const Color(0xFF090909),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Camera Not Available', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Text(
            'Camera capture is only available on mobile devices',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF090909),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // Show staging or live preview based on phase
    return _showLivePreview ? _buildLivePreviewUI() : _buildStagingUI();
  }

  Widget _buildStagingUI() {
    final currentStage = _stages[_stageIndex.clamp(0, _stages.length - 1)];
    final progress = (_stageIndex + (_goodPositionFrames / 12.0)) / _stages.length;
    final capturedCount = _capturedImages.length;

    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Capture Face Angles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                color: const Color(0xFFA99941),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _buildStagingCameraView(currentStage),
              ),
              const SizedBox(height: 14),
              _stageStatusRow(capturedCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLivePreviewUI() {
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Live Preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _buildLivePreviewCamera(),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _faceSessionReady ? _proceedToBooking : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA99941),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.grey[700],
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: const Text(
                        'Confirm and Proceed',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: CameraPreview(_camera!),
          ),
          if (_currentFaceRect != null)
            Positioned.fill(
              child: CustomPaint(
                painter: _FaceOverlayPainter(
                  faceRect: _currentFaceRect!,
                  isGoodPosition: _isGoodPosition,
                  stageIcon: stage.icon,
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
                        _isGoodPosition
                            ? 'Position good! Hold for ${(12 - _goodPositionFrames).clamp(0, 12)} frames...'
                            : 'Adjust position',
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

  Widget _buildLivePreviewCamera() {
    if (_camera == null) {
      return Container(
        color: const Color(0xFF121212),
        child: const Center(
          child: Text('Camera not available', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          CameraPreview(_camera!),
          if (_normalizedFaceRect != null)
            Positioned.fill(
              child: CustomPaint(
                painter: _LivePreviewOverlayPainter(
                  faceRect: _normalizedFaceRect!,
                  isReady: _faceSessionReady,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraView(_CaptureStage stage) {
    // Deprecated - use _buildStagingCameraView instead
    return _buildStagingCameraView(stage);
  }

  Widget _stageStatusRow(int capturedCount) {
    return Row(
      children: _stages.asMap().entries.map((entry) {
        final index = entry.key;
        final stage = entry.value;
        final captured = _capturedImages.containsKey(stage.keyName);
        final active = index == _stageIndex && !_isCompleting;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index == _stages.length - 1 ? 0 : 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: captured
                  ? const Color(0xFF1B1B1B)
                  : active
                      ? const Color(0xFF18120A)
                      : const Color(0xFF101010),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: captured
                    ? const Color(0xFFA99941).withOpacity(0.6)
                    : active
                        ? Colors.white24
                        : Colors.white12,
              ),
            ),
            child: Column(
              children: [
                Icon(stage.icon, size: 18, color: captured ? const Color(0xFFA99941) : Colors.white54),
                const SizedBox(height: 6),
                Text(
                  stage.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  captured ? '✓' : active ? '...' : 'Pending',
                  style: TextStyle(
                    color: captured ? const Color(0xFFA99941) : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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

class _FaceOverlayPainter extends CustomPainter {
  final Rect faceRect;
  final bool isGoodPosition;
  final IconData stageIcon;

  _FaceOverlayPainter({
    required this.faceRect,
    required this.isGoodPosition,
    required this.stageIcon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width;
    final scaleY = size.height;

    final rect = Rect.fromLTWH(
      faceRect.left * scaleX,
      faceRect.top * scaleY,
      faceRect.width * scaleX,
      faceRect.height * scaleY,
    );

    final borderPaint = Paint()
      ..color = isGoodPosition ? const Color(0xFF4CAF50) : const Color(0xFFFF9800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    canvas.drawRRect(rrect, borderPaint);

    final cornerSize = 20.0;
    final cornerPaint = Paint()
      ..color = isGoodPosition ? const Color(0xFF4CAF50) : const Color(0xFFFF9800)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Draw corner guides
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + cornerSize, rect.top), cornerPaint);
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left, rect.top + cornerSize), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right - cornerSize, rect.top), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + cornerSize), cornerPaint);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + cornerSize, rect.bottom), cornerPaint);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - cornerSize), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right - cornerSize, rect.bottom), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - cornerSize), cornerPaint);

    if (isGoodPosition) {
      final checkPaint = Paint()
        ..color = const Color(0xFF4CAF50)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final centerX = rect.center.dx;
      final centerY = rect.center.dy;
      final checkSize = 30.0;

      canvas.drawLine(
        Offset(centerX - checkSize / 2, centerY),
        Offset(centerX, centerY + checkSize / 2),
        checkPaint,
      );
      canvas.drawLine(
        Offset(centerX, centerY + checkSize / 2),
        Offset(centerX + checkSize / 2, centerY - checkSize / 2),
        checkPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_FaceOverlayPainter oldDelegate) {
    return oldDelegate.faceRect != faceRect || oldDelegate.isGoodPosition != isGoodPosition;
  }
}

class _LivePreviewOverlayPainter extends CustomPainter {
  final Rect faceRect;
  final bool isReady;

  _LivePreviewOverlayPainter({
    required this.faceRect,
    required this.isReady,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width;
    final scaleY = size.height;

    final rect = Rect.fromLTWH(
      faceRect.left * scaleX,
      faceRect.top * scaleY,
      faceRect.width * scaleX,
      faceRect.height * scaleY,
    );

    // Draw guide circle
    final guidePaint = Paint()
      ..color = isReady ? const Color(0xFF4CAF50).withOpacity(0.3) : const Color(0xFFFF9800).withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    canvas.drawRRect(rrect, guidePaint);

    // Draw crosshair
    final crossPaint = Paint()
      ..color = isReady ? const Color(0xFF4CAF50) : const Color(0xFFFF9800)
      ..strokeWidth = 2;

    final centerX = rect.center.dx;
    final centerY = rect.center.dy;
    canvas.drawLine(Offset(centerX - 20, centerY), Offset(centerX + 20, centerY), crossPaint);
    canvas.drawLine(Offset(centerX, centerY - 20), Offset(centerX, centerY + 20), crossPaint);
  }

  @override
  bool shouldRepaint(_LivePreviewOverlayPainter oldDelegate) {
    return oldDelegate.faceRect != faceRect || oldDelegate.isReady != isReady;
  }
}
