//
//  RopeApp.swift
//  Rope
//
//  Created by Yousef Jawdat on 27/12/2025.
//

import SwiftUI
import AppKit

@main
struct RopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createOverlayWindow()
    }

    private func createOverlayWindow() {
        let window = OverlayWindow()
        window.orderFrontRegardless()
        overlayWindow = window
    }
}
