import AppKit
import SwiftUI

final class OverlayWindow: NSWindow {
    init() {
        let screenFrame = NSScreen.main?.frame ?? .zero
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: RopeView().ignoresSafeArea())
        hostingView.frame = screenFrame
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView

        setFrame(screenFrame, display: true)
    }
}
