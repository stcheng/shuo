import CryptoKit
import Foundation

enum LocalWhisperAssetInstallerError: LocalizedError, Equatable {
    case homebrewNotFound
    case processFailed(command: String, statusCode: Int32, output: String)
    case installedExecutableNotFound(String)
    case invalidDownloadResponse(String)
    case invalidModelFile(filename: String, reason: String)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .homebrewNotFound:
            return "Homebrew was not found."
        case .processFailed(let command, let statusCode, let output):
            return "\(command) failed (\(statusCode)): \(output)"
        case .installedExecutableNotFound(let output):
            return "whisper.cpp installed, but whisper-cli was not found. \(output)"
        case .invalidDownloadResponse(let message):
            return "Model download failed: \(message)"
        case .invalidModelFile(let filename, let reason):
            return "The downloaded model \(filename) failed integrity validation: \(reason)"
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
            return "Not enough free space for the model download (requires \(requiredBytes) bytes, \(availableBytes) bytes available)."
        }
    }
}

struct LocalWhisperDownloadProgress: Equatable, Sendable {
    let receivedByteCount: Int64
    let totalByteCount: Int64

    var fractionCompleted: Double {
        guard totalByteCount > 0 else {
            return 0
        }
        return min(max(Double(receivedByteCount) / Double(totalByteCount), 0), 1)
    }
}

enum LocalWhisperDiskSpace {
    static let minimumReserveByteCount: Int64 = 64 * 1_024 * 1_024

    static func requiredByteCount(forDownloadByteCount downloadByteCount: Int64) -> Int64 {
        downloadByteCount + max(minimumReserveByteCount, downloadByteCount / 10)
    }

    static func availableByteCount(at url: URL) throws -> Int64? {
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        return values.volumeAvailableCapacity.map(Int64.init)
    }
}

enum LocalWhisperBackupPolicy {
    private struct ManagedAsset {
        let filename: String
        let expectedByteCount: Int64
    }

    // These models were offered by earlier Shuo builds. They are still
    // reproducible downloads, but are intentionally not shown in the current
    // catalog. Keeping their exact sizes here lets existing installations opt
    // them out of backup without treating arbitrary custom .bin files as cache.
    private static let legacyManagedAssets = [
        ManagedAsset(
            filename: "ggml-base.bin",
            expectedByteCount: 147_951_465
        ),
        ManagedAsset(
            filename: "ggml-base.en.bin",
            expectedByteCount: 147_964_211
        ),
        ManagedAsset(
            filename: "ggml-base.en-q5_1.bin",
            expectedByteCount: 59_721_011
        ),
        ManagedAsset(
            filename: "ggml-small.en.bin",
            expectedByteCount: 487_614_201
        ),
        ManagedAsset(
            filename: "ggml-small-q5_1.bin",
            expectedByteCount: 190_085_487
        ),
        ManagedAsset(
            filename: "ggml-medium.bin",
            expectedByteCount: 1_533_763_059
        ),
        ManagedAsset(
            filename: "ggml-medium-q5_0.bin",
            expectedByteCount: 539_212_467
        ),
        ManagedAsset(
            filename: "ggml-large-v3-turbo-q8_0.bin",
            expectedByteCount: 874_188_075
        )
    ]

    private static var managedAssets: [ManagedAsset] {
        LocalWhisperModelCatalog.managedModels.flatMap { model in
            [
                ManagedAsset(
                    filename: model.filename,
                    expectedByteCount: model.expectedByteCount
                )
            ] + model.supportingAssets.map {
                ManagedAsset(
                    filename: $0.filename,
                    expectedByteCount: $0.expectedByteCount
                )
            }
        } + legacyManagedAssets
    }

    static func excludeManagedModel(at url: URL) throws {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }

    static func applyToInstalledManagedModels(
        in directoryPath: String,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = LocalWhisperModelCatalog.directoryURL(for: directoryPath)
        for asset in managedAssets {
            let modelURL = directoryURL.appendingPathComponent(asset.filename)
            guard let attributes = try? fileManager.attributesOfItem(atPath: modelURL.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value == asset.expectedByteCount else {
                continue
            }
            try excludeManagedModel(at: modelURL)
        }
    }

    static func isManagedAsset(filename: String, byteCount: Int64) -> Bool {
        managedAssets.contains {
            $0.filename == filename && $0.expectedByteCount == byteCount
        }
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        return values?.isExcludedFromBackup == true
    }
}

struct LocalWhisperAssetInstaller {
    private struct DownloadableModelAsset {
        let filename: String
        let downloadURL: URL
        let expectedByteCount: Int64
        let expectedSHA256: String
        let destinationURL: URL

