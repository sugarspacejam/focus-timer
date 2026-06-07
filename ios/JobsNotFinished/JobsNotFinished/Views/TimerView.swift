import SwiftUI

struct TimerView: View {
    @EnvironmentObject var store: FocusStore
    @EnvironmentObject var cameraManager: CameraManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isQuitConfirmationPresented = false
    
    private var isLightTheme: Bool {
        colorScheme == .light
    }
    
    private var primaryTextColor: Color {
        isLightTheme ? .black : .white
    }
    
    private var secondaryTextColor: Color {
        isLightTheme ? .black.opacity(0.6) : .white.opacity(0.6)
    }
    
    private var cardBackgroundColor: Color {
        isLightTheme ? .white.opacity(0.9) : .white.opacity(0.08)
    }
    
    var body: some View {
        activeTimerSection
    }
    
    private var activeTimerSection: some View {
        VStack(spacing: 26) {
            Text(store.activeTaskName)
                .font(.title2.weight(.bold))
                .foregroundStyle(primaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if !store.timerState.isCompleted {
                cameraPresenceIndicator
            }
            
            timerDial
            
            if store.timerState.isCompleted {
                VStack(spacing: 12) {
                    Text("Block kept.")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.green)
                    
                    Text("+\(store.stats.currentMomentumStreak) Fire Power")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(store.flameColor)
                    
                    Text("Momentum x\(store.stats.currentMomentumStreak)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(store.flameColor)
                    
                    Text("Next block earns +\(store.nextFirePower)")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                    
                    Text("You have \(gracePeriodRemainingFormatted) to keep it alive.")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
                
                HStack(spacing: 16) {
                    Button("View Flame") {
                        store.returnToTasks()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Start Another Block") {
                        store.returnToTasks()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                VStack(spacing: 8) {
                    if store.isGracePeriodActive {
                        VStack(spacing: 4) {
                            Text("Momentum x\(store.stats.currentMomentumStreak)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(store.flameColor)
                            
                            Text("Keep it alive: \(gracePeriodRemainingFormatted)")
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor)
                        }
                        .padding(.bottom, 4)
                    }
                    
                    Text("If you leave the app, the timer keeps running.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                    
                    Text("Camera enforcement stops in background. If time runs out before you return, the block fails.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(.top, 2)
                
                HStack(spacing: 16) {
                    Button("Fail Block") {
                        isQuitConfirmationPresented = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(20)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .alert("Fail this block?", isPresented: $isQuitConfirmationPresented) {
            Button("Keep Going", role: .cancel) {}
            Button("Yes, Break It", role: .destructive) {
                store.stopTimer(asFailure: true)
                cameraManager.stopSession()
            }
        } message: {
            Text("The flame cooled. Your Fire Power is safe. Start again with +1.")
        }
    }
    
    private var timerDial: some View {
        ZStack {
            Circle()
                .stroke((isLightTheme ? Color.black : Color.white).opacity(0.12), lineWidth: 16)
                .frame(width: 250, height: 250)
            
            Circle()
                .trim(from: 0, to: store.timerState.isCompleted ? 1 : store.progress)
                .stroke(
                    AngularGradient(colors: [Color.cyan, Color.orange], center: .center),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .frame(width: 250, height: 250)
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: 6) {
                Text(store.formattedRemaining)
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                
                Text("remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }
    
    private var cameraPresenceIndicator: some View {
        HStack(spacing: 10) {
            presenceStatusIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cameraStatusText)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(cameraStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                
                if let detailText = cameraIndicatorDetailText {
                    Text(detailText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
            }
            
            Spacer(minLength: 0)
            
            Text("\(store.awayFailureSeconds)s away")
                .font(.caption.weight(.black))
                .foregroundStyle(cameraStatusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(cameraStatusColor.opacity(0.14))
                .clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cameraStatusColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var presenceStatusIcon: some View {
        ZStack {
            Circle()
                .fill(cameraStatusColor)
                .frame(width: 44, height: 44)
            
            Text(cameraIndicatorIconText)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }
    
    private var cameraIndicatorIconText: String {
        if cameraManager.presenceState == .away {
            return "\(awayCountdownRemaining)"
        }
        
        return cameraStatusSymbol
    }
    
    private var cameraStatusSymbol: String {
        switch cameraManager.presenceState {
        case .present:
            return "✓"
        case .away:
            return "!"
        case .noPermission, .error:
            return "!"
        case .idle:
            return "●"
        }
    }
    
    private var cameraIndicatorDetailText: String? {
        if cameraManager.presenceState == .away {
            return "\(awayCountdownRemaining)s until block fails"
        }
        
        if cameraManager.presenceState == .idle {
            return "Camera presence required"
        }
        
        return nil
    }
    
    private var awayCountdownRemaining: Int {
        let remaining = store.awayFailureSeconds - cameraManager.secondsAway
        if remaining < 0 {
            return 0
        }
        return remaining
    }
    
    private var cameraStatusText: String {
        switch cameraManager.presenceState {
        case .idle:
            return "Block ready"
        case .present:
            return "Present — block live"
        case .away:
            return "Away — get back now"
        case .noPermission:
            return "Camera permission required"
        case .error:
            return "Camera error"
        }
    }
    
    private var cameraStatusColor: Color {
        switch cameraManager.presenceState {
        case .idle:
            return .white.opacity(0.7)
        case .present:
            return .green
        case .away:
            return .orange
        case .noPermission, .error:
            return .red
        }
    }
    
    private var gracePeriodRemainingFormatted: String {
        let remaining = Int(store.gracePeriodRemainingSeconds)
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
