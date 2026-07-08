// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated struct VoicePlaybackOutcome: Sendable {
    enum Source: Sendable { case library, youtube }
    let title: String
    let source: Source
}

nonisolated enum NowPlayingBridge {
    nonisolated(unsafe) static var performTogglePlayPause: (@Sendable () async -> Void)?

    nonisolated(unsafe) static var performPlaySearch: (@Sendable (String) async -> VoicePlaybackOutcome?)?
}
