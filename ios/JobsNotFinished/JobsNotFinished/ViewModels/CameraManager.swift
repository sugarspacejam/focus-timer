import SwiftUI
import AVFoundation
import Vision
import Speech

@MainActor
class CameraManager: NSObject, ObservableObject, CameraManaging {
    @Published var isSessionActive = false
    @Published var presenceState: PresenceState = .unknown
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sessionQueue = DispatchQueue(label: "camera.session")
    private var awayThresholdTimer: Timer?
    private var awayThresholdAction: (() -> Void)?
    private var awayUtterances: [String] = []
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSeenTime = Date()
    private let awayThresholdSeconds: TimeInterval = 10
    
    override init() {
        super.init()
    }
    
    // MARK: - CameraManaging Protocol
    
    var isSessionActive: Bool {
        captureSession?.isRunning == true
    }
    
    func ensurePermissionAndStart() async throws {
        let status = await AVCaptureDevice.requestAccess(for: .video)
        guard status else {
            throw AppError.cameraPermissionDenied
        }
        
        try await startSession()
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
            self?.videoOutput = nil
            
            DispatchQueue.main.async {
                self?.isSessionActive = false
                self?.presenceState = .unknown
            }
        }
        
        awayThresholdTimer?.invalidate()
        awayThresholdTimer = nil
    }
    
    func setAwayThresholdAction(_ action: @escaping () -> Void) {
        awayThresholdAction = action
    }
    
    func updateAwayUtterances(_ utterances: [String]) {
        awayUtterances = utterances
    }
    
    // MARK: - Private Methods
    
    private func startSession() async throws {
        guard captureSession == nil else { return }
        
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                do {
                    try self?.setupCaptureSession()
                    DispatchQueue.main.async {
                        self?.isSessionActive = true
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func setupCaptureSession() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .low
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw AppError.cameraPermissionDenied
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            throw AppError.cameraPermissionDenied
        }
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            throw AppError.cameraPermissionDenied
        }
        
        captureSession = session
        videoOutput = output
        
        session.startRunning()
        startAwayThresholdTimer()
    }
    
    private func startAwayThresholdTimer() {
        awayThresholdTimer?.invalidate()
        awayThresholdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAwayThreshold()
        }
    }
    
    private func checkAwayThreshold() {
        let timeSinceLastSeen = Date().timeIntervalSince(lastSeenTime)
        
        if timeSinceLastSeen > awayThresholdSeconds {
            if presenceState != .away {
                DispatchQueue.main.async {
                    self.presenceState = .away
                    self.handleAwayState()
                }
            }
        } else {
            if presenceState != .present {
                DispatchQueue.main.async {
                    self.presenceState = .present
                }
            }
        }
    }
    
    private func handleAwayState() {
        speakRandomAwayUtterance()
        awayThresholdAction?()
    }
    
    private func speakRandomAwayUtterance() {
        guard !awayUtterances.isEmpty else { return }
        
        let randomUtterance = awayUtterances.randomElement() ?? ""
        let utterance = AVSpeechUtterance(string: randomUtterance)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        
        synthesizer.speak(utterance)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let observations = request.results as? [VNFaceObservation] else { return }
            
            DispatchQueue.main.async {
                self?.lastSeenTime = Date()
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
    }
}
