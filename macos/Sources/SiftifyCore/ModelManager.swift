import Foundation

enum ModelInstallState: Equatable {
    case notInstalled
    case downloading(downloadedBytes: Int64, totalBytes: Int64, bytesPerSec: Double)
    case failed(String)
    case installed(fileURL: URL, sizeBytes: Int64)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var installedURL: URL? {
        if case .installed(let url, _) = self { return url }
        return nil
    }
}

final class ModelManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let defaultModelName = "basal-2.0-mini-Q8_0.gguf"
    static let defaultDownloadURL = URL(
        string: "https://huggingface.co/Remek/basal-2.0-mini-GGUF/resolve/main/basal-2.0-mini-Q8_0.gguf"
    )!
    static let expectedBytes: Int64 = 1_699_567_552
    private static let minimumValidGGUFBytes: Int64 = 1_500_000_000

    let modelsDirectory: URL
    let defaultModelFileURL: URL

    var onStateChange: (@MainActor (ModelInstallState) -> Void)?

    private var session: URLSession!
    private var activeTask: URLSessionDownloadTask?
    private var resumeData: Data?

    private var lastSampleTime: CFAbsoluteTime = 0
    private var lastSampleBytes: Int64 = 0
    private var smoothedSpeed: Double = 0

    init(appSupportDirectory: URL) {
        let fm = FileManager.default
        let dir = appSupportDirectory.appendingPathComponent("models", isDirectory: true)
        self.modelsDirectory = dir
        let targetFile = dir.appendingPathComponent(Self.defaultModelName)
        self.defaultModelFileURL = targetFile
        super.init()

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Zero-cost APFS clone migration if model was previously downloaded under BasalTidy
        if !fm.fileExists(atPath: targetFile.path) {
            let legacyFile = appSupportDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("BasalTidy/models/\(Self.defaultModelName)")
            if Self.validGGUFSize(at: legacyFile, minBytes: Self.minimumValidGGUFBytes) != nil {
                try? fm.copyItem(at: legacyFile, to: targetFile)
            }
        }

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 7200
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func currentInstallState() -> ModelInstallState {
        let envModel = ProcessInfo.processInfo.environment["SIFTIFY_MODEL_PATH"]
            ?? ProcessInfo.processInfo.environment["BASAL_MODEL_PATH"]
        if let envPath = envModel, !envPath.isEmpty {
            let envURL = URL(fileURLWithPath: envPath)
            if let size = Self.validGGUFSize(at: envURL, minBytes: 50_000_000) {
                return .installed(fileURL: envURL, sizeBytes: size)
            }
        }
        if let size = Self.validGGUFSize(at: defaultModelFileURL, minBytes: Self.minimumValidGGUFBytes) {
            return .installed(fileURL: defaultModelFileURL, sizeBytes: size)
        }
        return .notInstalled
    }

    static func validGGUFSize(at url: URL, minBytes: Int64) -> Int64? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              size >= minBytes,
              let fh = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fh.close() }
        guard let magic = try? fh.read(upToCount: 4),
              magic == Data([0x47, 0x47, 0x55, 0x46]) else { // "GGUF"
            return nil
        }
        return size
    }

    func startDownload() {
        if activeTask != nil { return }
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        lastSampleTime = CFAbsoluteTimeGetCurrent()
        lastSampleBytes = 0
        smoothedSpeed = 0

        let task: URLSessionDownloadTask
        if let resume = resumeData {
            task = session.downloadTask(withResumeData: resume)
            resumeData = nil
        } else {
            var req = URLRequest(url: Self.defaultDownloadURL)
            req.setValue("Siftify/0.4 (macOS; Apple Silicon)", forHTTPHeaderField: "User-Agent")
            task = session.downloadTask(with: req)
        }
        activeTask = task
        emit(.downloading(downloadedBytes: 0, totalBytes: Self.expectedBytes, bytesPerSec: 0))
        task.resume()
    }

    func cancelDownload() {
        guard let task = activeTask else { return }
        activeTask = nil
        task.cancel { [weak self] data in
            self?.resumeData = data
        }
        emit(currentInstallState())
    }

    func deleteInstalledModel() throws {
        cancelDownload()
        resumeData = nil
        let fm = FileManager.default
        if fm.fileExists(atPath: defaultModelFileURL.path) {
            try fm.removeItem(at: defaultModelFileURL)
        }
        emit(currentInstallState())
    }

    private func emit(_ state: ModelInstallState) {
        let cb = onStateChange
        Task { @MainActor in
            cb?(state)
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = now - lastSampleTime
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Self.expectedBytes

        if lastSampleBytes == 0 {
            lastSampleBytes = totalBytesWritten
            lastSampleTime = now
            emit(.downloading(downloadedBytes: totalBytesWritten, totalBytes: total, bytesPerSec: 0))
            return
        }

        guard dt >= 0.12 || totalBytesWritten >= total else { return }

        let deltaBytes = max(0, totalBytesWritten - lastSampleBytes)
        let instantSpeed = dt > 0 ? Double(deltaBytes) / dt : 0
        if smoothedSpeed <= 0 {
            smoothedSpeed = instantSpeed
        } else {
            smoothedSpeed = 0.28 * instantSpeed + 0.72 * smoothedSpeed
        }

        lastSampleTime = now
        lastSampleBytes = totalBytesWritten

        emit(.downloading(
            downloadedBytes: totalBytesWritten,
            totalBytes: total,
            bytesPerSec: smoothedSpeed
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        activeTask = nil
        resumeData = nil

        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            emit(.failed("Download failed with HTTP \(http.statusCode) from Hugging Face."))
            return
        }

        guard let validSize = Self.validGGUFSize(at: location, minBytes: Self.minimumValidGGUFBytes) else {
            emit(.failed("Downloaded file did not pass GGUF integrity check."))
            return
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            let stagingURL = modelsDirectory.appendingPathComponent("\(Self.defaultModelName).part")
            if fm.fileExists(atPath: stagingURL.path) {
                try? fm.removeItem(at: stagingURL)
            }
            try fm.moveItem(at: location, to: stagingURL)
            if fm.fileExists(atPath: defaultModelFileURL.path) {
                _ = try fm.replaceItemAt(defaultModelFileURL, withItemAt: stagingURL)
            } else {
                try fm.moveItem(at: stagingURL, to: defaultModelFileURL)
            }
            emit(.installed(fileURL: defaultModelFileURL, sizeBytes: validSize))
        } catch {
            emit(.failed("Could not save model file: \(error.localizedDescription)"))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        activeTask = nil
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            if let data = nsErr.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                resumeData = data
            }
            emit(currentInstallState())
            return
        }
        if let data = nsErr.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resumeData = data
        }
        emit(.failed(error.localizedDescription))
    }
}
