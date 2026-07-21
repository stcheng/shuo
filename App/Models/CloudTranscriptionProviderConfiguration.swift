import Foundation

/// The transport and endpoint metadata for cloud services. Request payloads and
/// response parsing stay in the provider-specific service adapters.
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

/// Stable product-facing service identities. Their raw values intentionally
/// match the existing persisted picker enums so M1 can derive metadata without
/// migrating user settings.
enum CloudServiceID: String, CaseIterable, Codable, Identifiable {
    case alibaba
    case elevenLabs
    case gemini
    case groq
    case openAI
    case siliconFlow
    case custom

    var id: String { rawValue }
}

enum CloudServiceWorkload: Hashable {
    case transcription
    case textProcessing
}

enum CloudTranscriptionPreset: String, CaseIterable, Identifiable {
    case alibaba
    case elevenLabs
    case gemini
    case groq
    case openAI
    case siliconFlow
    case custom

    var id: String { rawValue }

    var serviceID: CloudServiceID {
        guard let serviceID = CloudServiceID(rawValue: rawValue) else {
            preconditionFailure("Missing cloud service ID for \(rawValue)")
        }
        return serviceID
    }

    init?(serviceID: CloudServiceID) {
        self.init(rawValue: serviceID.rawValue)
    }

    /// Picker order is owned by the cloud service catalog.
    static var allCases: [Self] {
        CloudServiceCatalog.definitions(for: .transcription).compactMap {
            Self(serviceID: $0.id)
        }
    }

}

/// One definition per selectable cloud service. It owns selection metadata only;
/// concrete providers continue to own their explicit request contracts.
struct CloudServiceDefinition: Identifiable, Hashable {
    let id: CloudServiceID
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

    /// Existing callers and persisted picker values use this name. Keep it as
    /// a compatibility view while `CloudServiceID` becomes the catalog key.
    var preset: CloudTranscriptionPreset {
        guard let preset = CloudTranscriptionPreset(serviceID: id) else {
            preconditionFailure("Missing transcription preset for \(id.rawValue)")
        }
        return preset
    }

    var supportsModelDiscovery: Bool {
        transportKind == .openAICompatible
    }

    func supports(_ workload: CloudServiceWorkload) -> Bool {
        switch workload {
        case .transcription:
            return true
        case .textProcessing:
            return supportsTextProcessing
        }
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
}

/// The single source of truth for selectable cloud-service metadata and order.
enum CloudServiceCatalog {
    static let all: [CloudServiceDefinition] = [
        CloudServiceDefinition(
            id: .alibaba,
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
        ),
        CloudServiceDefinition(
            id: .elevenLabs,
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
        ),
        CloudServiceDefinition(
            id: .gemini,
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
        ),
        CloudServiceDefinition(
            id: .groq,
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
        ),
        CloudServiceDefinition(
            id: .openAI,
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
        ),
        CloudServiceDefinition(
            id: .siliconFlow,
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
        ),
        CloudServiceDefinition(
            id: .custom,
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
    ]

    static func definitions(for workload: CloudServiceWorkload) -> [CloudServiceDefinition] {
        all.filter { $0.supports(workload) }
    }

    static func definition(for id: CloudServiceID) -> CloudServiceDefinition {
        guard let definition = all.first(where: { $0.id == id }) else {
            preconditionFailure("Missing cloud service definition for \(id.rawValue)")
        }
        return definition
    }

    static func defaultDefinition(
        for backendProvider: TranscriptionProvider
    ) -> CloudServiceDefinition? {
        // `.openAI` backs several built-in services and Custom. The official
        // OpenAI definition remains the legacy default for this backend.
        if backendProvider == .openAI || backendProvider == .custom {
            return definition(for: .openAI)
        }
        return all.first { definition in
            definition.backendProvider == backendProvider && definition.id != .custom
        }
    }

    static func inferred(
        backendProvider: TranscriptionProvider,
        compatibleBaseURL: String
    ) -> CloudServiceDefinition {
        guard backendProvider == .openAI || backendProvider == .custom else {
            return defaultDefinition(for: backendProvider) ?? definition(for: .openAI)
        }

        let identity = OpenAICompatibleRequestBuilder.connectionIdentity(
            baseURLString: compatibleBaseURL
        )
        return definitions(for: .transcription).first { definition in
            definition.transportKind == .openAICompatible
                && !definition.endpoint.isEditable
                && OpenAICompatibleRequestBuilder.connectionIdentity(
                    baseURLString: definition.endpoint.defaultURLString
                ) == identity
        } ?? definition(for: .custom)
    }

    static func enabled(
        isPluginEnabled: (PluginID) -> Bool
    ) -> [CloudServiceDefinition] {
        // A Custom endpoint is configured by the user rather than supplied by
        // an integrated provider plugin. Keep it available even in a profile
        // that disables every built-in cloud provider.
        all.filter { $0.id == .custom || isPluginEnabled($0.requiredPlugin) }
    }
}

/// Identifies how a text-processing connection was selected. Transcription
/// always uses the current transcription service; text can either reuse it or
/// select its own service.
enum CloudConnectionSource: Hashable {
    case transcriptionService
    case separateTextService
}

enum CloudConnectionModelSelection: Hashable {
    case automatic(String)
    case fixed(String)
    case disabled

