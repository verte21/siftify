import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FlowMainView: View {
    @Bindable var store: FlowStore
    @Namespace private var glassNamespace
    @State private var isDropTargeted: Bool = false

    var body: some View {
        ZStack {
            GlassWindowConfigurator()
                .frame(width: 0, height: 0)

            LivingAuroraBackdrop(stage: store.stage, isDropTargeted: isDropTargeted)

            VStack(spacing: 0) {
                topHeaderBar
                    .padding(.top, 12)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)

                ZStack {
                    switch store.stage {
                    case .setupModel:
                        FlowModelSetupStageView(store: store)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 1.03))
                            ))

                    case .pickFolder:
                        FlowHomeStageView(
                            store: store,
                            namespace: glassNamespace,
                            isDropTargeted: isDropTargeted
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))

                    case .scanning:
                        FlowScanningStageView(store: store)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 1.03))
                            ))

                    case .review:
                        FlowReviewStageView(store: store, namespace: glassNamespace)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))

                    case .completed(let summary):
                        FlowCompletedStageView(store: store, summary: summary)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.container, edges: .top)

            if let toast = store.toastMessage {
                VStack {
                    toastBanner(toast)
                        .padding(.top, 56)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(20)
            }

            if let target = store.inspectorTarget {
                FlowStackDetailOverlay(store: store, target: target) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        store.inspectorTarget = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(30)
            }

            if store.showCustomizeSheet {
                FlowCustomizeOverlay(store: store) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        store.showCustomizeSheet = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(40)
            }

            if store.showPrivacySheet {
                FlowPrivacyOverlay(store: store) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        store.showPrivacySheet = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(50)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
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

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            // Leave room for macOS window traffic lights on the leading edge
            Color.clear
                .frame(width: 64, height: 28)

            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.62, blue: 0.98),
                                    Color(red: 0.16, green: 0.84, blue: 0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                        .shadow(color: Color(red: 0.22, green: 0.72, blue: 0.94).opacity(0.45), radius: 8)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Siftify")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                privacyStatusPill
            }

            Spacer()

            if let undo = store.lastUndoBatch, !store.isScanning {
                Button {
                    store.undoLastSift()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Undo (\(undo.moves.count))")
                            .font(.system(size: 12, weight: .semibold))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(TranslucentGlassButtonStyle())
                .help("Put the last organized batch of files right back")
            }

            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    store.showCustomizeSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Folders & Style")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
            }
            .buttonStyle(TranslucentGlassButtonStyle())
        }
    }

    private var privacyStatusPill: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                store.showPrivacySheet = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusDotColor)

                Text(statusLabelText)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 4.5)
            .background(
                Capsule(style: .continuous)
                    .fill(statusDotColor.opacity(0.11))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(statusDotColor.opacity(0.35), lineWidth: 0.9)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Click to see how Siftify runs 100% offline on your Mac")
    }

    private var statusDotColor: Color {
        if store.engineOnline {
            return Color(red: 0.20, green: 0.90, blue: 0.58)
        }
        if store.isStartingEngine || store.modelState.isDownloading {
            return Color(red: 0.98, green: 0.74, blue: 0.24)
        }
        return Color(red: 0.34, green: 0.80, blue: 0.98)
    }

    private var statusLabelText: String {
        if store.isStartingEngine {
            return "Waking Up \(store.localChipName)…"
        }
        if store.engineOnline {
            return "On Your \(store.localChipName) · Offline"
        }
        if store.modelState.isDownloading {
            return "Setting Up Local AI…"
        }
        return "On Your \(store.localChipName) · Private"
    }

    private func toastBanner(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: store.toastIsError ? "exclamationmark.circle.fill" : "sparkles")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(
                    store.toastIsError
                        ? Color(red: 0.98, green: 0.62, blue: 0.26)
                        : Color(red: 0.24, green: 0.90, blue: 0.66)
                )

            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    store.toastMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassSurface(
            cornerRadius: 999,
            tint: store.toastIsError ? .orange : .mint,
            tintOpacity: 0.08,
            borderOpacity: 0.38,
            isHighlighted: true
        )
    }
}

// MARK: - Stage 0: First-Launch Friendly Setup

