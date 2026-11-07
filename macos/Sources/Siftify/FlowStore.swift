import AppKit
import Darwin
import Foundation
import Observation
import SwiftUI

enum CarefulnessPreset: String, CaseIterable, Identifiable {
    case relaxed
    case balanced
    case careful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .balanced: return "Balanced"
        case .careful: return "Extra Careful"
        }
    }

    var subtitle: String {
        switch self {
        case .relaxed: return "Sorts more files, including looser matches"
        case .balanced: return "Moves clear matches and leaves mysteries untouched"
        case .careful: return "Only moves files when it is very confident"
        }
    }

    var icon: String {
        switch self {
        case .relaxed: return "wind"
        case .balanced: return "sparkles"
        case .careful: return "shield.lefthalf.filled"
        }
    }

    var wrongCost: Double {
        switch self {
        case .relaxed: return 1.85
        case .balanced: return 2.20
        case .careful: return 3.00
        }
    }

    static func closest(to cost: Double) -> CarefulnessPreset {
        if cost < 2.0 { return .relaxed }
        if cost > 2.6 { return .careful }
        return .balanced
    }
}

struct SubfolderSummaryPill: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let count: Int
}

struct FolderStackGroup: Identifiable, Equatable {
    var id: String { tagKey }
    let tagKey: String
    let title: String
    let icon: String
    let palette: TagPalette
    let entries: [(item: ScanItem, decision: EffectiveDecision)]
    let subfolderPills: [SubfolderSummaryPill]

    var selectedCount: Int {
        entries.filter { $0.decision.shouldMove }.count
    }

    var totalCount: Int {
        entries.count
    }

    var totalBytes: Int64 {
        entries.reduce(0) { $0 + $1.item.xray.sizeBytes }
    }

    var totalFormattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var isAllSelected: Bool {
        selectedCount == totalCount && totalCount > 0
    }

    var isAnySelected: Bool {
        selectedCount > 0
    }

    static func == (lhs: FolderStackGroup, rhs: FolderStackGroup) -> Bool {
        guard lhs.tagKey == rhs.tagKey,
              lhs.title == rhs.title,
              lhs.icon == rhs.icon,
              lhs.palette == rhs.palette,
              lhs.subfolderPills == rhs.subfolderPills,
              lhs.entries.count == rhs.entries.count else {
            return false
        }
        for (a, b) in zip(lhs.entries, rhs.entries) {
            if a.item != b.item || a.decision != b.decision { return false }
        }
        return true
    }
}

struct OrganizedFolderCount: Identifiable, Equatable {
    var id: String { relPath }
    let relPath: String
    let tagKey: String
    let count: Int
    let folderURL: URL
}

struct CompletionSummary: Equatable {
    let movedCount: Int
    let untouchedCount: Int
    let rootFolderName: String
    let rootFolderURL: URL
    let folders: [OrganizedFolderCount]
}

enum FlowStage: Equatable {
    case setupModel
    case pickFolder
    case scanning
    case review
    case completed(CompletionSummary)
}

enum FlowInspectorTarget: Identifiable, Equatable {
    case group(String)
    case stayingPut

    var id: String {
        switch self {
        case .group(let key): return "group-\(key)"
        case .stayingPut: return "staying-put"
        }
    }
}

