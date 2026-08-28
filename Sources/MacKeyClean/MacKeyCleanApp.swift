import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
