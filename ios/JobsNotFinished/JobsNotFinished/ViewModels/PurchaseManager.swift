import Foundation
import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    @Published var isUnlocked = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let productID = "com.5minutesblockstimer.pro.lifetime"
    private var updateListenerTask: Task<Void, Never>?
    
    init() {
        updateListenerTask = observeTransactionUpdates()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func prepare() async {
        errorMessage = nil
        await refreshEntitlements()
    }
    
    func purchase() async throws {
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil

        do {
            guard let product = try await Product.products(for: [productID]).first else {
                errorMessage = "Product not available yet. Confirm the IAP exists in App Store Connect and your device is signed into a Sandbox account."
                throw AppError.transactionVerificationFailed
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try verify(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                errorMessage = "Purchase pending."
            case .userCancelled:
                errorMessage = nil
            @unknown default:
                errorMessage = "Unknown purchase state."
            }
        } catch {
            if errorMessage == nil {
                errorMessage = "Purchase failed: \(error.localizedDescription)"
            }
            throw error
        }
    }
    
    func restore() async throws {
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isUnlocked == false {
                errorMessage = "No purchase found to restore for this Apple ID."
            }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
            throw error
        }
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
