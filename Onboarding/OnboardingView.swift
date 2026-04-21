//
//  OnboardingView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.sumiSettings) var sumiSettings

    @State private var currentStage: Int = 0
    @State private var topBarAddressView: Bool = false

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.16),
                    Color(red: 0.12, green: 0.17, blue: 0.27),
                    Color(red: 0.18, green: 0.22, blue: 0.33)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 420, height: 420)
                .blur(radius: 36)
                .offset(x: -180, y: -160)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 42)
                .offset(x: 220, y: 180)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            onboardingBackground

            VStack {
                StageIndicator(stages: 3, activeStage: currentStage)
                Spacer()
                stageView
                    .transition(.slideAndBlur)
                Spacer()
                StageFooter(
                    currentStage: currentStage,
                    finalStage: 2,
                    onContinue: advance,
                    onBack: goBack
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            advance()
            return .handled
        }
    }

    @ViewBuilder
    private var stageView: some View {
        switch currentStage {
        case 0: HelloStage()
        case 1: URLBarStage(topBarAddressView: $topBarAddressView)
        case 2: FinalStage()
        default: EmptyView()
        }
    }

    private func applySettings() {
        sumiSettings.topBarAddressView = topBarAddressView

        sumiSettings.didFinishOnboarding = true
    }

    private func advance() {
        guard currentStage < 3 else { return }
        if currentStage == 2 {
            applySettings()
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            currentStage += 1
        }
    }

    private func goBack() {
        guard currentStage > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStage -= 1
        }
    }

}
