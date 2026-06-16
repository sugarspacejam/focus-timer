import SwiftUI
import StoreKit

struct DoneIn5PaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showRestoreAlert = false
    @State private var restoreMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.orange)
                            
                            Text("Unlock Your Flame")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text("Subscribe to track blocks, build streaks, and keep your promises.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 40)
                        
                        VStack(spacing: 16) {
                            FeatureRow(icon: "flame.fill", text: "Unlimited 5-minute blocks")
                            FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Track streaks & momentum")
                            FeatureRow(icon: "bell.fill", text: "Accountability notifications")
                            FeatureRow(icon: "lock.shield.fill", text: "Premium accountability features")
                        }
                        .padding(.horizontal)
                        
                        if purchaseManager.isLoading {
                            ProgressView()
                                .tint(.orange)
                                .scaleEffect(1.2)
                        } else if let error = purchaseManager.loadingError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            VStack(spacing: 12) {
                                if let annual = purchaseManager.annualProduct {
                                    Button {
                                        Task { await purchase(annual) }
                                    } label: {
                                        PlanButton(
                                            title: "Annual",
                                            price: annual.displayPrice,
                                            subtext: "Best value",
                                            isPrimary: true
                                        )
                                    }
                                    .disabled(isPurchasing)
                                }
                                
                                if let monthly = purchaseManager.monthlyProduct {
                                    Button {
                                        Task { await purchase(monthly) }
                                    } label: {
                                        PlanButton(
                                            title: "Monthly",
                                            price: monthly.displayPrice,
                                            subtext: "Flexible",
                                            isPrimary: false
                                        )
                                    }
                                    .disabled(isPurchasing)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        Button {
                            Task { await restore() }
                        } label: {
                            Text("Restore Purchases")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .disabled(isPurchasing)
                        
                        HStack(spacing: 20) {
                            Link("Terms", destination: URL(string: "https://celestifyltd.com/terms.html")!)
                            Link("Privacy", destination: URL(string: "https://celestifyltd.com/support/primealarm.html")!)
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        
                        Spacer(minLength: 40)
                    }
                }
            }
        }
        .alert("Restore Purchases", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage)
        }
    }
    
    private func purchase(_ product: Product) async {
        isPurchasing = true
        let success = await purchaseManager.purchase(product)
        isPurchasing = false
        guard success else { return }
    }
    
    private func restore() async {
        await purchaseManager.restorePurchases()
        if purchaseManager.isPro {
            restoreMessage = "Purchases restored successfully!"
            showRestoreAlert = true
        } else {
            restoreMessage = "No active subscriptions found."
            showRestoreAlert = true
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(.white)
            Spacer()
        }
    }
}

private struct PlanButton: View {
    let title: String
    let price: String
    let subtext: String
    let isPrimary: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(price)
                    .font(.headline)
            }
            HStack {
                Text(subtext)
                    .font(.caption)
                Spacer()
            }
        }
        .foregroundStyle(isPrimary ? .black : .white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(isPrimary ? Color.orange : Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}
