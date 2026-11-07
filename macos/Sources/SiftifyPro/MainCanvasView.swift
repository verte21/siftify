import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainCanvasView: View {
    @Bindable var store: TidyStore
    @State private var showInspector: Bool = true
    @State private var isCanvasDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.vertical, 13)

            if store.isScanning {
                scanningProgressStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let msg = store.bannerMessage {
                bannerStrip(msg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if store.needsRescanForPromptChanges && !store.isScanning {
                rescanNoticeStrip
                    .transition(.opacity)
            }

            Divider()
                .opacity(0.55)

            if !store.modelState.isInstalled && store.items.isEmpty {
                modelSetupOnboardingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty && !store.isScanning {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        filterAndSummaryBar
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)

                        Divider()
                            .opacity(0.4)

                        resultsList
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showInspector, let selected = store.selectedItem {
                        Divider()
                            .opacity(0.5)
                        FileInspectorPane(store: store, item: selected)
                            .frame(width: 296)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.fileURL], isTargeted: $isCanvasDropTargeted) { providers in
            guard let first = providers.first else { return false }
            _ = first.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    DispatchQueue.main.async {
                        store.selectFolder(url)
                    }
                }
            }
            return true
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: store.targetFolderURL.path))
                    .resizable()
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(store.targetFolderURL.lastPathComponent)
                            .font(.system(size: 15, weight: .semibold))
                        Button {
                            NSWorkspace.shared.open(store.targetFolderURL)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open folder in Finder")
                    }
                    Text(store.targetFolderURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let undo = store.lastUndoBatch, !store.isScanning {
                Button {
                    store.undoLastBatch()
                } label: {
                    Label("Undo (\(undo.moves.count))", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Revert last batch of moved files")
            }

            if store.isScanning {
                Button {
                    store.cancelDryRun()
                } label: {
                    Label("Stop (\(store.scanProgressCurrent)/\(store.scanProgressTotal))", systemImage: "stop.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .contentTransition(.numericText())
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                Button {
                    store.startDryRun()
                } label: {
                    Label(store.items.isEmpty ? "Dry Run" : "Re-run Dry Run", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!store.modelState.isInstalled)
                .keyboardShortcut("r", modifiers: [.command])
            }

            Button {
                store.applyMoves()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Apply \(store.willMoveCount) Move\(store.willMoveCount == 1 ? "" : "s")")
                        .contentTransition(.numericText())
                }
                .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.13, green: 0.65, blue: 0.44))
            .controlSize(.regular)
            .disabled(store.isScanning || store.willMoveCount == 0)

            if !store.items.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showInspector.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                        .foregroundStyle(showInspector ? Color.accentColor : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Toggle File X-Ray Inspector")
            }
        }
    }

    private var scanningProgressStrip: some View {
        VStack(spacing: 6) {
            ProgressView(
                value: Double(store.scanProgressCurrent),
                total: Double(max(1, store.scanProgressTotal))
            )
            .progressViewStyle(.linear)

            HStack {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Inspecting \(store.currentScanningFilename)…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(store.scanProgressCurrent) of \(store.scanProgressTotal) · Read-only Dry Run")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func bannerStrip(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: store.bannerIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundStyle(store.bannerIsError ? Color.orange : Color.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button {
                withAnimation(.snappy) { store.bannerMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(store.bannerIsError ? Color.orange.opacity(0.10) : Color.green.opacity(0.09))
    }

    private var rescanNoticeStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text("Tag descriptions changed — run Dry Run again to score files against your updated prompts.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Re-run Now") {
                store.startDryRun()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.07))
    }

    private var modelSetupOnboardingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.11))
                    .frame(width: 72, height: 72)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 7) {
                Text("Set Up Local Classifier Engine")
                    .font(.system(size: 19, weight: .semibold))

                Text("One-time download · basal-2.0-mini-Q8_0 (1.70 GB) · 100% offline Apple Silicon Metal")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Siftify Pro bundles a standalone Metal GPU inference engine with zero Python or CLI dependencies. Download the default Q8_0 classifier once (or point SIFTIFY_MODEL_PATH at any local GGUF) to classify files locally with full privacy.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 470)
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                setupFeaturePill(icon: "lock.shield.fill", text: "Zero Cloud Uploads")
                setupFeaturePill(icon: "bolt.horizontal.fill", text: "Native Metal GPU")
                setupFeaturePill(icon: "dial.high.fill", text: "Calibrated Q8_0")
            }

            switch store.modelState {
            case .downloading(let downloaded, let total, let speed):
                VStack(spacing: 9) {
                    ProgressView(
                        value: Double(downloaded),
                        total: Double(max(1, total))
                    )
                    .progressViewStyle(.linear)
                    .frame(width: 360)

                    let dlStr = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
                    let totStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                    let pct = Int((Double(downloaded) / Double(max(1, total)) * 100.0).rounded())
                    let speedMB = speed / (1024.0 * 1024.0)

                    HStack(spacing: 6) {
                        Text("\(dlStr) of \(totStr) (\(pct)%)")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        if speedMB >= 0.1 {
                            Text(String(format: "· %.1f MB/s", speedMB))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Cancel Download") {
                        store.cancelModelDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 2)
                }
                .padding(.top, 4)

            case .failed(let message):
                VStack(spacing: 10) {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    Button {
                        store.startModelDownload()
                    } label: {
                        Label("Retry Model Download (1.70 GB)", systemImage: "arrow.clockwise")
                            .font(.system(size: 13.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

            case .notInstalled, .installed:
                Button {
                    store.startModelDownload()
                } label: {
                    Label("Download Local Model (1.70 GB)", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(36)
    }

    private func setupFeaturePill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 68, height: 68)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("Ready to Dry-Run \(store.targetFolderURL.lastPathComponent)")
                    .font(.system(size: 18, weight: .semibold))

                Text("\(store.totalTopLevelFilesInFolder) top-level files · \(store.activeLeafCount) active tags & subtags · 100% offline Metal · Q8_0")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                Text("Dry-run previews proposed folders using Vision OCR, PDF/Office content, and Spotlight metadata without moving any files.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                Button {
                    store.startDryRun()
                } label: {
                    Label("Start Dry-Run Preview", systemImage: "play.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Choose Another Folder…") {
                    store.chooseFolderPanel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(32)
        .overlay {
            if isCanvasDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(16)
            }
        }
    }

    private var filterAndSummaryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                filterPill(
                    title: "All (\(store.items.count))",
                    isSelected: store.filterMode == .all
                ) {
                    withAnimation(.snappy(duration: 0.18)) { store.filterMode = .all }
                }

                filterPill(
                    title: "Will Move (\(store.willMoveCount))",
                    accent: Color(red: 0.13, green: 0.65, blue: 0.44),
                    isSelected: store.filterMode == .willMove
                ) {
                    withAnimation(.snappy(duration: 0.18)) { store.filterMode = .willMove }
                }

                filterPill(
                    title: "Leave in Place (\(store.untouchedCount))",
                    accent: .secondary,
                    isSelected: store.filterMode == .untouched
                ) {
                    withAnimation(.snappy(duration: 0.18)) { store.filterMode = .untouched }
                }

                if store.averageLatencyMs > 0 {
                    Text("· Avg \(store.averageLatencyMs) ms/file")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Filter files…", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 130)
                    if !store.searchQuery.isEmpty {
                        Button {
                            store.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            let summaryChips = store.destinationSummaryCounts
            if !summaryChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(summaryChips, id: \.relPath) { chip in
                            let tagColor = store.config.folders[chip.tagKey].map { TagPalette.forTag($0).swiftUIColor } ?? .accentColor
                            let isSelected = store.filterMode == .byTag(chip.relPath)
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    store.filterMode = isSelected ? .all : .byTag(chip.relPath)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(tagColor)
                                        .frame(width: 6.5, height: 6.5)
                                    Text(chip.relPath.replacingOccurrences(of: "/", with: " › "))
                                        .font(.system(size: 11, weight: .medium))
                                    Text("\(chip.count)")
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isSelected ? tagColor : .secondary)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? tagColor.opacity(0.18) : Color.primary.opacity(0.045))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? tagColor.opacity(0.6) : .clear, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func filterPill(
        title: String,
        accent: Color = .accentColor,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(isSelected ? accent.opacity(0.16) : Color.primary.opacity(0.045))
                )
                .foregroundStyle(isSelected ? accent : .secondary)
                .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(store.filteredItems, id: \.item.id) { pair in
                    FileResultRow(
                        store: store,
                        item: pair.item,
                        decision: pair.decision,
                        isSelected: store.selectedItemID == pair.item.id
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

struct FileResultRow: View {
    @Bindable var store: TidyStore
    let item: ScanItem
    let decision: EffectiveDecision
    let isSelected: Bool

    @State private var isHovered: Bool = false

    private var tagColor: Color {
        if let tag = store.config.folders[decision.tagKey] {
            return TagPalette.forTag(tag).swiftUIColor
        }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 11) {
            Button {
                store.toggleItemMove(item.id)
            } label: {
                Image(systemName: decision.shouldMove ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(decision.shouldMove ? Color(red: 0.13, green: 0.65, blue: 0.44) : .secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(decision.shouldMove ? "Click to keep file in place" : "Click to include file in move batch")

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.xray.path))
                .resizable()
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.xray.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(decision.shouldMove ? .primary : .secondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(item.xray.formattedSize)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)

                    ForEach(item.xray.signalBadges.prefix(2), id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.055))
                            )
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            destinationMenuPill

            confidenceBadge
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.11) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.18)) {
                store.selectedItemID = item.id
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open File") { store.openFile(item.xray.path) }
            Button("Reveal in Finder") { store.revealInFinder(item.xray.path) }
            Divider()
            Button(decision.shouldMove ? "Leave File in Place" : "Include in Move Batch") {
                store.toggleItemMove(item.id)
            }
            if item.manualDestinationRelPath != nil || item.manualIncludeOverride != nil {
                Button("Reset to AI Suggestion") {
                    store.setManualDestination(itemID: item.id, relPath: nil, tagKey: nil)
                }
            }
        }
    }

    private var destinationMenuPill: some View {
        Menu {
            Button("Auto (\(decision.destinationRelPath.replacingOccurrences(of: "/", with: " › ")))") {
                store.setManualDestination(itemID: item.id, relPath: nil, tagKey: nil)
            }
            Button("Leave in Place (Do Not Move)") {
                store.setManualDestination(itemID: item.id, relPath: "__leave__", tagKey: nil)
            }
            Divider()
            ForEach(store.config.sortedTags) { tag in
                let subs = tag.sortedSubtags
                if subs.isEmpty {
                    Button(tag.path) {
                        store.setManualDestination(itemID: item.id, relPath: tag.path, tagKey: tag.key)
                    }
                } else {
                    Menu(tag.path) {
                        ForEach(subs) { sub in
                            Button(sub.path) {
                                store.setManualDestination(
                                    itemID: item.id,
                                    relPath: "\(tag.path)/\(sub.path)",
                                    tagKey: tag.key
                                )
                            }
                        }
                        Divider()
                        Button("\(tag.path) / General") {
                            store.setManualDestination(
                                itemID: item.id,
                                relPath: "\(tag.path)/General",
                                tagKey: tag.key
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if decision.shouldMove {
                    Circle()
                        .fill(tagColor)
                        .frame(width: 7, height: 7)
                    Text(decision.destinationRelPath.replacingOccurrences(of: "/", with: " › "))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(deferSubtitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(decision.shouldMove ? tagColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var deferSubtitle: String {
        switch decision.deferReason {
        case .lowConfidence:
            return "Leave in place · low conf"
        case .tagUnchecked:
            return "Skipped · \(decision.destinationRelPath.replacingOccurrences(of: "/", with: " › ")) off"
        case .manualSkip, .none:
            return "Leave in place"
        }
    }

    private var confidenceBadge: some View {
        let pct = Int((decision.confidence * 100.0).rounded())
        return Text("\(pct)%")
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(decision.shouldMove ? .primary : .secondary)
            .frame(width: 40, alignment: .trailing)
    }
}

struct FileInspectorPane: View {
    @Bindable var store: TidyStore
    let item: ScanItem

    var body: some View {
        let decision = item.evaluate(config: store.config, wrongCost: store.wrongCost)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.xray.path))
                        .resizable()
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.xray.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        Text("\(item.xray.formattedSize) · \(item.elapsedMs) ms on Metal")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        store.openFile(item.xray.path)
                    } label: {
                        Label("Open", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        store.revealInFinder(item.xray.path)
                    } label: {
                        Label("Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("CLASSIFIER PROBABILITIES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    let topSorted = item.topProbabilities.sorted { $0.value > $1.value }.prefix(4)
                    ForEach(Array(topSorted), id: \.key) { entry in
                        let label = store.config.folders[entry.key]?.path ?? entry.key
                        probabilityRow(label: label, prob: entry.value, highlight: entry.key == decision.tagKey)
                    }

                    if !item.subProbabilities.isEmpty,
                       let parent = store.config.folders[item.topKey],
                       let subs = parent.subfolders {
                        Text("SUBTAG READOUT (\(parent.path.uppercased()))")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)

                        let subSorted = item.subProbabilities.sorted { $0.value > $1.value }.prefix(4)
                        ForEach(Array(subSorted), id: \.key) { entry in
                            let subLabel = subs[entry.key]?.path ?? entry.key
                            probabilityRow(label: subLabel, prob: entry.value, highlight: entry.key == decision.subtagKey)
                        }
                    }
                }

                if !item.xray.downloadedFrom.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DOWNLOAD SOURCE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        ForEach(item.xray.downloadedFrom.prefix(2), id: \.self) { url in
                            Text(url)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                }

                if let preview = item.xray.textPreview, !preview.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("EXTRACTED CONTENT")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let pages = item.xray.pageCount {
                                Text("\(pages) page\(pages == 1 ? "" : "s")")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(preview)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                } else if !item.xray.archiveEntries.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARCHIVE CONTENTS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        Text(item.xray.archiveEntries.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                }
            }
            .padding(14)
        }
        .background(.ultraThinMaterial)
    }

    private func probabilityRow(label: String, prob: Double, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: highlight ? .semibold : .regular))
                    .foregroundStyle(highlight ? .primary : .secondary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.1f%%", prob * 100.0))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(highlight ? .primary : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(highlight ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: max(3, geo.size.width * CGFloat(min(1.0, max(0.0, prob)))))
                }
            }
            .frame(height: 4.5)
        }
    }
}
