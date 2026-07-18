import Foundation

/// The connection metadata for every cloud transcription choice. This is the
/// single source of truth for the cloud-service picker, its endpoint, the
/// credential it uses, and its model capabilities. Transport implementations
/// remain in their dedicated service types.
enum CloudProviderTransportKind: Hashable {
    case openAICompatible
    case native
}

enum CloudProviderEndpoint: Hashable {
    case fixed(URL)
    case editable(defaultURL: String)

    var fixedURL: URL? {
        guard case let .fixed(url) = self else {
            return nil
        }
        return url
    }

    var defaultURLString: String {
        switch self {
        case let .fixed(url):
            return url.absoluteString
        case let .editable(defaultURL):
            return defaultURL
        }
    }

    var isEditable: Bool {
        if case .editable = self {
            return true
        }
        return false
    }
}

enum CloudProviderCredential: Hashable {
    case openAICompatible
    case gemini
    case elevenLabs
    case alibaba
}

enum CloudProviderConnectionDetail: Hashable {
    case alibabaQwen3
}

enum CloudTranscriptionPreset: String, CaseIterable, Identifiable {
    case openAI
    case groq
    case siliconFlow
    case gemini
    case elevenLabs
    case alibaba
    case custom

    var id: String { rawValue }

    var configuration: CloudTranscriptionProviderConfiguration {
        CloudTranscriptionProviderConfiguration.configuration(for: self)
    }

    var provider: TranscriptionProvider {
        configuration.backendProvider
    }

    /// Compatibility shims for persisted settings, keychain migration, and
    /// existing tests. Endpoint ownership lives in the configuration above.
    static var groqBaseURL: String {
        CloudTranscriptionProviderConfiguration
            .configuration(for: .groq)
            .endpoint
            .defaultURLString
    }

    static var siliconFlowBaseURL: String {
        CloudTranscriptionProviderConfiguration
            .configuration(for: .siliconFlow)
            .endpoint
            .defaultURLString
    }

    static func inferred(
        provider: TranscriptionProvider,
        openAIBaseURL: String
    ) -> CloudTranscriptionPreset {
        CloudTranscriptionProviderConfiguration.inferred(
            backendProvider: provider,
            compatibleBaseURL: openAIBaseURL
        ).preset
    }
}

struct CloudTranscriptionProviderConfiguration: Identifiable, Hashable {
    let preset: CloudTranscriptionPreset
    let backendProvider: TranscriptionProvider
    let requiredPlugin: PluginID
    let transportKind: CloudProviderTransportKind
    let endpoint: CloudProviderEndpoint
    let credential: CloudProviderCredential
    let apiKeyGuideURL: URL?
    let automaticTranscriptionModelID: String?
    let automaticTextModelID: String?
    let fixedTranscriptionModelID: String?
    let connectionDetail: CloudProviderConnectionDetail?
    let supportsTextProcessing: Bool

    var id: CloudTranscriptionPreset { preset }

    var supportsModelDiscovery: Bool {
        transportKind == .openAICompatible
    }

    var apiKeySearchTarget: SettingsSearchTarget {
        switch credential {
        case .openAICompatible:
            return .openAIAPIKey
        case .gemini:
            return .geminiAPIKey
        case .elevenLabs:
            return .elevenLabsAPIKey
        case .alibaba:
            return .alibabaAPIKey
        }
    }

    static let openAI = Self(
        preset: .openAI,
        backendProvider: .openAI,
        requiredPlugin: .providerOpenAI,
        transportKind: .openAICompatible,
        endpoint: .fixed(URL(string: AppSettings.defaultOpenAIBaseURL)!),
        credential: .openAICompatible,
        apiKeyGuideURL: URL(
            string: "https://help.openai.com/en/articles/4936850-where-do-i-find-my-openai-api-key"
        ),
        automaticTranscriptionModelID: nil,
        automaticTextModelID: nil,
        fixedTranscriptionModelID: nil,
        connectionDetail: nil,
        supportsTextProcessing: true
    )

    static let groq = Self(
        preset: .groq,
        backendProvider: .openAI,
        requiredPlugin: .providerOpenAI,
        transportKind: .openAICompatible,
        endpoint: .fixed(URL(string: "https://api.groq.com/openai/v1")!),
        credential: .openAICompatible,
        apiKeyGuideURL: nil,
        automaticTranscriptionModelID: nil,
        automaticTextModelID: nil,
        fixedTranscriptionModelID: nil,
        connectionDetail: nil,
        supportsTextProcessing: true
    )

