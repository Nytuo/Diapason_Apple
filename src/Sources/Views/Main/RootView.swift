// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct RootView: View {
    @Environment(\.appContainer) private var container
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    #if !os(tvOS)
    @AppStorage("interfaceMode") private var interfaceModeRaw = InterfaceMode.modern.rawValue
    #endif

    var body: some View {
        if let serverState = container?.serverState {
            if serverState.isLoadingPersistedState {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if serverState.activeServer != nil && onboardingComplete {
                #if os(macOS)
                RootViewMacOS()
                    .accentColor(.cassetteAccent)
                #elseif os(tvOS)
                TVMainView()
                    .accentColor(.cassetteAccent)
                #else
                if InterfaceMode(rawValue: interfaceModeRaw) == .ipod {
                    iPodShellView()
                } else {
                    MainTabView()
                        .accentColor(.cassetteAccent)
                }
                #endif
            } else {
                OnboardingView()
            }
        }
    }
}
