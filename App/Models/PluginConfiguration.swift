import Foundation

struct PluginID: RawRepresentable, Hashable, Codable, Comparable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func < (lhs: PluginID, rhs: PluginID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension PluginID {
    static let providerOpenAI = PluginID(rawValue: "provider.openai")
    static let providerElevenLabs = PluginID(rawValue: "provider.elevenLabs")
    static let providerAlibaba = PluginID(rawValue: "provider.alibaba")
    static let providerGemini = PluginID(rawValue: "provider.gemini")
    static let providerLocalWhisper = PluginID(rawValue: "provider.localWhisper")
    static let historyBasic = PluginID(rawValue: "history.basic")
    static let metricsBasic = PluginID(rawValue: "metrics.basic")
    static let quickCopy = PluginID(rawValue: "quick.copy")
    static let quickPlayAudio = PluginID(rawValue: "quick.playAudio")
    static let quickRetranscribe = PluginID(rawValue: "quick.retranscribe")
    static let outputCleanup = PluginID(rawValue: "output.cleanup")
    static let outputCustomCorrections = PluginID(rawValue: "output.customCorrections")
    static let outputChineseConversion = PluginID(rawValue: "output.chineseConversion")
    static let outputEmoji = PluginID(rawValue: "output.emoji")
    static let outputLLMRetouch = PluginID(rawValue: "output.llmRetouch")
    static let commandModifyPrevious = PluginID(rawValue: "command.modifyPrevious")
    static let commandDeletePrevious = PluginID(rawValue: "command.deletePrevious")
    static let smartPromptContext = PluginID(rawValue: "smart.promptContext")
    static let smartPreferredTerms = PluginID(rawValue: "smart.preferredTerms")
    static let smartAdaptiveRecognition = PluginID(rawValue: "smart.adaptiveRecognition")
    static let smartCorrectionWindow = PluginID(rawValue: "smart.correctionWindow")
    static let advancedSettingsExport = PluginID(rawValue: "advanced.settingsExport")
    static let metricsAdvancedDashboard = PluginID(rawValue: "metrics.advancedDashboard")
    static let workflowMessageToVideo = PluginID(rawValue: "workflow.messageToVideo")
}

enum PluginCategory: String, Codable, CaseIterable, Identifiable {
    case core
    case provider
    case quick
    case output
    case command
    case smart
    case metrics
    case advanced
    case workflow

    var id: String { rawValue }
}

struct PluginDescriptor: Identifiable, Codable, Equatable {
    let id: PluginID
    let name: String
    let category: PluginCategory
    let summary: String
    let isCore: Bool
    let isPublic: Bool
    let isExperimental: Bool

    var displayCategory: String {
        category.rawValue
    }
}

struct PluginConfiguration: Codable, Equatable {
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var profile: String
    var enabledPlugins: Set<PluginID>
    var disabledPlugins: Set<PluginID>

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        profile: String,
        enabledPlugins: Set<PluginID>,
        disabledPlugins: Set<PluginID> = []
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.enabledPlugins = enabledPlugins
        self.disabledPlugins = disabledPlugins
    }

    func isEnabled(_ pluginID: PluginID) -> Bool {
        guard !disabledPlugins.contains(pluginID) else {
            return false
        }

        return enabledPlugins.contains(pluginID)
    }

    mutating func setEnabled(_ isEnabled: Bool, for pluginID: PluginID) {
        if isEnabled {
            disabledPlugins.remove(pluginID)
            enabledPlugins.insert(pluginID)
        } else {
            enabledPlugins.remove(pluginID)
            disabledPlugins.insert(pluginID)
        }
    }
}

extension PluginConfiguration {
    static let mvp = PluginConfiguration(
        profile: "mvp",
        enabledPlugins: [
            .providerOpenAI,
            .providerElevenLabs,
            .providerAlibaba,
            .providerGemini,
            .providerLocalWhisper,
            .historyBasic,
            .metricsBasic,
            .quickCopy,
            .quickPlayAudio,
            .quickRetranscribe,
            .outputCleanup,
            .smartPreferredTerms,
            .smartCorrectionWindow
        ],
        disabledPlugins: [
            .outputCustomCorrections,
            .outputChineseConversion,
            .outputEmoji,
            .outputLLMRetouch,
            .commandModifyPrevious,
            .commandDeletePrevious,
            .smartPromptContext,
            .smartAdaptiveRecognition,
            .advancedSettingsExport,
            .metricsAdvancedDashboard,
            .workflowMessageToVideo
        ]
    )

