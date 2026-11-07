import AppKit
import SwiftUI

struct FlowMenuBarView: View {
    @Bindable var store: FlowStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color(red: 0.24, green: 0.68, blue: 0.98))
                Text("Siftify")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.engineOnline ? Color.green : (store.modelState.isInstalled ? Color.cyan : Color.orange))
                        .frame(width: 7, height: 7)
                    Text(
                        store.engineOnline
                            ? "Ready"
                            : (store.modelState.isDownloading ? "Setting Up…" : (store.modelState.isInstalled ? "Private AI" : "Setup Needed"))
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            if store.modelState.isInstalled {
                Button {
                    bringWindowForward()
                    let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    store.selectFolder(downloads, autoStart: true)
                } label: {
                    Label("Preview ~/Downloads", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    bringWindowForward()
                    let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                    store.selectFolder(desktop, autoStart: true)
                } label: {
                    Label("Preview ~/Desktop", systemImage: "menubar.dock.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                Button {
                    bringWindowForward()
                    if !store.modelState.isDownloading {
                        store.startModelDownload()
                    }
                } label: {
                    Label(
                        store.modelState.isDownloading ? "View Setup Progress…" : "Set Up Private Organizer",
                        systemImage: "arrow.down.circle.fill"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            if store.willMoveCount > 0 && !store.isScanning {
                Button {
                    bringWindowForward()
                    store.organizeSelectedFiles()
                } label: {
                    Label("Organize \(store.willMoveCount) Ready Files", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            if let undo = store.lastUndoBatch {
                Button {
                    store.undoLastSift()
                } label: {
                    Label("Undo Last Sift (\(undo.moves.count))", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button {
                bringWindowForward()
            } label: {
                Label("Open Siftify", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Siftify", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(13)
        .frame(width: 244)
    }

    private func bringWindowForward() {
        if let existing = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "siftify-main")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
