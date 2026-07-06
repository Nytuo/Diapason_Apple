// diapason — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import OSLog

// All properties are `nonisolated` to prevent SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor
// from implicitly isolating them, which would cause concurrency warnings when accessed
// from non-MainActor contexts (actors, background tasks, etc.). Logger is Sendable.
extension Logger {
    nonisolated static let server     = Logger(subsystem: "app.diapason.server",     category: "ServerService")
    nonisolated static let player     = Logger(subsystem: "app.diapason.player",     category: "PlayerService")
    nonisolated static let library    = Logger(subsystem: "app.diapason.library",    category: "LibraryService")
    nonisolated static let cache      = Logger(subsystem: "app.diapason.cache",      category: "CacheService")
    nonisolated static let download   = Logger(subsystem: "app.diapason.download",   category: "DownloadService")
    nonisolated static let resolver   = Logger(subsystem: "app.diapason.resolver",   category: "MediaResolver")
    nonisolated static let nowPlaying = Logger(subsystem: "app.diapason.nowplaying", category: "NowPlayingService")
    nonisolated static let keychain   = Logger(subsystem: "app.diapason.keychain",   category: "KeychainService")
    nonisolated static let network     = Logger(subsystem: "app.diapason.network",    category: "NetworkMonitor")
    nonisolated static let ui         = Logger(subsystem: "app.diapason.ui",         category: "UI")
    nonisolated static let favorites   = Logger(subsystem: "app.diapason.favorites",  category: "FavoritesService")
    nonisolated static let pin         = Logger(subsystem: "app.diapason.pin",        category: "PinService")
    nonisolated static let session     = Logger(subsystem: "app.diapason.session",    category: "PlaybackSessionService")
    nonisolated static let playlist    = Logger(subsystem: "app.diapason.playlist",   category: "PlaylistService")
    nonisolated static let radio       = Logger(subsystem: "app.diapason.radio",      category: "RadioService")
    nonisolated static let discover      = Logger(subsystem: "app.diapason.discover",      category: "DiscoverViewModel")
    nonisolated static let dominantColor = Logger(subsystem: "app.diapason.dominantColor", category: "DominantColorExtractor")
    nonisolated static let stats         = Logger(subsystem: "app.diapason.stats",         category: "StatsService")
    nonisolated static let wrapped       = Logger(subsystem: "app.diapason.wrapped",       category: "WrappedPlaylistService")
    nonisolated static let wrappedStory  = Logger(subsystem: "app.diapason.wrappedstory",  category: "WrappedStoryPlayer")
    nonisolated static let lyrics        = Logger(subsystem: "app.diapason.lyrics",        category: "LyricsService")
    nonisolated static let widget           = Logger(subsystem: "app.diapason.widget",           category: "WidgetSyncService")
    nonisolated static let recommendations  = Logger(subsystem: "app.diapason.recommendations",  category: "RecommendationService")
    nonisolated static let listenBrainz     = Logger(subsystem: "app.diapason.listenbrainz",     category: "ListenBrainz")
    nonisolated static let integrations       = Logger(subsystem: "app.diapason.integrations",       category: "Integrations")
    nonisolated static let externalArtwork    = Logger(subsystem: "app.diapason.externalartwork",    category: "ExternalArtworkCache")
    nonisolated static let artistArtwork      = Logger(subsystem: "app.diapason.artistartwork",      category: "ExternalArtistImageResolver")
    nonisolated static let httpTransport      = Logger(subsystem: "app.diapason.transport",          category: "CustomHeadersTransport")
    nonisolated static let artworkCache       = Logger(subsystem: "app.diapason.artworkcache",       category: "ArtworkCache")
    nonisolated static let settings           = Logger(subsystem: "app.diapason.settings",           category: "Settings")
    nonisolated static let boot               = Logger(subsystem: "app.diapason.boot",               category: "Boot")
    nonisolated static let migration          = Logger(subsystem: "app.diapason.migration",          category: "Migration")
    nonisolated static let crossfade          = Logger(subsystem: "app.diapason.crossfade",          category: "Crossfade")
}
