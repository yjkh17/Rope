//
//  RopeApp.swift
//  Rope
//
//  Created by Yousef Jawdat on 27/12/2025.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayWindow = OverlayWindow()
        overlayWindow?.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}

@main
struct RopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
