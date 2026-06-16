import SwiftUI

struct MainTabView: View {
    @StateObject private var store = FocusStore()
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var purchaseManager = PurchaseManager.shared
    
    @State private var selectedTab = 0
    @State private var isPaywallPresented = false
    
    var body: some View {
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
        .environmentObject(store)
        .environmentObject(cameraManager)
        .environmentObject(purchaseManager)
        .sheet(isPresented: $isPaywallPresented) {
            DoneIn5PaywallView()
                .environmentObject(purchaseManager)
        }
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
            if !purchaseManager.isPro {
                isPaywallPresented = true
            }
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