struct FlowModelSetupStageView: View {
    @Bindable var store: FlowStore

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                PhaseAnimator([false, true]) { pulse in
                    Circle()
                        .fill(Color(red: 0.24, green: 0.68, blue: 0.98).opacity(pulse ? 0.22 : 0.10))
                        .frame(width: pulse ? 104 : 88, height: pulse ? 104 : 88)
                } animation: { _ in
                    .easeInOut(duration: 2.2)
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.54, blue: 0.98),
                                Color(red: 0.14, green: 0.80, blue: 0.74)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: Color(red: 0.20, green: 0.70, blue: 0.95).opacity(0.5), radius: 16)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 110, height: 110)

            VStack(spacing: 9) {
                Text("Meet Your On-Device File Organizer")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("One quick download installs Siftify’s local classifier onto your \(store.localChipName). After this, it works even with Wi-Fi off — your files never touch the cloud.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .lineSpacing(3)
            }

            HStack(spacing: 10) {
                featureBadge(icon: "cpu.fill", label: "Runs on \(store.localChipName)")
                featureBadge(icon: "wifi.slash", label: "Works Offline")
                featureBadge(icon: "arrow.uturn.backward.circle.fill", label: "1-Click Undo")
            }

            switch store.modelState {
            case .downloading(let downloaded, let total, let speed):
                let fraction = min(1.0, max(0.0, Double(downloaded) / Double(max(1, total))))
                let pct = Int((fraction * 100.0).rounded())
                let dlStr = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
                let totStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                let speedMB = speed / (1024.0 * 1024.0)

                VStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 340, height: 10)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.26, green: 0.64, blue: 0.98),
                                        Color(red: 0.18, green: 0.88, blue: 0.68)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(14, 340 * fraction), height: 10)
                            .animation(.easeOut(duration: 0.22), value: fraction)
                    }

                    HStack(spacing: 6) {
                        Text("\(pct)% · \(dlStr) of \(totStr)")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .contentTransition(.numericText())

                        if speedMB >= 0.1 {
                            Text(String(format: "· %.1f MB/s", speedMB))
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    Button {
                        store.cancelModelDownload()
                    } label: {
                        Text("Pause Download")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(TranslucentGlassButtonStyle())
                }

            case .failed(let err):
                VStack(spacing: 12) {
                    Text(err)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(red: 0.98, green: 0.66, blue: 0.30))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button {
                        store.startModelDownload()
                    } label: {
                        Label("Try Download Again", systemImage: "arrow.clockwise")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(GlowActionButtonStyle())
                }

            case .notInstalled, .installed:
                Button {
                    store.startModelDownload()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Install Offline AI on This Mac (1.7 GB)")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                }
                .buttonStyle(GlowActionButtonStyle())
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 38)
        .frame(maxWidth: 560)
        .glassSurface(
            cornerRadius: 30,
            tint: Color(red: 0.24, green: 0.58, blue: 0.98),
            tintOpacity: 0.05,
            borderOpacity: 0.34,
            isHighlighted: true
        )
        .padding(24)
    }

    private func featureBadge(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.32, green: 0.84, blue: 0.96))
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.80))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Stage 1: Home / Drop Portal

struct FlowHomeStageView: View {
    @Bindable var store: FlowStore
    let namespace: Namespace.ID
    let isDropTargeted: Bool

    private var portalIconImage: NSImage {
        if let folderURL = store.targetFolderURL {
            return NSWorkspace.shared.icon(forFile: folderURL.path)
        }
        // Uses UTType.folder so zero TCC-protected user folders are touched before user clicks one
        return NSWorkspace.shared.icon(for: .folder)
    }

    private var portalHeadline: String {
        if isDropTargeted {
            return "Drop Folder to Sift"
        }
        if let folderURL = store.targetFolderURL {
            return "Sift \(folderURL.lastPathComponent)"
        }
        return "Pick or Drop a Folder to Sift"
    }

    private var portalSubtitle: String {
        guard store.targetFolderURL != nil else {
            return "Drag any messy folder onto this window, or choose one below to preview."
        }
        if store.totalTopLevelFilesInFolder == 0 {
            return "No loose files waiting right here — pick or drop another folder below."
        }
        return "\(store.totalTopLevelFilesInFolder) loose file\(store.totalTopLevelFilesInFolder == 1 ? "" : "s") ready to sort into \(store.enabledCategoryCount) smart folders"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)

