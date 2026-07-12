// Diapason — Apple Watch app (standalone).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// A standalone watch app.
///
/// It used to be the companion of the Diapason iPhone app, talking to it over
/// WatchConnectivity. That app is gone — phones are served by the Flutter app now
/// — and WatchConnectivity can only ever reach the iOS app that embeds the watch
/// app, never a different one. So the watch speaks Diapason Connect over the
/// network instead, like every other device in the ecosystem.
///
/// The phone is needed to sync the catalogue, and nothing else: downloads live on
/// the watch, and stream URLs point straight at the music server.
@main
struct DiapasonWatchApp: App {
    @StateObject private var store = WatchLibraryStore()
    @StateObject private var player = WatchAudioPlayer()
    @StateObject private var connect = WatchConnect()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(connect)
                .task { player.configure(store: store) }
        }
    }
}
