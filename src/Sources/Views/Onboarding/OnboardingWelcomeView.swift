// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct OnboardingWelcomeView: View {
    let onServerConnected: () -> Void

    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?
    @State private var showingServerForm = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            CassetteColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AnimatedDiapasonHero()
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .animation(.spring(duration: 0.6, bounce: 0.4), value: appeared)

                Spacer().frame(height: CassetteSpacing.xxxxl)

                VStack(spacing: CassetteSpacing.m) {
                    Text("Your music.\nYour rules.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(CassetteColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05), value: appeared)

                    Text("Stream your library from your own server.\nNo subscriptions. No Ads.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(CassetteColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.1), value: appeared)
                }
                .padding(.horizontal, CassetteSpacing.xxxl)

                Spacer()

                getStartedButton
                    .padding(.horizontal, CassetteSpacing.xxxl)
                    .padding(.bottom, CassetteSpacing.xxxl)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.2), value: appeared)
            }
        }
        .onAppear {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
            appeared = true
        }
        .onChange(of: container?.serverState.activeServer != nil) { _, connected in
            if connected { showingServerForm = false }
        }
        .sheet(isPresented: $showingServerForm, onDismiss: {
            if container?.serverState.activeServer != nil {
                onServerConnected()
            }
        }) {
            if let viewModel {
                NavigationStack {
                    ServerFormView(viewModel: viewModel)
                }
            }
        }
    }

    private var getStartedButton: some View {
        Button {
            triggerHaptic()
            showingServerForm = true
        } label: {
            Text("Get Started")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(CassetteColors.accent)
        .disabled(viewModel == nil)
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

// MARK: - Animated Diapason Hero

private struct AnimatedDiapasonHero: View {
    @State private var wiggleAngle: Double = 0
    @State private var waveProgress: CGFloat = 0

    private let forkSize: CGFloat = 96
    private let waveBaseSize: CGFloat = 110

    var body: some View {
        ZStack {
            Circle()
                .fill(CassetteColors.accent.opacity(0.08))
                .frame(width: 290, height: 290)
                .blur(radius: 60)

            ForEach(0..<3, id: \.self) { i in
                let delay = CGFloat(i) * 0.34
                let progress = (waveProgress + delay).truncatingRemainder(dividingBy: 1)
                Circle()
                    .stroke(CassetteColors.accent.opacity(0.5 * (1 - progress)), lineWidth: 2)
                    .frame(width: waveBaseSize + progress * 130, height: waveBaseSize + progress * 130)
            }

            Image(systemName: "tuningfork")
                .font(.system(size: forkSize, weight: .light))
                .foregroundStyle(CassetteColors.accent)
                .rotationEffect(.degrees(wiggleAngle))
        }
        .frame(width: 200, height: 130)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true)) {
                wiggleAngle = 3.5
            }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                waveProgress = 1
            }
        }
    }
}