    static let fullDevelopment = PluginConfiguration(
        profile: "full-dev",
        enabledPlugins: Set(
            PluginCatalog.allDescriptors
                .map(\.id)
                .filter { $0 != .workflowMessageToVideo }
        ),
        disabledPlugins: [
            .workflowMessageToVideo
        ]
    )

    static let publicRelease = PluginConfiguration(
        profile: "public",
        enabledPlugins: [
            .providerOpenAI,
            .providerElevenLabs,
            .providerAlibaba,
            .providerGemini,
            .providerLocalWhisper,
            .historyBasic,
            .metricsBasic,
            .quickCopy,
            .quickPlayAudio,
            .quickRetranscribe,
            .outputCleanup,
            .smartPreferredTerms,
            .smartCorrectionWindow,
            .advancedSettingsExport
        ],
        disabledPlugins: [
            .outputCustomCorrections,
            .outputChineseConversion,
            .outputEmoji,
            .outputLLMRetouch,
            .commandModifyPrevious,
            .commandDeletePrevious,
            .smartPromptContext,
            .smartAdaptiveRecognition,
            .metricsAdvancedDashboard,
            .workflowMessageToVideo
        ]
    )
}

struct PluginCapabilityPolicy {
    let configuration: PluginConfiguration

    func isTranscriptionProviderEnabled(_ provider: TranscriptionProvider) -> Bool {
        configuration.isEnabled(provider.requiredPlugin)
    }

    /// Custom OpenAI-compatible endpoints remain available independently of
    /// the built-in OpenAI-compatible provider plugin. They are explicitly
    /// configured by the user and still require endpoint verification.
    func isTranscriptionEnabled(for settings: AppSettings) -> Bool {
        settings.isCustomOpenAITranscriptionService
            || isTranscriptionProviderEnabled(settings.provider)
    }

    var voiceEditCommandsEnabled: Bool {
        configuration.isEnabled(.commandModifyPrevious)
            || configuration.isEnabled(.commandDeletePrevious)
    }

    func availableProvider(fallingBackFrom provider: TranscriptionProvider) -> TranscriptionProvider? {
        if isTranscriptionProviderEnabled(provider) {
            return provider
        }
        if configuration.isEnabled(.providerLocalWhisper) {
            return .local
        }
        if configuration.isEnabled(.providerOpenAI) {
            return .openAI
        }
        if configuration.isEnabled(.providerElevenLabs) {
            return .elevenLabs
        }
        if configuration.isEnabled(.providerAlibaba) {
            return .alibaba
        }
        if configuration.isEnabled(.providerGemini) {
            return .gemini
        }
        return nil
    }

    func applying(to source: AppSettings) -> AppSettings {
        var adjusted = source

        if !configuration.isEnabled(.outputCleanup) {
            adjusted.punctuationPostProcessingMode = .keep
            adjusted.lowercaseEnglishAfterTranscription = false
            adjusted.insertSpaceBetweenChineseAndEnglish = false
            adjusted.appendNewlineAfterTranscription = false
            adjusted.appendSpaceAfterTranscription = false
        }

        if !configuration.isEnabled(.outputCustomCorrections) {
            adjusted.useCustomCorrections = false
        }

        if !configuration.isEnabled(.outputChineseConversion) {
            adjusted.chineseTextConversionMode = .keep
        }

        if !configuration.isEnabled(.outputEmoji) {
            adjusted.emojiPostProcessingEnabled = false
            adjusted.smartEmojiMatchingAfterTranscription = false
            adjusted.aiEmojiResolverEnabled = false
        }

        if !configuration.isEnabled(.outputLLMRetouch) {
            adjusted.transcriptRetouchEnabled = false
        }

        if !configuration.isEnabled(.smartPromptContext) {
            adjusted.promptContextItems = []
        }

        if !configuration.isEnabled(.smartPreferredTerms) {
            adjusted.useDeveloperGlossary = false
        }

        if !configuration.isEnabled(.smartAdaptiveRecognition) {
            adjusted.adaptiveRecognitionEnabled = false
        }

        if !voiceEditCommandsEnabled {
            adjusted.voiceEditCommandsEnabled = false
        }

        return CloudTextAICapabilityPolicy.applying(to: adjusted)
    }
}

