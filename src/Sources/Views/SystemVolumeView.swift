import SwiftUI
import AVFoundation
import MediaPlayer

struct SystemVolumeView: View {
    var contentColor: Color = .white
    @StateObject private var observer = SystemVolumeObserver()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundColor(contentColor.opacity(0.6))
                .font(.footnote)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(contentColor.opacity(0.2))
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(contentColor.opacity(0.8))
                        .frame(width: CGFloat(observer.volume) * geo.size.width, height: 4)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = Float(value.location.x / geo.size.width)
                            let newVol = max(0, min(1, ratio))
                            observer.volume = newVol
                        }
                )
            }
            .frame(height: 12)
            .background {
                HiddenVolumeViewRepresentable(volume: observer.volume)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            
            Image(systemName: "speaker.wave.3.fill")
                .foregroundColor(contentColor.opacity(0.6))
                .font(.footnote)
        }
    }
}

class SystemVolumeObserver: ObservableObject {
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume
    private var observation: NSKeyValueObservation?

    init() {
        volume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(
            \.outputVolume, options: [.new]
        ) { [weak self] _, change in
            guard let newVolume = change.newValue else { return }
            DispatchQueue.main.async {
                self?.volume = newVolume
            }
        }
    }
}

private struct HiddenVolumeViewRepresentable: UIViewRepresentable {
    let volume: Float

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        guard let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first,
              abs(slider.value - volume) > 0.01 else { return }
        slider.setValue(volume, animated: false)
    }
}