            // Centerpiece Glass Drop Portal
            VStack(spacing: 19) {
                ZStack {
                    PhaseAnimator([false, true]) { breathe in
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(breathe ? 0.28 : 0.10),
                                        Color(red: 0.22, green: 0.82, blue: 0.96).opacity(breathe ? 0.36 : 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                            .frame(width: breathe ? 116 : 98, height: breathe ? 116 : 98)
                    } animation: { _ in
                        .easeInOut(duration: 2.6)
                    }

                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 84, height: 84)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)

                    Image(nsImage: portalIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 52, height: 52)
                        .scaleEffect(isDropTargeted ? 1.12 : 1.0)
                        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isDropTargeted)
                }
                .frame(width: 120, height: 120)

                VStack(spacing: 6) {
                    Text(portalHeadline)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.interpolate)

                    Text(portalSubtitle)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .contentTransition(.numericText())
                }

                // Quick Folder Switcher Row (only accesses a folder AFTER user clicks it)
                HStack(spacing: 8) {
                    quickFolderPill(
                        title: "Downloads",
                        icon: "arrow.down.circle.fill",
                        url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    )
                    quickFolderPill(
                        title: "Desktop",
                        icon: "menubar.dock.rectangle",
                        url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                    )
                    quickFolderPill(
                        title: "Documents",
                        icon: "doc.on.doc.fill",
                        url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
                    )
                    if let demoURL = store.demoInboxURL {
                        quickFolderPill(
                            title: "Sample Inbox",
                            icon: "sparkles",
                            url: demoURL
                        )
                    }
                    Button {
                        store.chooseFolderPanel()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Choose…")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white.opacity(0.84))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 30)
            .frame(maxWidth: 680)
            .glassSurface(
                cornerRadius: 30,
                tint: isDropTargeted ? Color(red: 0.20, green: 0.84, blue: 0.96) : Color(red: 0.30, green: 0.52, blue: 0.98),
                tintOpacity: isDropTargeted ? 0.11 : 0.04,
                borderOpacity: isDropTargeted ? 0.55 : 0.30,
                isHighlighted: isDropTargeted
            )
            .scaleEffect(isDropTargeted ? 1.025 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.76), value: isDropTargeted)

            // Carefulness Selector Bar
            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    ForEach(CarefulnessPreset.allCases) { preset in
                        let selected = store.carefulness == preset
                        Button {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
                                store.carefulness = preset
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text(preset.title)
                                    .font(.system(size: 12.5, weight: selected ? .bold : .medium, design: .rounded))
                            }
                            .foregroundStyle(selected ? .white : .white.opacity(0.62))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background {
                                if selected {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.16))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                                        )
                                        .matchedGeometryEffect(id: "carefulness_pill", in: namespace)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .glassSurface(cornerRadius: 999, borderOpacity: 0.20)

                Text(store.carefulness.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.54))
            }

            // Primary Action CTA
            if store.targetFolderURL == nil {
                Button {
                    store.chooseFolderPanel()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Choose a Folder to Sift…")
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 13)
                }
                .buttonStyle(
                    GlowActionButtonStyle(
                        accent: Color(red: 0.26, green: 0.56, blue: 0.98),
                        secondaryAccent: Color(red: 0.14, green: 0.80, blue: 0.72)
                    )
                )
            } else {
                Button {
                    store.startPreviewScan()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 15, weight: .bold))
                        Text("Sift & Preview")
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 13)
                }
                .buttonStyle(
                    GlowActionButtonStyle(
                        accent: Color(red: 0.26, green: 0.56, blue: 0.98),
                        secondaryAccent: Color(red: 0.14, green: 0.80, blue: 0.72)
                    )
                )
                .disabled(store.totalTopLevelFilesInFolder == 0)
                .opacity(store.totalTopLevelFilesInFolder == 0 ? 0.45 : 1.0)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 28)
    }

    private func quickFolderPill(title: String, icon: String, url: URL) -> some View {
        let isSelected = store.targetFolderURL?.standardizedFileURL == url.standardizedFileURL
        return Button {
            store.selectFolder(url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(red: 0.36, green: 0.86, blue: 0.98) : .white.opacity(0.62))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.74))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color(red: 0.36, green: 0.86, blue: 0.98).opacity(0.65), lineWidth: 1.1)
                        )
                        .matchedGeometryEffect(id: "folder_quick_pill", in: namespace)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stage 2: Live Magical Sorting View

struct FlowScanningStageView: View {
    @Bindable var store: FlowStore

