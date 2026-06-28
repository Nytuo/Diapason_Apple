import SwiftUI
import MediaPlayer
import AVKit

// MARK: - Spring press style for transport buttons
private struct SpringPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var backend: BackendManager
    @Environment(\.dismiss) var dismiss

    @State private var lyricLines: [LyricLine] = []
    @State private var isLoadingLyrics = false
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var addToPlaylistSong: Song? = nil
    @State private var isFavorite = false

    @State private var backgroundColors: [Color] = [.red, .purple, .indigo]
    @State private var currentAlbumId: String?

    // Track song identity for transitions
    @State private var songId: String = ""

    var body: some View {
        GeometryReader { geometry in
            let isSmall = geometry.size.height < 700
            let hPad: CGFloat = 24
            let availableWidth = geometry.size.width - hPad * 2
            let artworkSize = min(availableWidth, isSmall ? 200 : 260)

            ZStack {
                AnimatedGradientBackground(colors: backgroundColors)
                    .ignoresSafeArea()
                    .id(currentAlbumId)

                VStack(spacing: 0) {
                    // ── Drag Indicator ───────────────────────────────────────
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // ── Top Header ───────────────────────────────────────────
                    ZStack {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.down")
                                    .font(.body.weight(.bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(SpringPressStyle())
                            Spacer()
                            // Sleep timer (cross-platform feature parity with Android)
                            Menu {
                                ForEach([15, 30, 45, 60], id: \.self) { mins in
                                    Button("\(mins) minutes") { player.setSleepTimer(minutes: mins) }
                                }
                                if player.sleepTimerEnd != nil {
                                    Button("Turn Off", role: .destructive) { player.cancelSleepTimer() }
                                }
                            } label: {
                                Image(systemName: player.sleepTimerEnd != nil ? "moon.fill" : "moon")
                                    .font(.body.weight(.bold))
                                    .foregroundColor(player.sleepTimerEnd != nil ? .red : .white.opacity(0.8))
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(SpringPressStyle())
                        }

                        VStack(spacing: 2) {
                            Text("PLAYING FROM")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(1)
                            Text(player.currentSong?.album ?? "Library")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .frame(maxWidth: availableWidth - 80)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, hPad)

                    // ── Main Content ─────────────────────────────────────────
                    VStack(spacing: 0) {
                        Spacer(minLength: 8)

                        if showLyrics {
                            // Mini artwork + song info header
                            HStack(spacing: 12) {
                                DiapasonArtworkView(
                                    url: player.currentSong.map { backend.client.getCoverArtURL(id: $0.albumId) } ?? nil
                                )
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(player.currentSong?.title ?? "")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(player.currentSong?.artist ?? "")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, hPad)
                            .padding(.bottom, 12)

                            // Lyrics body
                            if isLoadingLyrics {
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if !lyricLines.isEmpty {
                                SyncedLyricsView(
                                    lines: lyricLines,
                                    timeTracker: player.timeTracker,
                                    onSeek: player.seek
                                )
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.2))
                                    Text("Lyrics not available")
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            // Artwork — animates on song change
                            DiapasonArtworkView(
                                url: player.currentSong.map { backend.client.getCoverArtURL(id: $0.albumId) } ?? nil
                            ) { uiImage in
                                extractColors(from: uiImage)
                            }
                            .scaledToFill()
                            .frame(width: artworkSize, height: artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(
                                color: .black.opacity(player.isPlaying ? 0.4 : 0.18),
                                radius: player.isPlaying ? 28 : 12,
                                x: 0,
                                y: player.isPlaying ? 14 : 6
                            )
                            .scaleEffect(player.isPlaying ? 1.0 : 0.92)
                            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
                            .id(songId)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal:   .scale(scale: 1.04).combined(with: .opacity)
                            ))
                        }

                        Spacer(minLength: 8)

                        // ── Track Info ────────────────────────────────────────
                        if !showLyrics {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(player.currentSong?.title ?? "Nothing Playing")
                                        .font(.title2.weight(.bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    HStack(spacing: 8) {
                                        Text(player.currentSong?.artist ?? "")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.7))
                                            .lineLimit(1)

                                        if let label = player.currentSong?.qualityLabel {
                                            qualityBadge(label)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(songId)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal:   .move(edge: .top).combined(with: .opacity)
                                ))

                                HStack(spacing: 8) {
                                    // Heart / Favorite
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                            isFavorite.toggle()
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        if let song = player.currentSong {
                                            let newValue = isFavorite
                                            Task { await backend.client.setStarred(id: song.id, starred: newValue) }
                                        }
                                    }) {
                                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                                            .font(.body)
                                            .foregroundColor(isFavorite ? .red : .white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.12)))
                                            .scaleEffect(isFavorite ? 1.15 : 1.0)
                                    }
                                    .buttonStyle(.plain)

                                    // Ellipsis menu
                                    if let song = player.currentSong {
                                        Menu {
                                            Button {
                                                let insertIdx = player.currentIndex + 1
                                                var q = player.queue
                                                if insertIdx < q.count {
                                                    q.insert(song, at: insertIdx)
                                                } else {
                                                    q.append(song)
                                                }
                                                player.queue = q
                                            } label: {
                                                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                            }

                                            if !song.id.hasPrefix("local_song_") {
                                                Button {
                                                    addToPlaylistSong = song
                                                } label: {
                                                    Label("Add to Playlist…", systemImage: "music.note.list")
                                                }
                                            }

                                            Divider()

                                            Button("Go to Album", systemImage: "square.stack") { }
                                            Button("Go to Artist", systemImage: "music.mic") { }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(.body)
                                                .foregroundColor(.white)
                                                .frame(width: 40, height: 40)
                                                .background(Circle().fill(Color.white.opacity(0.12)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .fixedSize()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, hPad)

                            Spacer(minLength: 8)
                        }

                        // ── Scrubber ──────────────────────────────────────────
                        iOSProgressBar(timeTracker: player.timeTracker, onSeek: player.seek)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, hPad)

                        Spacer(minLength: 4)

                        // ── Transport Controls ────────────────────────────────
                        let playSize: CGFloat   = isSmall ? 64 : 80
                        let skipSize: CGFloat   = isSmall ? 44 : 56
                        let iconPlay: CGFloat   = isSmall ? 34 : 44
                        let iconSkip: CGFloat   = isSmall ? 22 : 26

                        HStack(spacing: 0) {
                            Spacer(minLength: 0)

                            // Shuffle
                            Button(action: { player.toggleShuffle() }) {
                                Image(systemName: player.shuffleMode.systemImage)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(player.shuffleMode.isActive ? .red : .white.opacity(0.5))
                                    .frame(width: skipSize, height: skipSize)
                                    .symbolEffect(.bounce, value: player.shuffleMode)
                            }
                            .buttonStyle(SpringPressStyle())

                            Spacer(minLength: 0)

                            // Previous
                            Button(action: { player.previous() }) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: iconSkip, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: skipSize, height: skipSize)
                            }
                            .buttonStyle(SpringPressStyle())

                            Spacer(minLength: 0)

                            // Play / Pause
                            Button(action: { player.togglePlayPause() }) {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: iconPlay, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: playSize, height: playSize)
                                    .contentTransition(.symbolEffect(.replace.byLayer.offUp))
                            }
                            .buttonStyle(SpringPressStyle())

                            Spacer(minLength: 0)

                            // Next
                            Button(action: { player.next() }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: iconSkip, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: skipSize, height: skipSize)
                            }
                            .buttonStyle(SpringPressStyle())

                            Spacer(minLength: 0)

                            // Repeat
                            Button(action: { player.cycleRepeat() }) {
                                Image(systemName: player.repeatMode.systemImage)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(player.repeatMode.isActive ? .red : .white.opacity(0.5))
                                    .frame(width: skipSize, height: skipSize)
                                    .symbolEffect(.bounce, value: player.repeatMode)
                            }
                            .buttonStyle(SpringPressStyle())

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: 4)

                        // ── Volume ────────────────────────────────────────────
                        SystemVolumeView(contentColor: .white)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, hPad)

                        Spacer(minLength: 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // ── Bottom Bar ────────────────────────────────────────────
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) { showLyrics.toggle() }
                        }) {
                            Image(systemName: "quote.bubble")
                                .font(.body)
                                .foregroundColor(showLyrics ? .white : .white.opacity(0.5))
                                .padding(10)
                                .background(showLyrics ? Color.white.opacity(0.18) : Color.clear)
                                .clipShape(Circle())
                        }
                        .buttonStyle(SpringPressStyle())

                        Spacer(minLength: 0)

                        AirPlayRouteButton(tintColor: .white.opacity(0.6))
                            .frame(width: 40, height: 40)

                        Spacer(minLength: 0)

                        Button(action: { showQueue = true }) {
                            Image(systemName: "list.bullet")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(10)
                                .clipShape(Circle())
                        }
                        .buttonStyle(SpringPressStyle())

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onChange(of: player.currentSong) { _, newSong in
            if let song = newSong {
                currentAlbumId = song.albumId
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    songId = song.id
                }
                fetchLyrics(for: song)
                isFavorite = false
                Task { isFavorite = await backend.client.isStarred(id: song.id) }
            }
        }
        .onAppear {
            if let song = player.currentSong {
                currentAlbumId = song.albumId
                songId = song.id
                fetchLyrics(for: song)
                Task { isFavorite = await backend.client.isStarred(id: song.id) }
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueSheetView()
        }
        .sheet(item: $addToPlaylistSong) { song in
            PlaylistPickerView(song: song)
        }
    }

    // MARK: - Quality Badge
    @ViewBuilder
    private func qualityBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - Color Extraction
    private func extractColors(from uiImage: UIImage) {
        let colors = ColorExtractor.extractColors(from: uiImage)
        withAnimation(.easeInOut(duration: 1.5)) {
            self.backgroundColors = colors
        }
    }

    // MARK: - Lyrics
    private func fetchLyrics(for song: Song) {
        Task {
            await MainActor.run { isLoadingLyrics = true; lyricLines = [] }

            async let internalRes = try? await backend.client.getLyricLines(id: song.id)
            async let externalRes = LyricsManager.shared.fetchLyrics(
                artist: song.artist,
                title: song.title,
                album: song.album,
                duration: song.duration.map { Double($0) }
            )

            let internalLines = await internalRes
            let externalResult = await externalRes

            let internalIsSynced = internalLines?.contains { $0.startMs != nil } ?? false
            let externalLines = externalResult.map {
                LyricsManager.shared.parseLRC($0.synced ?? $0.plain ?? "")
            } ?? []
            let externalIsSynced = externalResult?.synced != nil

            var finalLines: [LyricLine] = []
            if internalIsSynced {
                finalLines = internalLines ?? []
            } else if externalIsSynced {
                finalLines = externalLines
            } else if let lines = internalLines, !lines.isEmpty {
                finalLines = lines
            } else {
                finalLines = externalLines
            }

            await MainActor.run {
                self.lyricLines = finalLines
                self.isLoadingLyrics = false
            }
        }
    }
}

// MARK: - Format Badge Helper
struct AudioFormatBadge: View {
    let format: String
    var color: Color = .white

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .accessibilityLabel(format)
    }
}

// MARK: - Native AirPlay Button
struct AirPlayRouteButton: UIViewRepresentable {
    var tintColor: Color = Color.white.opacity(0.7)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .red
        view.tintColor = UIColor(tintColor)
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor(tintColor)
    }
}

// MARK: - Up Next Queue Sheet
struct QueueSheetView: View {
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .font(.body)
                                .fontWeight(index == player.currentIndex ? .bold : .regular)
                                .foregroundColor(index == player.currentIndex ? .red : .primary)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if index == player.currentIndex {
                            Image(systemName: "waveform").foregroundColor(.red)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.play(queue: player.queue, startingAt: index)
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
