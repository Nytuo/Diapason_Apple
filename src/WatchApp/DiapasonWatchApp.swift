// Diapason — Apple Watch app (on-device offline playback).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

@main
struct DiapasonWatchApp: App {
    @StateObject private var store = WatchLibraryStore()
    @StateObject private var player = WatchAudioPlayer()
    @StateObject private var connector = WatchConnector()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .environmentObject(player)
                .task {
                    player.configure(store: store)
                    connector.configure(store: store)
                }
        }
    }
}
