import AppKit
import Darwin
import SwiftUI

@MainActor
final class SiftifyAppDelegate: NSObject, NSApplicationDelegate {
    var store: FlowStore?
    var openMainWindow: (() -> Void)?
    private var sigtermSource: DispatchSourceSignal?
    private var sigintSource: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        installSignalHandlers()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow?()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown()
    }

    private func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSrc.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.store?.shutdown()
                NSApplication.shared.terminate(nil)
            }
        }
        termSrc.resume()
        self.sigtermSource = termSrc

        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSrc.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.store?.shutdown()
                NSApplication.shared.terminate(nil)
            }
        }
        intSrc.resume()
        self.sigintSource = intSrc
    }
}

@main
struct SiftifyApp: App {
    @NSApplicationDelegateAdaptor(SiftifyAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var store: FlowStore

    init() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        let created = FlowStore()
        _store = State(initialValue: created)
    }

    var body: some Scene {
        Window("Siftify", id: "siftify-main") {
            FlowMainView(store: store)
                .frame(minWidth: 820, minHeight: 600)
                .ignoresSafeArea(.container, edges: .top)
                .onAppear {
                    appDelegate.store = store
                    appDelegate.openMainWindow = { [openWindow] in
                        openWindow(id: "siftify-main")
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 670)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Siftify", systemImage: "wand.and.stars") {
            FlowMenuBarView(store: store)
                .onAppear {
                    appDelegate.store = store
                    appDelegate.openMainWindow = { [openWindow] in
                        openWindow(id: "siftify-main")
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
