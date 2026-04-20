//
//  StageFooter.swift
//  Sumi
//
//  Created by Maciek Bagiński on 17/02/2026.
//

import SwiftUI

struct StageFooter: View {
    var currentStage: Int
    var finalStage: Int
    var onContinue: () -> Void
    var onBack: () -> Void

    var secondaryText: String {
        currentStage == 0 ? "" : "Back"
    }

    var primaryText: String {
        if currentStage == finalStage {
            return "Start browsing"
        }

        switch currentStage {
        case 0: return "Get Started"
        default: return "Continue"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                onContinue()
            } label: {
                HStack {
                    Text(primaryText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .contentTransition(.numericText(value: Double(primaryText.count)))
                    Image(systemName: "return")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.8))

                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())
            if !(currentStage == 0) {
                Button {
                    if currentStage > 0 {
                        onBack()
                    }
                } label: {
                    Text(secondaryText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(12)
                }
                .buttonStyle(.plain)
            }

        }
    }
}
