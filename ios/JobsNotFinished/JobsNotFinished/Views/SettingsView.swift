import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: FocusStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var isOnboardingPresented = false
    @State private var supportiveUtterances: [String] = []
    @State private var awayFailureSecondsText = ""
    @State private var countdownSpeakingEnabled = true
    @State private var isResetConfirmationPresented = false
    @State private var resetConfirmationText = ""
    
    @FocusState private var focusedField: FocusedField?
    
    private enum FocusedField: Hashable {
        case awayTimeout
        case awayVoiceLines
    }
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    private var primaryTextColor: Color {
        isLight ? .black : .white
    }
    
    private var secondaryTextColor: Color {
        isLight ? .black.opacity(0.6) : .white.opacity(0.6)
    }
    
    private var subtleFillColor: Color {
        isLight ? .black.opacity(0.05) : .white.opacity(0.08)
    }
    
    private var cardBackgroundColor: Color {
        isLight ? .white.opacity(0.9) : .white.opacity(0.08)
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: isLight
                    ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)]
                    : [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("App Settings")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(primaryTextColor)
                    
                    Button {
                        isOnboardingPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .font(.title3)
                                .foregroundStyle(.cyan)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open Quick Guide")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(primaryTextColor)
                                
                                Text("See the onboarding walkthrough again.")
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.cyan)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(subtleFillColor)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Appearance")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                        
                        Picker("Appearance", selection: Binding(
                            get: { store.themeMode },
                            set: { store.setThemeMode($0) }
                        )) {
                            ForEach(AppThemeMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text("Choose Dark, Light, or follow the system setting.")
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Away Timeout")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                        
                        Text("Fail the block after this many seconds away from the camera.")
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                        
                        HStack(spacing: 12) {
                            TextField("6", text: $awayFailureSecondsText)
                                .focused($focusedField, equals: .awayTimeout)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(subtleFillColor)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(primaryTextColor)
                            
                            Text("seconds")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryTextColor)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Countdown Speaking")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(primaryTextColor)
                            
                            Spacer()
                            
                            Toggle("", isOn: $countdownSpeakingEnabled)
                        }
                        
                        Text("Speak the countdown when you're away from the camera.")
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Away Voice")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                        
                        Text("Edit the voice lines spoken when you leave frame.")
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Away Voice Lines")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                        
                        Text("Add voice lines below. These are the messages spoken when camera sees you away.")
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                        
                        VStack(spacing: 8) {
                            ForEach(0..<supportiveUtterances.count, id: \.self) { index in
                                HStack(spacing: 8) {
                                    TextField("Voice line \(index + 1)", text: $supportiveUtterances[index])
                                        .focused($focusedField, equals: .awayVoiceLines)
                                        .textFieldStyle(.plain)
                                        .padding(12)
                                        .background(subtleFillColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(primaryTextColor)
                                    
                                    Button(action: {
                                        if supportiveUtterances.count > 1 {
                                            supportiveUtterances.remove(at: index)
                                            persistSupportiveUtterancesDraft()
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(secondaryTextColor)
                                            .font(.title3)
                                    }
                                }
                            }
                            
                            Button(action: {
                                supportiveUtterances.append("")
                                focusedField = .awayVoiceLines
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add voice line")
                                }
                                .font(.subheadline)
                                .foregroundStyle(primaryTextColor)
                                .padding(12)
                                .background(subtleFillColor.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    
                    Button {
                        isResetConfirmationPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .font(.title3)
                                .foregroundStyle(.red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset All Data")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.red)
                                
                                Text("Delete all tasks, stats, and settings. This cannot be undone.")
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.red)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(subtleFillColor)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(cardBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSettingsKeyboardAndSave()
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView(onDismiss: { isOnboardingPresented = false })
        }
        .alert("Reset All Data", isPresented: $isResetConfirmationPresented) {
            TextField("Type 'delete' to confirm", text: $resetConfirmationText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            Button("Cancel", role: .cancel) {
                resetConfirmationText = ""
            }
            
            Button("Reset", role: .destructive) {
                if resetConfirmationText.lowercased() == "delete" {
                    store.resetAllData()
                    resetConfirmationText = ""
                }
            }
            .disabled(resetConfirmationText.lowercased() != "delete")
        } message: {
            Text("This will permanently delete all your blocks, statistics, and settings. Type 'delete' to confirm.")
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        supportiveUtterances = store.userState.supportiveUtterances
        awayFailureSecondsText = String(store.userState.awayFailureSeconds)
        countdownSpeakingEnabled = store.userState.countdownSpeakingEnabled
    }
    
    private func dismissSettingsKeyboardAndSave() {
        focusedField = nil
        
        if let seconds = Int(awayFailureSecondsText), seconds > 0 {
            store.updateAwayFailureSeconds(seconds)
        }
        
        store.updateCountdownSpeakingEnabled(countdownSpeakingEnabled)
        store.updateSupportiveUtterances(supportiveUtterances)
    }
    
    private func persistSupportiveUtterancesDraft() {
        store.updateSupportiveUtterances(supportiveUtterances)
    }
}
