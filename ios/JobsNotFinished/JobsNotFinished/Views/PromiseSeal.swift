import SwiftUI

enum SealState: Equatable {
    case forming(progress: Double)  // 0.0 to 1.0 as timer runs
    case stamped                    // Completed block
    case shattered                // Failed block
}

struct BlockSeal: View {
    let state: SealState
    let taskName: String
    let size: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    var body: some View {
        ZStack {
            // Wax seal base
            Circle()
                .fill(waxColor)
                .frame(width: size, height: size)
                .shadow(
                    color: shadowColor,
                    radius: state == .stamped ? 8 : 4,
                    x: 0,
                    y: state == .stamped ? 4 : 2
                )
            
            // Inner gradient for depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            waxColor.opacity(0.8),
                            waxColor.opacity(0.4)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size * 0.85, height: size * 0.85)
            
            // Content based on state
            switch state {
            case .forming(let progress):
                formingContent(progress: progress)
            case .stamped:
                stampedContent
            case .shattered:
                shatteredContent
            }
        }
    }
    
    // MARK: - State Content
    
    private func formingContent(progress: Double) -> some View {
        ZStack {
            // Ring that fills as block forms
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isLight ? Color.white : Color.black,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: size * 0.7, height: size * 0.7)
                .rotationEffect(.degrees(-90))
            
            // Center icon
            Image(systemName: "hand.raised.fill")
                .font(.system(size: size * 0.25, weight: .bold))
                .foregroundStyle(isLight ? .white : .black)
                .opacity(0.8)
        }
    }
    
    private var stampedContent: some View {
        VStack(spacing: 4) {
            // Checkmark for completed block
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(isLight ? .white : .black)
            
            // "KEPT" text
            Text("KEPT")
                .font(.system(size: size * 0.12, weight: .black))
                .foregroundStyle(isLight ? .white : .black)
                .tracking(2)
        }
    }
    
    private var shatteredContent: some View {
        VStack(spacing: 4) {
            // Broken seal icon
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            
            // "BROKEN" text
            Text("BROKEN")
                .font(.system(size: size * 0.1, weight: .black))
                .foregroundStyle(isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .tracking(1)
        }
    }
    
    // MARK: - Colors
    
    private var waxColor: Color {
        switch state {
        case .forming:
            return isLight ? Color(red: 0.75, green: 0.2, blue: 0.2) : Color(red: 0.6, green: 0.15, blue: 0.15)
        case .stamped:
            return isLight ? Color(red: 0.2, green: 0.6, blue: 0.3) : Color(red: 0.15, green: 0.5, blue: 0.25)
        case .shattered:
            return isLight ? Color(red: 0.5, green: 0.5, blue: 0.5) : Color(red: 0.35, green: 0.35, blue: 0.35)
        }
    }
    
    private var shadowColor: Color {
        isLight ? Color.black.opacity(0.15) : Color.black.opacity(0.3)
    }
}

// MARK: - Animated Seal for Timer

struct AnimatedBlockSeal: View {
    let progress: Double
    let taskName: String
    let isCompleted: Bool
    let isBroken: Bool
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        BlockSeal(
            state: sealState,
            taskName: taskName,
            size: 120
        )
        .scaleEffect(pulseScale)
        .onChange(of: progress) { _, newProgress in
            if newProgress > 0.9 {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.05
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
    
    private var sealState: SealState {
        if isBroken {
            return .shattered
        } else if isCompleted {
            return .stamped
        } else {
            return .forming(progress: progress)
        }
    }
}

// MARK: - Mini Seal for Ledger

struct MiniSeal: View {
    let isKept: Bool
    let size: CGFloat
    
    var body: some View {
        BlockSeal(
            state: isKept ? .stamped : .shattered,
            taskName: "",
            size: size
        )
    }
}

// MARK: - Seal Stamp Animation

struct SealStampEffect: ViewModifier {
    let isStamping: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isStamping ? 0.9 : 1.0)
            .offset(y: isStamping ? 10 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isStamping)
    }
}

extension View {
    func sealStampEffect(isStamping: Bool) -> some View {
        modifier(SealStampEffect(isStamping: isStamping))
    }
}
