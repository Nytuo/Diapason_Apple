// Diapason — tvOS launch splash animation.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI

/// Animated launch splash: the Diapason logo springs in, the wordmark fades up.
/// Shown over the root while the app boots, then dismissed with a crossfade.
struct SplashScreenView: View {
    @State private var scale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 30

    var body: some View {
        ZStack {
            Color(red: 0.031, green: 0.353, blue: 0.627)
                .ignoresSafeArea()
            VStack(spacing: 40) {
                Image("diapason")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
                    .scaleEffect(scale)
                    .opacity(iconOpacity)
                Text("Diapason")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                scale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.25)) {
                textOpacity = 1.0
                textOffset = 0
            }
        }
    }
}
#endif
