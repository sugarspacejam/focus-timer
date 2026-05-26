import SwiftUI

struct TimerModalView<ActiveTimerContent: View>: View {
    let activeTimerSection: ActiveTimerContent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .light
                        ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.99)]
                        : [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack {
                    Spacer(minLength: 0)
                    activeTimerSection
                    Spacer(minLength: 0)
                }
                .padding(20)
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
        }
    }
}
