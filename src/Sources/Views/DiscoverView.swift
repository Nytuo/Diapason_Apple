import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var backend: BackendManager
    @EnvironmentObject var player: PlayerManager

    @State private var recentlyAdded: [Album] = []
    @State private var mostPlayed: [Album] = []
    @State private var randomMix: [Album] = []
    @State private var freshReleases: [LBFreshRelease] = []

    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Section: Smart Shuffle
                smartShuffleCard

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading Discover...")
                        Spacer()
                    }
                    .padding(.top, 40)
                } else {
                    // Carousel: Recently Added
                    if !recentlyAdded.isEmpty {
                        DiscoverCarousel(title: "Recently Added", albums: recentlyAdded)
                    }

                    // Carousel: Most Played
                    if !mostPlayed.isEmpty {
                        DiscoverCarousel(title: "Most Played", albums: mostPlayed)
                    }

                    // Carousel: Smart Mix
                    if !randomMix.isEmpty {
                        DiscoverCarousel(title: "Smart Mix", albums: randomMix)
                    }

                    // Carousel: Fresh Releases from ListenBrainz
                    if !freshReleases.isEmpty {
                        LBFreshReleasesCarousel(releases: freshReleases)
                    }
                }

                Spacer(minLength: 120) // space for mini player
            }
            .padding(.top, 16)
        }
        .navigationTitle("Discover")
        .background(Color.customSystemGroupedBackground)
        .onAppear { loadData() }
        .onDisappear { loadTask?.cancel() }
        .onChange(of: backend.activeType) { _ in loadData(force: true) }
    }

    private var smartShuffleCard: some View {
        Button(action: {
            triggerSmartShuffle()
        }) {
            HStack(spacing: 16) {
                Image(systemName: "shuffle.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Shuffle")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Mix of random tracks from your server")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(18)
            .background(
                LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .red.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func loadData(force: Bool = false) {
        loadTask?.cancel()
        loadTask = Task {
            if recentlyAdded.isEmpty || force {
                if backend.client.isConnected {
                    await MainActor.run { isLoading = true }
                    do {
                        async let recent  = backend.client.getRecentlyAddedAlbums()
                        async let most    = backend.client.getMostPlayedAlbums()
                        async let random  = backend.client.getRandomAlbums()
                        async let fresh   = ListenBrainzClient.shared.getFreshReleases()

                        let (fetchedRecent, fetchedMost, fetchedRandom, fetchedFresh) =
                            try await (recent, most, random, fresh)

                        if !Task.isCancelled {
                            await MainActor.run {
                                self.recentlyAdded = fetchedRecent
                                self.mostPlayed    = fetchedMost
                                self.randomMix     = fetchedRandom
                                self.freshReleases = fetchedFresh
                                self.isLoading     = false
                            }
                        }
                    } catch {
                        print("Failed to load Discover: \(error)")
                        if !Task.isCancelled {
                            await MainActor.run { self.isLoading = false }
                        }
                    }
                } else {
                    // No backend connected — still load ListenBrainz
                    let fresh = await ListenBrainzClient.shared.getFreshReleases()
                    if !Task.isCancelled {
                        await MainActor.run { self.freshReleases = fresh }
                    }
                }
            }
        }
    }

    private func triggerSmartShuffle() {
        Task {
            do {
                let albums = try await backend.client.getRandomAlbums()
                guard !albums.isEmpty else { return }

                var allSongs: [Song] = []
                for album in albums.prefix(5) {
                    if let detail = try? await backend.client.getAlbumDetails(id: album.id) {
                        allSongs.append(contentsOf: detail.song)
                    }
                }

                guard !allSongs.isEmpty else { return }
                await MainActor.run {
                    player.play(queue: allSongs.shuffled(), startingAt: 0)
                }
            } catch {
                print("Failed to trigger smart shuffle: \(error)")
            }
        }
    }
}

// MARK: - Library album carousel

struct DiscoverCarousel: View {
    let title: String
    let albums: [Album]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            DiscoverCard(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct DiscoverCard: View {
    let album: Album
    @EnvironmentObject var backend: BackendManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DiapasonArtworkView(url: backend.client.getCoverArtURL(id: album.id))
                .scaledToFill()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

            Text(album.displayTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(album.artist)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140)
    }
}

// MARK: - ListenBrainz fresh releases carousel

struct LBFreshReleasesCarousel: View {
    let releases: [LBFreshRelease]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Fresh Releases")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("ListenBrainz")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(releases) { release in
                        LBReleaseCard(release: release)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct LBReleaseCard: View {
    let release: LBFreshRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: release.coverArtURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.secondary.opacity(0.4))
                        )
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

            Text(release.releaseName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(release.artistName)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let date = release.releaseDate {
                Text(date)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(width: 140)
    }
}