extension FileXRayData {
    var friendlyClueDescription: String {
        var parts: [String] = []
        if let firstUrl = downloadedFrom.first, let host = URL(string: firstUrl)?.host {
            let cleanHost = host.replacingOccurrences(of: "www.", with: "")
            parts.append("From \(cleanHost)")
        }

        let chars = textPreview?.count ?? 0
        switch extractionMethod {
        case "apple_vision_ocr" where chars > 0:
            parts.append("Read text inside image")
        case "pdfkit_text" where chars > 0:
            if let pages = pageCount, pages > 0 {
                parts.append("Read \(pages)-page PDF")
            } else {
                parts.append("Read PDF contents")
            }
        case "pdf_vision_ocr" where chars > 0:
            parts.append("Read scanned PDF")
        case "office_textutil" where chars > 0:
            parts.append("Read document text")
        case "pptx_slides" where chars > 0:
            if let slides = pageCount, slides > 0 {
                parts.append("Read \(slides) slides")
            } else {
                parts.append("Read presentation")
            }
        case "xlsx_sheets" where chars > 0:
            parts.append("Read spreadsheet")
        case "epub_content" where chars > 0:
            parts.append("Read ebook chapters")
        case "iwork_vision_ocr" where chars > 0:
            parts.append("Read document preview")
        case "blackbox_header" where chars > 0:
            parts.append("Read flight controller log")
        case "stl_header" where chars > 0:
            parts.append("Inspected 3D model")
        case "zip_manifest" where !archiveEntries.isEmpty:
            parts.append("Checked \(archiveEntries.count) archive items")
        default:
            if chars > 0 {
                parts.append("Read text note")
            } else if !visionTags.isEmpty {
                let firstTag = visionTags[0].replacingOccurrences(of: "_", with: " ")
                parts.append("Recognized \(firstTag)")
            }
        }

        if parts.isEmpty {
            return ext.isEmpty ? formattedSize : ".\(ext.uppercased()) file · \(formattedSize)"
        }
        return parts.prefix(2).joined(separator: " · ")
    }
}

@MainActor
@Observable
final class FlowStore {
    let appSupportDir: URL
    let workspaceRoot: URL?
    let localChipName: String
    var config: TidyConfig

    // Starts nil so we NEVER touch ~/Downloads, ~/Desktop, or ~/Documents before user explicitly picks one
    var targetFolderURL: URL? = nil {
        didSet {
            refreshCandidateCount()
        }
    }
    var scanScope: ScanScope = .latest40
    var carefulness: CarefulnessPreset = .balanced {
        didSet {
            wrongCost = carefulness.wrongCost
            saveConfigToDisk()
        }
    }
    var wrongCost: Double = 2.2

    var stage: FlowStage = .pickFolder
    var modelState: ModelInstallState = .notInstalled
    var engineOnline: Bool = false
    var isStartingEngine: Bool = false

    var isScanning: Bool = false
    var scanProgressCurrent: Int = 0
    var scanProgressTotal: Int = 0
    var currentScanningFilename: String = ""
    var currentScanningClue: String = ""
    var currentScanningPath: String = ""
    var totalTopLevelFilesInFolder: Int = 0

    var items: [ScanItem] = []
    var inspectorTarget: FlowInspectorTarget? = nil
    var showCustomizeSheet: Bool = false
    var showPrivacySheet: Bool = false

    var lastUndoBatch: UndoBatch? = nil
    var toastMessage: String? = nil
    var toastIsError: Bool = false

    private let service = ClassifierService()
    private let modelManager: ModelManager
    private var scanTask: Task<Void, Never>? = nil
    private var healthTimerTask: Task<Void, Never>? = nil
    private var toastDismissTask: Task<Void, Never>? = nil

    nonisolated private static let nonisolatedIgnoredExtensions: Set<String> = ["crdownload", "part", "download", "tmp"]

