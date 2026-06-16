import SwiftUI

struct MainTabView: View {
    @StateObject private var store = FocusStore()
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var purchaseManager = PurchaseManager.shared
    
    @State private var selectedTab = 0
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    
    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            } else if purchaseManager.isPro {
                appTabs
            } else {
                DoneIn5PaywallView()
            }
        }
        .environmentObject(store)
        .environmentObject(cameraManager)
        .environmentObject(purchaseManager)
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
        }
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            HomeTabView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            LedgerTabView()
                .tabItem {
                    Label("Flame", systemImage: "flame.fill")
                }
                .tag(1)

            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
    }
}

struct HomeTabView: View {
    @EnvironmentObject var store: FocusStore
    @EnvironmentObject var cameraManager: CameraManager
    
    var body: some View {
        NavigationStack {
            HomeContentView()
        }
    }
}

struct LibraryTabView: View {
    @EnvironmentObject var store: FocusStore
    
    var body: some View {
        NavigationStack {
            LibraryView()
        }
    }
}

struct LedgerTabView: View {
    @EnvironmentObject var store: FocusStore
    
    var body: some View {
        NavigationStack {
            LedgerView(entries: store.ledgerEntries)
        }
    }
}

struct SettingsTabView: View {
    @EnvironmentObject var store: FocusStore
    
    var body: some View {
        NavigationStack {
            SettingsView()
        }
    }
}
