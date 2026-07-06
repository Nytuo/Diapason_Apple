// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

// MARK: - Player navigation helpers

func postNavigateToAlbum(track: DisplayableSong) {
    guard let albumId = track.albumId else { return }
    NotificationCenter.default.post(
        name: .NavigateToAlbum,
        object: nil,
        userInfo: [
            "albumId":   albumId,
            "albumName": track.albumName ?? "",
            "coverArtId": track.coverArtId as Any
        ]
    )
}

func postNavigateToArtist(track: DisplayableSong) {
    guard let artistId = track.artistId else { return }
    postNavigateToArtist(artistId: artistId, artistName: track.artist ?? "", coverArtId: track.coverArtId)
}

func postNavigateToArtist(artistId: String, artistName: String, coverArtId: String?) {
    NotificationCenter.default.post(
        name: .NavigateToArtist,
        object: nil,
        userInfo: [
            "artistId":   artistId,
            "artistName": artistName,
            "coverArtId": coverArtId as Any
        ]
    )
}

extension Notification.Name {
    static let TogglePlayPause = Notification.Name("diapason.togglePlayPause")
    static let SkipNext = Notification.Name("diapason.skipNext")
    static let SkipPrevious = Notification.Name("diapason.skipPrevious")
    static let FocusSearch = Notification.Name("diapason.focusSearch")
    static let ToggleShuffle = Notification.Name("diapason.toggleShuffle")
    static let ToggleRepeat = Notification.Name("diapason.toggleRepeat")
    static let ToggleQueue = Notification.Name("diapason.toggleQueue")
    static let OpenFullPlayer = Notification.Name("diapason.openFullPlayer")
    static let OpenFullPlayerLyrics = Notification.Name("diapason.openFullPlayerLyrics")
    static let SelectAlbums = Notification.Name("diapason.selectAlbums")
    static let NavigateToAlbum  = Notification.Name("diapasonNavigateToAlbum")
    static let NavigateToArtist = Notification.Name("diapasonNavigateToArtist")
}
