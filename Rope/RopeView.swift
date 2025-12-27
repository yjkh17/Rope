import SwiftUI
import AppKit
import CoreVideo

struct RopeView: NSViewRepresentable {
    func makeNSView(context: Context) -> RopeRenderView {
        RopeRenderView()
    }

    func updateNSView(_ nsView: RopeRenderView, context: Context) {}
}

final class RopeRenderView: NSView {
    private struct VerletPoint {
        var position: CGPoint
        var previous: CGPoint
    }

    private var points: [VerletPoint] = []
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var lastBoundsSize: CGSize = .zero

    private let gravity = CGPoint(x: 0, y: 1400)
    private let damping: CGFloat = 0.992
    private let segmentLength: CGFloat = 18
    private let constraintIterations = 12
    private let segmentCount = 28
    private let boundsPadding: CGFloat = 240

    private var fallbackPosition: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    override var isFlipped: Bool { true }

    private var clampedBounds: CGRect {
        var rect = bounds.insetBy(dx: -boundsPadding, dy: -boundsPadding)
        if rect.width.isZero || rect.height.isZero { return CGRect(origin: .zero, size: CGSize(width: 1, height: 1)) }
        return rect
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        stopDisplayLink()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            resetRope(initialPosition: sanitized(currentCursorLocation()))
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        if lastBoundsSize != newSize {
            lastBoundsSize = newSize
            if window != nil {
                resetRope(initialPosition: sanitized(currentCursorLocation()))
            }
        }
    }

    private func resetRope(initialPosition: CGPoint) {
        let safePosition = sanitized(initialPosition)
        points = (0..<segmentCount).map { index in
            let offset = CGFloat(index) * segmentLength
            let pos = clamp(CGPoint(x: safePosition.x, y: safePosition.y + offset))
            return VerletPoint(position: pos, previous: pos)
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, inNow, _, _, _, userInfo in
            guard let userInfo else { return kCVReturnError }
            let view = Unmanaged<RopeRenderView>.fromOpaque(userInfo).takeUnretainedValue()
            let timestamp = CFTimeInterval(inNow.pointee.videoTime) / CFTimeInterval(inNow.pointee.videoTimeScale)
            view.displayLinkFired(timestamp: timestamp)
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
        lastTimestamp = nil
    }

    private func displayLinkFired(timestamp: CFTimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let deltaTime: CFTimeInterval
            if let lastTimestamp {
                deltaTime = max(1.0 / 120.0, min(timestamp - lastTimestamp, 1.0 / 15.0))
            } else {
                deltaTime = 1.0 / 60.0
            }
            self.lastTimestamp = timestamp
            self.stepSimulation(dt: deltaTime)
        }
    }

    private func stepSimulation(dt: CFTimeInterval) {
        guard !points.isEmpty else { return }
        let cursor = sanitized(currentCursorLocation())
        pinFirstPoint(to: cursor)
        integratePoints(dt: dt)
        satisfyConstraints(anchor: cursor)
        needsDisplay = true
    }

    private func currentCursorLocation() -> CGPoint {
        guard let window else { return CGPoint(x: bounds.midX, y: bounds.midY) }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(windowPoint, from: nil)
        return localPoint
    }

    private func pinFirstPoint(to position: CGPoint) {
        guard !points.isEmpty else { return }
        let safePosition = sanitized(position)
        points[0].position = safePosition
        points[0].previous = safePosition
    }

    private func integratePoints(dt: CFTimeInterval) {
        let dtSquared = CGFloat(dt * dt)
        let gravityStep = CGPoint(x: gravity.x * dtSquared, y: gravity.y * dtSquared)

        for index in points.indices.dropFirst() {
            var point = points[index]
            guard point.position.x.isFinite, point.position.y.isFinite else {
                let resetPosition = sanitized(points[index - 1].position)
                point.position = resetPosition
                point.previous = resetPosition
                points[index] = point
                continue
            }
            let velocity = CGPoint(x: (point.position.x - point.previous.x) * damping,
                                   y: (point.position.y - point.previous.y) * damping)
            let nextPosition = CGPoint(
                x: point.position.x + velocity.x + gravityStep.x,
                y: point.position.y + velocity.y + gravityStep.y
            )
            guard nextPosition.x.isFinite, nextPosition.y.isFinite else {
                let resetPosition = sanitized(points[index - 1].position)
                point.position = resetPosition
                point.previous = resetPosition
                points[index] = point
                continue
            }
            point.previous = point.position
            point.position = clamp(nextPosition)
            points[index] = point
        }
    }