    var modelID: String? {
        switch self {
        case let .automatic(modelID), let .fixed(modelID):
            return modelID
        case .disabled:
            return nil
        }
    }

    var isEnabled: Bool {
        self != .disabled
    }

    var configurationComponent: String {
        switch self {
        case let .automatic(modelID):
            return "automatic:\(modelID)"
        case let .fixed(modelID):
            return "fixed:\(modelID)"
        case .disabled:
            return "disabled"
        }
    }
}

enum CloudConnectionCredentialScope: Hashable {
    case openAICompatible(OpenAICompatibleCredentialScope)
    case native(CloudProviderCredential)

    var openAICompatibleScope: OpenAICompatibleCredentialScope? {
        guard case let .openAICompatible(scope) = self else {
            return nil
        }
        return scope
    }
}

enum CloudConnectionVerification: Hashable {
    case notRequired
    case required
    case verified

    var permitsRealRequests: Bool {
        self != .required
    }
}

/// The resolved, runtime-only connection for one cloud workload. It is derived
/// from the legacy `AppSettings` fields so introducing it does not migrate user
/// settings or Keychain records.
struct ResolvedCloudConnection: Hashable {
    let workload: CloudServiceWorkload
    let source: CloudConnectionSource
    let service: CloudServiceDefinition
    let endpoint: String
    let credentialScope: CloudConnectionCredentialScope
    let modelSelection: CloudConnectionModelSelection
    let verification: CloudConnectionVerification

    var backendProvider: TranscriptionProvider {
        service.backendProvider
    }

    var supportsModelDiscovery: Bool {
        service.supportsModelDiscovery
    }

    var isOpenAICompatible: Bool {
        service.transportKind == .openAICompatible
    }

    var configurationID: String {
        let endpointIdentity = isOpenAICompatible
            ? OpenAICompatibleRequestBuilder.connectionIdentity(baseURLString: endpoint)
            : endpoint
        return [
            workload == .transcription ? "transcription" : "text",
            service.id.rawValue,
            endpointIdentity,
            modelSelection.configurationComponent
        ].joined(separator: "\u{1F}")
    }

    /// Identifies the connection that owns discovery results. It intentionally
    /// excludes the selected model: changing models must cancel an in-flight
    /// test, but it should not discard the model list for the same endpoint.
    var discoveryConfigurationID: String {
        let endpointIdentity = isOpenAICompatible
            ? OpenAICompatibleRequestBuilder.connectionIdentity(baseURLString: endpoint)
            : endpoint
        let sourceComponent = source == .transcriptionService
            ? "transcriptionService"
            : "separateTextService"
        return [
            workload == .transcription ? "transcription" : "text",
            sourceComponent,
            service.id.rawValue,
            endpointIdentity
        ].joined(separator: "\u{1F}")
    }
}

extension AppSettings {
    var resolvedCloudTranscriptionConnection: ResolvedCloudConnection? {
        resolvedCloudConnection(for: .transcription)
    }

    var resolvedCloudTextConnection: ResolvedCloudConnection? {
        resolvedCloudConnection(for: .textProcessing)
    }

    func resolvedCloudConnection(
        for workload: CloudServiceWorkload
    ) -> ResolvedCloudConnection? {
        switch workload {
        case .transcription:
            return resolveCloudTranscriptionConnection()
        case .textProcessing:
            return resolveCloudTextConnection()
        }
    }

