import Foundation

/// The bundled local engines deliberately remain small command-line tools.
/// The model file extension is part of the engine contract, rather than an
/// invitation to run arbitrary GGUF files with the wrong runtime.
enum LocalTranscriptionEngine: String, Equatable {
    case whisper
    case senseVoice

    /// Only whisper.cpp exposes a request-scoped prompt interface. SenseVoice
    /// deliberately remains honest about this limitation instead of silently
    /// accepting vocabulary that cannot influence decoding.
    var supportsVocabularyHints: Bool {
        self == .whisper
    }

    /// whisper.cpp maps Shuo's balanced/fast control to decoder flags.
    /// SenseVoice has no equivalent public CLI control.
    var supportsPerformanceMode: Bool {
        self == .whisper
    }

    static func infer(fromModelPath modelPath: String) -> LocalTranscriptionEngine? {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        let modelURL = URL(fileURLWithPath: trimmedPath)
        switch modelURL.pathExtension.lowercased() {
        case "bin":
            return .whisper
        case "gguf":
            return modelURL.lastPathComponent
                .lowercased()
                .hasPrefix("sensevoice-")
                ? .senseVoice
                : nil
        default:
            return nil
        }
    }
}

enum LocalWhisperModelTier: String, CaseIterable, Identifiable {
    case small
    case balanced
    case large

    var id: String { rawValue }
}

enum LocalWhisperModelRecommendationReason: Equatable {
    case chineseJapaneseAndMixedSpeech
    case englishBestAccuracy
    case englishLightweight
    case widerLanguageBestAccuracy
    case widerLanguageLightweight
}

struct LocalWhisperModelRecommendation: Equatable {
    let modelID: String
    let reason: LocalWhisperModelRecommendationReason
}

struct LocalWhisperManagedModelSupportingAsset: Equatable {
    let filename: String
    let downloadURL: URL
    let expectedByteCount: Int64
    let expectedSHA256: String

