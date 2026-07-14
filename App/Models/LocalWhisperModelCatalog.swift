import Foundation

enum LocalWhisperModelTier: String, CaseIterable, Identifiable {
    case small
    case balanced
    case large

    var id: String { rawValue }
}

struct LocalWhisperManagedModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let filename: String
    let sizeDescription: String
    let tier: LocalWhisperModelTier
    let downloadURL: URL
    let expectedByteCount: Int64
    let expectedSHA256: String

    init(
        id: String,
        displayName: String,
        filename: String,
        sizeDescription: String,
        tier: LocalWhisperModelTier,
        downloadURLString: String,
        expectedByteCount: Int64,
        expectedSHA256: String
    ) {
        self.id = id
        self.displayName = displayName
        self.filename = filename
        self.sizeDescription = sizeDescription
        self.tier = tier
        downloadURL = URL(string: downloadURLString)!
        self.expectedByteCount = expectedByteCount
        self.expectedSHA256 = expectedSHA256
    }

    var languageCapability: LocalWhisperLanguageCapability {
        LocalWhisperLanguageCapability.infer(fromModelPath: filename)
    }

    func destinationURL(in directoryPath: String) -> URL {
        LocalWhisperModelCatalog.directoryURL(for: directoryPath)
            .appendingPathComponent(filename)
            .standardizedFileURL
    }

    func hasExpectedFileSize(at url: URL, fileManager: FileManager = .default) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value == expectedByteCount
    }
}

struct LocalWhisperModelCatalog {
    private static let cache = LocalWhisperModelCatalogCache()

    static let onboardingModelIDs = [
        "base",
        "small",
        "large-v3-turbo-q5_0"
    ]
    static let lightweightOnboardingModelID = "small"
    static let qualityOnboardingModelID = "large-v3-turbo-q5_0"
    static let largeModelRecommendedMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024

