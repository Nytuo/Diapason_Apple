import SwiftUI
import UniformTypeIdentifiers

struct LocalFilesView: View {
    @ObservedObject var localManager = LocalMusicManager.shared
    @EnvironmentObject var player: PlayerManager
    
    @State private var showFileImporter = false
    
    var body: some View {
        Group {
            if localManager.songs.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "folder.badge.minus")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Local Files Found")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Use the Desktop Diapason sharing tool or import audio files to play them here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button(action: {
                        showFileImporter = true
                    }) {
                        Label("Import Audio Files", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: 240)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
            } else {
                List {
                    // Play / Shuffle Header
                    Section {
                        HStack(spacing: 16) {
                            Button(action: {
                                player.play(queue: localManager.songs, startingAt: 0)
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            
                            Button(action: {
                                player.play(queue: localManager.songs.shuffled(), startingAt: 0)
                            }) {
                                HStack {
                                    Image(systemName: "shuffle")
                                    Text("Shuffle")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    
                    Section(header: Text("Tracks (\(localManager.songs.count))")) {
                        ForEach(Array(localManager.songs.enumerated()), id: \.element.id) { index, song in
                            Button(action: {
                                player.play(queue: localManager.songs, startingAt: index)
                            }) {
                                HStack(spacing: 16) {
                                    DiapasonArtworkView(url: LocalMusicManager.shared.coversDirURL.appendingPathComponent("\(song.albumId).jpg"))
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(player.currentSong?.id == song.id ? .red : .primary)
                                            .lineLimit(1)
                                        
                                        Text("\(song.artist) — \(song.album)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    if let dur = song.duration {
                                        Text(formatDuration(dur))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    localManager.deleteLocalSong(id: song.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    localManager.deleteLocalSong(id: song.id)
                                } label: {
                                    Label("Delete File", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Local Files")
        .background(Color.customSystemGroupedBackground)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showFileImporter = true
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.red)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    for url in urls {
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        _ = await localManager.importFile(from: url, filename: url.lastPathComponent)
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            case .failure(let error):
                print("Failed to select files: \(error)")
            }
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
