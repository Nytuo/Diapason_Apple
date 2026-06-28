import SwiftUI

struct ArtistDetailView: View {
    @EnvironmentObject var backend: BackendManager
    let artist: Artist

    @State private var albums: [Album] = []
    @State private var isLoading = true

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Artist Header
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.customTertiarySystemGroupedBackground)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary.opacity(0.6))
                        )
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

                    Text(artist.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Artist")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)

                // Albums Grid
                VStack(alignment: .leading, spacing: 16) {
                    Text("Albums")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.horizontal)

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.top, 40)
                    } else if albums.isEmpty {
                        HStack {
                            Spacer()
                            Text("No albums found")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(albums) { album in
                                NavigationLink(destination: AlbumDetailView(album: album)) {
                                    LibraryAlbumGridCard(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 120) // space for mini player
            }
        }
        .customNavigationBarTitleDisplayMode()
        .background(Color.customSystemGroupedBackground)
        .onAppear {
            loadArtistDetails()
        }
    }

    private func loadArtistDetails() {
        guard albums.isEmpty else { return }
        Task {
            do {
                let detail = try await backend.client.getArtistDetails(id: artist.id)
                await MainActor.run {
                    self.albums = detail.album
                    self.isLoading = false
                }
            } catch {
                print("Failed to load artist details: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}
