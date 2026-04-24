class OverlayImageSet {
  final String front;
  final String left;
  final String right;

  const OverlayImageSet({
    required this.front,
    required this.left,
    required this.right,
  });
}

class OverlayBox {
  final double left;
  final double top;
  final double width;
  final double height;
  final double yawScale;

  const OverlayBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.yawScale = 1.0,
  });
}

class OverlayCalibration {
  final double widthScale;
  final double heightScale;
  final double xOffset;
  final double yOffset;
  final double hairClipFactor;
  final double visualScale;
  final double yawShiftFactor;

  const OverlayCalibration({
    required this.widthScale,
    required this.heightScale,
    required this.xOffset,
    required this.yOffset,
    this.hairClipFactor = 0.57,
    this.visualScale = 1.0,
    this.yawShiftFactor = 0.07,
  });

  static const defaults = OverlayCalibration(
    widthScale: 1.12,
    heightScale: 1.22,
    xOffset: 0.00,
    yOffset: -0.18,
    hairClipFactor: 0.74,
    visualScale: 1.16,
    yawShiftFactor: 0.06,
  );
}
