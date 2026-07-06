// Diapason — iPod LCD screen.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct iPodScreenView: View {
    @ObservedObject var controller: iPodController
    @ObservedObject var screen: iPodScreen

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(Color.black.opacity(0.15))
            if screen.isNowPlaying {
                iPodNowPlayingView()
            } else {
                listBody
            }
        }
        .background(Color(white: 0.98))
        .task(id: screen.id) { await screen.loadIfNeeded() }
    }

    private var titleBar: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.92), Color(red: 0.62, green: 0.70, blue: 0.82)],
                           startPoint: .top, endPoint: .bottom)
            Text(screen.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(white: 0.15))
                .lineLimit(1)
        }
        .frame(height: 26)
    }

    private var listBody: some View {
        Group {
            if screen.isLoading {
                VStack { Spacer(); ProgressView(); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen.rows.isEmpty {
                VStack { Spacer(); Text("Empty").font(.system(size: 13)).foregroundColor(.secondary); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(screen.rows.enumerated()), id: \.element.id) { idx, row in
                                iPodListRow(row: row, selected: idx == screen.selection).id(idx)
                            }
                        }
                    }
                    .onChange(of: screen.selection) { _, sel in
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(sel, anchor: .center) }
                    }
                }
            }
        }
    }
}

private struct iPodListRow: View {
    let row: iPodRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .white : Color(white: 0.12))
                    .lineLimit(1)
                if let sub = row.subtitle {
                    Text(sub).font(.system(size: 10)).foregroundColor(selected ? .white.opacity(0.85) : .secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if case .push = row.action {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    .foregroundColor(selected ? .white.opacity(0.9) : Color(white: 0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected
            ? AnyView(LinearGradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.95), Color(red: 0.13, green: 0.36, blue: 0.80)], startPoint: .top, endPoint: .bottom))
            : AnyView(Color.clear))
    }
}

private struct iPodNowPlayingView: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        let ps = container?.playerState
        VStack(spacing: 10) {
            if let track = ps?.currentTrack {
                HStack(spacing: 10) {
                    CoverArtCard(id: track.coverArtId ?? track.id, size: 92)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        if let artist = track.artist { Text(artist).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1) }
                        if let album = track.albumName { Text(album).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundColor(Color(white: 0.12))

                Text("\((ps?.currentIndex ?? 0) + 1) of \(ps?.queue.count ?? 0)")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.85)).frame(height: 5)
                            Capsule().fill(Color.accent)
                                .frame(width: max(0, CGFloat(ratio(ps)) * geo.size.width), height: 5)
                        }
                    }
                    .frame(height: 5)
                    HStack {
                        Text(fmt(ps?.position ?? 0))
                        Spacer()
                        Text("-" + fmt(max(0, (ps?.duration ?? 0) - (ps?.position ?? 0))))
                    }
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                }
            } else {
                Spacer()
                Image(systemName: "music.note").font(.system(size: 40)).foregroundColor(Color(white: 0.7))
                Text("Nothing Playing").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func ratio(_ ps: PlayerState?) -> Double {
        guard let ps, ps.duration > 0 else { return 0 }
        return ps.position / ps.duration
    }
    private func fmt(_ s: Double) -> String { let t = Int(s); return String(format: "%d:%02d", t / 60, t % 60) }
}