    private func resolveCloudTranscriptionConnection() -> ResolvedCloudConnection? {
        guard provider != .local else {
            return nil
        }

        let service = CloudServiceCatalog.definition(
            for: effectiveCloudTranscriptionPreset.serviceID
        )
        let endpoint = resolvedEndpoint(
            for: service,
            configuredOpenAIBaseURL: openAIBaseURL
        )
        let modelSelection = transcriptionModelSelection(for: service)
        return ResolvedCloudConnection(
            workload: .transcription,
            source: .transcriptionService,
            service: service,
            endpoint: endpoint,
            credentialScope: credentialScope(for: service, endpoint: endpoint),
            modelSelection: modelSelection,
            verification: customVerification(
                workload: .transcription,
                service: service,
                endpoint: endpoint,
                modelSelection: modelSelection
            )
        )
    }

    private func resolveCloudTextConnection() -> ResolvedCloudConnection? {
        let service: CloudServiceDefinition
        let source: CloudConnectionSource
        let endpoint: String

        if cloudTextUsesTranscriptionService {
            guard let transcription = resolvedCloudTranscriptionConnection,
                  transcription.service.supports(.textProcessing) else {
                return nil
            }
            service = transcription.service
            source = .transcriptionService
            endpoint = transcription.endpoint
        } else {
            service = cloudTextServicePreset.definition
            source = .separateTextService
            // Built-in services own their endpoint. The editable endpoint belongs
            // only to the Custom service; otherwise switching a text service could
            // accidentally keep sending requests to a previous custom relay.
            endpoint = service.endpoint.isEditable
                ? resolvedEndpoint(
                    for: service,
                    configuredOpenAIBaseURL: cloudTextOpenAIBaseURL
                )
                : service.endpoint.defaultURLString
        }

        let modelSelection = textModelSelection(for: service, source: source)
        return ResolvedCloudConnection(
            workload: .textProcessing,
            source: source,
            service: service,
            endpoint: endpoint,
            credentialScope: credentialScope(for: service, endpoint: endpoint),
            modelSelection: modelSelection,
            verification: customVerification(
                workload: .textProcessing,
                service: service,
                endpoint: endpoint,
                modelSelection: modelSelection
            )
        )
    }

    private func resolvedEndpoint(
        for service: CloudServiceDefinition,
        configuredOpenAIBaseURL: String
    ) -> String {
        guard service.transportKind == .openAICompatible else {
            return service.endpoint.defaultURLString
        }

        return configuredOpenAIBaseURL
    }

    private func transcriptionModelSelection(
        for service: CloudServiceDefinition
    ) -> CloudConnectionModelSelection {
        guard service.transportKind == .openAICompatible else {
            return .fixed(service.fixedTranscriptionModelID ?? effectiveModel)
        }

        if openAITranscriptionModelSelectionMode == .automatic {
            return .automatic(effectiveModel)
        }
        return .fixed(effectiveModel)
    }

    private func textModelSelection(
        for service: CloudServiceDefinition,
        source: CloudConnectionSource
    ) -> CloudConnectionModelSelection {
        // This setting is the product-wide opt-out for optional cloud text
        // features, including when those features reuse Gemini.
        guard openAITextModelSelectionMode != .disabled else {
            return .disabled
        }

        if service.backendProvider == .gemini {
            let modelID: String
            if source == .transcriptionService {
                // Reuse means exactly that: text follows the selected
                // transcription model, not the separate Gemini-text choice.
                modelID = effectiveModel
            } else {
                modelID = GeminiTranscriptionService.modelIDs.contains(cloudTextGeminiModel)
                    ? cloudTextGeminiModel
                    : GeminiTranscriptionService.defaultModelID
            }
            return .fixed(modelID)
        }

        switch openAITextModelSelectionMode {
        case .automatic:
            return .automatic(effectiveOpenAICompatibleTextModel)
        case .fixed:
            return .fixed(effectiveOpenAICompatibleTextModel)
        case .disabled:
            // Covered by the early return above; retain exhaustiveness as the
            // persisted enum remains part of the settings contract.
            return .disabled
        }
    }