        func hasExpectedFileSize(fileManager: FileManager = .default) -> Bool {
            guard let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
                  let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value == expectedByteCount
        }
    }

    static func installEngineWithHomebrew() async throws -> URL {
        if let executableURL = LocalWhisperExecutableResolver.resolvedExecutableURL(configuredPath: "") {
            return executableURL
        }

        guard let brewURL = homebrewURL() else {
            throw LocalWhisperAssetInstallerError.homebrewNotFound
        }

        do {
            _ = try await runProcess(
                executableURL: brewURL,
                arguments: ["install", "whisper-cpp"],
                commandName: "brew install whisper-cpp"
            )
        } catch {
            if let executableURL = LocalWhisperExecutableResolver.resolvedExecutableURL(configuredPath: "") {
                return executableURL
            }
            throw error
        }

        if let executableURL = LocalWhisperExecutableResolver.resolvedExecutableURL(configuredPath: "") {
            return executableURL
        }

        throw LocalWhisperAssetInstallerError.installedExecutableNotFound("")
    }

    static func downloadModel(
        _ model: LocalWhisperManagedModel,
        to directoryPath: String,
        progress: @escaping @Sendable (LocalWhisperDownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let directoryURL = LocalWhisperModelCatalog.directoryURL(for: directoryPath)
        let destinationURL = model.destinationURL(in: directoryURL.path)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let assets = [
            DownloadableModelAsset(
                filename: model.filename,
                downloadURL: model.downloadURL,
                expectedByteCount: model.expectedByteCount,
                expectedSHA256: model.expectedSHA256,
                destinationURL: destinationURL
            )
        ] + model.supportingAssets.map {
            DownloadableModelAsset(
                filename: $0.filename,
                downloadURL: $0.downloadURL,
                expectedByteCount: $0.expectedByteCount,
                expectedSHA256: $0.expectedSHA256,
                destinationURL: $0.destinationURL(in: directoryURL.path)
            )
        }

        let requiredByteCount = LocalWhisperDiskSpace.requiredByteCount(
            forDownloadByteCount: assets
                .filter { !$0.hasExpectedFileSize() }
                .reduce(0) { $0 + $1.expectedByteCount }
        )
        if requiredByteCount > LocalWhisperDiskSpace.minimumReserveByteCount,
           let availableByteCount = try LocalWhisperDiskSpace.availableByteCount(at: directoryURL),
           availableByteCount < requiredByteCount {
            throw LocalWhisperAssetInstallerError.insufficientDiskSpace(
                requiredBytes: requiredByteCount,
                availableBytes: availableByteCount
            )
        }

        var completedByteCount: Int64 = 0
        for asset in assets {
            try await installAsset(
                asset,
                totalByteCount: model.totalDownloadByteCount,
                completedByteCount: completedByteCount,
                progress: progress
            )
            completedByteCount += asset.expectedByteCount
        }

        return destinationURL
    }

    static func deleteModel(at modelURL: URL) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: modelURL)
    }

    private static func installAsset(
        _ asset: DownloadableModelAsset,
        totalByteCount: Int64,
        completedByteCount: Int64,
        progress: @escaping @Sendable (LocalWhisperDownloadProgress) -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: asset.destinationURL.path) {
            do {
                try await LocalWhisperModelIntegrity.validate(
                    filename: asset.filename,
                    expectedByteCount: asset.expectedByteCount,
                    expectedSHA256: asset.expectedSHA256,
                    at: asset.destinationURL
                )
                try? LocalWhisperBackupPolicy.excludeManagedModel(at: asset.destinationURL)
                progress(
                    LocalWhisperDownloadProgress(
                        receivedByteCount: completedByteCount + asset.expectedByteCount,
                        totalByteCount: totalByteCount
                    )
                )
                return
            } catch {
                try? FileManager.default.removeItem(at: asset.destinationURL)
            }
        }

        let partialURL = asset.destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(asset.filename).download")
        try? FileManager.default.removeItem(at: partialURL)

        let downloader = LocalWhisperModelDownloader()
        let (temporaryURL, response) = try await downloader.download(from: asset.downloadURL) {
            receivedByteCount in
            progress(
                LocalWhisperDownloadProgress(
                    receivedByteCount: completedByteCount + receivedByteCount,
                    totalByteCount: totalByteCount
                )
            )
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw LocalWhisperAssetInstallerError.invalidDownloadResponse(
                "HTTP \(httpResponse.statusCode)"
            )
        }

