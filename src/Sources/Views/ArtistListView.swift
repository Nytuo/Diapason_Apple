import SwiftUI

struct ArtistListView: View {
    @EnvironmentObject var backend: BackendManager
    @State private var artists: [Artist] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var lastBackendType: BackendType?

    var filteredArtists: [Artist] {
        let sorted = artists.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        if searchText.isEmpty {
            return sorted
        } else {
            return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading Artists...")
                }
            } else if artists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.mic")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Artists Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(filteredArtists) { artist in
                        NavigationLink(destination: ArtistDetailView(artist: artist)) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.customTertiarySystemGroupedBackground)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.secondary.opacity(0.6))
                                    )
                                    .frame(width: 44, height: 44)

                                Text(artist.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .customListStyle()
                .searchable(text: $searchText, prompt: "Search Artists")
            }
        }
        .navigationTitle("Artists")
        .customNavigationBarTitleDisplayMode()
        .background(Color.customSystemGroupedBackground)
        .onAppear { refreshIfNecessary() }
        .onChange(of: backend.activeType) { _ in
            artists = []
            refreshIfNecessary()
        }
    }

    private func refreshIfNecessary() {
        if backend.client.isConnected && (artists.isEmpty || lastBackendType != backend.activeType) {
            lastBackendType = backend.activeType
            Task {
                await MainActor.run { isLoading = true }
                let fetched = (try? await backend.client.getArtists()) ?? []
                await MainActor.run {
                    self.artists = fetched
                    self.isLoading = false
                }
            }
        }
    }
}
