import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ToolbarSpectrumModel {
    static let bandCount = 40
    private let capHoldDuration: TimeInterval = 0.100
    private let capDropDecayRate: Double = 3.2
    private let fallSmoothingTimeConstant: TimeInterval = 0.050

    var targetLevels = Array(repeating: 0.0, count: bandCount)
    var levels = Array(repeating: 0.0, count: bandCount)
    var capLevels = Array(repeating: 0.0, count: bandCount)
    var gradientStartColor = NSColor.secondaryLabelColor
    var gradientEndColor = NSColor.white
    var peakColor = NSColor.white
    private var capHoldRemaining = Array(repeating: 0.0, count: bandCount)
    private var lastAnimationUptime: TimeInterval?
    private var displayTimer: Timer?

    func update(with newLevels: [Float]) {
        guard !newLevels.isEmpty else {
            reset()
            return
        }

        for index in targetLevels.indices {
            let newValue = index < newLevels.count ? Double(newLevels[index]) : 0
            targetLevels[index] = min(max(newValue, 0), 1)
        }
    }

    private func startDisplayTimer() {
        guard displayTimer == nil else { return }
        displayTimer?.invalidate()
        lastAnimationUptime = ProcessInfo.processInfo.systemUptime
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepAnimation()
            }
        }
        if let displayTimer {
            RunLoop.main.add(displayTimer, forMode: .common)
        }
    }

    func setAnimating(_ isAnimating: Bool) {
        if isAnimating {
            startDisplayTimer()
            return
        }
        displayTimer?.invalidate()
        displayTimer = nil
        reset()
    }

    private func stepAnimation() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastAnimationUptime.map { max(1.0 / 120.0, now - $0) } ?? (1.0 / 60.0)
        lastAnimationUptime = now

        for index in levels.indices {
            let targetLevel = targetLevels[index]
            let nextLevel: Double
            if targetLevel >= levels[index] {
                nextLevel = targetLevel
            } else {
                let decay = exp(-elapsed / fallSmoothingTimeConstant)
                nextLevel = targetLevel + ((levels[index] - targetLevel) * decay)
            }
            levels[index] = nextLevel

            if nextLevel >= capLevels[index] {
                capLevels[index] = nextLevel
                capHoldRemaining[index] = capHoldDuration
                continue
            }

            if capHoldRemaining[index] > 0 {
                capHoldRemaining[index] = max(0, capHoldRemaining[index] - elapsed)
            } else {
                let decayedLevel = capLevels[index] * exp(-capDropDecayRate * elapsed)
                capLevels[index] = max(nextLevel, decayedLevel)
            }
        }
    }

    func reset() {
        guard targetLevels.contains(where: { $0 != 0 })
                || levels.contains(where: { $0 != 0 })
                || capLevels.contains(where: { $0 != 0 })
                || capHoldRemaining.contains(where: { $0 != 0 }) else {
            return
        }
        for index in levels.indices {
            targetLevels[index] = 0
            levels[index] = 0
            capLevels[index] = 0
            capHoldRemaining[index] = 0
        }
        lastAnimationUptime = ProcessInfo.processInfo.systemUptime
    }
}

struct ToolbarSpectrumView: View {
    @Bindable var model: ToolbarSpectrumModel

    private let barWidth: CGFloat = 5
    private let spacing: CGFloat = 1
    private let meterHeight: CGFloat = 22
    private let minimumVisibleHeight: CGFloat = 2
    private let peakHeight: CGFloat = 1
    private let peakGap: CGFloat = 1
    private let membraneColor = Color(.sRGB, red: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0, opacity: 1.0)

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { index, level in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(barFill)
                        .frame(
                            width: barWidth,
                            height: max(minimumVisibleHeight, barRenderableHeight * CGFloat(level))
                        )

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(capFill)
                        .frame(
                            width: barWidth,
                            height: peakHeight
                        )
                        .offset(y: -peakBottomOffset(for: model.capLevels[index]))
                }
                .frame(width: barWidth, height: meterHeight, alignment: .bottom)
            }
        }
        .frame(height: meterHeight, alignment: .bottom)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(membraneColor)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        }
        .fixedSize()
        .accessibilityLabel("Spectrum Analyzer")
    }

    private var barFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: model.gradientStartColor),
                Color(nsColor: model.gradientEndColor)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var capFill: Color {
        Color(nsColor: model.peakColor).opacity(0.95)
    }

    private var barRenderableHeight: CGFloat {
        meterHeight - peakGap - peakHeight
    }

    private func peakBottomOffset(for level: Double) -> CGFloat {
        (barRenderableHeight * CGFloat(min(max(level, 0), 1))) + peakGap
    }
}
