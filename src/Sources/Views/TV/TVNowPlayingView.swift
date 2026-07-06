// Diapason — tvOS Now Playing (artwork + transport + synced lyrics).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI
import SwiftSonic

struct TVNowPlayingView: View {
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor

    @State private var showLyrics = true
    @State private var lyricsViewModel: LyricsViewModel?
    @State private var palette: [Color] = [.indigo, .purple, .blue, .pink]
    @State private var showConnect = false
    @StateObject private var connect = ConnectController()
    @FocusState private var focus: Control?

    private enum Control: Hashable { case shuffle, previous, playPause, next, repeatMode, lyrics, connect }

    private var state: PlayerState? { container?.playerState }
    private var track: DisplayableSong? { state?.currentTrack }
    private var isPlaying: Bool { state?.playbackState == .playing }
    private var isShuffled: Bool { state?.isShuffled == true }
    private var repeatMode: RepeatMode { state?.repeatMode ?? .off }

    var body: some View {
        ZStack {
            TVAnimatedBackground(colors: palette)
            if track == nil { emptyState } else { content }
        }
        .task(id: track?.id) { await refresh(for: track) }
        .onAppear { if let container { connect.start(container: container) } }
        .sheet(isPresented: $showConnect) { TVConnectSheet(controller: connect) }
    }

    private var emptyState: some View {
        VStack(spacing: 30) {
            Image(systemName: "music.note")
                .font(.system(size: 120))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing Playing")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 0) {
            playerColumn
                .frame(maxWidth: .infinity)
                .frame(width: showLyrics ? 780 : nil)
                .focusSection()

            if showLyrics {
                TVLyricsView(viewModel: lyricsViewModel)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 40)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .focusSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 60)
        .foregroundStyle(.white)
    }

    private var playerColumn: some View {
        // No Spacers: the outer maxHeight frame vertically centres this compact
        // stack, and the artwork is sized to fit within screen height so it never
        // overflows (which previously hid the top under the tab bar).
        VStack(spacing: 30) {
            CoverArtView(id: track?.coverArtId ?? "", size: 1000, cornerRadius: 20)
                .frame(width: showLyrics ? 460 : 540, height: showLyrics ? 460 : 540)
                .shadow(color: .black.opacity(0.55), radius: 34, y: 18)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showLyrics)

            VStack(spacing: 8) {
                Text(track?.title ?? "")
                    .font(.system(size: showLyrics ? 40 : 46, weight: .bold))
                    .lineLimit(1)
                Text(track?.artist ?? "—")
                    .font(.system(size: showLyrics ? 25 : 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }

            progressBar

            transportRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 24)
        .padding(.bottom, 40)
    }

    /// Single centered transport row: shuffle · prev · play/pause · next · repeat · lyrics · connect.
    private var transportRow: some View {
        HStack(spacing: 28) {
            transport("shuffle", 26, .shuffle, isActive: isShuffled) {
                await container?.playerService.toggleShuffle()
            }
            transport("backward.fill", 30, .previous) { try? await container?.playerService.skipToPrevious() }
            transport(isPlaying ? "pause.fill" : "play.fill", 46, .playPause) { await container?.playerService.togglePlayPause() }
            transport("forward.fill", 30, .next) { try? await container?.playerService.skipToNext() }
            transport(repeatIcon, 26, .repeatMode, isActive: repeatMode != .off) {
                await container?.playerService.setRepeatMode(nextRepeat)
            }
            transport("quote.bubble.fill", 24, .lyrics, isActive: showLyrics) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showLyrics.toggle() }
            }
            transport(connect.manager.connectedDevice != nil ? "dot.radiowaves.left.and.right" : "airplayaudio",
                      24, .connect, isActive: connect.manager.connectedDevice != nil) {
                showConnect = true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var repeatIcon: String { repeatMode == .one ? "repeat.1" : "repeat" }
    private var nextRepeat: RepeatMode {
        switch repeatMode { case .off: return .all; case .all: return .one; case .one: return .off }
    }

    private var progressBar: some View {
        let duration = max(state?.duration ?? 0, 0.001)
        let fraction = min(max((state?.position ?? 0) / duration, 0), 1)
        return VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            HStack {
                Text(TVSongRow.duration(state?.position ?? 0))
                Spacer()
                Text(TVSongRow.duration(state?.duration ?? 0))
            }
            .font(.system(size: 22).monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))
        }
        .frame(width: showLyrics ? 560 : 640)
    }

