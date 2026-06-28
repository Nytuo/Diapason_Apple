import SwiftUI
import AVFoundation
import UIKit

@main
struct DiapasonApp: App {
    @StateObject private var playerManager = PlayerManager.shared
    @StateObject private var backendManager = BackendManager.shared
    @StateObject private var subsonicClient = SubsonicClient.shared
    @StateObject private var plexClient = PlexClient.shared
    @State private var showSplash = true

    init() {
        // Audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        // Legacy transparent navigation bar
        UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
        UINavigationBar.appearance().shadowImage = UIImage()
        UINavigationBar.appearance().isTranslucent = true
        UINavigationBar.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(playerManager)
                    .environmentObject(backendManager)
                    .environmentObject(subsonicClient)
                    .environmentObject(plexClient)
                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
        }
    }
}
