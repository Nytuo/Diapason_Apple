// Diapason — tvOS navigation routing.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI
import SwiftSonic

/// The dedicated library "See All" pages reachable from Home rails / the tab bar.
enum TVLibrarySection: Hashable {
    case recentlyAdded
    case albums
    case artists
    case songs
}

extension View {
    /// Registers every tvOS push destination on a NavigationStack root: the four
    /// library sections plus album / artist / playlist detail. Applied once per
    /// tab's NavigationStack so links from anywhere in that stack resolve.
    func tvDestinations() -> some View {
        self
            .navigationDestination(for: TVLibrarySection.self) { section in
                switch section {
                case .recentlyAdded: TVAlbumsView(source: .recentlyAdded)
                case .albums:        TVAlbumsView(source: .all)
                case .artists:       TVArtistsView()
                case .songs:         TVSongsView()
                }
            }
            .navigationDestination(for: AlbumID3.self) { album in
                TVAlbumDetailView(album: album)
            }
            .navigationDestination(for: ArtistID3.self) { artist in
                TVArtistDetailView(artist: artist)
            }
            .navigationDestination(for: Playlist.self) { playlist in
                TVPlaylistDetailView(playlist: playlist)
            }
    }
}
#endif
