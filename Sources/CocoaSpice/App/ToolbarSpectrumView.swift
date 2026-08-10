import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ToolbarSpectrumModel {
    private(set) var bandCount = SpectrumBandCount.defaultValue
    private let capHoldDuration: TimeInterval = 0.1
    private let capDropDecayRate: Double = 3.2

    var targetLevels = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    var levels = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    var capLevels = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    var gradientStartColor = NSColor.secondaryLabelColor {
        didSet { invalidateDisplaySurface() }
    }
    var gradientEndColor = NSColor.white {
        didSet { invalidateDisplaySurface() }
    }
    var peakColor = NSColor.white {
        didSet { invalidateDisplaySurface() }
    }
    private var capHoldRemaining = Array(repeating: 0.0, count: SpectrumBandCount.defaultValue)
    private var lastAnimationUptime: TimeInterval?
    private var displayTimer: Timer?
    private weak var displaySurface: NSView?
    private(set) var isAnimating = false
    var isVisible = false {
        didSet {
            if !isVisible {
                setAnimating(false)
            }
        }
    }

    func attachDisplaySurface(_ surface: NSView) {
        displaySurface = surface
        surface.needsDisplay = true
    }

    func update(with newLevels: [Float]) {
        // The audio callback may have one in-flight result after playback is
        // paused or the preference is turned off. Do not publish it into the
        // observable model: an invisible or stopped analyzer must have no
        // reason to invalidate its titlebar view.
        guard isVisible, isAnimating else { return }
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
        invalidateDisplaySurface()
    }

    private func startDisplayTimer() {
        guard isVisible, isAnimating, displayTimer == nil else { return }
        lastAnimationUptime = ProcessInfo.processInfo.systemUptime
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
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
        let shouldAnimate = isAnimating && isVisible
        guard self.isAnimating != shouldAnimate else { return }

        self.isAnimating = shouldAnimate
        if shouldAnimate {
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
        invalidateDisplaySurface()
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
        invalidateDisplaySurface()
    }

    private func invalidateDisplaySurface() {
        displaySurface?.needsDisplay = true
    }
}

enum SpectrumBandCount {
    static let supported = [10, 20, 40]
    static let defaultValue = 10

    static func clamped(_ value: Int) -> Int {
        supported.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultValue
    }
}

/// A fixed AppKit surface deliberately avoids a SwiftUI view graph and
/// constraint pass for every bar on every display tick. One invalidation draws
/// the whole widget, so 10/20/40 bars cost one small titlebar repaint.
@MainActor
final class ToolbarSpectrumNativeView: NSView {
    private let model: ToolbarSpectrumModel
    private let barWidth: CGFloat = 5
    private let spacing: CGFloat = 1
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 6
    private let meterHeight: CGFloat = 22
    private let minimumVisibleHeight: CGFloat = 2
    private let peakHeight: CGFloat = 1
    private let peakGap: CGFloat = 1
    private var cachedGradientStrip: NSImage?
    private var cachedGradientColors: (start: NSColor, end: NSColor)?

    init(model: ToolbarSpectrumModel) {
        self.model = model
        super.init(frame: .zero)
        // Keep the animated meter in its own backing layer.  Invalidating a
        // titlebar accessory at display rate must not redraw or recomposite
        // the surrounding SwiftUI toolbar.
        wantsLayer = true
        model.attachDisplaySurface(self)
        setAccessibilityLabel("Spectrum Analyzer")
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: horizontalPadding * 2 + CGFloat(model.bandCount) * barWidth + CGFloat(max(0, model.bandCount - 1)) * spacing,
            height: verticalPadding * 2 + meterHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        NSColor(srgbRed: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        NSColor.white.withAlphaComponent(0.06).setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        outline.lineWidth = 0.5
        outline.stroke()

        let baseY = verticalPadding
        let usableHeight = meterHeight - peakGap - peakHeight
        let gradientStrip = resolvedGradientStrip()
        for index in model.levels.indices {
            let x = horizontalPadding + CGFloat(index) * (barWidth + spacing)
            let level = CGFloat(min(max(model.levels[index], 0), 1))
            let barHeight = max(minimumVisibleHeight, usableHeight * level)
            let barRect = NSRect(x: x, y: baseY, width: barWidth, height: barHeight)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
            NSGraphicsContext.saveGraphicsState()
            barPath.addClip()
            gradientStrip.draw(in: barRect, from: NSRect(x: 0, y: 0, width: 1, height: 64), operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()

            let capLevel = CGFloat(min(max(model.capLevels[index], 0), 1))
            let capRect = NSRect(x: x, y: baseY + usableHeight * capLevel + peakGap, width: barWidth, height: peakHeight)
            model.peakColor.withAlphaComponent(0.95).setFill()
            NSBezierPath(roundedRect: capRect, xRadius: 1, yRadius: 1).fill()
        }
    }

    private func resolvedGradientStrip() -> NSImage {
        let start = model.gradientStartColor
        let end = model.gradientEndColor
        if let cachedGradientStrip,
           let cachedGradientColors,
           cachedGradientColors.start.isEqual(start),
           cachedGradientColors.end.isEqual(end) {
            return cachedGradientStrip
        }

        let image = NSImage(size: NSSize(width: 1, height: 64))
        image.lockFocus()
        NSGradient(starting: start, ending: end)?.draw(in: NSRect(x: 0, y: 0, width: 1, height: 64), angle: 90)
        image.unlockFocus()
        cachedGradientStrip = image
        cachedGradientColors = (start, end)
        return image
    }
}
