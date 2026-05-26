import Foundation
import SwiftUI

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    var isPro: Bool {
        true // Paid app - all features unlocked
    }
    
    func refreshEntitlements() async {
        // No-op for paid app
    }
}
