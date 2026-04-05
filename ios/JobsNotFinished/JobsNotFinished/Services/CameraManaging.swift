import Foundation
import AVFoundation
import Vision

protocol CameraManaging: ObservableObject {
    var isSessionActive: Bool { get }
    var presenceState: PresenceState { get }
    
    func ensurePermissionAndStart() async throws
    func stopSession()
    func setAwayThresholdAction(_ action: @escaping () -> Void)
    func updateAwayUtterances(_ utterances: [String])
}

enum PresenceState {
    case present
    case away
    case unknown
}
