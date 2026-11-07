import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TidyStore {
    let appSupportDir: URL
    let workspaceRoot: URL?
    var config: TidyConfig
    var targetFolderURL: URL {
        didSet {
            refreshCandidateCount()
        }
    }
    var scanScope: ScanScope = .latest40
    var wrongCost: Double = 2.2

    var modelState: ModelInstallState = .notInstalled
    var engineOnline: Bool = false
    var isStartingEngine: Bool = false

    var isScanning: Bool = false
    var scanProgressCurrent: Int = 0
    var scanProgressTotal: Int = 0
    var currentScanningFilename: String = ""
    var totalTopLevelFilesInFolder: Int = 0

    var items: [ScanItem] = []
    var selectedItemID: String? = nil
    var filterMode: ResultFilterMode = .all
    var searchQuery: String = ""
    var expandedTagKeys: Set<String> = ["documents_notes"]

    var needsRescanForPromptChanges: Bool = false
    var lastUndoBatch: UndoBatch? = nil
    var bannerMessage: String? = nil
    var bannerIsError: Bool = false

    private let service = ClassifierService()
    private let modelManager: ModelManager
    private var scanTask: Task<Void, Never>? = nil
    private var healthTimerTask: Task<Void, Never>? = nil

    nonisolated private static let nonisolatedIgnoredExtensions: Set<String> = ["crdownload", "part", "download", "tmp"]

    init() {
        let fm = FileManager.default
        let supportBase = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let support = supportBase.appendingPathComponent("Siftify", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        self.appSupportDir = support

        let wsRoot = Self.detectWorkspaceRoot()
        self.workspaceRoot = wsRoot

        let loadedConfig = Self.loadInitialConfig(appSupportDir: support, workspaceRoot: wsRoot)
        self.config = loadedConfig
        self.wrongCost = loadedConfig.costs.wrong

        let manager = ModelManager(appSupportDirectory: support)
        self.modelManager = manager
        self.modelState = manager.currentInstallState()

        if ProcessInfo.processInfo.environment["SIFTIFY_DEMO_START"] == "1",
           let demo = wsRoot?.appendingPathComponent("demo-inbox"),
           fm.fileExists(atPath: demo.path) {
            self.targetFolderURL = demo
        } else {
            self.targetFolderURL = fm.homeDirectoryForCurrentUser
        }

        manager.onStateChange = { [weak self] nextState in
            guard let self else { return }
            let wasDownloading = self.modelState.isDownloading
            withAnimation(.snappy(duration: 0.22)) {
                self.modelState = nextState
            }
            if wasDownloading, case .installed = nextState {
                self.showBanner("Downloaded local Q8_0 model. Loading onto Apple Silicon Metal GPU…", isError: false)
                Task {
                    _ = await self.ensureEngineRunning()
                }
            }
        }

        loadUndoHistory()
        refreshCandidateCount()
        startHealthPolling()

        if modelState.isInstalled {
            Task {
                _ = await self.ensureEngineRunning()
            }
        }
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
        let supportConfigURL = appSupportDir.appendingPathComponent("siftify.config.json")

        var candidates: [URL] = []
        if let ws = workspaceRoot {
            candidates.append(ws.appendingPathComponent("siftify.config.json"))
        }
        candidates.append(supportConfigURL)
        if let bundled = Bundle.main.url(forResource: "siftify.config", withExtension: "json") {
            candidates.append(bundled)
        }
        if let resDir = Bundle.main.resourceURL {
            candidates.append(resDir.appendingPathComponent("siftify.config.json"))
        }

        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(TidyConfig.self, from: data) {
                if !fm.fileExists(atPath: supportConfigURL.path) {
                    try? data.write(to: supportConfigURL, options: .atomic)
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
        if let ws = workspaceRoot {
            return ws.appendingPathComponent(".siftify-history", isDirectory: true)
        }
        return appSupportDir.appendingPathComponent("pro-history", isDirectory: true)
    }

    var demoInboxURL: URL? {
        guard let ws = workspaceRoot else { return nil }
        let url = ws.appendingPathComponent("demo-inbox", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var impliedThresholdPercent: Int {
        let pct = max(0.0, (1.0 - config.costs.deferCost / max(1.05, wrongCost)) * 100.0)
        return Int(pct.rounded())
    }

    var activeLeafCount: Int {
        config.sortedTags.reduce(0) { $0 + $1.activeSubtagCount }
    }

    var selectedItem: ScanItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.id == id }
    }

    var evaluatedItems: [(item: ScanItem, decision: EffectiveDecision)] {
        items.map { ($0, $0.evaluate(config: config, wrongCost: wrongCost)) }
    }

    var filteredItems: [(item: ScanItem, decision: EffectiveDecision)] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return evaluatedItems.filter { pair in
            if !q.isEmpty {
                let hay = "\(pair.item.xray.filename) \(pair.decision.destinationRelPath)".lowercased()
                if !hay.contains(q) { return false }
            }
            switch filterMode {
            case .all:
                return true
            case .willMove:
                return pair.decision.shouldMove
            case .untouched:
                return !pair.decision.shouldMove
            case .byTag(let relPath):
                return pair.decision.shouldMove && pair.decision.destinationRelPath == relPath
            }
        }
    }

    var willMoveCount: Int {
        evaluatedItems.filter { $0.decision.shouldMove }.count
    }

    var untouchedCount: Int {
        items.count - willMoveCount
    }

    var averageLatencyMs: Int {
        guard !items.isEmpty else { return 0 }
        let sum = items.reduce(0) { $0 + $1.elapsedMs }
        return sum / items.count
    }

    var destinationSummaryCounts: [(relPath: String, tagKey: String, count: Int)] {
        var counts: [String: (tagKey: String, count: Int)] = [:]
        for (_, dec) in evaluatedItems where dec.shouldMove {
            let prev = counts[dec.destinationRelPath]?.count ?? 0
            counts[dec.destinationRelPath] = (dec.tagKey, prev + 1)
        }
        return counts.map { (relPath: $0.key, tagKey: $0.value.tagKey, count: $0.value.count) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.relPath.localizedStandardCompare(b.relPath) == .orderedAscending
            }
    }

    // MARK: - Model Download & Metal Engine Lifecycle

    func startModelDownload() {
        bannerMessage = nil
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
        cancelDryRun()
        service.stopServer()
        withAnimation(.snappy) {
            engineOnline = false
            isStartingEngine = false
            showBanner("Unloaded Q8_0 model from unified memory.", isError: false)
        }
    }

    func restartEngine() {
        cancelDryRun()
        service.stopServer()
        engineOnline = false
        Task {
            _ = await ensureEngineRunning()
        }
    }

    func deleteDownloadedModel() {
        cancelDryRun()
        service.stopServer()
        do {
            try modelManager.deleteInstalledModel()
            withAnimation(.snappy) {
                engineOnline = false
                isStartingEngine = false
                modelState = modelManager.currentInstallState()
                showBanner("Removed downloaded Q8_0 model from disk (1.70 GB freed).", isError: false)
            }
        } catch {
            showBanner("Could not remove model file: \(error.localizedDescription)", isError: true)
        }
    }

    func shutdown() {
        scanTask?.cancel()
        healthTimerTask?.cancel()
        modelManager.cancelDownload()
        service.stopServer()
    }

    func startHealthPolling() {
        healthTimerTask?.cancel()
        healthTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let ok = await self.service.checkHealth()
                if self.engineOnline != ok {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
            return false
        }

        if await service.checkHealth() {
            engineOnline = true
            isStartingEngine = false
            return true
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isStartingEngine = true
        }

        do {
            try service.startEmbeddedServer(modelURL: modelURL)
        } catch {
            isStartingEngine = false
            showBanner("Could not start embedded Metal engine: \(error.localizedDescription)", isError: true)
            return false
        }

        for _ in 0..<60 {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await service.checkHealth() {
                withAnimation(.snappy) {
                    engineOnline = true
                    isStartingEngine = false
                    if bannerMessage?.contains("Loading onto Apple Silicon Metal") == true {
                        bannerMessage = nil
                    }
                }
                return true
            }
            if !service.isProcessRunning {
                break
            }
        }

        isStartingEngine = false
        let details = service.recentStderr
        let suffix = details.isEmpty ? "" : " (\(details.suffix(180)))"
        showBanner("Metal inference engine exited before becoming ready.\(suffix)", isError: true)
        return false
    }

    // MARK: - Folder Selection

    func refreshCandidateCount() {
        let folderSnapshot = targetFolderURL
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
            self.totalTopLevelFilesInFolder = count
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

    func selectFolder(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        cancelDryRun()
        withAnimation(.snappy(duration: 0.22)) {
            targetFolderURL = url
            items = []
            selectedItemID = nil
            filterMode = .all
            bannerMessage = nil
        }
    }

    func chooseFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder to Organize"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = targetFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            selectFolder(url)
        }
    }

    // MARK: - Tags & Subtags Management

    func saveConfigToDisk() {
        config.costs.wrong = (wrongCost * 10.0).rounded() / 10.0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }

        let supportConfigURL = appSupportDir.appendingPathComponent("siftify.config.json")
        try? data.write(to: supportConfigURL, options: .atomic)

        if let ws = workspaceRoot {
            let repoConfigURL = ws.appendingPathComponent("siftify.config.json")
            try? data.write(to: repoConfigURL, options: .atomic)
        }
    }

    func resetDefaultCategories() {
        guard let bundled = Bundle.main.url(forResource: "siftify.config", withExtension: "json")
                ?? Bundle.main.resourceURL?.appendingPathComponent("siftify.config.json"),
              let data = try? Data(contentsOf: bundled),
              let defaults = try? JSONDecoder().decode(TidyConfig.self, from: data) else {
            return
        }
        withAnimation(.snappy) {
            config = defaults
            wrongCost = defaults.costs.wrong
            if !items.isEmpty { needsRescanForPromptChanges = true }
            showBanner("Restored default categories and Document subtags.", isError: false)
        }
        saveConfigToDisk()
    }

    func toggleTag(_ key: String) {
        guard var tag = config.folders[key] else { return }
        let next = !tag.isEnabled
        withAnimation(.snappy(duration: 0.2)) {
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

    func toggleSubtag(parentKey: String, subKey: String) {
        guard var parent = config.folders[parentKey],
              var subs = parent.subfolders,
              var sub = subs[subKey] else { return }
        let next = !sub.isEnabled
        withAnimation(.snappy(duration: 0.2)) {
            sub.isEnabled = next
            subs[subKey] = sub
            parent.subfolders = subs
            if next {
                parent.isEnabled = true
            } else if subs.values.allSatisfy({ !$0.isEnabled }) {
                parent.isEnabled = false
            }
            config.folders[parentKey] = parent
        }
        saveConfigToDisk()
    }

    func setAllTags(enabled: Bool) {
        withAnimation(.snappy(duration: 0.22)) {
            for key in Array(config.folders.keys) {
                config.folders[key]?.isEnabled = enabled
                if var subs = config.folders[key]?.subfolders {
                    for sk in subs.keys {
                        subs[sk]?.isEnabled = enabled
                    }
                    config.folders[key]?.subfolders = subs
                }
            }
        }
        saveConfigToDisk()
    }

    func upsertTag(
        existingKey: String?,
        name: String,
        description: String,
        icon: String,
        color: String
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanDesc.isEmpty else { return }

        let key = existingKey ?? Self.slugKey(from: cleanName, existing: Set(config.folders.keys))
        var rule = config.folders[key] ?? TagRule(
            key: key,
            path: cleanName,
            description: cleanDesc,
            enabled: true,
            icon: icon,
            color: color,
            order: config.folders.count + 10
        )
        rule.path = cleanName
        rule.description = cleanDesc
        rule.icon = icon
        rule.color = color
        if existingKey == nil { rule.enabled = true }

        withAnimation(.snappy) {
            config.folders[key] = rule
            if !items.isEmpty { needsRescanForPromptChanges = true }
        }
        saveConfigToDisk()
    }

    func deleteTag(key: String) {
        guard config.folders.count > 2 else {
            showBanner("At least two categories are required for classification.", isError: true)
            return
        }
        withAnimation(.snappy) {
            config.folders.removeValue(forKey: key)
            if !items.isEmpty { needsRescanForPromptChanges = true }
        }
        saveConfigToDisk()
    }

    func upsertSubtag(
        parentKey: String,
        existingSubKey: String?,
        name: String,
        description: String
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanDesc.isEmpty, var parent = config.folders[parentKey] else { return }

        var subs = parent.subfolders ?? [:]
        let subKey = existingSubKey ?? Self.slugKey(from: cleanName, existing: Set(subs.keys))
        var sub = subs[subKey] ?? SubtagRule(
            key: subKey,
            path: cleanName,
            description: cleanDesc,
            enabled: true,
            order: subs.count + 1
        )
        sub.path = cleanName
        sub.description = cleanDesc
        if existingSubKey == nil { sub.enabled = true }
        subs[subKey] = sub
        parent.subfolders = subs
        parent.isEnabled = true
        if parent.subCostWrong == nil { parent.subCostWrong = 1.8 }

        withAnimation(.snappy) {
            config.folders[parentKey] = parent
            expandedTagKeys.insert(parentKey)
            if !items.isEmpty { needsRescanForPromptChanges = true }
        }
        saveConfigToDisk()
    }

    func deleteSubtag(parentKey: String, subKey: String) {
        guard var parent = config.folders[parentKey], var subs = parent.subfolders else { return }
        subs.removeValue(forKey: subKey)
        parent.subfolders = subs.isEmpty ? nil : subs
        withAnimation(.snappy) {
            config.folders[parentKey] = parent
            if !items.isEmpty { needsRescanForPromptChanges = true }
        }
        saveConfigToDisk()
    }

    private static func slugKey(from label: String, existing: Set<String>) -> String {
        let base = label.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let stem = base.isEmpty ? "custom_tag" : String(base.prefix(28))
        if !existing.contains(stem) { return stem }
        var idx = 2
        while existing.contains("\(stem)_\(idx)") { idx += 1 }
        return "\(stem)_\(idx)"
    }

    // MARK: - Dry-Run Execution

    func startDryRun() {
        cancelDryRun()
        guard modelManager.currentInstallState().isInstalled else {
            modelState = modelManager.currentInstallState()
            showBanner("Download the local Q8_0 model first to run offline classification.", isError: true)
            return
        }

        let folderSnapshot = targetFolderURL
        let scopeLimit = scanScope.limit
        let cfgSnapshot = config
        let costSnapshot = wrongCost
        let topNames = Set(cfgSnapshot.folders.values.map(\.path))
        saveConfigToDisk()

        withAnimation(.snappy(duration: 0.2)) {
            items = []
            selectedItemID = nil
            filterMode = .all
            isScanning = true
            scanProgressCurrent = 0
            scanProgressTotal = max(1, totalTopLevelFilesInFolder)
            needsRescanForPromptChanges = false
            bannerMessage = nil
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
                self.scanProgressTotal = urls.count
            }

            guard !urls.isEmpty else {
                await MainActor.run {
                    self.isScanning = false
                    self.showBanner("No top-level files found in \(folderSnapshot.lastPathComponent).", isError: false)
                }
                return
            }

            let ready = await self.ensureEngineRunning()
            guard ready, !Task.isCancelled else {
                await MainActor.run { self.isScanning = false }
                return
            }

            for (idx, fileURL) in urls.enumerated() {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.currentScanningFilename = fileURL.lastPathComponent
                }

                let path = fileURL.path
                let xray = await Task.detached(priority: .userInitiated) {
                    FileXRayExtractor.inspect(path: path)
                }.value

                if Task.isCancelled { break }

                do {
                    let result = try await self.service.classifyFile(
                        xray: xray,
                        config: cfgSnapshot,
                        wrongCost: costSnapshot
                    )
                    if Task.isCancelled { break }
                    await MainActor.run {
                        withAnimation(.snappy(duration: 0.24)) {
                            self.items.append(result)
                            self.scanProgressCurrent = idx + 1
                            if self.selectedItemID == nil {
                                self.selectedItemID = result.id
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.showBanner("Classification error on \(fileURL.lastPathComponent): \(error.localizedDescription)", isError: true)
                    }
                    break
                }
            }

            await MainActor.run {
                withAnimation(.snappy) {
                    self.isScanning = false
                    self.currentScanningFilename = ""
                }
            }
        }
    }

    func cancelDryRun() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        currentScanningFilename = ""
    }

    // MARK: - Per-File Overrides & Apply / Undo

    func toggleItemMove(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let currentDec = items[idx].evaluate(config: config, wrongCost: wrongCost)
        withAnimation(.snappy(duration: 0.18)) {
            items[idx].manualIncludeOverride = !currentDec.shouldMove
        }
    }

    func setManualDestination(itemID: String, relPath: String?, tagKey: String?) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        withAnimation(.snappy(duration: 0.18)) {
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

    func applyMoves() {
        let fm = FileManager.default
        let pairsToMove = evaluatedItems.filter { $0.decision.shouldMove }
        guard !pairsToMove.isEmpty else { return }

        var moveRecords: [MoveRecord] = []
        var movedIDs: Set<String> = []

        for (item, dec) in pairsToMove {
            let srcURL = URL(fileURLWithPath: item.xray.path)
            guard fm.fileExists(atPath: srcURL.path) else { continue }
            let destDir = targetFolderURL.appendingPathComponent(dec.destinationRelPath, isDirectory: true)
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
                movedIDs.insert(item.id)
            } catch {
                showBanner("Failed moving \(item.xray.filename): \(error.localizedDescription)", isError: true)
            }
        }

        guard !moveRecords.isEmpty else { return }

        let historyDir = historyDirectoryURL
        try? fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter().string(from: Date())
        let batch = UndoBatch(timestamp: iso, targetDir: targetFolderURL.path, moves: moveRecords)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(batch) {
            try? data.write(to: historyDir.appendingPathComponent("latest.json"), options: .atomic)
            let ts = Int(Date().timeIntervalSince1970 * 1000)
            try? data.write(to: historyDir.appendingPathComponent("run-\(ts).json"), options: .atomic)
        }

        withAnimation(.snappy(duration: 0.28)) {
            items.removeAll { movedIDs.contains($0.id) }
            if let sel = selectedItemID, movedIDs.contains(sel) {
                selectedItemID = items.first?.id
            }
            lastUndoBatch = batch
            filterMode = .all
            refreshCandidateCount()
            showBanner("Moved \(moveRecords.count) file\(moveRecords.count == 1 ? "" : "s") into organized folders.", isError: false)
        }
    }

    func undoLastBatch() {
        loadUndoHistory()
        guard let batch = lastUndoBatch else {
            showBanner("No recent move batch found to undo.", isError: true)
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

        withAnimation(.snappy(duration: 0.25)) {
            lastUndoBatch = nil
            refreshCandidateCount()
            showBanner("Restored \(restored) of \(batch.moves.count) file\(batch.moves.count == 1 ? "" : "s") back to \(stopRoot.lastPathComponent).", isError: false)
        }
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
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    func showBanner(_ text: String, isError: Bool) {
        withAnimation(.snappy) {
            bannerMessage = text
            bannerIsError = isError
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
