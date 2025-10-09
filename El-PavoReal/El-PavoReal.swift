//
//  El-PavoReal.swift
//  El-PavoReal
//
//  Created by Simone Azzinelli on 23/08/25.
//

import SwiftUI

@main
struct El_PavoRealApp: App {
    @State private var showSplash = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Mostra la splash per 2 secondi
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
