// Diapason — resolves a spoken Siri query into a playable queue, library-first.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// Turns a free-text voice query into tracks to play. Always prefers the user's
/// library — a matching song, else a matching album's tracks, else a matching
/// artist's tracks — and only streams from YouTube when nothing is in the library.
enum VoicePlayback {
    static func resolve(
        query: String,
        library: any LibraryServiceProtocol
    ) async -> (tracks: [DisplayableSong], outcome: VoicePlaybackOutcome)? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }

        let results = try? await library.search(q)

        // 1. Direct song matches — rank so the closest title plays first.
        if let songs = results?.song, !songs.isEmpty {
            let ranked = rankSongs(songs, query: q)
            let tracks = ranked.prefix(30).map { DisplayableSong(from: $0) }
            let title = ranked.first?.title ?? q
            return (Array(tracks), VoicePlaybackOutcome(title: title, source: .library))
        }

        // 2. Album match — play the whole album.
        if let album = results?.album?.first,
           let full = try? await library.album(id: album.id),
           let albumSongs = full.song, !albumSongs.isEmpty {
            let tracks = albumSongs.map { DisplayableSong(from: $0) }
            return (tracks, VoicePlaybackOutcome(title: album.name, source: .library))
        }

        // 3. Artist match — play that artist's tracks.
        let artists = results?.artist ?? []
        let artist = artists.first { ($0.albumCount ?? 0) > 0 } ?? artists.first
        if let artist,
           let tracks = try? await library.fetchAllTracks(forArtistID: artist.id), !tracks.isEmpty {
            return (Array(tracks.prefix(60)), VoicePlaybackOutcome(title: artist.name, source: .library))
        }

        // 4. Nothing owned — stream the top YouTube result (like Discover).
        if let first = await YouTubeResolver.shared.search(q, limit: 1).first {
            let ds = DisplayableSong.youtubeVideo(videoId: first.videoId, rawTitle: first.title, channel: first.author)
            return ([ds], VoicePlaybackOutcome(title: ds.title, source: .youtube))
        }

        return nil
    }

    private static func rankSongs(_ songs: [Song], query: String) -> [Song] {
        let ql = query.lowercased()
        return songs.sorted { score($0, ql) > score($1, ql) }
    }

    private static func score(_ song: Song, _ ql: String) -> Int {
        let t = song.title.lowercased()
        if t == ql { return 3 }
        if t.contains(ql) || ql.contains(t) { return 2 }
        return 1
    }
}
