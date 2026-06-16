import Foundation
import SwiftUI
import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    private let monthlyProductId = "com.5minutesblockstimer.pro.monthly"
    private let annualProductId = "com.5minutesblockstimer.pro.annual"
    
    @Published var monthlyProduct: Product?
    @Published var annualProduct: Product?
    @Published var isPro: Bool = false
    @Published var isLoading = false
    @Published var loadingError: String?
    
    private var updateListenerTask: Task<Void, Error>?
    
    init() {
        updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let products = try await Product.products(for: [monthlyProductId, annualProductId])
            monthlyProduct = products.first { $0.id == monthlyProductId }
            annualProduct = products.first { $0.id == annualProductId }
            loadingError = nil
        } catch {
            loadingError = "Failed to load: \(error.localizedDescription)"
        }
    }
    
    func refreshEntitlements() async {
        let proIds = [monthlyProductId, annualProductId]
        var hasActiveEntitlement = false
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               proIds.contains(transaction.productID),
               transaction.revocationDate == nil {
                hasActiveEntitlement = true
                break
            }
        }
        
        isPro = hasActiveEntitlement
    }
    
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    return true
                }
            case .userCancelled:
                return false
            default:
                return false
            }
        } catch {
            return false
        }
        return false
    }
    
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }
}