    private var progressFraction: Double {
        guard store.scanProgressTotal > 0 else { return 0.05 }
        return min(1.0, max(0.04, Double(store.scanProgressCurrent) / Double(store.scanProgressTotal)))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            // Circular Orbital Glass Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.09), lineWidth: 8)
                    .frame(width: 132, height: 132)

                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.24, green: 0.78, blue: 0.98),
                                Color(red: 0.44, green: 0.46, blue: 0.98),
                                Color(red: 0.18, green: 0.88, blue: 0.66),
                                Color(red: 0.24, green: 0.78, blue: 0.98)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 132, height: 132)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(red: 0.20, green: 0.82, blue: 0.94).opacity(0.45), radius: 10)
                    .animation(.spring(response: 0.45, dampingFraction: 0.82), value: progressFraction)

                VStack(spacing: 2) {
                    Text("\(store.scanProgressCurrent) / \(store.scanProgressTotal)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("files read")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            VStack(spacing: 6) {
                Text("Sifting \(store.selectedFolderDisplayName)…")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Reading text, images, and metadata — nothing has moved yet.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            // Active File Glass Card with Sweeping Light Beam
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: store.currentScanningPath))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.currentScanningFilename.isEmpty ? "Wrapping up…" : store.currentScanningFilename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(store.currentScanningClue.isEmpty ? "Matching best folder…" : store.currentScanningClue)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.98))
                        .lineLimit(1)
                }

                Spacer()

                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let angle = (timeline.date.timeIntervalSinceReferenceDate * 260.0).truncatingRemainder(dividingBy: 360.0)
                    Circle()
                        .trim(from: 0.12, to: 0.78)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.28, green: 0.84, blue: 0.98),
                                    Color(red: 0.20, green: 0.90, blue: 0.68)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                        )
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(angle))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 480)
            .overlay {
                ScanningLightSweep()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .glassSurface(
                cornerRadius: 18,
                tint: Color(red: 0.22, green: 0.78, blue: 0.96),
                tintOpacity: 0.06,
                borderOpacity: 0.34,
                isHighlighted: true
            )

            // Live-forming Folder Stacks
            let liveStacks = store.folderStacks
            if !liveStacks.isEmpty {
                VStack(spacing: 8) {
                    Text("FORMING STACKS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 8) {
                        ForEach(liveStacks.prefix(5)) { group in
                            let color = group.palette.swiftUIColor
                            HStack(spacing: 6) {
                                Image(systemName: group.icon)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(color)
                                    .symbolEffect(.bounce, value: group.totalCount)

                                Text(group.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)

                                Text("\(group.totalCount)")
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(color)
                                    .contentTransition(.numericText())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(color.opacity(0.18)))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .glassSurface(cornerRadius: 999, tint: color, tintOpacity: 0.06, borderOpacity: 0.28)
                            .transition(.scale(scale: 0.78).combined(with: .opacity))
                        }
                    }
                }
                .padding(.top, 2)
            }

            Button {
                store.cancelScan()
            } label: {
                Text("Stop")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(TranslucentGlassButtonStyle())

            Spacer(minLength: 10)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Stage 3: Visual Folder Stacks Review

struct FlowReviewStageView: View {
    @Bindable var store: FlowStore
    let namespace: Namespace.ID

    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 14, alignment: .top),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            reviewHeader
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.folderStacks.isEmpty {
                        emptyMoveSuggestionCard
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(store.folderStacks.enumerated()), id: \.element.id) { index, group in
                                FolderStackGlassCard(
                                    group: group,
                                    entranceDelay: Double(index) * 0.045,
                                    onInspect: {
                                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                            store.inspectorTarget = .group(group.tagKey)
                                        }
                                    },
                                    onToggleAll: {
                                        store.toggleGroupSelection(group.tagKey)
                                    }
                                )
                            }
                        }
                    }

                    if !store.stayingPutEntries.isEmpty {
                        stayingPutStripCard
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)

            bottomFloatingDock
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
    }

    private var reviewHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    store.willMoveCount > 0
                        ? "Ready to sift \(store.willMoveCount) file\(store.willMoveCount == 1 ? "" : "s") in \(store.selectedFolderDisplayName)"
                        : "All files are set to stay in place"
                )
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

                Text("Nothing has moved yet — click any folder stack to inspect or change individual files.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            // Instant 0ms Carefulness Switcher
            HStack(spacing: 4) {
                ForEach(CarefulnessPreset.allCases) { preset in
                    let active = store.carefulness == preset
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
                            store.carefulness = preset
                        }
                    } label: {
                        Text(preset.title)
                            .font(.system(size: 11.5, weight: active ? .bold : .medium, design: .rounded))
                            .foregroundStyle(active ? .white : .white.opacity(0.60))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                            .background {
                                if active {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.16))
                                        .matchedGeometryEffect(id: "carefulness_pill", in: namespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3.5)
            .glassSurface(cornerRadius: 999, borderOpacity: 0.20)
        }
    }

    private var emptyMoveSuggestionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28))
                .foregroundStyle(Color(red: 0.36, green: 0.82, blue: 0.98))
            Text("No confident matches at this carefulness setting")
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Try switching to “Relaxed” above, or click below to assign folders manually.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(cornerRadius: 22, borderOpacity: 0.24)
    }

    private var stayingPutStripCard: some View {
        let entries = store.stayingPutEntries
        let count = entries.count
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                store.inspectorTarget = .stayingPut
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 40, height: 40)
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.56, green: 0.78, blue: 0.98))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keeping \(count) unsure file\(count == 1 ? "" : "s") safely in place")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("We never guess on ambiguous files — click if you’d like to pick a folder for \(count == 1 ? "it" : "them").")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                StackedFileIconsView(paths: entries.map(\.item.xray.path), iconSize: 24)

                HStack(spacing: 4) {
                    Text("Inspect")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10.5, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding(.leading, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassSurface(cornerRadius: 20, borderOpacity: 0.22)
        }
        .buttonStyle(.plain)
    }

    private var bottomFloatingDock: some View {
        HStack(spacing: 12) {
            Button {
                store.returnToHome()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11.5, weight: .bold))
                    Text("Change Folder")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(TranslucentGlassButtonStyle())

            Button {
                store.startPreviewScan()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .bold))
                    Text("Re-scan")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
            .buttonStyle(TranslucentGlassButtonStyle())

            Spacer()

            if store.keepingInPlaceCount > 0 {
                Text("\(store.keepingInPlaceCount) staying untouched")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.trailing, 4)
            }

            Button {
                store.organizeSelectedFiles()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Organize \(store.willMoveCount) File\(store.willMoveCount == 1 ? "" : "s")")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
            }
            .buttonStyle(
                GlowActionButtonStyle(
                    accent: Color(red: 0.12, green: 0.76, blue: 0.50),
                    secondaryAccent: Color(red: 0.12, green: 0.68, blue: 0.74)
                )
            )
            .disabled(store.willMoveCount == 0)
            .opacity(store.willMoveCount == 0 ? 0.42 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 22, borderOpacity: 0.26)
    }
}