    init(
        filename: String,
        downloadURLString: String,
        expectedByteCount: Int64,
        expectedSHA256: String
    ) {
        self.filename = filename
        downloadURL = URL(string: downloadURLString)!
        self.expectedByteCount = expectedByteCount
        self.expectedSHA256 = expectedSHA256
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

struct LocalWhisperManagedModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let filename: String
    let sizeDescription: String
    let tier: LocalWhisperModelTier
    let engine: LocalTranscriptionEngine
    let supportingAssets: [LocalWhisperManagedModelSupportingAsset]
    let downloadURL: URL
    let expectedByteCount: Int64
    let expectedSHA256: String

    init(
        id: String,
        displayName: String,
        filename: String,
        sizeDescription: String,
        tier: LocalWhisperModelTier,
        engine: LocalTranscriptionEngine = .whisper,
        supportingAssets: [LocalWhisperManagedModelSupportingAsset] = [],
        downloadURLString: String,
        expectedByteCount: Int64,
        expectedSHA256: String
    ) {
        self.id = id
        self.displayName = displayName
        self.filename = filename
        self.sizeDescription = sizeDescription
        self.tier = tier
        self.engine = engine
        self.supportingAssets = supportingAssets
        downloadURL = URL(string: downloadURLString)!
        self.expectedByteCount = expectedByteCount
        self.expectedSHA256 = expectedSHA256
    }

    var languageCapability: LocalWhisperLanguageCapability {
        switch engine {
        case .whisper:
            return LocalWhisperLanguageCapability.infer(fromModelPath: filename)
        case .senseVoice:
            return .senseVoice
        }
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

    var totalDownloadByteCount: Int64 {
        expectedByteCount + supportingAssets.reduce(0) { $0 + $1.expectedByteCount }
    }

    func isFullyInstalled(
        in directoryPath: String,
        fileManager: FileManager = .default
    ) -> Bool {
        hasExpectedFileSize(
            at: destinationURL(in: directoryPath),
            fileManager: fileManager
        ) && supportingAssets.allSatisfy {
            $0.hasExpectedFileSize(
                at: $0.destinationURL(in: directoryPath),
                fileManager: fileManager
            )
        }
    }
}

struct LocalWhisperModelCatalog {
    private static let cache = LocalWhisperModelCatalogCache()

    static let onboardingModelIDs = [
        "sensevoice-small-q8",
        "small",
        "large-v3-turbo-q5_0"
    ]
    static let chineseMixedOnboardingModelID = "sensevoice-small-q8"
    static let lightweightOnboardingModelID = "small"
    static let qualityOnboardingModelID = "large-v3-turbo-q5_0"
    static let largeModelRecommendedMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024

    /// Fresh Shuo installs begin with Chinese + English selected, so SenseVoice
    /// is the sensible default there. For English-only or broader language
    /// selections, choose the best Whisper tier the current hardware supports.
    static var defaultOnboardingModelID: String {
        recommendedOnboardingModelID(
            for: [.chinese, .english],
            isAppleSilicon: isRunningOnAppleSilicon,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    static func recommendedOnboardingModelID(
        for selectedLanguages: Set<TranscriptionLanguage>,
        isAppleSilicon: Bool = isRunningOnAppleSilicon,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> String {
        recommendedOnboardingModel(
            for: selectedLanguages,
            isAppleSilicon: isAppleSilicon,
            physicalMemoryBytes: physicalMemoryBytes
        ).modelID
    }

    static func recommendedOnboardingModel(
        for selectedLanguages: Set<TranscriptionLanguage>,
        isAppleSilicon: Bool = isRunningOnAppleSilicon,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> LocalWhisperModelRecommendation {
        let senseVoiceLanguages: Set<TranscriptionLanguage> = [.chinese, .english, .japanese]
        if !selectedLanguages.isDisjoint(with: [.chinese, .japanese]),
           selectedLanguages.isSubset(of: senseVoiceLanguages) {
            return LocalWhisperModelRecommendation(
                modelID: chineseMixedOnboardingModelID,
                reason: .chineseJapaneseAndMixedSpeech
            )
        }

        let whisperModelID = recommendedWhisperOnboardingModelID(
            isAppleSilicon: isAppleSilicon,
            physicalMemoryBytes: physicalMemoryBytes
        )
        let isEnglishOnly = selectedLanguages == [.english]
        let reason: LocalWhisperModelRecommendationReason
        if whisperModelID == qualityOnboardingModelID {
            reason = isEnglishOnly ? .englishBestAccuracy : .widerLanguageBestAccuracy
        } else {
            reason = isEnglishOnly ? .englishLightweight : .widerLanguageLightweight
        }
        return LocalWhisperModelRecommendation(modelID: whisperModelID, reason: reason)
    }

    static func recommendedWhisperOnboardingModelID(
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
    // revision of their upstream repositories. Every managed download is
    // verified by byte count and SHA-256 before it becomes selectable.
    static let senseVoiceVADAsset = LocalWhisperManagedModelSupportingAsset(
        filename: "fsmn-vad.gguf",
        downloadURLString: "https://huggingface.co/FunAudioLLM/fsmn-vad-GGUF/resolve/6840bae4c5c92ee8c04faaf4db23dd0105098d7f/fsmn-vad.gguf",
        expectedByteCount: 1_720_512,
        expectedSHA256: "1270f2559c495f4e7b6e739541151027d360761a3fda43fc147034f5719f5479"
    )

    static let managedModels: [LocalWhisperManagedModel] = [
        LocalWhisperManagedModel(
            id: "sensevoice-small-q8",
            displayName: "SenseVoice Small",
            filename: "sensevoice-small-q8.gguf",
            sizeDescription: "242 MiB",
            tier: .balanced,
            engine: .senseVoice,
            supportingAssets: [senseVoiceVADAsset],
            downloadURLString: "https://huggingface.co/FunAudioLLM/SenseVoiceSmall-GGUF/resolve/90c1c61912018b70ada0fcc024ea24aca62f2e63/sensevoice-small-q8.gguf",
            expectedByteCount: 254_208_320,
            expectedSHA256: "4ae45c94422de949b387e2e0fb10d7e14e4c42c69db30c3444ecc7d4b844b7c5"
        ),
        LocalWhisperManagedModel(
            id: "small",
            displayName: "Whisper Small",
            filename: "ggml-small.bin",
            sizeDescription: "466 MiB",
            tier: .balanced,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.bin",
            expectedByteCount: 487_601_967,
            expectedSHA256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
        ),
        LocalWhisperManagedModel(
            id: "large-v3-turbo-q5_0",
            displayName: "Whisper Large Turbo",
            filename: "ggml-large-v3-turbo-q5_0.bin",
            sizeDescription: "547 MiB",
            tier: .large,
            downloadURLString: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin",
            expectedByteCount: 574_041_195,
            expectedSHA256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
        )
    ]

    static var onboardingModels: [LocalWhisperManagedModel] {
        let modelsByID = Dictionary(uniqueKeysWithValues: managedModels.map { ($0.id, $0) })
        return onboardingModelIDs.compactMap { modelsByID[$0] }
    }

    /// All downloadable models are intentional product choices. Existing and
    /// custom local files remain available through Manual Setup, but Shuo no
    /// longer presents legacy download variants as competing recommendations.
    static var featuredModels: [LocalWhisperManagedModel] {
        onboardingModels
    }

    static var additionalModels: [LocalWhisperManagedModel] {
        []
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
            .filter { isSelectableModelURL($0, in: directoryURL) }
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
        model.isFullyInstalled(in: directoryPath)
    }

    static func senseVoiceVADURL(in directoryPath: String) -> URL {
        senseVoiceVADAsset.destinationURL(in: directoryPath)
    }

    static func invalidateCache(for directoryPath: String) {
        cache.invalidate(directoryURL(for: directoryPath).path)
    }

    /// A SenseVoice main model is not usable without its VAD companion. Keep a
    /// valid, already-downloaded main file on disk so a retry need not fetch it
    /// again, but never surface an incomplete pair as a selectable model.
    private static func isSelectableModelURL(_ url: URL, in directoryURL: URL) -> Bool {
        guard let engine = LocalTranscriptionEngine.infer(fromModelPath: url.path) else {
            return false
        }

        switch engine {
        case .whisper:
            return true
        case .senseVoice:
            return senseVoiceVADAsset.hasExpectedFileSize(
                at: senseVoiceVADAsset.destinationURL(in: directoryURL.path)
            )
        }
    }

    /// Supporting assets are shared by engine family rather than by one model
    /// filename. This keeps a future SenseVoice model (or an advanced manual model)
    /// from being broken when another SenseVoice model is removed.
    static func hasAnotherModelUsing(
        supportingAsset: LocalWhisperManagedModelSupportingAsset,
        excludingModelURL: URL,
        in directoryPath: String,
        fileManager: FileManager = .default
    ) -> Bool {
        let modelsDirectoryURL = directoryURL(for: directoryPath)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: modelsDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let excludedURL = excludingModelURL.standardizedFileURL
        return contents.contains { candidateURL in
            guard candidateURL.standardizedFileURL != excludedURL,
                  LocalTranscriptionEngine.infer(fromModelPath: candidateURL.path) == .senseVoice,
                  let values = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return false
            }

            // All current and planned SenseVoice variants use the same VAD
            // filename. Leave the asset in place if another engine model is
            // still present, even if that other model was copied in manually.
            return supportingAsset.filename == senseVoiceVADAsset.filename
        }
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

enum LocalSenseVoiceExecutableResolver {
    static func resolvedExecutableURL(
        bundledExecutableURL: URL? = bundledExecutableURL()
    ) -> URL? {
        guard let bundledExecutableURL,
              FileManager.default.isExecutableFile(atPath: bundledExecutableURL.path) else {
            return nil
        }
        return bundledExecutableURL.standardizedFileURL
    }

    static func bundledExecutableURL(bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: "sensevoice-cli",
            withExtension: nil,
            subdirectory: "Runtime"
        )
    }
}