    init() {
        let fm = FileManager.default
        let supportBase = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let support = supportBase.appendingPathComponent("Siftify", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        self.appSupportDir = support
        self.localChipName = Self.detectLocalChipName()

        let wsRoot = Self.detectWorkspaceRoot()
        self.workspaceRoot = wsRoot

        let loadedConfig = Self.loadInitialConfig(appSupportDir: support, workspaceRoot: wsRoot)
        self.config = loadedConfig
        let initialPreset = CarefulnessPreset.closest(to: loadedConfig.costs.wrong)
        self.carefulness = initialPreset
        self.wrongCost = initialPreset.wrongCost

        let manager = ModelManager(appSupportDirectory: support)
        self.modelManager = manager
        let initialModel = manager.currentInstallState()
        self.modelState = initialModel
        self.stage = initialModel.isInstalled ? .pickFolder : .setupModel

        // Only pre-select demo-inbox when explicitly requested via SIFTIFY_DEMO_START=1 (never touch TCC folders at launch)
        if ProcessInfo.processInfo.environment["SIFTIFY_DEMO_START"] == "1",
           let demo = wsRoot?.appendingPathComponent("demo-inbox"),
           fm.fileExists(atPath: demo.path) {
            self.targetFolderURL = demo
        }

        manager.onStateChange = { [weak self] nextState in
            guard let self else { return }
            let wasDownloading = self.modelState.isDownloading
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                self.modelState = nextState
                if nextState.isInstalled && self.stage == .setupModel {
                    self.stage = .pickFolder
                }
            }
            if wasDownloading, case .installed = nextState {
                self.showToast("Private organizer is ready on your \(self.localChipName)!", isError: false)
                Task {
                    _ = await self.ensureEngineRunning()
                }
            }
        }

        loadUndoHistory()
        if targetFolderURL != nil {
            refreshCandidateCount()
        }
        startHealthPolling()

        if initialModel.isInstalled {
            Task {
                _ = await self.ensureEngineRunning()
                if ProcessInfo.processInfo.environment["SIFTIFY_AUTOSCAN"] == "1", self.targetFolderURL != nil {
                    self.startPreviewScan()
                }
            }
        }
    }

