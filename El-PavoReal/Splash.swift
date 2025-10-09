import SwiftUI

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appear = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // responsive ma più grande
            let targetWidth = max(200, side * 0.5)

            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                Image(colorScheme == .dark ? "logoBianco" : "logoNero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: targetWidth)
                    .opacity(appear ? 1 : 0)
                    .scaleEffect(appear ? 1 : 0.96)
                    .animation(.easeOut(duration: 0.6), value: appear)
                    .accessibilityLabel("El Pavo‑Real logo")
            }
        }
        .onAppear {
            // piccolo delay per rendere il fade‑in più piacevole
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                appear = true
            }
        }
    }
}

#Preview {
    SplashView()
}
