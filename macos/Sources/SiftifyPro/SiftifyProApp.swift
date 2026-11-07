import AppKit
import SwiftUI

@MainActor
final class SiftifyProAppDelegate: NSObject, NSApplicationDelegate {
    var store: TidyStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown()
    }
}

@main
struct SiftifyProApp: App {
    @NSApplicationDelegateAdaptor(SiftifyProAppDelegate.self) private var appDelegate
    @State private var store: TidyStore

    init() {
        let created = TidyStore()
        _store = State(initialValue: created)
    }

    var body: some Scene {
        WindowGroup("Siftify Pro", id: "main") {
            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 268, ideal: 294, max: 344)
            } detail: {
                MainCanvasView(store: store)
            }
            .frame(minWidth: 920, minHeight: 580)
            .onAppear {
                appDelegate.store = store
            }
        }
        .defaultSize(width: 1080, height: 680)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Siftify Pro", systemImage: "sparkles.rectangle.stack") {
            MenuBarView(store: store)
                .onAppear {
                    appDelegate.store = store
                }
        }
        .menuBarExtraStyle(.window)
    }
}