        try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
        do {
            try await LocalWhisperModelIntegrity.validate(
                filename: asset.filename,
                expectedByteCount: asset.expectedByteCount,
                expectedSHA256: asset.expectedSHA256,
                at: partialURL
            )
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }
        try FileManager.default.moveItem(at: partialURL, to: asset.destinationURL)
        try? LocalWhisperBackupPolicy.excludeManagedModel(at: asset.destinationURL)
    }

    private static func homebrewURL() -> URL? {
        [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map { URL(fileURLWithPath: $0) }
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        commandName: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    let outputPipe = Pipe()

                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardOutput = outputPipe
                    process.standardError = outputPipe

                    try process.run()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    guard process.terminationStatus == 0 else {
                        continuation.resume(
                            throwing: LocalWhisperAssetInstallerError.processFailed(
                                command: commandName,
                                statusCode: process.terminationStatus,
                                output: cleanProcessOutput(output)
                            )
                        )
                        return
                    }

                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func cleanProcessOutput(_ output: String) -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 1_000 else {
            return cleaned
        }

        return String(cleaned.prefix(1_000)) + "..."
    }
}

enum LocalWhisperModelIntegrity {
    static func validate(model: LocalWhisperManagedModel, at url: URL) async throws {
        try await validate(
            filename: model.filename,
            expectedByteCount: model.expectedByteCount,
            expectedSHA256: model.expectedSHA256,
            at: url
        )
    }

    static func validate(
        filename: String,
        expectedByteCount: Int64,
        expectedSHA256: String,
        at url: URL
    ) async throws {

        let validationTask = Task.detached(priority: .utility) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value == expectedByteCount else {
                let actualSize = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?
                    .int64Value ?? -1
                throw LocalWhisperAssetInstallerError.invalidModelFile(
                    filename: filename,
                    reason: "expected \(expectedByteCount) bytes, found \(actualSize)"
                )
            }

            let actualSHA256 = try sha256(of: url)
            guard actualSHA256.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                throw LocalWhisperAssetInstallerError.invalidModelFile(
                    filename: filename,
                    reason: "SHA-256 mismatch"
                )
            }
        }
        try await withTaskCancellationHandler {
            try await validationTask.value
        } onCancel: {
            validationTask.cancel()
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class LocalWhisperModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias DownloadResult = (temporaryURL: URL, response: URLResponse)

    private let lock = NSLock()
    private var continuation: CheckedContinuation<DownloadResult, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var downloadedResult: DownloadResult?
    private var progress: (@Sendable (Int64) -> Void)?
    private var isCancelled = false

    func download(
        from url: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> DownloadResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                self.progress = progress
                let session = URLSession(
                    configuration: .ephemeral,
                    delegate: self,
                    delegateQueue: nil
                )
                self.session = session
                let task = session.downloadTask(with: url)
                self.task = task
                let shouldCancel = isCancelled
                lock.unlock()

                if shouldCancel {
                    task.cancel()
                } else {
                    task.resume()
                }
            }
        } onCancel: { [weak self] in
            self?.cancel()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let progress = progress
        lock.unlock()
        progress?(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response else {
            finish(.failure(LocalWhisperAssetInstallerError.invalidDownloadResponse("Missing response")))
            return
        }

        let retainedURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Shuo-model-download-\(UUID().uuidString)"
        )
        do {
            try FileManager.default.moveItem(at: location, to: retainedURL)
            lock.lock()
            downloadedResult = (retainedURL, response)
            lock.unlock()
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let downloadedResult = downloadedResult
        let isCancelled = isCancelled
        lock.unlock()

        if isCancelled || (error as? URLError)?.code == .cancelled {
            if let downloadedResult {
                try? FileManager.default.removeItem(at: downloadedResult.temporaryURL)
            }
            finish(.failure(CancellationError()))
        } else if let error {
            finish(.failure(error))
        } else if let downloadedResult {
            finish(.success(downloadedResult))
        } else {
            finish(.failure(LocalWhisperAssetInstallerError.invalidDownloadResponse("Missing downloaded file")))
        }
    }

    private func finish(_ result: Result<DownloadResult, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        progress = nil
        let session = session
        self.session = nil
        task = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