    static let siliconFlow = Self(
        preset: .siliconFlow,
        backendProvider: .openAI,
        requiredPlugin: .providerOpenAI,
        transportKind: .openAICompatible,
        endpoint: .fixed(URL(string: "https://api.siliconflow.cn/v1")!),
        credential: .openAICompatible,
        apiKeyGuideURL: nil,
        automaticTranscriptionModelID: "FunAudioLLM/SenseVoiceSmall",
        automaticTextModelID: "Qwen/Qwen-3-8B",
        fixedTranscriptionModelID: nil,
        connectionDetail: nil,
        supportsTextProcessing: true
    )

    static let gemini = Self(
        preset: .gemini,
        backendProvider: .gemini,
        requiredPlugin: .providerGemini,
        transportKind: .native,
        endpoint: .fixed(URL(string: "https://generativelanguage.googleapis.com/v1beta")!),
        credential: .gemini,
        apiKeyGuideURL: URL(string: "https://aistudio.google.com/apikey"),
        automaticTranscriptionModelID: nil,
        automaticTextModelID: nil,
        fixedTranscriptionModelID: "gemini-3.1-flash-lite",
        connectionDetail: nil,
        supportsTextProcessing: true
    )

    static let elevenLabs = Self(
        preset: .elevenLabs,
        backendProvider: .elevenLabs,
        requiredPlugin: .providerElevenLabs,
        transportKind: .native,
        endpoint: .fixed(URL(string: "https://api.elevenlabs.io/v1")!),
        credential: .elevenLabs,
        apiKeyGuideURL: URL(
            string: "https://elevenlabs.io/docs/overview/administration/workspaces/api-keys"
        ),
        automaticTranscriptionModelID: nil,
        automaticTextModelID: nil,
        fixedTranscriptionModelID: "scribe_v2",
        connectionDetail: nil,
        supportsTextProcessing: false
    )

    static let alibaba = Self(
        preset: .alibaba,
        backendProvider: .alibaba,
        requiredPlugin: .providerAlibaba,
        transportKind: .native,
        endpoint: .fixed(URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!),
        credential: .alibaba,
        apiKeyGuideURL: URL(
            string: "https://www.alibabacloud.com/help/en/model-studio/get-api-key"
        ),
        automaticTranscriptionModelID: nil,
        automaticTextModelID: nil,
        fixedTranscriptionModelID: "qwen3-asr-flash",
        connectionDetail: .alibabaQwen3,
        supportsTextProcessing: false
    )

    static let custom = Self(
        preset: .custom,
        backendProvider: .openAI,
        requiredPlugin: .providerOpenAI,
        transportKind: .openAICompatible,
        endpoint: .editable(defaultURL: AppSettings.defaultOpenAIBaseURL),
        credential: .openAICompatible,
        apiKeyGuideURL: nil,
        automaticTranscriptionModelID: nil,
        automaticTextModelID: nil,
        fixedTranscriptionModelID: nil,
        connectionDetail: nil,
        supportsTextProcessing: true
    )

    static let all = [
        openAI,
        groq,
        siliconFlow,
        gemini,
        elevenLabs,
        alibaba,
        custom
    ]

    static func configuration(
        for preset: CloudTranscriptionPreset
    ) -> CloudTranscriptionProviderConfiguration {
        guard let configuration = all.first(where: { $0.preset == preset }) else {
            preconditionFailure("Missing cloud provider configuration for \(preset.rawValue)")
        }
        return configuration
    }

    static func defaultConfiguration(
        for backendProvider: TranscriptionProvider
    ) -> CloudTranscriptionProviderConfiguration? {
        all.first { configuration in
            configuration.backendProvider == backendProvider && configuration.preset != .custom
        }
    }

    static func inferred(
        backendProvider: TranscriptionProvider,
        compatibleBaseURL: String
    ) -> CloudTranscriptionProviderConfiguration {
        guard backendProvider == .openAI || backendProvider == .custom else {
            return defaultConfiguration(for: backendProvider) ?? openAI
        }

        let identity = OpenAICompatibleRequestBuilder.connectionIdentity(
            baseURLString: compatibleBaseURL
        )
        return all.first { configuration in
            configuration.transportKind == .openAICompatible
                && !configuration.endpoint.isEditable
                && OpenAICompatibleRequestBuilder.connectionIdentity(
                    baseURLString: configuration.endpoint.defaultURLString
                ) == identity
        } ?? custom
    }

    static func enabled(
        isPluginEnabled: (PluginID) -> Bool
    ) -> [CloudTranscriptionProviderConfiguration] {
        let configurations = all.filter { isPluginEnabled($0.requiredPlugin) }
        return configurations.isEmpty ? all : configurations
    }

    static func apiKeyGuideURL(
        for backendProvider: TranscriptionProvider
    ) -> URL? {
        defaultConfiguration(for: backendProvider)?.apiKeyGuideURL
    }
}
