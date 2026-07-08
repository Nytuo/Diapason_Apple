// Diapason — Siri / Shortcuts "Play <music> in Diapason" App Intent.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import AppIntents

/// Plays a spoken song/artist/playlist. Resolves against the library first, then
/// falls back to YouTube (like Discover), via `NowPlayingBridge.performPlaySearch`.
nonisolated struct PlayMusicIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Music"
    static let description = IntentDescription("Play a song, artist, or playlist in Diapason.")

    static let openAppWhenRun: Bool = false

    @Parameter(title: "Music", requestValueDialog: "What would you like to play?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$query) in Diapason")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let play = NowPlayingBridge.performPlaySearch else {
            return .result(dialog: "Open Diapason first, then try again.")
        }
        guard let outcome = await play(query) else {
            return .result(dialog: "I couldn't find \(query) in your library or on YouTube.")
        }
        switch outcome.source {
        case .library:
            return .result(dialog: "Playing \(outcome.title) from your library.")
        case .youtube:
            return .result(dialog: "\(outcome.title) isn't in your library — playing it from YouTube.")
        }
    }
}

/// Registers the spoken phrases so users can say "Play … in Diapason" to Siri.
nonisolated struct DiapasonAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMusicIntent(),
            phrases: [
                "Play music in \(.applicationName)",
                "Play a song in \(.applicationName)",
                "Put something on in \(.applicationName)",
                "Start playing in \(.applicationName)",
            ],
            shortTitle: "Play Music",
            systemImageName: "play.circle.fill"
        )
    }
}
#endif