enum PluginCatalog {
    static let allDescriptors: [PluginDescriptor] = [
        PluginDescriptor(
            id: .providerOpenAI,
            name: "OpenAI-compatible Transcription",
            category: .provider,
            summary: "Cloud or OpenAI-compatible transcription provider.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .providerLocalWhisper,
            name: "Local Whisper",
            category: .provider,
            summary: "Local whisper.cpp transcription and model management.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .providerElevenLabs,
            name: "ElevenLabs Scribe",
            category: .provider,
            summary: "Cloud transcription in 90+ languages with terminology keyterms.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .providerAlibaba,
            name: "Alibaba Cloud Qwen ASR",
            category: .provider,
            summary: "Qwen3-ASR-Flash transcription through Model Studio's Beijing endpoint.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .providerGemini,
            name: "Google Gemini Transcription",
            category: .provider,
            summary: "Gemini audio understanding for cloud transcription through Google's native API.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .historyBasic,
            name: "Basic History",
            category: .core,
            summary: "Stores transcripts, audio references, deletion, playback, and retranscription support.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .metricsBasic,
            name: "Basic Metrics",
            category: .core,
            summary: "Records core counters and exportable usage metrics.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .quickCopy,
            name: "Quick Copy",
            category: .quick,
            summary: "Copy the latest transcript from the menu bar.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .quickPlayAudio,
            name: "Quick Audio Replay",
            category: .quick,
            summary: "Play the latest transcript audio from the menu bar.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .quickRetranscribe,
            name: "Quick Retranscribe",
            category: .quick,
            summary: "Retranscribe the latest saved audio.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .outputCleanup,
            name: "Output Cleanup",
            category: .output,
            summary: "Trim whitespace, collapse repeated spaces, and apply safe formatting cleanup.",
            isCore: false,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .outputCustomCorrections,
            name: "Custom Corrections",
            category: .output,
            summary: "Apply user-defined replacement rules after transcription.",
            isCore: false,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .outputChineseConversion,
            name: "Chinese Script Conversion",
            category: .output,
            summary: "Convert Chinese output to Simplified or Traditional Chinese.",
            isCore: false,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .outputEmoji,
            name: "Emoji Output",
            category: .output,
            summary: "Replace spoken emoji phrases with emoji characters.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .outputLLMRetouch,
            name: "LLM Retouch",
            category: .output,
            summary: "Use an LLM to lightly repair typos and awkward transcripts.",
            isCore: false,
            isPublic: false,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .commandModifyPrevious,
            name: "Modify Previous Insertion",
            category: .command,
            summary: "Use voice commands to rewrite the previous inserted text.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .commandDeletePrevious,
            name: "Delete Previous Insertion",
            category: .command,
            summary: "Use voice commands to delete the previous inserted text.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .smartPromptContext,
            name: "Prompt Context",
            category: .smart,
            summary: "Send configurable transcription context prompts.",
            isCore: false,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .smartPreferredTerms,
            name: "Preferred Terms",
            category: .smart,
            summary: "Send preferred spelling and terminology hints.",
            isCore: true,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .smartAdaptiveRecognition,
            name: "Adaptive Recognition",
            category: .smart,
            summary: "Use repeated local corrections as spelling hints or conservative replacements.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .smartCorrectionWindow,
            name: "Floating Bar",
            category: .smart,
            summary: "Keep a lightweight indicator on top and expand it for safe transcript correction.",
            isCore: false,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .advancedSettingsExport,
            name: "Settings Export",
            category: .advanced,
            summary: "Export current settings to a JSON file.",
            isCore: false,
            isPublic: true,
            isExperimental: false
        ),
        PluginDescriptor(
            id: .metricsAdvancedDashboard,
            name: "Advanced Metrics Dashboard",
            category: .metrics,
            summary: "Charts, trend views, and deeper metric analysis.",
            isCore: false,
            isPublic: true,
            isExperimental: true
        ),
        PluginDescriptor(
            id: .workflowMessageToVideo,
            name: "Message to Video",
            category: .workflow,
            summary: "Generate publishable video messages from voice notes.",
            isCore: false,
            isPublic: false,
            isExperimental: true
        )
    ]

    static func descriptor(for pluginID: PluginID) -> PluginDescriptor? {
        allDescriptors.first { $0.id == pluginID }
    }
}

struct PluginStatusItem: Identifiable, Equatable {
    let descriptor: PluginDescriptor
    let isEnabled: Bool

    var id: PluginID { descriptor.id }
}

struct PluginConfigurationDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date?
    let configuration: PluginConfiguration

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date? = nil,
        configuration: PluginConfiguration
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.configuration = configuration
    }
}

