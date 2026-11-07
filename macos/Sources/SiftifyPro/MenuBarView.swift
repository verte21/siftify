import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var store: TidyStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Siftify Pro")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.engineOnline ? Color.green : (store.modelState.isInstalled ? Color.secondary : Color.orange))
                        .frame(width: 7, height: 7)
                    Text(
                        store.engineOnline
                            ? "Metal Ready"
                            : (store.modelState.isDownloading ? "Downloading…" : (store.modelState.isInstalled ? "Standby" : "Setup Needed"))
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
                    store.selectFolder(downloads)
                    store.startDryRun()
                } label: {
                    Label("Dry-Run ~/Downloads", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Button {
                    bringWindowForward()
                    if !store.modelState.isDownloading {
                        store.startModelDownload()
                    }
                } label: {
                    Label(
                        store.modelState.isDownloading ? "View Model Download…" : "Download Q8_0 Model (1.7 GB)",
                        systemImage: "arrow.down.circle.fill"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            if store.willMoveCount > 0 && !store.isScanning {
                Button {
                    store.applyMoves()
                } label: {
                    Label("Apply \(store.willMoveCount) Ready Moves", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            if let undo = store.lastUndoBatch {
                Button {
                    store.undoLastBatch()
                } label: {
                    Label("Undo Last Batch (\(undo.moves.count))", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button {
                bringWindowForward()
            } label: {
                Label("Open Workspace Window", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Siftify Pro", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 240)
    }

    private func bringWindowForward() {
        if let existing = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
