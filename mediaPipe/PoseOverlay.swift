// PoseOverlay.swift

import UIKit
import MediaPipeTasksVision

/// A straight line.
struct Line {
  let from: CGPoint
  let to: CGPoint
}

/**
 This structure holds the display parameters for the overlay to be drawn on a pose landmarker object.
 */
struct PoseOverlay {
  let dots: [CGPoint]
  let lines: [Line]
}

/// Custom view to visualize the pose landmarks result on top of the input image.
class OverlayView: UIView {

  var poseOverlays: [PoseOverlay] = []
  private var contentImageSize: CGSize = .zero
  var imageContentMode: UIView.ContentMode = .scaleAspectFit
  private var orientation = UIDeviceOrientation.portrait
  private var edgeOffset: CGFloat = 0.0

  // MARK: Public Functions

  func draw(
    poseOverlays: [PoseOverlay],
    inBoundsOfContentImageOfSize imageSize: CGSize,
    edgeOffset: CGFloat = 0.0,
    imageContentMode: UIView.ContentMode
  ) {
    self.clear()  // resets data
    contentImageSize = imageSize
    self.edgeOffset = edgeOffset
    self.poseOverlays = poseOverlays
    self.imageContentMode = imageContentMode
    orientation = UIDevice.current.orientation
    setNeedsDisplay()
  }

  func redrawPoseOverlays(forNewDeviceOrientation deviceOrientation: UIDeviceOrientation) {
    orientation = deviceOrientation
    switch orientation {
    case .portrait, .landscapeLeft, .landscapeRight:
      setNeedsDisplay()
    default:
      break
    }
  }

  func clear() {
    poseOverlays = []
    contentImageSize = .zero
    imageContentMode = .scaleAspectFit
    orientation = UIDevice.current.orientation
    edgeOffset = 0.0
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.clear(rect)  // 🧹 clear previous frame's drawings

    for overlay in poseOverlays {
      drawLines(overlay.lines)
      drawDots(overlay.dots)
    }
  }

  // MARK: Private Functions

  private func drawDots(_ dots: [CGPoint]) {
    for dot in dots {
      let dotRect = CGRect(
        x: dot.x - DefaultConstants.pointRadius / 2,
        y: dot.y - DefaultConstants.pointRadius / 2,
        width: DefaultConstants.pointRadius,
        height: DefaultConstants.pointRadius
      )
      let path = UIBezierPath(ovalIn: dotRect)
      DefaultConstants.pointFillColor.setFill()
      DefaultConstants.pointColor.setStroke()
      path.stroke()
      path.fill()
    }
  }

  private func drawLines(_ lines: [Line]) {
    let path = UIBezierPath()
    for line in lines {
      path.move(to: line.from)
      path.addLine(to: line.to)
    }
    path.lineWidth = DefaultConstants.lineWidth
    DefaultConstants.lineColor.setStroke()
    path.stroke()
  }

  // MARK: Helper Functions

  private func rectAfterApplyingBoundsAdjustment(onOverlayBorderRect borderRect: CGRect) -> CGRect {
    var currentSize = bounds.size
    let minDim = min(bounds.width, bounds.height)
    let maxDim = max(bounds.width, bounds.height)

    switch orientation {
    case .portrait:
      currentSize = CGSize(width: minDim, height: maxDim)
    case .landscapeLeft, .landscapeRight:
      currentSize = CGSize(width: maxDim, height: minDim)
    default:
      break
    }

    let (xOffset, yOffset, scaleFactor) = OverlayView.offsetsAndScaleFactor(
      forImageOfSize: contentImageSize,
      tobeDrawnInViewOfSize: currentSize,
      withContentMode: imageContentMode
    )

    var newRect = borderRect
      .applying(CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
      .applying(CGAffineTransform(translationX: xOffset, y: yOffset))

    // boundary checks...
    if newRect.origin.x < 0 && newRect.maxX > edgeOffset {
      newRect.size.width = newRect.maxX - edgeOffset
      newRect.origin.x = edgeOffset
    }
    if newRect.origin.y < 0 && newRect.maxY > edgeOffset {
      newRect.size.height = newRect.maxY - edgeOffset
      newRect.origin.y = edgeOffset
    }
    if newRect.maxY > currentSize.height {
      newRect.size.height = currentSize.height - newRect.origin.y - edgeOffset
    }
    if newRect.maxX > currentSize.width {
      newRect.size.width = currentSize.width - newRect.origin.x - edgeOffset
    }

    return newRect
  }

  static func offsetsAndScaleFactor(
    forImageOfSize imageSize: CGSize,
    tobeDrawnInViewOfSize viewSize: CGSize,
    withContentMode contentMode: UIView.ContentMode
  ) -> (xOffset: CGFloat, yOffset: CGFloat, scaleFactor: Double) {
    let wScale = viewSize.width / imageSize.width
    let hScale = viewSize.height / imageSize.height
    let scaleFactor: Double

    switch contentMode {
    case .scaleAspectFill:
      scaleFactor = Double(max(wScale, hScale))
    case .scaleAspectFit:
      scaleFactor = Double(min(wScale, hScale))
    default:
      scaleFactor = 1.0
    }

    let scaledSize = CGSize(
      width: imageSize.width * CGFloat(scaleFactor),
      height: imageSize.height * CGFloat(scaleFactor)
    )
    let xOffset = (viewSize.width - scaledSize.width) / 2
    let yOffset = (viewSize.height - scaledSize.height) / 2
    return (xOffset, yOffset, scaleFactor)
  }

  static func poseOverlays(
    fromMultiplePoseLandmarks landmarks: [[NormalizedLandmark]],
    inferredOnImageOfSize originalImageSize: CGSize,
    ovelayViewSize: CGSize,
    imageContentMode: UIView.ContentMode,
    andOrientation orientation: UIImage.Orientation
  ) -> [PoseOverlay] {
    guard !landmarks.isEmpty else { return [] }

    let (xOffset, yOffset, scaleFactor) = offsetsAndScaleFactor(
      forImageOfSize: originalImageSize,
      tobeDrawnInViewOfSize: ovelayViewSize,
      withContentMode: imageContentMode
    )

    return landmarks.map { poseLandmarks in
      // convert normalized points → [CGPoint]
      let normalizedPoints: [CGPoint]
      switch orientation {
      case .left:
        normalizedPoints = poseLandmarks.map { CGPoint(x: CGFloat($0.y), y: 1 - CGFloat($0.x)) }
      case .right:
        normalizedPoints = poseLandmarks.map { CGPoint(x: 1 - CGFloat($0.y), y: CGFloat($0.x)) }
      default:
        normalizedPoints = poseLandmarks.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
      }

      // scale + offset into view coords
      let dots = normalizedPoints.map {
        CGPoint(
          x: $0.x * originalImageSize.width * CGFloat(scaleFactor) + xOffset,
          y: $0.y * originalImageSize.height * CGFloat(scaleFactor) + yOffset
        )
      }

      // connect according to MediaPipe’s default landmark connections
      let lines: [Line] = PoseLandmarker.poseLandmarks.map { connection in
        let start = dots[Int(connection.start)]
        let end   = dots[Int(connection.end)]
        return Line(from: start, to: end)
      }

      return PoseOverlay(dots: dots, lines: lines)
    }
  }
}