enum PluginConfigurationStoreError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyConfiguration

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported plugin configuration schema version: \(version)."
        case .emptyConfiguration:
            return "The plugin configuration does not enable or disable any plugins."
        }
    }
}

enum PluginConfigurationStore {
    static let userDefaultsKey = "pluginConfiguration"

    static func load(
        preservingConfiguredProvider configuredProvider: TranscriptionProvider? = nil
    ) -> PluginConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let configuration = try? decoder.decode(PluginConfiguration.self, from: data) else {
            var configuration = PluginConfiguration.publicRelease
            if let pluginID = providerPluginID(for: configuredProvider) {
                configuration.setEnabled(true, for: pluginID)
            }
            return configuration
        }

        return normalized(configuration)
    }

    static func save(_ configuration: PluginConfiguration) {
        guard let data = try? encoder.encode(normalized(configuration)) else {
            return
        }

        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    static func configuration(from data: Data) throws -> PluginConfiguration {
        if let document = try? decoder.decode(PluginConfigurationDocument.self, from: data) {
            return try validated(document.configuration)
        }

        return try validated(decoder.decode(PluginConfiguration.self, from: data))
    }

    static func exportData(
        configuration: PluginConfiguration,
        exportedAt: Date = Date()
    ) throws -> Data {
        let document = PluginConfigurationDocument(
            exportedAt: exportedAt,
            configuration: normalized(configuration)
        )
        return try encoder.encode(document)
    }

    static func statusItems(for configuration: PluginConfiguration) -> [PluginStatusItem] {
        PluginCatalog.allDescriptors.map {
            PluginStatusItem(
                descriptor: $0,
                isEnabled: configuration.isEnabled($0.id)
            )
        }
    }

    private static func validated(_ configuration: PluginConfiguration) throws -> PluginConfiguration {
        guard configuration.schemaVersion <= PluginConfiguration.currentSchemaVersion else {
            throw PluginConfigurationStoreError.unsupportedSchemaVersion(configuration.schemaVersion)
        }

        guard !configuration.enabledPlugins.isEmpty || !configuration.disabledPlugins.isEmpty else {
            throw PluginConfigurationStoreError.emptyConfiguration
        }

        return normalized(configuration)
    }

    private static func normalized(_ configuration: PluginConfiguration) -> PluginConfiguration {
        var normalized = configuration
        if normalized.schemaVersion < 2,
           ["mvp", "public"].contains(normalized.profile) {
            normalized.disabledPlugins.remove(.smartPreferredTerms)
            normalized.enabledPlugins.insert(.smartPreferredTerms)
        }
        if normalized.schemaVersion < 3 {
            if normalized.profile == "full-dev" {
                normalized.enabledPlugins.formUnion(
                    PluginCatalog.allDescriptors
                        .map(\.id)
                        .filter {
                            $0 != .workflowMessageToVideo
                                && !normalized.disabledPlugins.contains($0)
                        }
                )
                normalized.disabledPlugins.insert(.workflowMessageToVideo)
            } else if ["mvp", "public"].contains(normalized.profile) {
                if !normalized.disabledPlugins.contains(.providerElevenLabs) {
                    normalized.enabledPlugins.insert(.providerElevenLabs)
                }
                normalized.disabledPlugins.insert(.smartCorrectionWindow)
            }
        }
        if normalized.schemaVersion < 4 {
            if normalized.profile == "full-dev" {
                if !normalized.disabledPlugins.contains(.providerAlibaba) {
                    normalized.enabledPlugins.insert(.providerAlibaba)
                }
            } else if ["mvp", "public"].contains(normalized.profile) {
                if !normalized.disabledPlugins.contains(.providerAlibaba) {
                    normalized.enabledPlugins.insert(.providerAlibaba)
                }
            }
        }
        if normalized.schemaVersion < 5,
           ["mvp", "public", "full-dev"].contains(normalized.profile) {
            // Gemini is surfaced in the default profiles so users can try the
            // requested cloud provider without manually editing a profile.
            // Preserve an explicit opt-out in imported configurations.
            if !normalized.disabledPlugins.contains(.providerGemini) {
                normalized.enabledPlugins.insert(.providerGemini)
            }
        }
        normalized.schemaVersion = PluginConfiguration.currentSchemaVersion
        normalized.disabledPlugins.subtract(normalized.enabledPlugins)
        return normalized
    }

    private static func providerPluginID(
        for provider: TranscriptionProvider?
    ) -> PluginID? {
        provider?.requiredPlugin
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
