import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ToolbarSpectrumModel {
    private(set) var bandCount = SpectrumBandCount.defaultValue
    private let capHoldDuration: TimeInterval = 0.1
    private let capDropDecayRate: Double = 3.2

    var targetLevels = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    var levels = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    var capLevels = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    var gradientStartColor = NSColor.secondaryLabelColor
    var gradientEndColor = NSColor.white
    var peakColor = NSColor.white
    private var capHoldRemaining = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    private var lastAnimationUptime: TimeInterval?
    private var displayTimer: Timer?
    private(set) var isAnimating = false
    var isVisible = false {
        didSet {
            if !isVisible {
                setAnimating(false)
            }
        }
    }

    func update(with newLevels: [Float]) {
        guard newLevels.count == bandCount else {
            reset()
            return
        }

        for index in levels.indices {
            targetLevels[index] = min(max(Double(newLevels[index]), 0), 1)
        }
    }

    func configure(bandCount: Int) {
        let clamped = SpectrumBandCount.clamped(bandCount)
        guard self.bandCount != clamped else { return }
        self.bandCount = clamped
        targetLevels = Array(repeating: 0, count: clamped)
        levels = Array(repeating: 0, count: clamped)
        capLevels = Array(repeating: 0, count: clamped)
        capHoldRemaining = Array(repeating: 0, count: clamped)
    }

    private func startDisplayTimer() {
        guard isVisible, isAnimating, displayTimer == nil else { return }
        lastAnimationUptime = ProcessInfo.processInfo.systemUptime
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            // The timer is registered only on the main run loop below.
            MainActor.assumeIsolated {
                self?.stepAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    // Audio probes only set frequency targets. This timer exists
    // solely to animate a small number of bar heights between those targets.
    func setAnimating(_ isAnimating: Bool) {
        self.isAnimating = isAnimating && isVisible
        if self.isAnimating {
            startDisplayTimer()
            return
        }
        displayTimer?.invalidate()
        displayTimer = nil
        lastAnimationUptime = nil
        reset()
    }

    private func stepAnimation() {
        guard isVisible, isAnimating else {
            setAnimating(false)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastAnimationUptime.map { max(1.0 / 60.0, now - $0) } ?? (1.0 / 30.0)
        lastAnimationUptime = now

        for index in levels.indices {
            let target = targetLevels[index]
            // Direct target display while evaluating the FFT meter. Peak caps
            // still fall independently, but bar height has no smoothing.
            let next = target
            levels[index] = next
            if next >= capLevels[index] {
                capLevels[index] = next
                capHoldRemaining[index] = capHoldDuration
            } else if capHoldRemaining[index] > 0 {
                capHoldRemaining[index] = max(0, capHoldRemaining[index] - elapsed)
            } else {
                capLevels[index] = max(next, capLevels[index] * exp(-capDropDecayRate * elapsed))
            }
        }
    }

    func reset() {
        guard targetLevels.contains(where: { $0 != 0 })
                || levels.contains(where: { $0 != 0 })
                || capLevels.contains(where: { $0 != 0 }) else {
            return
        }
        for index in levels.indices {
            targetLevels[index] = 0
            levels[index] = 0
            capLevels[index] = 0
            capHoldRemaining[index] = 0
        }
    }
}

enum SpectrumBandCount {
    static let supported = [10, 20, 40]
    static let defaultValue = 10

    static func clamped(_ value: Int) -> Int {
        supported.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultValue
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
