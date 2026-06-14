import Foundation

enum PaywallEntryPoint: String, CaseIterable, Identifiable {
    case onboarding
    case backupCallToggle
    case backupCallSettings
    case settings
    case featureGate
    case upgradeButton
    
    var id: String { rawValue }
}

struct PaywallPreferences: Codable, Hashable {
    var hasSeenPaywall: Bool
    
    static let `default` = PaywallPreferences(hasSeenPaywall: false)
    
    mutating func resetPaywall() {
        hasSeenPaywall = false
    }
}