    private func credentialScope(
        for service: CloudServiceDefinition,
        endpoint: String
    ) -> CloudConnectionCredentialScope {
        switch service.credential {
        case .openAICompatible:
            return .openAICompatible(
                OpenAICompatibleCredentialScope(baseURLString: endpoint)
            )
        case .gemini, .elevenLabs, .alibaba:
            return .native(service.credential)
        }
    }

    private func customVerification(
        workload: CloudServiceWorkload,
        service: CloudServiceDefinition,
        endpoint: String,
        modelSelection: CloudConnectionModelSelection
    ) -> CloudConnectionVerification {
        guard service.id == .custom,
              let modelID = modelSelection.modelID else {
            return .notRequired
        }

        if workload == .transcription,
           (try? OpenAIModelCatalog.validatedFixedTranscriptionModelID(modelID)) == nil {
            // The transcription adapter reports the invalid model ID before it
            // can upload audio. Preserve that existing validation behavior.
            return .notRequired
        }

        let profile = customOpenAIEndpointProfiles[
            OpenAICompatibleRequestBuilder.connectionIdentity(baseURLString: endpoint)
        ]
        let isVerified: Bool
        switch workload {
        case .transcription:
            isVerified = profile?.verifiedTranscriptionModelID == modelID
        case .textProcessing:
            isVerified = profile?.verifiedTextModelID == modelID
        }
        return isVerified ? .verified : .required
    }
}

/// A user intent that changes which cloud connection owns a workload. This is
/// deliberately independent from `AppState`: it can preserve Custom profiles
/// and describe the resulting invalidation without touching Keychain or UI
/// state.
enum CloudConnectionSettingsAction: Hashable {
    case selectLocalTranscription
    case selectTranscriptionService(CloudTranscriptionPreset)
    case updateCustomTranscriptionEndpoint(String)
    case setTextServiceReuse(Bool)
    case selectTextService(CloudTextServicePreset)
    case updateCustomTextEndpoint(String)
}

/// The observable connection change produced by a settings transition.
/// `AppState` uses this to cancel obsolete tests and invalidate only the model
/// availability data that belongs to a different endpoint.
struct CloudConnectionTransition: Equatable {
    let previousTranscriptionConfigurationID: String?
    let transcriptionConfigurationID: String?
    let previousTranscriptionDiscoveryConfigurationID: String?
    let transcriptionDiscoveryConfigurationID: String?
    let previousTextConfigurationID: String?
    let textConfigurationID: String?
    let previousTextDiscoveryConfigurationID: String?
    let textDiscoveryConfigurationID: String?

    var transcriptionChanged: Bool {
        previousTranscriptionConfigurationID != transcriptionConfigurationID
    }

    var transcriptionDiscoveryChanged: Bool {
        previousTranscriptionDiscoveryConfigurationID
            != transcriptionDiscoveryConfigurationID
    }

    var textChanged: Bool {
        previousTextConfigurationID != textConfigurationID
    }

    var textDiscoveryChanged: Bool {
        previousTextDiscoveryConfigurationID != textDiscoveryConfigurationID
    }
}

/// Owns the pure settings transition for service selection and Custom endpoint
/// switching. Credentials remain in Keychain and request work remains in
/// provider adapters; this coordinator only preserves user choices and emits
/// the identity changes that matter to UI-owned asynchronous state.
enum CloudConnectionSettingsCoordinator {
    @discardableResult
    static func apply(
        _ action: CloudConnectionSettingsAction,
        to settings: inout AppSettings
    ) -> CloudConnectionTransition {
        let previousSettings = settings

        switch action {
        case .selectLocalTranscription:
            saveCurrentCustomProfiles(in: &settings)
            settings.provider = .local

        case let .selectTranscriptionService(preset):
            selectTranscriptionService(preset, in: &settings)

        case let .updateCustomTranscriptionEndpoint(baseURL):
            saveCurrentCustomProfiles(in: &settings)
            settings.provider = .openAI
            settings.openAIBaseURL = baseURL
            settings.lastCustomOpenAIBaseURL = baseURL
            settings.openAIUsesCustomEndpoint = true
            restoreCurrentCustomProfiles(in: &settings)

        case let .setTextServiceReuse(usesTranscriptionService):
            saveCurrentCustomProfiles(in: &settings)
            settings.cloudTextUsesTranscriptionService = usesTranscriptionService
            restoreCurrentCustomProfiles(in: &settings)

        case let .selectTextService(preset):
            selectTextService(preset, in: &settings)

        case let .updateCustomTextEndpoint(baseURL):
            saveCurrentCustomProfiles(in: &settings)
            settings.cloudTextUsesTranscriptionService = false
            settings.cloudTextServicePreset = .custom
            settings.cloudTextOpenAIBaseURL = baseURL
            settings.lastCustomCloudTextOpenAIBaseURL = baseURL
            restoreCurrentCustomProfiles(in: &settings)
        }

        return transition(from: previousSettings, to: settings)
    }

