import SwiftUI

struct MainTabView: View {
    @StateObject private var store = FocusStore()
    @StateObject private var cameraManager = CameraManager()
    
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            LibraryTabView()
                .tabItem {
                    Label("Library", systemImage: "book.fill")
                }
                .tag(1)
            
            LedgerTabView()
                .tabItem {
                    Label("Ledger", systemImage: "building.2.fill")
                }
                .tag(2)
            
            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .environmentObject(store)
        .environmentObject(cameraManager)
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
