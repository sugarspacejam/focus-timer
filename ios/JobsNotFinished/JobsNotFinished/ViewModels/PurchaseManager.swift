import Foundation
import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    @Published var isUnlocked = false
    @Published var errorMessage: String?
    
    private let productID = "com.5minutesblockstimer.pro"
    private var updateListenerTask: Task<Void, Error>?
    
    init() {
        updateListenerTask = observeTransactionUpdates()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func prepare() async {
        await refreshEntitlements()
    }
    
    func purchase() async throws {
        guard let product = try await Product.products(for: [productID]).first else {
            throw AppError.transactionVerificationFailed
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try verify(verification)
            await transaction.finish()
            await refreshEntitlements()
        case .pending:
            // Transaction is pending - wait for it to complete
            break
        case .userCancelled:
            // User cancelled the purchase
            break
        @unknown default:
            break
        }
    }
    
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }
    
    private func refreshEntitlements() async {
        var hasUnlock = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verify(result)
                if transaction.productID == productID {
                    hasUnlock = true
                }
            } catch {
                errorMessage = "Failed to verify current entitlement: \(error.localizedDescription)"
            }
        }
        
        isUnlocked = hasUnlock
    }
    
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try verify(result)
                    await transaction.finish()
                    await refreshEntitlements()
                } catch {
                    errorMessage = "Transaction verification failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signedType):
            return signedType
        case .unverified:
            throw AppError.transactionVerificationFailed
        }
    }
}