    static func transition(
        from previousSettings: AppSettings,
        to settings: AppSettings
    ) -> CloudConnectionTransition {
        let previousTranscription = previousSettings.resolvedCloudTranscriptionConnection
        let previousText = previousSettings.resolvedCloudTextConnection
        let transcription = settings.resolvedCloudTranscriptionConnection
        let text = settings.resolvedCloudTextConnection
        return CloudConnectionTransition(
            previousTranscriptionConfigurationID: previousTranscription?.configurationID,
            transcriptionConfigurationID: transcription?.configurationID,
            previousTranscriptionDiscoveryConfigurationID:
                previousTranscription?.discoveryConfigurationID,
            transcriptionDiscoveryConfigurationID: transcription?.discoveryConfigurationID,
            previousTextConfigurationID: previousText?.configurationID,
            textConfigurationID: text?.configurationID,
            previousTextDiscoveryConfigurationID: previousText?.discoveryConfigurationID,
            textDiscoveryConfigurationID: text?.discoveryConfigurationID
        )
    }

    private static func selectTranscriptionService(
        _ preset: CloudTranscriptionPreset,
        in settings: inout AppSettings
    ) {
        saveCurrentCustomProfiles(in: &settings)

        let service = CloudServiceCatalog.definition(for: preset.serviceID)
        settings.provider = service.backendProvider
        guard service.transportKind == .openAICompatible else {
            return
        }

        if service.endpoint.isEditable {
            let savedBaseURL = settings.lastCustomOpenAIBaseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
            settings.openAIBaseURL = savedBaseURL.isEmpty
                ? AppSettings.defaultOpenAIBaseURL
                : savedBaseURL
            settings.openAIUsesCustomEndpoint = true
            settings.openAIOrganizationID = ""
            settings.openAIProjectID = ""
            restoreCurrentCustomProfiles(in: &settings)
            return
        }

        settings.openAIBaseURL = service.endpoint.defaultURLString
        settings.openAIUsesCustomEndpoint = false
        settings.openAIOrganizationID = ""
        settings.openAIProjectID = ""
        settings.openAITranscriptionModelSelectionMode = .automatic
        settings.automaticOpenAITranscriptionModel = service.automaticTranscriptionModelID
            ?? OpenAIModelCatalog.defaultTranscriptionModelID
    }

    private static func selectTextService(
        _ preset: CloudTextServicePreset,
        in settings: inout AppSettings
    ) {
        saveCurrentCustomProfiles(in: &settings)

        let service = preset.definition
        settings.cloudTextUsesTranscriptionService = false
        settings.cloudTextServicePreset = preset
        guard service.transportKind == .openAICompatible else {
            return
        }

        if service.endpoint.isEditable {
            let savedBaseURL = settings.lastCustomCloudTextOpenAIBaseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
            settings.cloudTextOpenAIBaseURL = savedBaseURL.isEmpty
                ? AppSettings.defaultOpenAIBaseURL
                : savedBaseURL
            restoreCurrentCustomProfiles(in: &settings)
            return
        }

        settings.cloudTextOpenAIBaseURL = service.endpoint.defaultURLString
        settings.openAITextModelSelectionMode = .automatic
        settings.automaticOpenAITextModel = service.automaticTextModelID
            ?? OpenAIModelCatalog.defaultTextModelID
    }

    private static func saveCurrentCustomProfiles(in settings: inout AppSettings) {
        settings.saveCurrentCustomOpenAITranscriptionProfile()
        settings.saveCurrentCustomOpenAICloudTextProfile()
    }

    private static func restoreCurrentCustomProfiles(in settings: inout AppSettings) {
        settings.restoreCustomOpenAITranscriptionProfile()
        settings.restoreCustomOpenAICloudTextProfile()
    }
}
