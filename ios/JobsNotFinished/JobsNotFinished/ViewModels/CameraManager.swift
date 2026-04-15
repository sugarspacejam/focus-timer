import SwiftUI
import AVFoundation
import Vision
import Speech

@MainActor
class CameraManager: NSObject, ObservableObject, CameraManaging {
    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var isSessionActive = false
    @Published private(set) var presenceState: PresenceState = .idle
    @Published private(set) var secondsAway: Int = 0

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let visionQueue = DispatchQueue(label: "CameraManager.vision")
    nonisolated private let sessionQueue = DispatchQueue(label: "CameraManager.session")
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var isConfigured = false
    private var awayStartedAt: Date?
    private var didTriggerAwayFailure = false
    private var awayThresholdAction: (() -> Void)?
    private var awayThresholdSeconds = 6
    private let requiredMissCount = 8
    private let awaySpeechRepeatInterval: TimeInterval = 4
    private var consecutiveMissCount = 0
    private var lastAwaySpeechAt: Date?
    private var awayUtterances = AwayVoiceMode.supportive.utterances
    private var awayUtteranceIndex = 0
    private var isMonitoringActive = false
    
    override init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
    }
    
    // MARK: - CameraManaging Protocol
    
    func ensurePermissionAndStart() async {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authorizationStatus == .authorized {
            configureIfNeeded()
            startSession()
            return
        }

        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
            if granted {
                configureIfNeeded()
                startSession()
            } else {
                presenceState = .noPermission
            }
            return
        }

        presenceState = .noPermission
    }
    
    func stopSession() {
        isMonitoringActive = false
        if session.isRunning {
            session.stopRunning()
        }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        awayStartedAt = nil
        secondsAway = 0
        didTriggerAwayFailure = false
        consecutiveMissCount = 0
        lastAwaySpeechAt = nil
        isSessionActive = false
        presenceState = .idle
    }
    
    func setAwayThresholdAction(_ action: @escaping () -> Void) {
        awayThresholdAction = action
    }

    func updateAwayFailureSeconds(_ seconds: Int) {
        awayThresholdSeconds = max(seconds, 1)
    }
    
    func updateAwayUtterances(_ utterances: [String]) {
        if utterances.isEmpty {
            fatalError("Away utterances are required")
        }
        awayUtterances = utterances
    }
    
    // MARK: - Private Methods
    
    private func configureIfNeeded() {
        if isConfigured {
            return
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            presenceState = .error
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            presenceState = .error
            return
        }

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.sessionPreset = .medium
        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        session.commitConfiguration()
        isConfigured = true
    }
    
    private func startSession() {
        if session.isRunning {
            isSessionActive = true
            isMonitoringActive = true
            return
        }

        isMonitoringActive = true
        isSessionActive = true
        didTriggerAwayFailure = false
        awayStartedAt = nil
        secondsAway = 0
        consecutiveMissCount = 0
        lastAwaySpeechAt = nil
        presenceState = .idle

        let session = self.session
        sessionQueue.async {
            session.startRunning()
        }
    }
    
    private func handleDetection(hasPerson: Bool) {
        if isMonitoringActive == false {
            return
        }

        if hasPerson {
            consecutiveMissCount = 0
            awayStartedAt = nil
            secondsAway = 0
            didTriggerAwayFailure = false
            lastAwaySpeechAt = nil
            presenceState = .present
            return
        }

        consecutiveMissCount += 1
        if consecutiveMissCount < requiredMissCount {
            if presenceState == .idle {
                presenceState = .idle
            } else {
                presenceState = .present
            }
            return
        }

        presenceState = .away
        if awayStartedAt == nil {
            awayStartedAt = Date()
            speakAwayAlertIfNeeded(force: true)
        }
        guard let awayStartedAt else {
            secondsAway = 0
            return
        }

        secondsAway = Int(Date().timeIntervalSince(awayStartedAt))
        speakAwayAlertIfNeeded(force: false)

        if secondsAway >= awayThresholdSeconds && !didTriggerAwayFailure {
            didTriggerAwayFailure = true
            awayThresholdAction?()
        }
    }

    private func speakAwayAlertIfNeeded(force: Bool) {
        if isMonitoringActive == false {
            return
        }

        let now = Date()
        if !force {
            if let lastAwaySpeechAt, now.timeIntervalSince(lastAwaySpeechAt) < awaySpeechRepeatInterval {
                return
            }
            if speechSynthesizer.isSpeaking {
                return
            }
        }

        if awayUtterances.isEmpty {
            return
        }

        let utterance = AVSpeechUtterance(string: awayUtterances[awayUtteranceIndex % awayUtterances.count])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        awayUtteranceIndex += 1
        lastAwaySpeechAt = now
        speechSynthesizer.speak(utterance)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            Task { @MainActor in
                self.presenceState = .error
            }
            return
        }

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
            let faceRequest = VNDetectFaceRectanglesRequest()
            let upperBodyRequest = VNDetectHumanRectanglesRequest()
            upperBodyRequest.upperBodyOnly = true
            try handler.perform([faceRequest, upperBodyRequest])

            let hasFace = !(faceRequest.results ?? []).isEmpty
            let hasUpperBody = !(upperBodyRequest.results ?? []).isEmpty
            Task { @MainActor in
                self.handleDetection(hasPerson: hasFace || hasUpperBody)
            }
        } catch {
            Task { @MainActor in
                self.presenceState = .error
            }
        }
    }
}
