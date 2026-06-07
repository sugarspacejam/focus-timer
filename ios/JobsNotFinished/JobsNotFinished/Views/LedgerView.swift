import SwiftUI

struct LedgerEntry: Identifiable {
    let id = UUID()
    let taskName: String
    let date: Date
    let isKept: Bool
}

struct LedgerView: View {
    let entries: [LedgerEntry]
    
    @EnvironmentObject var store: FocusStore
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var timerTick = Date()
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    private var keptEntries: [LedgerEntry] {
        entries.filter { $0.isKept }
    }
    
    private var failedEntries: [LedgerEntry] {
        entries.filter { !$0.isKept }
    }
    
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ZStack {
                    backgroundGradient
                        .ignoresSafeArea()
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 32) {
                            flameBadge
                            
                            statsGrid
                            
                            recentActivity
                        }
                        .padding(24)
                        .padding(.bottom, 20)
                    }
                }
                .navigationTitle("Your Flame")
                .navigationBarTitleDisplayMode(.large)
                .onAppear {
                    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        timerTick = Date()
                    }
                }
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: isLight
                ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)]
                : [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Flame Badge
    
    private var flameBadge: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Your Flame")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isLight ? .black : .white)
                
                Spacer()
            }
            
            ZStack {
                let baseSize: CGFloat = 120
                let scaledSize = baseSize * store.flameSizeMultiplier
                
                if store.stats.totalFirePower == 0 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.3, green: 0.1, blue: 0.05), Color(red: 0.15, green: 0.05, blue: 0.02)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: scaledSize, height: scaledSize)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 0.5, green: 0.2, blue: 0.1).opacity(0.3), lineWidth: 4)
                        )
                        .shadow(color: Color(red: 0.8, green: 0.3, blue: 0.1).opacity(0.2), radius: 15, x: 0, y: 8)
                    
                    Image(systemName: "flame.fill")
                        .font(.system(size: 40 * store.flameSizeMultiplier))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.8, green: 0.3, blue: 0.1), Color(red: 0.4, green: 0.15, blue: 0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(0.6)
                } else {
                    ForEach(0..<store.prestigeRingCount, id: \.self) { ring in
                        let ringSize = scaledSize + CGFloat(ring + 1) * 16
                        Circle()
                            .stroke(
                                store.flameGlowColor.opacity(0.3 - Double(ring) * 0.05),
                                lineWidth: 2
                            )
                            .frame(width: ringSize, height: ringSize)
                    }
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [store.flameColor, store.flameSecondaryColor != .clear ? store.flameSecondaryColor : store.flameColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: scaledSize, height: scaledSize)
                        .overlay(
                            Circle()
                                .stroke(store.flameColor.opacity(0.3), lineWidth: 4)
                        )
                        .shadow(color: store.flameGlowColor.opacity(0.4), radius: 20 * store.flameSizeMultiplier, x: 0, y: 10)
                    
                    Image(systemName: "flame.fill")
                        .font(.system(size: 50 * store.flameSizeMultiplier))
                        .foregroundStyle(.white)
                }
            }
            
            VStack(spacing: 8) {
                Text("\(store.stats.totalFirePower)")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(isLight ? .black : .white)
                
                Text("Fire Power")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isLight ? .black.opacity(0.6) : .white.opacity(0.6))
            }
            
            Text(store.flameTier)
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.flameColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(store.flameColor.opacity(0.15))
                )
            
            if store.stats.totalFirePower == 0 {
                Text("Complete your first block to ignite your flame")
                    .font(.caption)
                    .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
                
                Text("Start a block to earn +1 Fire Power")
                    .font(.caption)
                    .foregroundStyle(store.flameColor)
                    .multilineTextAlignment(.center)
            } else if store.isGracePeriodActive {
                let remaining = Int(store.gracePeriodRemainingSeconds)
                let minutes = remaining / 60
                let seconds = remaining % 60
                Text("\(minutes):\(String(format: "%02d", seconds)) to keep momentum")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(store.flameColor)
                    .id(timerTick)
                
                Text("Next block earns +\(store.nextFirePower) Fire Power")
                    .font(.caption)
                    .foregroundStyle(isLight ? .black.opacity(0.7) : .white.opacity(0.7))
                
                Text("Momentum x\(store.stats.currentMomentumStreak)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.flameColor)
            } else {
                Text("Start a block to earn +1 Fire Power")
                    .font(.caption)
                    .foregroundStyle(isLight ? .black.opacity(0.7) : .white.opacity(0.7))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(isLight ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
        )
    }
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        HStack(spacing: 12) {
            ProgressStatCard(
                title: "Today",
                value: "\(store.stats.todayBlocks)",
                subtitle: "blocks completed",
                color: .cyan
            )
            
            ProgressStatCard(
                title: "Momentum",
                value: "\(store.stats.currentMomentumStreak)",
                subtitle: "current streak",
                color: .orange
            )
            
            ProgressStatCard(
                title: "Total",
                value: "\(store.stats.totalFirePower)",
                subtitle: "Fire Power",
                color: store.flameColor
            )
        }
    }
    
    // MARK: - Recent Activity
    
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline.weight(.bold))
                .foregroundStyle(isLight ? .black : .white)
            
            if keptEntries.isEmpty && failedEntries.isEmpty {
                Text("No blocks completed yet")
                    .font(.subheadline)
                    .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach((keptEntries + failedEntries).prefix(5)) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.isKept ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(entry.isKept ? .green : .red)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.taskName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(isLight ? .black : .white)
                                
                                Text(formatDate(entry.date))
                                    .font(.caption)
                                    .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isLight ? Color.white.opacity(0.5) : Color.white.opacity(0.03))
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isLight ? Color.white.opacity(0.85) : Color.white.opacity(0.07))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Progress Stat Card

struct ProgressStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isLight ? .black.opacity(0.6) : .white.opacity(0.6))
                .textCase(.uppercase)
            
            Text(value)
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(color)
            
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isLight ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
        )
    }
}

