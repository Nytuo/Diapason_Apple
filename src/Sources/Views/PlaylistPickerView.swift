import SwiftUI

/// A sheet that lets the user pick a playlist to add a song to.
struct PlaylistPickerView: View {
    @EnvironmentObject var backend: BackendManager
    @Environment(\.dismiss) var dismiss

    let song: Song

    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var successMessage: String? = nil
    @State private var showCreateSheet = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading playlists…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Playlists")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Create playlist") { showCreateSheet = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            Button(action: { addTo(playlist: playlist) }) {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .foregroundColor(.red)
                                        .frame(width: 32)
                                    Text(playlist.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if let sc = playlist.songCount {
                                        Text("\(sc)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showCreateSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = successMessage {
                    Text(msg)
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: successMessage)
            .sheet(isPresented: $showCreateSheet) {
                createPlaylistSheet
            }
        }
        .onAppear { loadPlaylists() }
    }

    // MARK: - Create Playlist mini-sheet
    private var createPlaylistSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Playlist name", text: $newPlaylistName)
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        showCreateSheet = false
                        Task {
                            try? await backend.client.createPlaylist(name: name, songId: song.id)
                            loadPlaylists()
                            showSuccess("Added to \"\(name)\"")
                        }
                    }
                    .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers
    private func loadPlaylists() {
        Task {
            isLoading = true
            let fetched = (try? await backend.client.getPlaylists()) ?? []
            // Only remote playlists (no local_ prefix)
            playlists = fetched.filter { !$0.id.hasPrefix("local_") }
            isLoading = false
        }
    }

    private func addTo(playlist: Playlist) {
        Task {
            try? await backend.client.addSongToPlaylist(songId: song.id, playlistId: playlist.id)
            showSuccess("Added to \"\(playlist.name)\"")
        }
    }

    private func showSuccess(_ msg: String) {
        successMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            successMessage = nil
            dismiss()
        }
    }
}
