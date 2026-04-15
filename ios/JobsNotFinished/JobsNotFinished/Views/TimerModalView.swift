import SwiftUI

struct TimerModalView<ActiveTimerContent: View, CameraContent: View>: View {
    let activeTimerSection: ActiveTimerContent
    let cameraSection: CameraContent

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.05, green: 0.07, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        activeTimerSection
                        cameraSection
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
        }
    }
}