    private static func detectLocalChipName() -> String {
        var size: Int = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return "Mac"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return "Mac"
        }
        let raw = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Mac" : raw
    }

    static func detectWorkspaceRoot() -> URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["SIFTIFY_ROOT"], !env.isEmpty {
            let envURL = URL(fileURLWithPath: env)
            if fm.fileExists(atPath: envURL.appendingPathComponent("siftify.config.json").path) {
                return envURL
            }
        }

        var cur = Bundle.main.bundleURL.standardizedFileURL
        for _ in 0..<5 {
            let parent = cur.deletingLastPathComponent()
            if parent.path == cur.path { break }
            cur = parent
            if fm.fileExists(atPath: cur.appendingPathComponent("siftify.config.json").path) {
                return cur
            }
        }
        return nil
    }

    private static func loadInitialConfig(appSupportDir: URL, workspaceRoot: URL?) -> TidyConfig {
        let fm = FileManager.default
        let userConfigURL = appSupportDir.appendingPathComponent("siftify.config.json")

        var candidates: [URL] = [userConfigURL]
        if let ws = workspaceRoot {
            candidates.append(ws.appendingPathComponent("siftify.config.json"))
        }
        if let bundled = Bundle.main.url(forResource: "siftify.config", withExtension: "json") {
            candidates.append(bundled)
        }
        if let resDir = Bundle.main.resourceURL {
            candidates.append(resDir.appendingPathComponent("siftify.config.json"))
        }

        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(TidyConfig.self, from: data) {
                if !fm.fileExists(atPath: userConfigURL.path) {
                    try? data.write(to: userConfigURL, options: .atomic)
                }
                return decoded
            }
        }

        return TidyConfig(
            engineUrl: "http://127.0.0.1:8766",
            costs: CostsConfig(wrong: 2.2, deferCost: 1.0),
            folders: [:]
        )
    }

    var historyDirectoryURL: URL {
        appSupportDir.appendingPathComponent("history", isDirectory: true)
    }

    var demoInboxURL: URL? {
        guard let ws = workspaceRoot else { return nil }
        let url = ws.appendingPathComponent("demo-inbox", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var selectedFolderDisplayName: String {
        targetFolderURL?.lastPathComponent ?? "Your Folder"
    }

    var evaluatedItems: [(item: ScanItem, decision: EffectiveDecision)] {
        items.map { ($0, $0.evaluate(config: config, wrongCost: wrongCost)) }
    }

    func tagRule(for key: String) -> TagRule? {
        guard var rule = config.folders[key] else { return nil }
        rule.key = key
        return rule
    }

    var folderStacks: [FolderStackGroup] {
        var bucketed: [String: [(item: ScanItem, decision: EffectiveDecision)]] = [:]
        for pair in evaluatedItems where pair.decision.wouldAutoMove {
            bucketed[pair.decision.tagKey, default: []].append(pair)
        }

        let orderedTagKeys = config.sortedTags.map(\.key)
        let extraKeys = bucketed.keys.filter { !orderedTagKeys.contains($0) }.sorted()
        let allKeys = orderedTagKeys + extraKeys

        return allKeys.compactMap { key in
            guard let entries = bucketed[key], !entries.isEmpty else { return nil }
            let rule = tagRule(for: key)
            let title = rule?.path ?? key
            let palette = rule.map { TagPalette.forTag($0) } ?? .indigo
            let icon = rule.map { TagPalette.iconForTag($0) } ?? "folder.fill"

            var subCounts: [String: Int] = [:]
            for (_, dec) in entries where dec.shouldMove {
                let parts = dec.destinationRelPath.split(separator: "/")
                if parts.count >= 2 {
                    let subName = parts.dropFirst().joined(separator: " › ")
                    subCounts[subName, default: 0] += 1
                }
            }
            let pills = subCounts
                .map { SubfolderSummaryPill(name: $0.key, count: $0.value) }
                .sorted { a, b in
                    if a.count != b.count { return a.count > b.count }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }

            return FolderStackGroup(
                tagKey: key,
                title: title,
                icon: icon,
                palette: palette,
                entries: entries,
                subfolderPills: pills
            )
        }
        .sorted { a, b in
            if a.entries.count != b.entries.count {
                return a.entries.count > b.entries.count
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    var stayingPutEntries: [(item: ScanItem, decision: EffectiveDecision)] {
        evaluatedItems.filter { !$0.decision.wouldAutoMove }
    }

    var willMoveCount: Int {
        evaluatedItems.filter { $0.decision.shouldMove }.count
    }

    var keepingInPlaceCount: Int {
        items.count - willMoveCount
    }

    var enabledCategoryCount: Int {
        config.sortedTags.filter(\.isEnabled).count
    }

    // MARK: - Model & Engine Lifecycle

    func startModelDownload() {
        toastMessage = nil
        modelManager.startDownload()
    }

    func cancelModelDownload() {
        modelManager.cancelDownload()
    }

    func revealModelInFinder() {
        if let url = modelState.installedURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(modelManager.modelsDirectory)
        }
    }

    func unloadEngineFromMemory() {
        cancelScan()
        service.stopServer()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            engineOnline = false
            isStartingEngine = false
            showToast("Paused local AI engine to free memory.", isError: false)
        }
    }

    func shutdown() {
        scanTask?.cancel()
        healthTimerTask?.cancel()
        toastDismissTask?.cancel()
        modelManager.cancelDownload()
        service.stopServer()
    }

    private func startHealthPolling() {
        healthTimerTask?.cancel()
        healthTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let ok = await self.service.checkHealth()
                if self.engineOnline != ok {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        self.engineOnline = ok
                        if ok { self.isStartingEngine = false }
                    }
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func ensureEngineRunning() async -> Bool {
        let refreshedState = modelManager.currentInstallState()
        if !modelState.isDownloading {
            modelState = refreshedState
        }
        guard let modelURL = refreshedState.installedURL else {
            engineOnline = false
            isStartingEngine = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                stage = .setupModel
            }
            return false
        }

        if await service.checkHealth() {
            engineOnline = true
            isStartingEngine = false
            return true
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            isStartingEngine = true
        }

        do {
            try service.startEmbeddedServer(modelURL: modelURL)
        } catch {
            isStartingEngine = false
            showToast("Could not start local organizer engine: \(error.localizedDescription)", isError: true)
            return false
        }

        for _ in 0..<60 {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await service.checkHealth() {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    engineOnline = true
                    isStartingEngine = false
                }
                return true
            }
            if !service.isProcessRunning {
                break
            }
        }

        isStartingEngine = false
        showToast("Local AI engine stopped unexpectedly. Try again in a moment.", isError: true)
        return false
    }

    // MARK: - Folder Selection & Navigation

    func refreshCandidateCount() {
        guard let folderSnapshot = targetFolderURL else {
            totalTopLevelFilesInFolder = 0
            return
        }
        let topNames = Set(config.folders.values.map(\.path))
        Task { [weak self] in
            let count = await Task.detached(priority: .utility) {
                Self.collectCandidateURLs(
                    in: folderSnapshot,
                    configuredTopFolders: topNames,
                    limit: nil
                ).count
            }.value
            guard let self, self.targetFolderURL == folderSnapshot else { return }
            withAnimation(.snappy(duration: 0.24)) {
                self.totalTopLevelFilesInFolder = count
            }
        }
    }

    nonisolated static func collectCandidateURLs(
        in folderURL: URL,
        configuredTopFolders: Set<String>,
        limit: Int?
    ) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let files: [(url: URL, mtime: Date)] = entries.compactMap { url in
            let name = url.lastPathComponent
            if configuredTopFolders.contains(name) { return nil }
            let ext = url.pathExtension.lowercased()
            if Self.nonisolatedIgnoredExtensions.contains(ext) { return nil }
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  vals.isRegularFile == true else {
                return nil
            }
            return (url, vals.contentModificationDate ?? .distantPast)
        }.sorted { a, b in
            if a.mtime != b.mtime { return a.mtime > b.mtime }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }

        if let limit {
            return Array(files.prefix(limit)).map(\.url)
        }
        return files.map(\.url)
    }

    func selectFolder(_ url: URL, autoStart: Bool = false) {
        var isDir: ObjCBool = false
        let target: URL
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            target = isDir.boolValue ? url : url.deletingLastPathComponent()
        } else {
            return
        }

        cancelScan()
        withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
            targetFolderURL = target
            items = []
            inspectorTarget = nil
            if modelState.isInstalled {
                stage = .pickFolder
            }
        }

        if autoStart && modelState.isInstalled {
            startPreviewScan()
        }
    }

    func chooseFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder to Sift"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let existing = targetFolderURL {
            panel.directoryURL = existing
        }
        if panel.runModal() == .OK, let url = panel.url {
            selectFolder(url)
        }
    }

    func returnToHome() {
        cancelScan()
        withAnimation(.spring(response: 0.50, dampingFraction: 0.82)) {
            items = []
            inspectorTarget = nil
            stage = modelState.isInstalled ? .pickFolder : .setupModel
        }
        refreshCandidateCount()
    }

    // MARK: - Categories & Preferences

    func saveConfigToDisk() {
        config.costs.wrong = (wrongCost * 100.0).rounded() / 100.0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }

        let userConfigURL = appSupportDir.appendingPathComponent("siftify.config.json")
        try? data.write(to: userConfigURL, options: .atomic)
    }

    func toggleCategory(_ key: String) {
        guard var tag = config.folders[key] else { return }
        let next = !tag.isEnabled
        if !next && enabledCategoryCount <= 2 {
            showToast("Keep at least two folder categories turned on.", isError: true)
            return
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
            tag.isEnabled = next
            if var subs = tag.subfolders {
                for sk in subs.keys {
                    subs[sk]?.isEnabled = next
                }
                tag.subfolders = subs
            }
            config.folders[key] = tag
        }
        saveConfigToDisk()
    }

    func addCustomCategory(name: String, description: String, icon: String, color: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanDesc.isEmpty else { return }

        let key = Self.slugKey(from: cleanName, existing: Set(config.folders.keys))
        let rule = TagRule(
            key: key,
            path: cleanName,
            description: cleanDesc,
            enabled: true,
            icon: icon,
            color: color,
            order: config.folders.count + 10
        )
        withAnimation(.spring(response: 0.40, dampingFraction: 0.80)) {
            config.folders[key] = rule
        }
        saveConfigToDisk()
        showToast("Added “\(cleanName)” folder category.", isError: false)
    }

    func restoreDefaultCategories() {
        guard let bundled = Bundle.main.url(forResource: "siftify.config", withExtension: "json")
                ?? Bundle.main.resourceURL?.appendingPathComponent("siftify.config.json"),
              let data = try? Data(contentsOf: bundled),
              let defaults = try? JSONDecoder().decode(TidyConfig.self, from: data) else {
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            config = defaults
            carefulness = .balanced
            wrongCost = CarefulnessPreset.balanced.wrongCost
        }
        saveConfigToDisk()
        showToast("Restored default folder categories.", isError: false)
    }

    private static func slugKey(from label: String, existing: Set<String>) -> String {
        let base = label.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let stem = base.isEmpty ? "custom_folder" : String(base.prefix(28))
        if !existing.contains(stem) { return stem }
        var idx = 2
        while existing.contains("\(stem)_\(idx)") { idx += 1 }
        return "\(stem)_\(idx)"
    }

    // MARK: - Live Preview Scan

    func startPreviewScan() {
        cancelScan()
        guard modelManager.currentInstallState().isInstalled else {
            modelState = modelManager.currentInstallState()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                stage = .setupModel
            }
            return
        }

        guard let folderSnapshot = targetFolderURL else {
            chooseFolderPanel()
            return
        }

        let scopeLimit = scanScope.limit
        let cfgSnapshot = config
        let costSnapshot = wrongCost
        let topNames = Set(cfgSnapshot.folders.values.map(\.path))
        saveConfigToDisk()

        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
            items = []
            inspectorTarget = nil
            isScanning = true
            scanProgressCurrent = 0
            scanProgressTotal = max(1, totalTopLevelFilesInFolder)
            currentScanningFilename = "Preparing folder…"
            currentScanningClue = "Inspecting loose files…"
            currentScanningPath = folderSnapshot.path
            stage = .scanning
        }

        scanTask = Task { [weak self] in
            guard let self else { return }
            let urls = await Task.detached(priority: .userInitiated) {
                Self.collectCandidateURLs(
                    in: folderSnapshot,
                    configuredTopFolders: topNames,
                    limit: scopeLimit
                )
            }.value

            guard !Task.isCancelled else {
                await MainActor.run { self.isScanning = false }
                return
            }

            await MainActor.run {
                self.totalTopLevelFilesInFolder = scopeLimit == nil ? urls.count : max(self.totalTopLevelFilesInFolder, urls.count)
                self.scanProgressTotal = max(1, urls.count)
            }

            guard !urls.isEmpty else {
                await MainActor.run {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                        self.isScanning = false
                        self.stage = .pickFolder
                    }
                    self.showToast("\(folderSnapshot.lastPathComponent) is already organized — no loose files found!", isError: false)
                }
                return
            }

            let ready = await self.ensureEngineRunning()
            guard ready, !Task.isCancelled else {
                await MainActor.run {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                        self.isScanning = false
                        self.stage = .pickFolder
                    }
                }
                return
            }

            for (idx, fileURL) in urls.enumerated() {
                if Task.isCancelled { break }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        self.currentScanningFilename = fileURL.lastPathComponent
                        self.currentScanningPath = fileURL.path
                        self.currentScanningClue = "Looking inside file locally…"
                    }
                }

                let path = fileURL.path
                let xray = await Task.detached(priority: .userInitiated) {
                    FileXRayExtractor.inspect(path: path)
                }.value

                if Task.isCancelled { break }

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.currentScanningClue = xray.friendlyClueDescription
                    }
                }

                do {
                    let result = try await self.service.classifyFile(
                        xray: xray,
                        config: cfgSnapshot,
                        wrongCost: costSnapshot
                    )
                    if Task.isCancelled { break }
                    await MainActor.run {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                            self.items.append(result)
                            self.scanProgressCurrent = idx + 1
                        }
                    }
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        break
                    }
                    await MainActor.run {
                        self.showToast("Stopped while reading \(fileURL.lastPathComponent): \(error.localizedDescription)", isError: true)
                    }
                    break
                }
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isScanning = false }
                return
            }

            try? await Task.sleep(nanoseconds: 220_000_000)

            await MainActor.run {
                withAnimation(.spring(response: 0.54, dampingFraction: 0.82)) {
                    self.isScanning = false
                    self.currentScanningFilename = ""
                    self.currentScanningClue = ""
                    self.stage = self.items.isEmpty ? .pickFolder : .review
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning {
            isScanning = false
            currentScanningFilename = ""
            currentScanningClue = ""
            if items.isEmpty {
                stage = modelState.isInstalled ? .pickFolder : .setupModel
            } else {
                stage = .review
            }
        }
    }

    // MARK: - Stack & Per-File Overrides

    func toggleGroupSelection(_ tagKey: String) {
        guard let group = folderStacks.first(where: { $0.tagKey == tagKey }) else { return }
        let targetInclude = !group.isAllSelected
        let ids = Set(group.entries.map { $0.item.id })
        withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
            for idx in items.indices where ids.contains(items[idx].id) {
                items[idx].manualIncludeOverride = targetInclude
            }
        }
    }

    func toggleItemMove(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let dec = items[idx].evaluate(config: config, wrongCost: wrongCost)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
            items[idx].manualIncludeOverride = !dec.shouldMove
        }
    }

    func setManualDestination(itemID: String, relPath: String?, tagKey: String?) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            items[idx].manualDestinationRelPath = relPath
            items[idx].manualTagKey = tagKey
            if relPath == "__leave__" {
                items[idx].manualIncludeOverride = false
            } else if relPath != nil {
                items[idx].manualIncludeOverride = true
            } else {
                items[idx].manualIncludeOverride = nil
            }
        }
    }

    // MARK: - Organize & Undo

    func organizeSelectedFiles() {
        guard let folderURL = targetFolderURL else { return }
        let fm = FileManager.default
        let pairsToMove = evaluatedItems.filter { $0.decision.shouldMove }
        guard !pairsToMove.isEmpty else { return }

        var moveRecords: [MoveRecord] = []
        var countsByPath: [String: (tagKey: String, count: Int)] = [:]

        for (item, dec) in pairsToMove {
            let srcURL = URL(fileURLWithPath: item.xray.path)
            guard fm.fileExists(atPath: srcURL.path) else { continue }
            let destDir = folderURL.appendingPathComponent(dec.destinationRelPath, isDirectory: true)
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destURL = Self.uniqueDestinationURL(in: destDir, filename: item.xray.filename)
            do {
                try fm.moveItem(at: srcURL, to: destURL)
                let keyCombo = dec.subtagKey.map { "\(dec.tagKey)/\($0)" } ?? dec.tagKey
                moveRecords.append(
                    MoveRecord(
                        from: srcURL.path,
                        to: destURL.path,
                        folderKey: keyCombo,
                        folderPath: dec.destinationRelPath,
                        confidence: dec.confidence
                    )
                )
                let prev = countsByPath[dec.destinationRelPath]?.count ?? 0
                countsByPath[dec.destinationRelPath] = (dec.tagKey, prev + 1)
            } catch {
                showToast("Could not move \(item.xray.filename): \(error.localizedDescription)", isError: true)
            }
        }

        guard !moveRecords.isEmpty else { return }

        let historyDir = historyDirectoryURL
        try? fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter().string(from: Date())
        let batch = UndoBatch(timestamp: iso, targetDir: folderURL.path, moves: moveRecords)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(batch) {
            try? data.write(to: historyDir.appendingPathComponent("latest.json"), options: .atomic)
            let ts = Int(Date().timeIntervalSince1970 * 1000)
            try? data.write(to: historyDir.appendingPathComponent("run-\(ts).json"), options: .atomic)
        }

        let organizedFolders = countsByPath.map { relPath, info in
            OrganizedFolderCount(
                relPath: relPath,
                tagKey: info.tagKey,
                count: info.count,
                folderURL: folderURL.appendingPathComponent(relPath, isDirectory: true)
            )
        }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.relPath.localizedStandardCompare(b.relPath) == .orderedAscending
        }

        let summary = CompletionSummary(
            movedCount: moveRecords.count,
            untouchedCount: max(0, items.count - moveRecords.count),
            rootFolderName: folderURL.lastPathComponent,
            rootFolderURL: folderURL,
            folders: organizedFolders
        )

        withAnimation(.spring(response: 0.56, dampingFraction: 0.80)) {
            inspectorTarget = nil
            items = []
            lastUndoBatch = batch
            stage = .completed(summary)
        }
        refreshCandidateCount()
    }

    func undoLastSift() {
        loadUndoHistory()
        guard let batch = lastUndoBatch else {
            showToast("Nothing recent to undo.", isError: true)
            return
        }
        let fm = FileManager.default
        var restored = 0
        var touchedDirs = Set<URL>()

        for m in batch.moves {
            let fromURL = URL(fileURLWithPath: m.from)
            let toURL = URL(fileURLWithPath: m.to)
            if fm.fileExists(atPath: toURL.path) && !fm.fileExists(atPath: fromURL.path) {
                touchedDirs.insert(toURL.deletingLastPathComponent())
                if (try? fm.moveItem(at: toURL, to: fromURL)) != nil {
                    restored += 1
                }
            }
        }

        let stopRoot = URL(fileURLWithPath: batch.targetDir).standardizedFileURL
        for dir in touchedDirs {
            Self.pruneEmptyDirsUpTo(leaf: dir, stopAt: stopRoot)
        }

        let latestURL = historyDirectoryURL.appendingPathComponent("latest.json")
        try? fm.removeItem(at: latestURL)

        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
            lastUndoBatch = nil
            if case .completed = stage {
                stage = .pickFolder
            }
        }
        refreshCandidateCount()
        showToast("Put \(restored) file\(restored == 1 ? "" : "s") right back in \(stopRoot.lastPathComponent).", isError: false)
    }

    func loadUndoHistory() {
        let latestURL = historyDirectoryURL.appendingPathComponent("latest.json")
        if let data = try? Data(contentsOf: latestURL),
           let batch = try? JSONDecoder().decode(UndoBatch.self, from: data),
           !batch.moves.isEmpty {
            lastUndoBatch = batch
        } else {
            lastUndoBatch = nil
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func showToast(_ message: String, isError: Bool) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            toastMessage = message
            toastIsError = isError
        }
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toastMessage = nil
            }
        }
    }

    private static func uniqueDestinationURL(in dir: URL, filename: String) -> URL {
        let fm = FileManager.default
        let ns = filename as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var candidate = dir.appendingPathComponent(filename)
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            candidate = dir.appendingPathComponent(nextName)
            counter += 1
        }
        return candidate
    }

    private static func pruneEmptyDirsUpTo(leaf: URL, stopAt: URL) {
        let fm = FileManager.default
        var cur = leaf.standardizedFileURL
        while cur.path != stopAt.path && cur.path.hasPrefix(stopAt.path + "/") {
            if let contents = try? fm.contentsOfDirectory(atPath: cur.path), contents.isEmpty {
                try? fm.removeItem(at: cur)
                cur = cur.deletingLastPathComponent()
            } else {
                break
            }
        }
    }
}