    @ViewBuilder
    private func transport(_ symbol: String, _ size: CGFloat, _ control: Control,
                           isActive: Bool = false, action: @escaping () async -> Void) -> some View {
        let isFocused = focus == control
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 78, height: 78)
                .background(
                    Circle().fill(isFocused ? Color.white : Color.white.opacity(0.14))
                )
                .foregroundStyle(isFocused ? .black : (isActive ? Color.accent : .white))
                .scaleEffect(isFocused ? 1.14 : 1.0)
        }
        .buttonStyle(.plain)
        .focused($focus, equals: control)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    // MARK: - Data

    private func refresh(for track: DisplayableSong?) async {
        guard let track else { lyricsViewModel = nil; return }
        await updatePalette(for: track.coverArtId)
        if let serverId = container?.serverState.activeServer?.id,
           let lyricsService = container?.lyricsService,
           let playerService = container?.playerService,
           let playerState = container?.playerState {
            let vm = LyricsViewModel(
                songId: track.id,
                serverId: serverId,
                lyricsService: lyricsService,
                playerService: playerService,
                playerState: playerState,
                fallback: LyricsFallback(
                    artist: track.artist ?? "",
                    title: track.title,
                    album: track.albumName,
                    durationSeconds: Int(track.duration)
                )
            )
            lyricsViewModel = vm
            await vm.load()
        }
        if focus == nil { focus = .playPause }
    }

    /// Loads the hero artwork and derives the backdrop palette from its actual
    /// pixels; falls back to the cached dominant colour (hue-spread) if the image
    /// or a colourful palette isn't available.
    private func updatePalette(for coverArtId: String?) async {
        if let cache = container?.artworkImageCache,
           let image = await cache.load(coverArtId: coverArtId, tier: .hero) {
            let colors = TVArtworkPalette.palette(from: image, count: 4)
            if colors.count >= 4 {
                palette = colors
                return
            }
            if let first = colors.first {
                palette = TVColorPalette.palette(from: first)
                return
            }
        }
        palette = TVColorPalette.palette(from: colorExtractor.dominantColor(for: coverArtId, image: nil))
    }
}

// MARK: - TV-optimised lyrics

private struct TVLyricsView: View {
    let viewModel: LyricsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                message("No Lyrics")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(_ vm: LyricsViewModel) -> some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let structured):
            LoadedLyrics(vm: vm, structured: structured)
        case .empty, .unsupported:
            message("No Lyrics")
        case .error:
            message("Lyrics Unavailable")
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note")
                .font(.system(size: 90))
                .foregroundStyle(.white.opacity(0.25))
            Text(text)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LoadedLyrics: View {
    @Bindable var vm: LyricsViewModel
    let structured: StructuredLyrics

    private var current: Int {
        let total = structured.line.count
        guard total > 0 else { return 0 }
        return min(max(vm.currentLineIndex ?? 0, 0), total - 1)
    }

    var body: some View {
        // A tall scroller clipped to a short band so only ~3 lines show at a time.
        // The active line is scrolled to centre, which slides the lines up smoothly
        // (the "old" animation) rather than cross-fading their contents.
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 44) {
                    ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                        let isCurrent = index == current
                        Text(line.value.isEmpty ? "♪" : line.value)
                            .font(.system(size: isCurrent ? 54 : 34, weight: isCurrent ? .bold : .semibold))
                            .foregroundStyle(isCurrent ? .white : .white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(index)
                    }
                }
                .padding(.vertical, 190)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.3), value: current)
            }
            .onAppear {
                vm.startTracking()
                proxy.scrollTo(current, anchor: .center)
            }
            .onDisappear { vm.stopTracking() }
            .onChange(of: current) { _, newValue in
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 380)
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                        .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Connect sheet

private struct TVConnectSheet: View {
    @ObservedObject var controller: ConnectController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Diapason Connect") {
                    if controller.manager.discoveredDevices.isEmpty {
                        Text("Searching for devices on your network…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.manager.discoveredDevices) { device in
                        Button { controller.toggle(device) } label: {
                            HStack {
                                Image(systemName: "display")
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.baseURL).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if controller.manager.connectedDevice == device {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connect")
        }
    }
}

// MARK: - Colorful animated background

/// A lively multi-colour mesh gradient derived from the album-art accent.
struct TVAnimatedBackground: View {
    let colors: [Color]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(t), colors: meshColors)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.4), value: colors)
        }
    }

    private var meshColors: [Color] {
        let p = colors.count >= 4 ? colors : (colors + [Color.black, .black, .black, .black])
        return [p[0], p[1], p[2],
                p[1], p[3], p[0],
                p[2], p[0], p[1]]
    }

    private func points(_ t: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.22)) * 0.06
        let b = Float(cos(t * 0.17)) * 0.06
        return [
            [0, 0], [0.5 + a, 0], [1, 0],
            [0, 0.5 - b], [0.5 + b, 0.5 + a], [1, 0.5 + b],
            [0, 1], [0.5 - a, 1], [1, 1]
        ]
    }
}

// MARK: - Palette derivation

enum TVColorPalette {
    /// Builds a colourful analogous palette from a single accent colour by
    /// rotating hue and nudging brightness — richer than a flat tint.
    static func palette(from base: Color) -> [Color] {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(base).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let sat = max(s, 0.6)
        let bri = min(max(b, 0.5), 0.85)
        func c(_ dh: CGFloat, _ db: CGFloat) -> Color {
            Color(hue: (h + dh + 1).truncatingRemainder(dividingBy: 1),
                  saturation: sat, brightness: min(max(bri + db, 0.25), 0.95))
        }
        return [c(0, 0.0), c(0.09, -0.12), c(-0.09, 0.06), c(0.18, -0.2)]
        #else
        return [base, base.opacity(0.7), base.opacity(0.5), .black]
        #endif
    }
}
#endif
