import UIKit
import AVFoundation

protocol CameraFeedServiceDelegate: AnyObject {
  func didOutput(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation)
  func didEncounterSessionRuntimeError()
  func sessionWasInterrupted(canResumeManually resumeManually: Bool)
  func sessionInterruptionEnded()
}

class CameraFeedService: NSObject {
  enum CameraConfigurationStatus {
    case success
    case failed
    case permissionDenied
  }

  var videoResolution: CGSize {
    guard let size = imageBufferSize else {
      return CGSize.zero
    }
    let minDimension = min(size.width, size.height)
    let maxDimension = max(size.width, size.height)
    switch UIDevice.current.orientation {
    case .portrait:
      return CGSize(width: minDimension, height: maxDimension)
    case .landscapeLeft, .landscapeRight:
      return CGSize(width: maxDimension, height: minDimension)
    default:
      return CGSize(width: minDimension, height: maxDimension)
    }
  }

  let videoGravity = AVLayerVideoGravity.resizeAspectFill

  private let session: AVCaptureSession = AVCaptureSession()
  private lazy var videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
  private let sessionQueue = DispatchQueue(label: "com.google.mediapipe.CameraFeedService.sessionQueue")
  private let cameraPosition: AVCaptureDevice.Position = .front

  private var cameraConfigurationStatus: CameraConfigurationStatus = .failed
  private lazy var videoDataOutput = AVCaptureVideoDataOutput()
  private var isSessionRunning = false
  private var imageBufferSize: CGSize?

  weak var delegate: CameraFeedServiceDelegate?

  init(previewView: UIView) {
    super.init()
    session.sessionPreset = .high
    setUpPreviewView(previewView)
    attemptToConfigureSession()
    NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func setUpPreviewView(_ view: UIView) {
    videoPreviewLayer.videoGravity = videoGravity
    videoPreviewLayer.connection?.videoOrientation = .portrait
    view.layer.addSublayer(videoPreviewLayer)
  }

  @objc func orientationChanged(notification: Notification) {
    switch UIImage.Orientation.from(deviceOrientation: UIDevice.current.orientation) {
    case .up:
      videoPreviewLayer.connection?.videoOrientation = .portrait
    case .left:
      videoPreviewLayer.connection?.videoOrientation = .landscapeRight
    case .right:
      videoPreviewLayer.connection?.videoOrientation = .landscapeLeft
    default:
      break
    }
  }

  func startLiveCameraSession(_ completion: @escaping(_ cameraConfiguration: CameraConfigurationStatus) -> Void) {
    sessionQueue.async {
      switch self.cameraConfigurationStatus {
      case .success:
        self.addObservers()
        self.startSession()
      default:
        break
      }
      completion(self.cameraConfigurationStatus)
    }
  }

  func stopSession() {
    self.removeObservers()
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
        self.isSessionRunning = self.session.isRunning
      }
    }
  }

  func resumeInterruptedSession(withCompletion completion: @escaping (Bool) -> ()) {
    sessionQueue.async {
      self.startSession()
      DispatchQueue.main.async {
        completion(self.isSessionRunning)
      }
    }
  }

  func updateVideoPreviewLayer(toFrame frame: CGRect) {
    videoPreviewLayer.frame = frame
  }

  private func startSession() {
    self.session.startRunning()
    self.isSessionRunning = self.session.isRunning
  }

  private func attemptToConfigureSession() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      self.cameraConfigurationStatus = .success
    case .notDetermined:
      self.sessionQueue.suspend()
      self.requestCameraAccess(completion: { _ in
        self.sessionQueue.resume()
      })
    case .denied:
      self.cameraConfigurationStatus = .permissionDenied
    default:
      break
    }

    self.sessionQueue.async {
      self.configureSession()
    }
  }

  private func requestCameraAccess(completion: @escaping (Bool) -> ()) {
    AVCaptureDevice.requestAccess(for: .video) { granted in
      self.cameraConfigurationStatus = granted ? .success : .permissionDenied
      completion(granted)
    }
  }

  private func configureSession() {
    guard cameraConfigurationStatus == .success else { return }
    session.beginConfiguration()

    guard addVideoDeviceInput() else {
      session.commitConfiguration()
      cameraConfigurationStatus = .failed
      return
    }

    guard addVideoDataOutput() else {
      session.commitConfiguration()
      cameraConfigurationStatus = .failed
      return
    }

    session.commitConfiguration()
    cameraConfigurationStatus = .success
  }

  private func addVideoDeviceInput() -> Bool {
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
      return false
    }

    do {
      let videoDeviceInput = try AVCaptureDeviceInput(device: camera)
      if session.canAddInput(videoDeviceInput) {
        session.addInput(videoDeviceInput)

        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        imageBufferSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))

        return true
      }
      return false
    } catch {
      fatalError("Cannot create video device input")
    }
  }

  private func addVideoDataOutput() -> Bool {
    let sampleBufferQueue = DispatchQueue(label: "sampleBufferQueue")
    videoDataOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
    videoDataOutput.alwaysDiscardsLateVideoFrames = true
    videoDataOutput.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA]

    if session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
      videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
      if videoDataOutput.connection(with: .video)?.isVideoOrientationSupported == true && cameraPosition == .front {
        videoDataOutput.connection(with: .video)?.isVideoMirrored = true
      }
      return true
    }
    return false
  }

  private func addObservers() {
    NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeErrorOccured), name: .AVCaptureSessionRuntimeError, object: session)
    NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
    NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
  }

  private func removeObservers() {
    NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
    NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
    NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
  }

  @objc func sessionWasInterrupted(notification: Notification) {
    let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? -1
    let canResume = AVCaptureSession.InterruptionReason(rawValue: reason) == .videoDeviceInUseByAnotherClient
    delegate?.sessionWasInterrupted(canResumeManually: canResume)
  }

  @objc func sessionInterruptionEnded(notification: Notification) {
    delegate?.sessionInterruptionEnded()
  }

  @objc func sessionRuntimeErrorOccured(notification: Notification) {
    let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
    print("Capture session runtime error: \(String(describing: error))")

    guard error?.code == .mediaServicesWereReset else {
      delegate?.didEncounterSessionRuntimeError()
      return
    }

    sessionQueue.async {
      if self.isSessionRunning {
        self.startSession()
      } else {
        DispatchQueue.main.async {
          self.delegate?.didEncounterSessionRuntimeError()
        }
      }
    }
  }
}

extension CameraFeedService: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    if imageBufferSize == nil {
      imageBufferSize = CGSize(width: CVPixelBufferGetHeight(imageBuffer), height: CVPixelBufferGetWidth(imageBuffer))
    }
    delegate?.didOutput(sampleBuffer: sampleBuffer, orientation: UIImage.Orientation.from(deviceOrientation: UIDevice.current.orientation))
  }
}

extension UIImage.Orientation {
  static func from(deviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
    switch deviceOrientation {
    case .portrait:
      return .up
    case .landscapeLeft:
      return .left
    case .landscapeRight:
      return .right
    default:
      return .up
    }
  }
}

