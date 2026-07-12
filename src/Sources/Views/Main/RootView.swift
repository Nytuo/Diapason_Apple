// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// The root of the Apple TV app.
///
/// The iPhone/iPad and macOS interfaces used to branch from here. They are gone:
/// phones and desktops are served by the Flutter app now, and this project keeps
/// only what Flutter cannot target — Apple TV, and the Watch app. The two
/// ecosystems talk over Diapason Connect.
struct RootView: View {
    @Environment(\.appContainer) private var container
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        if let serverState = container?.serverState {
            if serverState.isLoadingPersistedState {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if serverState.activeServer != nil && onboardingComplete {
                TVMainView()
                    .accentColor(.accentColor)
            } else {
                OnboardingView()
            }
        }
    }
}