    private func satisfyConstraints(anchor: CGPoint) {
        guard anchor.x.isFinite, anchor.y.isFinite else {
            resetRope(initialPosition: fallbackPosition)
            return
        }
        for _ in 0..<constraintIterations {
            guard points.count > 1 else { break }
            points[0].position = clamp(anchor)
            for i in 0..<(points.count - 1) {
                var p1 = points[i]
                var p2 = points[i + 1]
                guard p1.position.x.isFinite, p1.position.y.isFinite, p2.position.x.isFinite, p2.position.y.isFinite else {
                    resetRope(initialPosition: anchor)
                    return
                }
                let delta = CGPoint(x: p2.position.x - p1.position.x, y: p2.position.y - p1.position.y)
                let distance = max(0.0001, hypot(delta.x, delta.y))
                let error = segmentLength - distance
                let correction = (error / distance) * 0.5
                let offset = CGPoint(x: delta.x * correction, y: delta.y * correction)

                if i == 0 {
                    p2.position.x -= offset.x * 2
                    p2.position.y -= offset.y * 2
                } else {
                    p1.position.x -= offset.x
                    p1.position.y -= offset.y
                    p2.position.x += offset.x
                    p2.position.y += offset.y
                }
                points[i] = clamp(point: p1)
                points[i + 1] = clamp(point: p2)
            }
        }
    }

    private func sanitized(_ point: CGPoint) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite else { return fallbackPosition }
        return clamp(point)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        clamp(point: point)
    }

    private func clamp(point: CGPoint) -> CGPoint {
        point.clamped(to: clampedBounds)
    }

    private func catmullRomPoints(from points: [CGPoint], samplesPerSegment: Int = 14) -> [CGPoint] {
        guard points.count > 1 else { return points }

        var splinePoints: [CGPoint] = []
        let padded: [CGPoint]
        if let first = points.first, let last = points.last {
            padded = [first] + points + [last]
        } else {
            padded = points
        }

        for i in 0..<(padded.count - 3) {
            let p0 = padded[i]
            let p1 = padded[i + 1]
            let p2 = padded[i + 2]
            let p3 = padded[i + 3]

            splinePoints.append(p1)

            for j in 1...samplesPerSegment {
                let t = CGFloat(j) / CGFloat(samplesPerSegment)
                let t2 = t * t
                let t3 = t2 * t

                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                splinePoints.append(CGPoint(x: x, y: y))
            }
        }

        if let last = points.last {
            splinePoints.append(last)
        }

        return splinePoints
    }

    private func pseudoNoise(_ seed: Int) -> CGFloat {
        let x = sin(CGFloat(seed) * 12.9898) * 43758.5453
        return x - floor(x)
    }


    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext, points.count > 1 else { return }

        let sanitizedPositions = points.map { sanitized($0.position) }
        guard sanitizedPositions.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            resetRope(initialPosition: fallbackPosition)
            return
        }

        context.clear(bounds)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let smoothed = catmullRomPoints(from: sanitizedPositions)
        guard smoothed.count > 1 else { return }

        var totalLength: CGFloat = 0
        for i in 0..<(smoothed.count - 1) {
            let delta = CGPoint(x: smoothed[i + 1].x - smoothed[i].x, y: smoothed[i + 1].y - smoothed[i].y)
            totalLength += max(0.0001, hypot(delta.x, delta.y))
        }
        guard totalLength > 0 else { return }

        context.saveGState()
        context.setShadow(offset: .zero, blur: 4, color: NSColor.black.withAlphaComponent(0.15).cgColor)

        let maxWidth: CGFloat = 12
        let minWidth: CGFloat = 3
        let baseColor = NSColor(calibratedRed: 0.93, green: 0.71, blue: 0.33, alpha: 1.0)
        let highlightColor = NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.7, alpha: 1.0)

        var traveled: CGFloat = 0
        for i in 0..<(smoothed.count - 1) {
            let start = smoothed[i]
            let end = smoothed[i + 1]
            let segmentVector = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let segmentLength = max(0.0001, hypot(segmentVector.x, segmentVector.y))

            let progress = traveled / totalLength
            let nextProgress = min(1, (traveled + segmentLength) / totalLength)
            let midProgress = (progress + nextProgress) * 0.5

            let taper = 1 - midProgress
            let width = max(minWidth, maxWidth * taper)
            let alpha = max(0, 0.95 * taper)

            let noiseScale: CGFloat = 0.6
            let noiseAngle = pseudoNoise(i) * .pi * 2
            let jitter = CGPoint(x: cos(noiseAngle) * noiseScale, y: sin(noiseAngle) * noiseScale)

            let jitteredStart = CGPoint(x: start.x + jitter.x, y: start.y + jitter.y)
            let jitteredEnd = CGPoint(x: end.x - jitter.x, y: end.y - jitter.y)

            context.setLineWidth(width)
            context.setStrokeColor(baseColor.withAlphaComponent(alpha * 0.8).cgColor)
            context.beginPath()
            context.move(to: jitteredStart)
            context.addLine(to: jitteredEnd)
            context.strokePath()

            context.setLineWidth(width * 0.6)
            context.setStrokeColor(highlightColor.withAlphaComponent(alpha).cgColor)
            context.beginPath()
            context.move(to: jitteredStart)
            context.addLine(to: jitteredEnd)
            context.strokePath()

            traveled += segmentLength
        }

        context.restoreGState()
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        let clampedX = min(rect.maxX, max(rect.minX, x))
        let clampedY = min(rect.maxY, max(rect.minY, y))
        return CGPoint(x: clampedX, y: clampedY)
    }
}
