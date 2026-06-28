import SwiftUI
import Combine

struct SearchView: View {
    @EnvironmentObject var backend: BackendManager
    @EnvironmentObject var player: PlayerManager
    @State private var searchText = ""
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var addToPlaylistSong: Song? = nil

    @ObservedObject private var downloadManager = OfflineDownloadManager.shared

    /// Debounce publisher — waits 350ms after last keystroke before fetching
    @State private var searchSubject = PassthroughSubject<String, Never>()
    @State private var debounce: AnyCancellable?

    var body: some View {
        Group {
            if isSearching {
                VStack {
                    ProgressView("Searching…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results for \"\(searchText)\"")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Search your library")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, song in
                        Button(action: {
                            player.play(queue: results, startingAt: index)
                        }) {
                            HStack(spacing: 12) {
                                DiapasonArtworkView(url: backend.client.getCoverArtURL(id: song.albumId))
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(player.currentSong?.id == song.id ? .red : .primary)
                                        .lineLimit(1)
                                    Text("\(song.artist) — \(song.album)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if downloadManager.isDownloaded(songId: song.id) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if downloadManager.isDownloading(songId: song.id) {
                                    ProgressView()
                                        .scaleEffect(0.65)
                                        .frame(width: 14, height: 14)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .songContextMenu(
                            song: song,
                            downloadManager: downloadManager,
                            addToPlaylistSong: $addToPlaylistSong
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $searchText, prompt: "Songs, Artists, Albums")
        .onChange(of: searchText) { _, newValue in
            searchSubject.send(newValue)
        }
        .onAppear {
            debounce = searchSubject
                .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
                .removeDuplicates()
                .sink { query in
                    performSearch(query: query)
                }
        }
        .onDisappear {
            debounce?.cancel()
        }
        .background(Color.customSystemGroupedBackground)
        .sheet(item: $addToPlaylistSong) { song in
            PlaylistPickerView(song: song)
        }
    }

    private func performSearch(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []
            return
        }
        Task {
            await MainActor.run { isSearching = true }
            let fetched = (try? await backend.client.search(query: q)) ?? []
            await MainActor.run {
                self.results = fetched
                self.isSearching = false
            }
        }
    }
}
