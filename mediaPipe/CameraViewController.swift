// CameraViewController.swift

import UIKit
import AVFoundation
import MediaPipeTasksVision

class CameraViewController: UIViewController {

    private let previewView = UIView()
    private let overlayView = OverlayView()
    private let cameraUnavailableLabel = UILabel()
    private let resumeButton = UIButton(type: .system)

    private var isSessionRunning = false
    private var isObserving = false
    private let backgroundQueue = DispatchQueue(label: "com.google.mediapipe.cameraController.backgroundQueue")

    private lazy var cameraFeedService = CameraFeedService(previewView: previewView)

    private let poseLandmarkerServiceQueue = DispatchQueue(label: "com.google.mediapipe.cameraController.poseLandmarkerServiceQueue", attributes: .concurrent)
    private var _poseLandmarkerService: PoseLandmarkerService?
    private var poseLandmarkerService: PoseLandmarkerService? {
        get { poseLandmarkerServiceQueue.sync { self._poseLandmarkerService } }
        set { poseLandmarkerServiceQueue.async(flags: .barrier) { self._poseLandmarkerService = newValue } }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        cameraFeedService.delegate = self
        print(">>> Resolution:", cameraFeedService.videoResolution)
        // ⚠️ Don't size the preview layer here – wait until layout
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        initializePoseLandmarkerServiceOnSessionResumption()
        cameraFeedService.startLiveCameraSession { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failed:
                    self?.showAlert(title: "Camera Error", message: "Failed to configure camera")
                case .permissionDenied:
                    self?.showAlert(title: "Permission Denied", message: "Enable camera access in Settings")
                default: break
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Layout full‑screen preview + overlay
        previewView.frame = view.bounds
        overlayView.frame = view.bounds

        // Position labels/buttons
        let frame = view.bounds
        cameraUnavailableLabel.frame = CGRect(x: 0, y: 60, width: frame.width, height: 40)
        resumeButton.frame = CGRect(x: 20, y: frame.height - 80, width: 120, height: 44)

        // Now size the preview layer to exactly match the previewView
        cameraFeedService.updateVideoPreviewLayer(toFrame: previewView.bounds)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraFeedService.stopSession()
        clearPoseLandmarkerServiceOnSessionInterruption()
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .black

        // Preview
        previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(previewView)

        // Overlay (clear and non‑opaque so it redraws fresh each frame)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.backgroundColor = .clear
        overlayView.isOpaque = false
        view.addSubview(overlayView)

        // "Camera unavailable" label
        cameraUnavailableLabel.text = "Camera Unavailable"
        cameraUnavailableLabel.textColor = .white
        cameraUnavailableLabel.backgroundColor = .black.withAlphaComponent(0.6)
        cameraUnavailableLabel.textAlignment = .center
        cameraUnavailableLabel.isHidden = true
        view.addSubview(cameraUnavailableLabel)

        // Resume button
        resumeButton.setTitle("Resume", for: .normal)
        resumeButton.isHidden = true
        resumeButton.addTarget(self, action: #selector(onClickResume(_:)), for: .touchUpInside)
        view.addSubview(resumeButton)
    }

    // MARK: - Actions

    @objc private func onClickResume(_ sender: Any) {
        cameraFeedService.resumeInterruptedSession { [weak self] running in
            if running {
                self?.resumeButton.isHidden = true
                self?.cameraUnavailableLabel.isHidden = true
                self?.initializePoseLandmarkerServiceOnSessionResumption()
            }
        }
    }

    // MARK: - Pose Landmarker

    private func initializePoseLandmarkerServiceOnSessionResumption() {
        clearAndInitializePoseLandmarkerService()
        startObserveConfigChanges()
    }

    @objc private func clearAndInitializePoseLandmarkerService() {
        poseLandmarkerService = PoseLandmarkerService.liveStreamPoseLandmarkerService(
            modelPath: InferenceConfigurationManager.sharedInstance.model.modelPath,
            numPoses: InferenceConfigurationManager.sharedInstance.numPoses,
            minPoseDetectionConfidence: InferenceConfigurationManager.sharedInstance.minPoseDetectionConfidence,
            minPosePresenceConfidence: InferenceConfigurationManager.sharedInstance.minPosePresenceConfidence,
            minTrackingConfidence: InferenceConfigurationManager.sharedInstance.minTrackingConfidence,
            liveStreamDelegate: self,
            delegate: InferenceConfigurationManager.sharedInstance.delegate
        )
    }

    private func clearPoseLandmarkerServiceOnSessionInterruption() {
        stopObserveConfigChanges()
        poseLandmarkerService = nil
    }

    private func startObserveConfigChanges() {
        guard !isObserving else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearAndInitializePoseLandmarkerService),
            name: InferenceConfigurationManager.notificationName,
            object: nil
        )
        isObserving = true
    }

    private func stopObserveConfigChanges() {
        if isObserving {
            NotificationCenter.default.removeObserver(
                self,
                name: InferenceConfigurationManager.notificationName,
                object: nil
            )
            isObserving = false
        }
    }

    // MARK: - Alerts

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: – CameraFeedServiceDelegate

extension CameraViewController: CameraFeedServiceDelegate {
    func didOutput(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) {
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
        backgroundQueue.async { [weak self] in
            self?.poseLandmarkerService?.detectAsync(
                sampleBuffer: sampleBuffer,
                orientation: orientation,
                timeStamps: timestampMs
            )
        }
    }

    func sessionWasInterrupted(canResumeManually: Bool) {
        if canResumeManually {
            resumeButton.isHidden = false
        } else {
            cameraUnavailableLabel.isHidden = false
        }
        clearPoseLandmarkerServiceOnSessionInterruption()
    }

    func sessionInterruptionEnded() {
        cameraUnavailableLabel.isHidden = true
        resumeButton.isHidden = true
        initializePoseLandmarkerServiceOnSessionResumption()
    }

    func didEncounterSessionRuntimeError() {
        resumeButton.isHidden = false
        clearPoseLandmarkerServiceOnSessionInterruption()
    }
}

// MARK: – PoseLandmarkerServiceLiveStreamDelegate

extension CameraViewController: PoseLandmarkerServiceLiveStreamDelegate {
    func poseLandmarkerService(
        _ poseLandmarkerService: PoseLandmarkerService,
        didFinishDetection result: ResultBundle?,
        error: Error?
    ) {
        DispatchQueue.main.async {
            guard
                let poseResult = result?.poseLandmarkerResults.first as? PoseLandmarkerResult,
                self.cameraFeedService.videoResolution != .zero
            else { return }

            let imageSize = self.cameraFeedService.videoResolution
            let mode = self.cameraFeedService.videoGravity.contentMode

            let overlays = OverlayView.poseOverlays(
                fromMultiplePoseLandmarks: poseResult.landmarks,
                inferredOnImageOfSize: imageSize,
                ovelayViewSize: self.overlayView.bounds.size,
                imageContentMode: self.overlayView.imageContentMode,
                andOrientation: UIImage.Orientation.from(deviceOrientation: UIDevice.current.orientation)
            )

            self.overlayView.draw(
                poseOverlays: overlays,
                inBoundsOfContentImageOfSize: imageSize,
                imageContentMode: mode
            )
        }
    }
}

extension AVLayerVideoGravity {
    var contentMode: UIView.ContentMode {
        switch self {
        case .resizeAspectFill: return .scaleAspectFill
        case .resizeAspect:     return .scaleAspectFit
        case .resize:           return .scaleToFill
        default:                return .scaleAspectFill
        }
    }
}

