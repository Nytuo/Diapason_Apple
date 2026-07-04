// Diapason — iPod-classic click-wheel interface, wired to Cassette's services.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

enum InterfaceMode: String, CaseIterable, Identifiable {
    case modern, ipod
    var id: String { rawValue }
    var label: String { self == .modern ? "Modern" : "iPod Classic" }
}

struct iPodRow: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String? = nil
    let action: iPodRowAction
}

enum iPodRowAction {
    case push(title: String, loader: () async -> [iPodRow])
    case play(tracks: [DisplayableSong], index: Int)
    case nowPlaying
    case run(() -> Void)
}

@MainActor
final class iPodScreen: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let isNowPlaying: Bool
    @Published var rows: [iPodRow] = []
    @Published var selection: Int = 0
    @Published var isLoading = false
    private let loader: (() async -> [iPodRow])?

    init(title: String, isNowPlaying: Bool = false, rows: [iPodRow] = [], loader: (() async -> [iPodRow])? = nil) {
        self.title = title
        self.isNowPlaying = isNowPlaying
        self.rows = rows
        self.loader = loader
    }

    func loadIfNeeded() async {
        guard let loader, rows.isEmpty, !isNowPlaying else { return }
        isLoading = true
        rows = await loader()
        selection = 0
        isLoading = false
    }
}

@MainActor
final class iPodController: ObservableObject {
    @Published var stack: [iPodScreen] = []
    weak var container: AppContainer?

    private var library: (any LibraryServiceProtocol)? { container?.libraryService }
    private var player: (any PlayerServiceProtocol)? { container?.playerService }
    private var playerState: PlayerState? { container?.playerState }

    enum NavDirection { case forward, back }
    @Published private(set) var direction: NavDirection = .forward
    private let navAnimation = Animation.easeInOut(duration: 0.28)

    var current: iPodScreen { stack.last ?? root }
    private lazy var root: iPodScreen = makeMainMenu()

    private func push(_ screen: iPodScreen) {
        direction = .forward
        withAnimation(navAnimation) { stack.append(screen) }
        Haptics.pop()
    }

    func start(container: AppContainer) {
        self.container = container
        if stack.isEmpty { stack = [makeMainMenu()] }
    }

    func scroll(by steps: Int) {
        let screen = current
        if screen.isNowPlaying { scrub(by: steps); return }
        guard !screen.rows.isEmpty else { return }
        let next = min(max(screen.selection + steps, 0), screen.rows.count - 1)
        if next != screen.selection { screen.selection = next; Haptics.tick() }
    }

    func select() {
        let screen = current
        if screen.isNowPlaying { Task { await player?.togglePlayPause() }; return }
        guard screen.rows.indices.contains(screen.selection) else { return }
        activate(screen.rows[screen.selection])
    }

    func menuBack() {
        guard stack.count > 1 else { return }
        direction = .back
        withAnimation(navAnimation) { _ = stack.removeLast() }
        Haptics.pop()
    }

    func playPause() { Task { await player?.togglePlayPause() } }
    func next() { Task { try? await player?.skipToNext() } }
    func previous() { Task { try? await player?.skipToPrevious() } }

    private func scrub(by steps: Int) {
        guard let ps = playerState, ps.duration > 0 else { return }
        let delta = Double(steps) * max(2, ps.duration / 60)
        Task { await player?.seek(to: min(max(ps.position + delta, 0), ps.duration)) }
    }

    private func activate(_ row: iPodRow) {
        switch row.action {
        case let .push(title, loader):
            let screen = iPodScreen(title: title, loader: loader)
            push(screen)
            Task { await screen.loadIfNeeded() }
        case let .play(tracks, index):
            Task { try? await player?.play(tracks: tracks, startIndex: index) }
            openNowPlaying()
        case .nowPlaying:
            openNowPlaying()
        case let .run(effect):
            effect()
        }
    }

    func openNowPlaying() {
        if current.isNowPlaying { return }
        push(iPodScreen(title: "Now Playing", isNowPlaying: true))
    }

    private func makeMainMenu() -> iPodScreen {
        iPodScreen(title: "iPod", rows: [
            iPodRow(title: "Playlists", action: .push(title: "Playlists", loader: { [weak self] in await self?.playlistRows() ?? [] })),
            iPodRow(title: "Artists", action: .push(title: "Artists", loader: { [weak self] in await self?.artistRows() ?? [] })),
            iPodRow(title: "Albums", action: .push(title: "Albums", loader: { [weak self] in await self?.albumRows() ?? [] })),
            iPodRow(title: "Shuffle Songs", action: .run { [weak self] in Task { try? await self?.player?.playSmartShuffle(); self?.openNowPlaying() } }),
            iPodRow(title: "Now Playing", action: .nowPlaying),
            iPodRow(title: "Exit iPod Mode", action: .run { UserDefaults.standard.set(InterfaceMode.modern.rawValue, forKey: "interfaceMode") }),
        ])
    }

    private func playlistRows() async -> [iPodRow] {
        let playlists = (try? await library?.playlists()) ?? []
        return playlists.map { pl in
            iPodRow(title: pl.name, subtitle: "\(pl.songCount) songs", action: .push(title: pl.name, loader: { [weak self] in
                let detail = try? await self?.library?.playlist(id: pl.id)
                let songs = (detail?.entry ?? []).map { DisplayableSong(from: $0) }
                return self?.songRows(songs) ?? []
            }))
        }
    }

    private func artistRows() async -> [iPodRow] {
        let indexes = (try? await library?.artists()) ?? []
        let artists = indexes.flatMap { $0.artist }
        return artists.map { artist in
            iPodRow(title: artist.name, action: .push(title: artist.name, loader: { [weak self] in
                let full = try? await self?.library?.artist(id: artist.id)
                return (full?.album ?? []).map { self?.albumRow($0) ?? iPodRow(title: $0.name, action: .run {}) }
            }))
        }
    }

    private func albumRows() async -> [iPodRow] {
        let albums = (try? await library?.allAlbums()) ?? []
        return albums.map { albumRow($0) }
    }

    private func albumRow(_ album: AlbumID3) -> iPodRow {
        iPodRow(title: album.name, subtitle: album.artist, action: .push(title: album.name, loader: { [weak self] in
            let full = try? await self?.library?.album(id: album.id)
            let songs = (full?.song ?? []).map { DisplayableSong(from: $0) }
            return self?.songRows(songs) ?? []
        }))
    }

    private func songRows(_ songs: [DisplayableSong]) -> [iPodRow] {
        songs.enumerated().map { idx, song in
            iPodRow(title: song.title, subtitle: song.artist, action: .play(tracks: songs, index: idx))
        }
    }
}

enum Haptics {
    @MainActor static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    @MainActor static func pop() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
