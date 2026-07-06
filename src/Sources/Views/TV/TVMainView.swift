// Diapason — tvOS main shell.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI

/// Focus-first tvOS shell: a top tab bar over the shared services/view models.
/// Now Playing is a dedicated tab (no bottom mini-player). Each browsing tab has
/// its own NavigationStack with the shared tvOS push destinations registered.
struct TVMainView: View {
    @Environment(\.appContainer) private var container
    @State private var selectedTab: TVTab = .home
    @State private var searchText = ""
    @State private var searchPath = NavigationPath()

    private enum TVTab: Hashable { case home, search, playlists, nowPlaying, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: TVTab.home) {
                NavigationStack {
                    TVHomeView().tvDestinations()
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: TVTab.search) {
                NavigationStack(path: $searchPath) {
                    TVSearchView(searchQuery: $searchText, path: $searchPath)
                }
            }

            Tab("Playlists", systemImage: "music.note.list", value: TVTab.playlists) {
                NavigationStack {
                    TVPlaylistsView().tvDestinations()
                }
            }

            Tab("Now Playing", systemImage: "play.circle.fill", value: TVTab.nowPlaying) {
                TVNowPlayingView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: TVTab.settings) {
                NavigationStack { TVSettingsView() }
            }
        }
        .accentColor(.accent)
        .task(id: container?.serverState.isOnline) {
            guard container?.serverState.isOnline == true else { return }
            try? await container?.favoritesService.syncFromServer()
        }
    }
}
#endif
