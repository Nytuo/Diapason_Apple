// Diapason Watch — a locally-stored, offline-playable track.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation

struct WatchTrack: Identifiable, Codable, Hashable {
    let id: String          // songId
    let title: String
    let artist: String
    let album: String
    let coverArtId: String
    let filename: String    // relative filename within the watch music directory
    let duration: Int
}
