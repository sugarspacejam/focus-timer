import SwiftUI

struct CityBuilding {
    let date: Date
    let blockCount: Int
    let failedCount: Int
    let isToday: Bool
}

struct CityDistrict {
    let month: Date
    let buildings: [CityBuilding]
    let totalBlocks: Int
}

struct LedgerEntry: Identifiable {
    let id = UUID()
    let taskName: String
    let date: Date
    let isKept: Bool
}

struct LedgerView: View {
    let entries: [LedgerEntry]
    
    @State private var selectedEntry: LedgerEntry?
    @State private var selectedDate: Date?
    @State private var showingDatePicker = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    private var keptEntries: [LedgerEntry] {
        entries.filter { $0.isKept }
    }
    
    private var failedEntries: [LedgerEntry] {
        entries.filter { !$0.isKept }
    }
    
    private var cityBuildings: [CityBuilding] {
        let calendar = Calendar.current
        var buildingDict: [String: CityBuilding] = [:]
        
        for entry in keptEntries {
            let dayKey = calendar.startOfDay(for: entry.date)
            let key = ISO8601DateFormatter().string(from: dayKey)
            
            if var existing = buildingDict[key] {
                buildingDict[key] = CityBuilding(
                    date: existing.date,
                    blockCount: existing.blockCount + 1,
                    failedCount: existing.failedCount,
                    isToday: existing.isToday
                )
            } else {
                let isToday = calendar.isDateInToday(entry.date)
                buildingDict[key] = CityBuilding(
                    date: dayKey,
                    blockCount: 1,
                    failedCount: 0,
                    isToday: isToday
                )
            }
        }
        
        for entry in failedEntries {
            let dayKey = calendar.startOfDay(for: entry.date)
            let key = ISO8601DateFormatter().string(from: dayKey)
            
            if var existing = buildingDict[key] {
                buildingDict[key] = CityBuilding(
                    date: existing.date,
                    blockCount: existing.blockCount,
                    failedCount: existing.failedCount + 1,
                    isToday: existing.isToday
                )
            } else {
                let isToday = calendar.isDateInToday(entry.date)
                buildingDict[key] = CityBuilding(
                    date: dayKey,
                    blockCount: 0,
                    failedCount: 1,
                    isToday: isToday
                )
            }
        }
        
        return buildingDict.values.sorted { $0.date < $1.date }
    }
    
    private var totalKept: Int {
        keptEntries.count
    }
    
    private var todayKept: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return keptEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }.count
    }
    
    private var patternComplexity: Int {
        min(totalKept, 12)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        identityBadge
                        
                        statsGrid
                        
                        recentActivity
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Your Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(isLight ? .black : .white)
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
    
    // MARK: - Identity Badge
    
    private var identityBadge: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Your City")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isLight ? .black : .white)
                
                Spacer()
                
                Button(action: { showingDatePicker = true }) {
                    Image(systemName: "calendar")
                        .foregroundStyle(isLight ? .black.opacity(0.6) : .white.opacity(0.6))
                }
            }
            
            ScrollViewReader { proxy in
                ScrollView([.horizontal], showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(cityBuildings.enumerated()), id: \.offset) { index, building in
                            VStack(spacing: 4) {
                                let buildingHeight = CGFloat(building.blockCount) * 8 + 20
                                let maxHeight: CGFloat = 120
                                let clampedHeight = min(buildingHeight, maxHeight)
                                
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            building.isToday 
                                                ? (isLight ? Color.cyan : Color.cyan.opacity(0.8))
                                                : (isLight ? Color.blue.opacity(0.6) : Color.blue.opacity(0.4))
                                        )
                                        .frame(width: 30, height: clampedHeight)
                                    
                                    if building.failedCount > 0 {
                                        VStack(spacing: 2) {
                                            ForEach(0..<min(building.failedCount, 3), id: \.self) { _ in
                                                Circle()
                                                    .fill(isLight ? Color.red.opacity(0.6) : Color.red.opacity(0.4))
                                                    .frame(width: 6, height: 6)
                                            }
                                        }
                                        .offset(y: -clampedHeight - 8)
                                    }
                                }
                                
                                Text(building.date, format: .dateTime.month().day())
                                    .font(.caption2)
                                    .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                            }
                            .id(building.date)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 160)
                .onAppear {
                    if let todayBuilding = cityBuildings.first(where: { $0.isToday }) {
                        proxy.scrollTo(todayBuilding.date, anchor: .center)
                    }
                }
            }
            
            VStack(spacing: 8) {
                Text("\(totalKept)")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(isLight ? .black : .white)
                
                Text("blocks built")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isLight ? .black.opacity(0.6) : .white.opacity(0.6))
            }
            
            if totalKept == 0 {
                Text("Start your first block to begin building your city")
                    .font(.caption)
                    .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
            } else {
                Text("\(cityBuildings.count) days of building")
                    .font(.caption)
                    .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(isLight ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
        )
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet(
                selectedDate: $selectedDate,
                cityBuildings: cityBuildings,
                isPresented: $showingDatePicker
            )
        }
    }
    
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        HStack(spacing: 12) {
            ProgressStatCard(
                title: "Today",
                value: "\(todayKept)",
                subtitle: "blocks completed",
                color: .cyan
            )
            
            ProgressStatCard(
                title: "Total",
                value: "\(totalKept)",
                subtitle: "all time",
                color: .green
            )
        }
    }
    
    // MARK: - Recent Activity
    
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline.weight(.bold))
                .foregroundStyle(isLight ? .black : .white)
            
            if keptEntries.isEmpty {
                Text("No blocks completed yet")
                    .font(.subheadline)
                    .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(keptEntries.prefix(5)) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
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

struct DatePickerSheet: View {
    @Binding var selectedDate: Date?
    let cityBuildings: [CityBuilding]
    @Binding var isPresented: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                DatePicker(
                    "Jump to date",
                    selection: Binding(
                        get: { selectedDate ?? Date() },
                        set: { selectedDate = $0 }
                    ),
                    in: dateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                if let selected = selectedDate,
                   let building = cityBuildings.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                    VStack(spacing: 8) {
                        Text("\(building.blockCount) blocks")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(isLight ? .black : .white)
                        
                        if building.failedCount > 0 {
                            Text("\(building.failedCount) failed")
                                .font(.caption)
                                .foregroundStyle(isLight ? .red.opacity(0.8) : .red.opacity(0.6))
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                    )
                } else if let selected = selectedDate {
                    Text("No blocks on \(selected, format: .dateTime.month().day().year())")
                        .font(.caption)
                        .foregroundStyle(isLight ? .black.opacity(0.5) : .white.opacity(0.5))
                }
                
                Spacer()
                
                Button("Jump to Today") {
                    selectedDate = Date()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
            }
            .padding()
            .background(isLight ? Color.white : Color.black)
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private var dateRange: ClosedRange<Date> {
        guard let first = cityBuildings.first?.date,
              let last = cityBuildings.last?.date else {
            return Date()...Date()
        }
        return first...last
    }
}
