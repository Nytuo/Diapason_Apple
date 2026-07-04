// Diapason — full-screen iPod-classic shell.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct iPodShellView: View {
    @Environment(\.appContainer) private var container
    @StateObject private var controller = iPodController()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let screenHeight = h * 0.46
            let wheelDiameter = min(w * 0.72, 300)

            ZStack {
                LinearGradient(colors: [Color(white: 0.97), Color(white: 0.90)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack {
                        iPodScreenView(controller: controller, screen: controller.current)
                            .id(controller.current.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: controller.direction == .forward ? .trailing : .leading),
                                removal:   .move(edge: controller.direction == .forward ? .leading : .trailing)
                            ))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: screenHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.30), lineWidth: 2))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    .padding(.horizontal, w * 0.06)
                    .padding(.top, 8)

                    Spacer(minLength: 12)
                    ClickWheel(controller: controller, diameter: wheelDiameter)
                    Spacer(minLength: 8)
                }
                .padding(.vertical, geo.safeAreaInsets.top > 0 ? 4 : 12)
            }
        }
        .onAppear { if let container { controller.start(container: container) } }
    }
}

struct InterfaceSettingsSection: View {
    @AppStorage("interfaceMode") private var interfaceModeRaw = InterfaceMode.modern.rawValue

    var body: some View {
        Section("Interface") {
            Picker("Appearance", selection: $interfaceModeRaw) {
                ForEach(InterfaceMode.allCases) { mode in Text(mode.label).tag(mode.rawValue) }
            }
            .pickerStyle(.segmented)
            Text("iPod Classic replaces the app with an on-screen click-wheel iPod. Return via “Exit iPod Mode” on its menu.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