struct FolderStackGlassCard: View {
    let group: FolderStackGroup
    let entranceDelay: Double
    let onInspect: () -> Void
    let onToggleAll: () -> Void

    @State private var appeared: Bool = false
    @State private var isHovered: Bool = false

    private var accent: Color {
        group.palette.swiftUIColor
    }

    private var previewFilenames: String {
        let names = group.entries.map(\.item.xray.filename)
        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names[0]), \(names[1]) +\(names.count - 2) more"
    }

    var body: some View {
        let active = group.isAnySelected
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Category Icon + Title + Move/Skip Pill (fixed 40pt height)
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent.opacity(active ? 0.24 : 0.10))
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(accent.opacity(active ? 0.55 : 0.20), lineWidth: 1)
                        )
                    Image(systemName: group.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(active ? accent : .white.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? .white : .white.opacity(0.55))
                        .lineLimit(1)

                    Text(
                        group.isAllSelected
                            ? "\(group.totalCount) file\(group.totalCount == 1 ? "" : "s") ready"
                            : (active ? "\(group.selectedCount) of \(group.totalCount) selected" : "Paused · staying in place")
                    )
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(active ? .white.opacity(0.66) : .white.opacity(0.42))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: onToggleAll) {
                    HStack(spacing: 5) {
                        Image(systemName: group.isAllSelected ? "checkmark.circle.fill" : (active ? "minus.circle.fill" : "circle"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(active ? "Move" : "Skip")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(active ? accent : .white.opacity(0.50))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(active ? accent.opacity(0.18) : Color.white.opacity(0.06))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(active ? accent.opacity(0.42) : Color.white.opacity(0.12), lineWidth: 0.9)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(active ? "Skip moving this folder stack" : "Include this folder stack")
            }

            // Row 2: Fanned Icons + Reserved 2-Line Filename Preview (consistent height across all cards)
            HStack(spacing: 12) {
                StackedFileIconsView(paths: group.entries.map(\.item.xray.path), iconSize: 28)
                    .fixedSize()
                    .opacity(active ? 1.0 : 0.5)

                Text(previewFilenames)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(active ? 0.72 : 0.42))
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // Row 3: Always-present 26pt Footer Strip (subfolders OR destination + total size)
            Group {
                if !group.subfolderPills.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(group.subfolderPills) { pill in
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(accent.opacity(0.85))
                                    Text(pill.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.84))
                                    Text("\(pill.count)")
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(accent)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.065))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                        )
                                )
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(accent.opacity(0.85))
                            Text(group.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.80))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.065))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                        )

                        Text(group.totalFormattedSize)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.045))
                            )

                        Spacer(minLength: 4)

                        HStack(spacing: 3) {
                            Text("Inspect")
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .fixedSize()
                        .foregroundStyle(.white.opacity(isHovered ? 0.80 : 0.42))
                    }
                }
            }
            .frame(height: 26)
        }
        .padding(17)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 168, maxHeight: 168, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            onInspect()
        }
        .glassSurface(
            cornerRadius: 22,
            tint: accent,
            tintOpacity: active ? 0.055 : 0.015,
            borderOpacity: isHovered ? 0.42 : 0.25,
            isHighlighted: isHovered
        )
        .scaleEffect(appeared ? (isHovered ? 1.014 : 1.0) : 0.92)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.80).delay(entranceDelay)) {
                appeared = true
            }
        }
    }
}

