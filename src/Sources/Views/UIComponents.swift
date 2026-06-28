import SwiftUI
import UIKit

// MARK: - Color Extractor
class ColorExtractor {
    static func extractColors(from image: UIImage) -> [Color] {
        let size = image.size
        var points: [CGPoint] = []
        for x in stride(from: 0.1, through: 0.9, by: 0.2) {
            for y in stride(from: 0.1, through: 0.9, by: 0.2) {
                points.append(CGPoint(x: size.width * x, y: size.height * y))
            }
        }
        
        var colors: [Color] = []
        for point in points {
            if let color = image.getPixelColor(at: point) {
                colors.append(Color(uiColor: color))
            }
        }
        
        if colors.count < 2 {
            colors = [.blue, .purple, .pink, .orange, .red]
        }
        
        return Array(Set(colors)).shuffled().prefix(6).map { $0 }
    }
}

extension UIImage {
    func getPixelColor(at point: CGPoint) -> UIColor? {
        guard let cgImage = cgImage,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else { return nil }
        
        let pixelData = CFDataGetBytePtr(data)
        
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        let pixelInfo = Int(point.y) * bytesPerRow + Int(point.x) * bytesPerPixel
        
        let r = CGFloat(pixelData![pixelInfo]) / 255.0
        let g = CGFloat(pixelData![pixelInfo + 1]) / 255.0
        let b = CGFloat(pixelData![pixelInfo + 2]) / 255.0
        let a = CGFloat(pixelData![pixelInfo + 3]) / 255.0
        
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Animated Gradient Background
struct AnimatedGradientBackground: View {
    let colors: [Color]
    
    var body: some View {
        ZStack {
            (colors.first ?? .black)
                .ignoresSafeArea()
                .opacity(0.85)
            
            ZStack {
                ForEach(0..<min(colors.count, 3), id: \.self) { i in
                    GradientOrb(color: colors[i])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: 60)
            .saturation(1.3)
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            Color.black.opacity(0.4)
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .drawingGroup()
    }
}

struct GradientOrb: View {
    let color: Color
    @State private var offset = CGSize(
        width: CGFloat.random(in: -200...200),
        height: CGFloat.random(in: -200...200)
    )
    @State private var scale: CGFloat = CGFloat.random(in: 1.0...1.5)
    
    let duration: Double = Double.random(in: 15...30)
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [color.opacity(0.6), color.opacity(0)], 
                              center: .center, 
                              startRadius: 0, 
                              endRadius: 350)
            )
            .frame(width: 700, height: 700)
            .offset(offset)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    offset = CGSize(
                        width: CGFloat.random(in: -300...300),
                        height: CGFloat.random(in: -300...300)
                    )
                    scale = CGFloat.random(in: 1.2...1.8)
                }
            }
    }
}

// MARK: - Interactive Scrubber (iOS Scrubber)
struct iOSProgressBar: View {
    @ObservedObject var timeTracker: PlaybackTimeTracker
    var onSeek: (Double) -> Void
    
    @State private var isDragging = false
    @State private var dragTime: Double = 0
    
    var displayTime: Double {
        isDragging ? dragTime : timeTracker.currentTime
    }
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Progress Fill
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: max(0, min(geo.size.width, CGFloat(progressRatio()) * geo.size.width)), height: 4)
                    
                    // Scrubber Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 12 : 8, height: isDragging ? 12 : 8)
                        .offset(x: max(0, min(geo.size.width - 8, CGFloat(progressRatio()) * geo.size.width - 4)))
                        .shadow(radius: 2)
                }
                .contentShape(Rectangle())
                #if os(iOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let ratio = Double(value.location.x / geo.size.width)
                            dragTime = max(0, min(timeTracker.duration, ratio * timeTracker.duration))
                        }
                        .onEnded { value in
                            let ratio = Double(value.location.x / geo.size.width)
                            let finalTime = max(0, min(timeTracker.duration, ratio * timeTracker.duration))
                            onSeek(finalTime)
                            isDragging = false
                        }
                )
                #endif
            }
            .frame(height: 12)
            
            HStack {
                Text(formatTime(displayTime))
                Spacer()
                Text("-" + formatTime(max(0, timeTracker.duration - displayTime)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private func progressRatio() -> Double {
        guard timeTracker.duration > 0 else { return 0 }
        return displayTime / timeTracker.duration
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Adaptive Artwork View
struct DiapasonArtworkView: View {
    let url: URL?
    var onImageLoaded: ((UIImage) -> Void)? = nil
    
    @State private var localImage: UIImage? = nil
    
    var body: some View {
        Group {
            if let url = url {
                if url.isFileURL {
                    if let img = localImage {
                        Image(uiImage: img)
                            .resizable()
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white.opacity(0.2))
                            )
                            .onAppear {
                                loadLocalImage(from: url)
                            }
                    }
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .onAppear {
                                    fetchAndReportRemoteImage(from: url)
                                }
                        case .failure(_), .empty:
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.white.opacity(0.2))
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.2))
                    )
            }
        }
    }
    
    private func loadLocalImage(from fileURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: fileURL),
               let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.localImage = img
                    onImageLoaded?(img)
                }
            }
        }
    }
    
    private func fetchAndReportRemoteImage(from remoteURL: URL) {
        guard let onImageLoaded = onImageLoaded else { return }
        URLSession.shared.dataTask(with: remoteURL) { data, _, _ in
            if let data = data, let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    onImageLoaded(img)
                }
            }
        }.resume()
    }
}
