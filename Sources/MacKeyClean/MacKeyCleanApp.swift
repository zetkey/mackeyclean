import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // install.sh launches the binary directly; setting the icon from the bundle
        // guarantees the Dock and app switcher show the real icon either way.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MacKeyCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = LockController()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(controller)
        }
        .windowResizability(.contentSize)
    }
}
