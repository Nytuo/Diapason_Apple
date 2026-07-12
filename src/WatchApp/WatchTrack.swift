// Diapason Watch — a track the watch knows about.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// A track in the watch's catalogue.
///
/// The catalogue is fetched from the Diapason phone app over Connect, but a
/// track's `streamUrl` points at the *music server*, not at the phone. That is
/// what lets the watch keep working with the phone switched off or left at home:
/// it either plays the downloaded file, or streams straight from the server over
/// Wi-Fi or LTE.
struct WatchTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Int

    /// Direct, self-authenticating URL to the music server.
    let streamUrl: String

    let artUrl: String?

    /// Set once the track has been downloaded for offline play. Relative to the
    /// watch's music directory.
    var filename: String?

    var isDownloaded: Bool { filename != nil }
}
