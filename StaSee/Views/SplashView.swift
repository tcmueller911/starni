import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var opacity = 1.0

    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 64))
                        .foregroundStyle(.cyan)

                    Text("Starni")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Starnberger See")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    ProgressView()
                        .tint(.cyan)
                        .padding(.top, 16)
                }
            }
            .opacity(opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isActive = true
                    }
                }
            }
        }
    }
}
