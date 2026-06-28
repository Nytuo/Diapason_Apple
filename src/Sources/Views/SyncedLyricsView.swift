import SwiftUI

struct SyncedLyricsView: View {
    let lines: [LyricLine]
    @ObservedObject var timeTracker: PlaybackTimeTracker
    let onSeek: (Double) -> Void

    @State private var currentLineId: Int?

    var isSynced: Bool {
        lines.contains { $0.startMs != nil }
    }

    var body: some View {
        GeometryReader { geo in
            if isSynced {
                syncedLayout(geo: geo)
            } else {
                plainLayout(geo: geo)
            }
        }
    }

    @ViewBuilder
    private func syncedLayout(geo: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        VStack(alignment: .leading, spacing: 32) {
                            Button(action: {
                                if let startMs = line.startMs {
                                    onSeek(Double(startMs) / 1000.0)
                                }
                            }) {
                                iOSLyricLineRow(
                                    line: line,
                                    currentLineId: currentLineId,
                                    isPast: isLinePast(line)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(line.id)

                            if let nextTime = nextLineStartTime(after: index) {
                                IntermissionDots(currentTime: timeTracker.currentTime, targetTime: Double(nextTime) / 1000.0)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 120)
                .padding(.bottom, geo.size.height * 0.5) // Bottom space so last lines scroll to center
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: timeTracker.currentTime) { _, newTime in
                updateSync(at: newTime, proxy: proxy)
            }
            .onAppear {
                updateSync(at: timeTracker.currentTime, proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func plainLayout(geo: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 80)
        }
    }

    private func updateSync(at time: Double, proxy: ScrollViewProxy) {
        let currentMs = Int(time * 1000)
        let syncedLines = lines.filter { $0.startMs != nil }

        guard !syncedLines.isEmpty else { return }

        if let line = syncedLines.last(where: { $0.startMs! <= currentMs }) {
            if line.id != currentLineId {
                currentLineId = line.id
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    proxy.scrollTo(line.id, anchor: .center)
                }
            }
        }
    }

    private func isLinePast(_ line: LyricLine) -> Bool {
        guard let currentId = currentLineId,
              let currentLine = lines.first(where: { $0.id == currentId }),
              let lineStart = line.startMs,
              let currentStart = currentLine.startMs else { return false }
        return lineStart < currentStart
    }

    private func nextLineStartTime(after index: Int) -> Int? {
        guard index < lines.count - 1 else { return nil }
        let current = lines[index]
        let next = lines[index + 1]
        guard let start = current.startMs, let nextStart = next.startMs else { return nil }
        if (nextStart - start) > 5000 {
            return nextStart
        }
        return nil
    }
}

struct iOSLyricLineRow: View {
    let line: LyricLine
    let currentLineId: Int?
    let isPast: Bool

    var isCurrent: Bool { line.id == currentLineId }

    var body: some View {
        Text(line.text)
            .font(.system(size: isCurrent ? 28 : 24, weight: .bold))
            .foregroundColor(.white)
            .opacity(isCurrent ? 1.0 : (isPast ? 0.5 : 0.3))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: isCurrent ? 0 : 0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCurrent)
    }
}

struct IntermissionDots: View {
    let currentTime: Double
    let targetTime: Double
    
    @State private var activeDot = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        let timeRemaining = targetTime - currentTime
        
        if timeRemaining > 0 && timeRemaining < 15 {
            HStack(spacing: 16) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .opacity(activeDot == i ? 1.0 : 0.3)
                        .scaleEffect(activeDot == i ? 1.3 : 1.0)
                }
            }
            .onReceive(timer) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
    }
}

