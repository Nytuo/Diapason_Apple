import SwiftUI

struct AlbumListView: View {
    @EnvironmentObject var backend: BackendManager
    @State private var albums: [Album] = []
    @State private var searchText = ""
    @State private var isLoading = false

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var filteredAlbums: [Album] {
        if searchText.isEmpty {
            return albums.sorted(by: { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending })
        } else {
            return albums.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
            }.sorted(by: { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending })
        }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading Albums...")
                }
            } else if albums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Albums Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredAlbums) { album in
                            NavigationLink(destination: AlbumDetailView(album: album)) {
                                LibraryAlbumGridCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    Spacer(minLength: 120) // space for mini player
                }
                .searchable(text: $searchText, prompt: "Search Albums")
            }
        }
        .navigationTitle("Albums")
        .customNavigationBarTitleDisplayMode()
        .background(Color.customSystemGroupedBackground)
        .onAppear {
            loadAlbums()
        }
    }

    private func loadAlbums() {
        guard albums.isEmpty else { return }
        isLoading = true
        Task {
            do {
                let fetched = try await backend.client.getAlbums()
                await MainActor.run {
                    self.albums = fetched
                    self.isLoading = false
                }
            } catch {
                print("Failed to fetch albums: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}
