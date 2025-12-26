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

    private let gravity = CGPoint(x: 0, y: 1400)
    private let damping: CGFloat = 0.992
    private let segmentLength: CGFloat = 18
    private let constraintIterations = 12
    private let segmentCount = 28

    override var isFlipped: Bool { true }

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
        resetRope(initialPosition: CGPoint(x: bounds.midX, y: bounds.midY))
        startDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if points.isEmpty {
            resetRope(initialPosition: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    private func resetRope(initialPosition: CGPoint) {
        points = (0..<segmentCount).map { index in
            let offset = CGFloat(index) * segmentLength
            let pos = CGPoint(x: initialPosition.x, y: initialPosition.y + offset)
            return VerletPoint(position: pos, previous: pos)
        }
    }

    private func startDisplayLink() {
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
        let cursor = currentCursorLocation()
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
        points[0].position = position
        points[0].previous = position
    }

    private func integratePoints(dt: CFTimeInterval) {
        let dtSquared = CGFloat(dt * dt)
        let gravityStep = CGPoint(x: gravity.x * dtSquared, y: gravity.y * dtSquared)

        for index in points.indices.dropFirst() {
            var point = points[index]
            let velocity = CGPoint(x: (point.position.x - point.previous.x) * damping,
                                   y: (point.position.y - point.previous.y) * damping)
            let nextPosition = CGPoint(
                x: point.position.x + velocity.x + gravityStep.x,
                y: point.position.y + velocity.y + gravityStep.y
            )
            point.previous = point.position
            point.position = nextPosition
            points[index] = point
        }
    }

    private func satisfyConstraints(anchor: CGPoint) {
        for _ in 0..<constraintIterations {
            guard points.count > 1 else { break }
            points[0].position = anchor
            for i in 0..<(points.count - 1) {
                var p1 = points[i]
                var p2 = points[i + 1]
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
                points[i] = p1
                points[i + 1] = p2
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext, points.count > 1 else { return }

        context.clear(bounds)
        context.setLineWidth(3)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let gradientColors = [NSColor.systemYellow.withAlphaComponent(0.9).cgColor,
                              NSColor.systemOrange.withAlphaComponent(0.9).cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors as CFArray, locations: [0, 1]) {
            let path = CGMutablePath()
            path.move(to: points[0].position)
            for point in points.dropFirst() {
                path.addLine(to: point.position)
            }
            context.addPath(path)
            context.replacePathWithStrokedPath()
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(3)
            context.replacePathWithStrokedPath()
            context.clip()
            context.drawLinearGradient(gradient,
                                       start: points.first?.position ?? .zero,
                                       end: points.last?.position ?? .zero,
                                       options: [])
            context.restoreGState()
        }

        for (index, point) in points.enumerated() {
            let radius: CGFloat = index == 0 ? 4 : 3
            let rect = CGRect(x: point.position.x - radius, y: point.position.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(NSColor.white.withAlphaComponent(index == 0 ? 0.9 : 0.6).cgColor)
            context.fillEllipse(in: rect)
        }
    }
}
