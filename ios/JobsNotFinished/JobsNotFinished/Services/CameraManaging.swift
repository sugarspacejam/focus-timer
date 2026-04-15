import Foundation
import AVFoundation
import Vision

@MainActor
protocol CameraManaging: ObservableObject {
    var authorizationStatus: AVAuthorizationStatus { get }
    var isSessionActive: Bool { get }
    var presenceState: PresenceState { get }
    var secondsAway: Int { get }
    
    func ensurePermissionAndStart() async
    func stopSession()
    func setAwayThresholdAction(_ action: @escaping () -> Void)
    func updateAwayFailureSeconds(_ seconds: Int)
    func updateAwayUtterances(_ utterances: [String])
}

enum PresenceState: Sendable {
    case idle
    case present
    case away
    case noPermission
    case error
}