    /// Large Turbo Q5 is only a small download increase over Small and is the
    /// stronger default on modern Apple Silicon. Keep Small as the conservative
    /// choice on Intel and lower-memory Macs until that hardware matrix is
    /// benchmarked.
    static var defaultOnboardingModelID: String {
        recommendedOnboardingModelID(
            isAppleSilicon: isRunningOnAppleSilicon,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    static func recommendedOnboardingModelID(
        isAppleSilicon: Bool,
        physicalMemoryBytes: UInt64
    ) -> String {
        isAppleSilicon && physicalMemoryBytes >= largeModelRecommendedMemoryBytes
            ? qualityOnboardingModelID
            : lightweightOnboardingModelID
    }

    private static var isRunningOnAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    // Download URLs and LFS object metadata are pinned to the same verified
    // revision of the official ggerganov/whisper.cpp Hugging Face repository.
    static let managedModels: [LocalWhisperManagedModel] = [
        LocalWhisperManagedModel(
            id: "base",
            displayName: "Base",
            filename: "ggml-base.bin",
            sizeDescription: "142 MiB",
            tier: .small,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin",
            expectedByteCount: 147_951_465,
            expectedSHA256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
        ),
        LocalWhisperManagedModel(
            id: "base.en",
            displayName: "Base English",
            filename: "ggml-base.en.bin",
            sizeDescription: "142 MiB",
            tier: .small,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.en.bin",
            expectedByteCount: 147_964_211,
            expectedSHA256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
        ),
        LocalWhisperManagedModel(
            id: "small",
            displayName: "Small",
            filename: "ggml-small.bin",
            sizeDescription: "466 MiB",
            tier: .balanced,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.bin",
            expectedByteCount: 487_601_967,
            expectedSHA256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
        ),
        LocalWhisperManagedModel(
            id: "small.en",
            displayName: "Small English",
            filename: "ggml-small.en.bin",
            sizeDescription: "466 MiB",
            tier: .balanced,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.en.bin",
            expectedByteCount: 487_614_201,
            expectedSHA256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
        ),
        LocalWhisperManagedModel(
            id: "medium",
            displayName: "Medium",
            filename: "ggml-medium.bin",
            sizeDescription: "1.5 GiB",
            tier: .large,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-medium.bin",
            expectedByteCount: 1_533_763_059,
            expectedSHA256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"
        ),
        LocalWhisperManagedModel(
            id: "large-v3-turbo-q5_0",
            displayName: "Large Turbo",
            filename: "ggml-large-v3-turbo-q5_0.bin",
            sizeDescription: "547 MiB",
            tier: .large,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin",
            expectedByteCount: 574_041_195,
            expectedSHA256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
        ),
        LocalWhisperManagedModel(
            id: "large-v3-turbo-q8_0",
            displayName: "Large Turbo · Q8",
            filename: "ggml-large-v3-turbo-q8_0.bin",
            sizeDescription: "834 MiB",
            tier: .large,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin",
            expectedByteCount: 874_188_075,
            expectedSHA256: "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1"
        )
    ]

    static var onboardingModels: [LocalWhisperManagedModel] {
        let modelsByID = Dictionary(uniqueKeysWithValues: managedModels.map { ($0.id, $0) })
        return onboardingModelIDs.compactMap { modelsByID[$0] }
    }

    /// The short list shown before a user asks for additional model variants.
    /// It intentionally offers one clear quality step at each practical size,
    /// rather than presenting quantization variants as separate model families.
    static var featuredModels: [LocalWhisperManagedModel] {
        onboardingModels
    }

    static var additionalModels: [LocalWhisperManagedModel] {
        let featuredIDs = Set(featuredModels.map(\.id))
        return managedModels.filter { !featuredIDs.contains($0.id) }
    }

    static func directoryURL(for directoryPath: String) -> URL {
        let trimmedPath = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty {
            return URL(fileURLWithPath: AppSettings.defaultLocalWhisperModelDirectoryPath, isDirectory: true)
                .standardizedFileURL
        }

        return URL(fileURLWithPath: trimmedPath, isDirectory: true).standardizedFileURL
    }

    static func modelURLs(in directoryPath: String) -> [URL] {
        let trimmedPath = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return []
        }

        let directoryURL = URL(fileURLWithPath: trimmedPath, isDirectory: true).standardizedFileURL
        let cacheKey = directoryURL.path
        let signature = directorySignature(for: directoryURL)
        if let cachedURLs = cache.urls(for: cacheKey, signature: signature) {
            return cachedURLs
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let urls = contents
            .filter { $0.pathExtension.lowercased() == "bin" }
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
                    return false
                }
                return values.isRegularFile == true
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            .map(\.standardizedFileURL)

        cache.store(urls: urls, for: cacheKey, signature: signature)
        return urls
    }

    static func modelPaths(in directoryPath: String) -> [String] {
        modelURLs(in: directoryPath).map(\.path)
    }

    static func isInstalled(_ model: LocalWhisperManagedModel, in directoryPath: String) -> Bool {
        model.hasExpectedFileSize(at: model.destinationURL(in: directoryPath))
    }

    static func invalidateCache(for directoryPath: String) {
        cache.invalidate(directoryURL(for: directoryPath).path)
    }

    private static func directorySignature(for directoryURL: URL) -> Date? {
        try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

private final class LocalWhisperModelCatalogCache: @unchecked Sendable {
    private struct Entry {
        let signature: Date?
        let urls: [URL]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func urls(for key: String, signature: Date?) -> [URL]? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[key], entry.signature == signature else {
            return nil
        }

        return entry.urls
    }

    func store(urls: [URL], for key: String, signature: Date?) {
        lock.lock()
        entries[key] = Entry(signature: signature, urls: urls)
        lock.unlock()
    }

    func invalidate(_ key: String) {
        lock.lock()
        entries.removeValue(forKey: key)
        lock.unlock()
    }
}

enum LocalWhisperExecutableResolver {
    static let commonExecutablePaths = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cpp",
        "/opt/homebrew/bin/main",
        "/usr/local/bin/main"
    ]

    static func resolvedExecutableURL(
        configuredPath: String,
        bundledExecutableURL: URL? = bundledExecutableURL(),
        commonPaths: [String] = commonExecutablePaths
    ) -> URL? {
        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidatePaths: [String] = []
        if !trimmedPath.isEmpty {
            candidatePaths.append(trimmedPath)
        }
        if let bundledExecutableURL {
            candidatePaths.append(bundledExecutableURL.path)
        }
        candidatePaths.append(contentsOf: commonPaths)

        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        return nil
    }

    static func bundledExecutableURL(bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: "whisper-cli",
            withExtension: nil,
            subdirectory: "Runtime"
        )
    }
}