// MARK: - Stage 4: Celebration & Instant Undo

struct FlowCompletedStageView: View {
    @Bindable var store: FlowStore
    let summary: CompletionSummary
    @State private var sealBounce: Bool = false

    var body: some View {
        ZStack {
            CelebrationBurstView()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.84, blue: 0.56).opacity(0.20))
                        .frame(width: 92, height: 92)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.82, blue: 0.54),
                                    Color(red: 0.12, green: 0.68, blue: 0.76)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                        .shadow(color: Color(red: 0.14, green: 0.82, blue: 0.54).opacity(0.5), radius: 16)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: sealBounce)
                }

                VStack(spacing: 7) {
                    Text("\(summary.rootFolderName) is all sorted!")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    let untouchedSuffix = summary.untouchedCount > 0
                        ? " · \(summary.untouchedCount) unsure file\(summary.untouchedCount == 1 ? "" : "s") left safely untouched"
                        : ""
                    Text("Organized \(summary.movedCount) file\(summary.movedCount == 1 ? "" : "s") into \(summary.folders.count) neat folder\(summary.folders.count == 1 ? "" : "s")\(untouchedSuffix).")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                // Clickable Destination Folder Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(summary.folders) { folder in
                            let color = store.tagRule(for: folder.tagKey).map { TagPalette.forTag($0).swiftUIColor }
                                ?? Color(red: 0.24, green: 0.82, blue: 0.68)
                            Button {
                                NSWorkspace.shared.open(folder.folderURL)
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 7.5, height: 7.5)
                                    Text(folder.relPath.replacingOccurrences(of: "/", with: " › "))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("\(folder.count)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(color)
                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassSurface(cornerRadius: 999, tint: color, tintOpacity: 0.06, borderOpacity: 0.28)
                            }
                            .buttonStyle(.plain)
                            .help("Open \(folder.relPath) in Finder")
                        }
                    }
                    .padding(.horizontal, 6)
                }

                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(summary.rootFolderURL)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13.5, weight: .semibold))
                            Text("Open in Finder")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(
                        GlowActionButtonStyle(
                            accent: Color(red: 0.14, green: 0.76, blue: 0.52),
                            secondaryAccent: Color(red: 0.14, green: 0.68, blue: 0.76)
                        )
                    )

                    if store.lastUndoBatch != nil {
                        Button {
                            store.undoLastSift()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("Undo & Put Back")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(TranslucentGlassButtonStyle())
                    }

                    Button {
                        store.returnToHome()
                    } label: {
                        Text("Sift Another Folder")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(TranslucentGlassButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: 640)
            .glassSurface(
                cornerRadius: 30,
                tint: Color(red: 0.14, green: 0.80, blue: 0.58),
                tintOpacity: 0.05,
                borderOpacity: 0.36,
                isHighlighted: true
            )
            .padding(24)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                sealBounce.toggle()
            }
        }
    }
}
