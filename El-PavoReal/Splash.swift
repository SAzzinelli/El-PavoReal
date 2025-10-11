import SwiftUI

struct SplashView: View {
    @State private var appear = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // Logo più grande - 70% dello schermo invece di 50%
            let targetWidth = max(250, side * 0.7)

            ZStack {
                Color.black
                    .ignoresSafeArea()

                Image("logoBianco")
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
