import SwiftUI

private enum CloudTextModelPickerSelection: Hashable {
    case automatic
    case fixed(String)
}

struct LLMRequirementBadge: View {
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            Text("AI")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PostProcessingView: View {
    enum Presentation {
        case complete
        case architectureProcessing
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSearchTarget: SettingsSearchTarget?
    @State private var highlightedSearchRequestID: UUID?
    @State private var isConfirmingCloudTextRelayTest = false

    private let presentation: Presentation
    private let navigationSection: AppPanelSection

    init(
        presentation: Presentation = .complete,
        navigationSection: AppPanelSection = .postProcessing
    ) {
        self.presentation = presentation
        self.navigationSection = navigationSection
    }

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    private var isCloudTextAIAvailable: Bool {
        CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: appState.settings)
    }

    private var cloudTextAIUnavailableDetail: String {
        appState.settings.provider == .local
            ? localizer.cloudAIUnavailableInLocalModeDetail()
            : localizer.disabledOpenAITextModelHint()
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                switch presentation {
                case .complete:
                    processingSections(
                        includesArchitectureAI: false
                    )
                case .architectureProcessing:
                    processingSections(
                        includesArchitectureAI: true
                    )
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: appState.settingsNavigationRequest?.id) {
                await handleSettingsNavigation(using: proxy)
            }
        }
    }

    @ViewBuilder
    private func processingSections(
        includesArchitectureAI: Bool
    ) -> some View {
        if includesArchitectureAI {
            transcriptRetouchSection
        }

        correctionRulesSection

        emojiOutputSection(includesAIResolver: includesArchitectureAI)
        punctuationAndFormattingSection
    }

    @ViewBuilder
    private var transcriptRetouchSection: some View {
        Section {
            featureToggle(
                title: localizer.text(.transcriptRetouch),
                detail: localizer.text(.transcriptRetouchHint),
                pluginIDs: [.outputLLMRetouch],
                target: .featureTranscriptRetouch,
                requiresLLM: true,
                isAvailable: true,
                isRuntimeEnabled: { appState.settings.transcriptRetouchEnabled }
            ) { isEnabled in
                appState.settings.transcriptRetouchEnabled = isEnabled
                if isEnabled,
                   appState.settings.openAITextModelSelectionMode == .disabled {
                    appState.settings.openAITextModelSelectionMode = .automatic
                }
            }

            if appState.settings.transcriptRetouchEnabled {
                transcriptRetouchCloudConfiguration
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

        } header: {
            SettingsSectionHeader(
                title: localizer.transcriptionEnhancementsLabel(),
                target: .featureTranscriptRetouch
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.transcriptRetouchEnabled
        )
        .alert(
            localizer.cloudTextRelayTestConfirmationTitle(),
            isPresented: $isConfirmingCloudTextRelayTest
        ) {
            Button(localizer.cancelLabel(), role: .cancel) {}
            Button(localizer.testSelectedOpenAIModelLabel()) {
                appState.acknowledgeCloudTextRelayAndTestModel()
            }
        } message: {
            Text(localizer.cloudTextRelayTestConfirmationDetail())
        }
    }

    @ViewBuilder
    private var transcriptRetouchCloudConfiguration: some View {
        Toggle(localizer.useSameCloudServiceLabel(), isOn: $appState.settings.cloudTextUsesTranscriptionService)
            .onChange(of: appState.settings.cloudTextUsesTranscriptionService) {
                appState.cloudTextConnectionConfigurationDidChange()
            }

        if appState.settings.cloudTextUsesTranscriptionService,
           appState.settings.cloudTextServiceProvider == nil {
            SettingsRowFeedback(
                text: localizer.sameCloudTextServiceUnavailableDetail(),
                style: .warning
            )
        }

        if !appState.settings.cloudTextUsesTranscriptionService {
            Picker(localizer.cloudServiceLabel(), selection: cloudTextServicePreset) {
                ForEach(CloudTextServicePreset.allCases) { preset in
                    Text(localizer.cloudTextServicePresetName(preset)).tag(preset)
                }
            }

            cloudTextConnectionControls
        }

        cloudTextModelControls
            .onAppear {
                appState.loadCloudTextCredentialsIfNeeded()
            }
    }

    @ViewBuilder
    private var cloudTextConnectionControls: some View {
        switch appState.settings.cloudTextServicePreset {
        case .openAI, .groq, .siliconFlow, .custom:
            let preset = appState.settings.cloudTextServicePreset
            TextField(
                localizer.text(.baseURL),
                text: cloudTextBaseURL,
                prompt: Text(AppSettings.defaultOpenAIBaseURL)
            )
            .textContentType(.URL)
            .disabled(preset != .custom)
            .onSubmit {
                appState.refreshCloudTextModels()
            }

            SecureField(localizer.text(.apiKey), text: Binding(
                get: { appState.cloudTextOpenAIAPIKey },
                set: { appState.updateCloudTextOpenAIAPIKey($0) }
            ))
            .onSubmit {
                appState.refreshCloudTextModels()
            }
            .onAppear {
                appState.loadCloudTextOpenAIAPIKeyIfNeeded()
            }

            Button(localizer.refreshOpenAIModelsLabel()) {
                appState.refreshCloudTextModels()
            }
            .disabled(
                appState.isRefreshingCloudTextModels
                    || appState.cloudTextOpenAIAPIKey.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            )

            if appState.isRefreshingCloudTextModels {
                SettingsRowFeedback(
                    text: localizer.refreshingOpenAIModels(),
                    showsProgress: true
                )
            } else if let error = appState.cloudTextModelAvailabilityError {
                SettingsRowFeedback(
                    text: localizer.openAIModelRefreshFailed(error),
                    style: .warning
                )
            }

        case .gemini:
            fixedBaseURLRow(CloudTranscriptionProviderConfiguration.gemini.endpoint.fixedURL!)
            SecureField(localizer.text(.apiKey), text: Binding(
                get: { appState.geminiAPIKey },
                set: { appState.updateGeminiAPIKey($0) }
            ))
            .onAppear {
                appState.loadGeminiAPIKeyIfNeeded()
            }
        }
    }

    private func fixedBaseURLRow(_ baseURL: URL) -> some View {
        TextField(localizer.text(.baseURL), text: .constant(baseURL.absoluteString))
            .textContentType(.URL)
            .disabled(true)
    }

    @ViewBuilder
    private var cloudTextModelControls: some View {
        if appState.settings.cloudTextUsesGemini {
            Picker(localizer.text(.model), selection: $appState.settings.cloudTextGeminiModel) {
                ForEach(GeminiTranscriptionService.modelIDs, id: \.self) { modelID in
                    Text(modelID).tag(modelID)
                }
            }
        } else if appState.settings.cloudTextServiceProvider == .openAI {
            Picker(selection: cloudTextModelSelection) {
                Text(localizer.automaticCloudTextModelLabel())
                    .tag(CloudTextModelPickerSelection.automatic)

                if !cloudTextModelOptions.isEmpty {
                    Divider()
                    ForEach(cloudTextModelOptions, id: \.self) { model in
                        Text(appState.cloudTextModelOptionLabel(model))
                            .tag(CloudTextModelPickerSelection.fixed(model))
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.text(.model))
                    if appState.settings.openAITextModelSelectionMode == .automatic {
                        Text(appState.openAIAutomaticTextModelMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Button(localizer.testSelectedOpenAIModelLabel()) {
            if appState.settings.cloudTextRequiresRelayAcknowledgement,
               !appState.settings.hasAcknowledgedCloudTextRelay {
                isConfirmingCloudTextRelayTest = true
            } else {
                appState.testCloudTextModel()
            }
        }
        .disabled(
            appState.isTestingCloudTextModel
                || !cloudTextHasAPIKey
                || appState.settings.cloudTextServiceProvider == nil
        )

        if let message = appState.cloudTextModelTestMessage {
            SettingsRowFeedback(
                text: message,
                style: appState.cloudTextModelTestSucceeded
                    ? .success
                    : (appState.cloudTextModelTestError == nil ? .neutral : .warning),
                showsProgress: appState.isTestingCloudTextModel
            )
        }
    }

    private var cloudTextServicePreset: Binding<CloudTextServicePreset> {
        Binding(
            get: { appState.settings.cloudTextServicePreset },
            set: { preset in
                var updatedSettings = appState.settings
                updatedSettings.cloudTextServicePreset = preset
                switch preset {
                case .openAI, .groq, .siliconFlow:
                    updatedSettings.cloudTextOpenAIBaseURL = preset.baseURL ?? AppSettings.defaultOpenAIBaseURL
                case .custom:
                    updatedSettings.cloudTextOpenAIBaseURL = updatedSettings
                        .lastCustomCloudTextOpenAIBaseURL
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if updatedSettings.cloudTextOpenAIBaseURL.isEmpty {
                        updatedSettings.cloudTextOpenAIBaseURL = AppSettings.defaultOpenAIBaseURL
                    }
                case .gemini:
                    break
                }
                appState.settings = updatedSettings
                appState.cloudTextConnectionConfigurationDidChange()
            }
        )
    }

    private var cloudTextBaseURL: Binding<String> {
        Binding(
            get: { appState.settings.cloudTextOpenAIBaseURL },
            set: { baseURL in
                var updatedSettings = appState.settings
                updatedSettings.cloudTextOpenAIBaseURL = baseURL
                if updatedSettings.cloudTextServicePreset == .custom {
                    updatedSettings.lastCustomCloudTextOpenAIBaseURL = baseURL
                }
                appState.settings = updatedSettings
                appState.cloudTextConnectionConfigurationDidChange()
            }
        )
    }

    private var cloudTextModelSelection: Binding<CloudTextModelPickerSelection> {
        Binding(
            get: {
                appState.settings.openAITextModelSelectionMode == .automatic
                    ? .automatic
                    : .fixed(appState.settings.fixedOpenAITextModel)
            },
            set: { selection in
                switch selection {
                case .automatic:
                    appState.settings.openAITextModelSelectionMode = .automatic
                    let availableModelIDs = appState.settings.cloudTextUsesTranscriptionService
                        ? appState.openAIAvailableModelIDs
                        : appState.cloudTextAvailableModelIDs
                    if let recommendedModelID = OpenAIModelCatalog.recommendedTextModelID(
                        availableModelIDs: availableModelIDs
                    ) {
                        appState.settings.automaticOpenAITextModel = recommendedModelID
                    }
                case let .fixed(modelID):
                    appState.settings.fixedOpenAITextModel = modelID
                    appState.settings.openAITextModelSelectionMode = .fixed
                }
            }
        )
    }

    private var cloudTextModelOptions: [String] {
        guard appState.settings.cloudTextServiceProvider == .openAI else {
            return []
        }

        let availableModelIDs: Set<String>
        let didRefresh: Bool
        if appState.settings.cloudTextUsesTranscriptionService {
            availableModelIDs = appState.openAIAvailableModelIDs
            didRefresh = appState.openAIModelAvailabilityFetchedAt != nil
        } else {
            availableModelIDs = appState.cloudTextAvailableModelIDs
            didRefresh = appState.cloudTextModelAvailabilityFetchedAt != nil
        }

        guard didRefresh else {
            return OpenAIModelCatalog.textModels.map(\.id)
        }
        return availableModelIDs
            .filter(OpenAIModelCatalog.supportsTextGeneration)
            .sorted()
    }

    private var cloudTextHasAPIKey: Bool {
        switch appState.settings.cloudTextServiceProvider {
        case .gemini:
            return !appState.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openAI:
            let apiKey = appState.settings.cloudTextUsesTranscriptionService
                ? appState.openAIAPIKey
                : appState.cloudTextOpenAIAPIKey
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .none, .some(.local), .some(.elevenLabs), .some(.alibaba), .some(.custom):
            return false
        }
    }

    @ViewBuilder
    private var correctionRulesSection: some View {
        Section {
            featureToggle(
                title: localizer.enableRulesLabel(),
                detail: localizer.text(.correctionRulesHint),
                pluginIDs: [.outputCustomCorrections],
                target: .featureCorrectionRules,
                isRuntimeEnabled: { appState.settings.useCustomCorrections }
            ) { isEnabled in
                appState.settings.useCustomCorrections = isEnabled
            }

            if appState.isPluginEnabled(.outputCustomCorrections),
               appState.settings.useCustomCorrections {
                ReplacementRulesEditor(
                    serializedRules: $appState.settings.customCorrections,
                    localizer: localizer
                )
                .settingsSearchAnchor(.customCorrections, highlightedTarget: highlightedSearchTarget)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.text(.correctionRules),
                target: .featureCorrectionRules
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.useCustomCorrections
        )
    }

    @ViewBuilder
    private func emojiOutputSection(includesAIResolver: Bool) -> some View {
        Section {
            featureToggle(
                title: localizer.enableEmojiOutputLabel(),
                detail: localizer.text(.emojiReplacementHint),
                pluginIDs: [.outputEmoji],
                target: .featureEmojiOutput,
                isRuntimeEnabled: { appState.settings.emojiPostProcessingEnabled }
            ) { isEnabled in
                appState.settings.emojiPostProcessingEnabled = isEnabled
            }

            if appState.isPluginEnabled(.outputEmoji),
               appState.settings.emojiPostProcessingEnabled {
                Toggle(isOn: $appState.settings.smartEmojiMatchingAfterTranscription) {
                    SettingsRowLabel(
                        title: localizer.text(.smartEmojiMatching),
                        detail: localizer.text(.smartEmojiMatchingHint)
                    )
                }
                .settingsSearchAnchor(.smartEmojiMatching, highlightedTarget: highlightedSearchTarget)

                if includesAIResolver {
                    Toggle(isOn: Binding(
                        get: {
                            isCloudTextAIAvailable
                                && appState.settings.aiEmojiResolverEnabled
                        },
                        set: { appState.settings.aiEmojiResolverEnabled = $0 }
                    )) {
                        SettingsRowLabel(
                            title: localizer.text(.aiEmojiResolver),
                            detail:
                                !isCloudTextAIAvailable
                                    ? cloudTextAIUnavailableDetail
                                    : localizer.text(.aiEmojiResolverHint)
                        ) {
                            LLMRequirementBadge(
                                accessibilityLabel: localizer.requiresCloudAILabel()
                            )
                        }
                    }
                    .disabled(!isCloudTextAIAvailable)
                    .settingsSearchAnchor(.aiEmojiResolver, highlightedTarget: highlightedSearchTarget)
                }
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.text(.emojiOutput),
                target: .featureEmojiOutput
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.emojiPostProcessingEnabled
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.aiEmojiResolverEnabled
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.provider
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.openAITextModelSelectionMode
        )
    }

    @ViewBuilder
    private var punctuationAndFormattingSection: some View {
        Section {
            if !appState.isPluginEnabled(.outputCleanup) {
                featureToggle(
                    title: localizer.enableTextCleanupLabel(),
                    detail: localizer.outputCleanupFeatureDetail(),
                    pluginIDs: [.outputCleanup],
                    target: .featureTextCleanup
                )
            } else {
                LabeledContent {
                    Picker(
                        localizer.text(.punctuationHandling),
                        selection: $appState.settings.punctuationPostProcessingMode
                    ) {
                        ForEach(PunctuationPostProcessingMode.allCases) { mode in
                            Text(punctuationModeTitle(mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } label: {
                    SettingsRowLabel(
                        title: localizer.text(.punctuationHandling),
                        detail: localizer.punctuationModeDetail(
                            appState.settings.punctuationPostProcessingMode
                        )
                    )
                }
                .settingsSearchAnchor(.punctuationHandling, highlightedTarget: highlightedSearchTarget)

                LabeledContent {
                    Picker(
                        localizer.text(.afterEachTranscription),
                        selection: Binding(
                            get: { appState.settings.transcriptInsertionBoundaryMode },
                            set: { appState.settings.setTranscriptInsertionBoundaryMode($0) }
                        )
                    ) {
                        Text(localizer.text(.smartSpaceRecommended))
                            .tag(TranscriptInsertionBoundaryMode.smartSpace)
                        Text(localizer.text(.newLine))
                            .tag(TranscriptInsertionBoundaryMode.newline)
                        Text(localizer.text(.addNothing))
                            .tag(TranscriptInsertionBoundaryMode.none)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 450)
                } label: {
                    SettingsRowLabel(
                        title: localizer.text(.afterEachTranscription),
                        detail: localizer.transcriptBoundaryModeDetail(
                            appState.settings.transcriptInsertionBoundaryMode
                        )
                    )
                }
                .settingsSearchAnchor(
                    .transcriptBoundary,
                    highlightedTarget: highlightedSearchTarget
                )
                if appState.settings.includesEnglishTranscription {
                    Toggle(
                        localizer.text(.lowercaseEnglish),
                        isOn: $appState.settings.lowercaseEnglishAfterTranscription
                    )
                    .settingsSearchAnchor(
                        .lowercaseEnglish,
                        highlightedTarget: highlightedSearchTarget
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if appState.settings.includesChineseTranscription,
                   appState.settings.includesEnglishTranscription {
                    Toggle(
                        localizer.text(.insertSpaceBetweenChineseAndEnglish),
                        isOn: $appState.settings.insertSpaceBetweenChineseAndEnglish
                    )
                    .settingsSearchAnchor(
                        .insertChineseEnglishSpace,
                        highlightedTarget: highlightedSearchTarget
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if appState.settings.includesChineseTranscription {
                Group {
                    featureToggle(
                        title: localizer.enableChineseConversionLabel(),
                        detail: localizer.text(.chineseTextConversionHint),
                        pluginIDs: [.outputChineseConversion],
                        target: .featureChineseConversion,
                        onChange: { isEnabled in
                            guard isEnabled else {
                                return
                            }
                            appState.settings.setPreferredChineseTextConversionMode(
                                appState.settings.resolvedChineseTextConversionMode
                            )
                        }
                    )

                    if appState.isPluginEnabled(.outputChineseConversion) {
                        Picker(
                            localizer.text(.chineseTextConversion),
                            selection: Binding(
                                get: {
                                    appState.settings.resolvedChineseTextConversionMode
                                },
                                set: { mode in
                                    appState.settings.setPreferredChineseTextConversionMode(mode)
                                }
                            )
                        ) {
                            ForEach(ChineseTextConversionMode.explicitCases) { mode in
                                Text(chineseTextConversionModeTitle(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsSearchAnchor(
                            .chineseTextConversion,
                            highlightedTarget: highlightedSearchTarget
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.text(.textCleanup),
                target: .featureTextCleanup
            )
        }
        .settingsSearchAnchor(
            .featureTextCleanup,
            highlightedTarget: highlightedSearchTarget
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.isPluginEnabled(.outputCleanup)
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.isPluginEnabled(.outputChineseConversion)
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.includesEnglishTranscription
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.includesChineseTranscription
        )
    }

    private func featureToggle(
        title: String,
        detail: String,
        pluginIDs: [PluginID],
        target: SettingsSearchTarget,
        requiresLLM: Bool = false,
        isAvailable: Bool = true,
        isRuntimeEnabled: @escaping () -> Bool = { true },
        onChange: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: {
                    isAvailable
                        && pluginIDs.contains(where: appState.isPluginEnabled)
                        && isRuntimeEnabled()
                },
                set: { isEnabled in
                    for pluginID in pluginIDs {
                        appState.setPluginEnabled(pluginID, isEnabled: isEnabled)
                    }
                    onChange(isEnabled)
                }
            )
        ) {
            SettingsRowLabel(
                title: title,
                detail: requiresLLM && !isAvailable ? cloudTextAIUnavailableDetail : detail
            ) {
                if requiresLLM {
                    LLMRequirementBadge(
                        accessibilityLabel: localizer.requiresCloudAILabel()
                    )
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(!isAvailable)
        .settingsSearchAnchor(target, highlightedTarget: highlightedSearchTarget)
    }

    @MainActor
    private func handleSettingsNavigation(using proxy: ScrollViewProxy) async {
        guard let request = appState.settingsNavigationRequest,
              request.section == navigationSection else {
            return
        }

        switch presentation {
        case .architectureProcessing:
            guard request.target.pipelinePlacement?.stage == .postProcessing else {
                return
            }
        case .complete:
            break
        }

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else {
            return
        }

        highlightedSearchTarget = request.target
        highlightedSearchRequestID = request.id
        if reduceMotion {
            proxy.scrollTo(request.target, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(request.target, anchor: .center)
            }
        }
        appState.consumeSettingsNavigationRequest(id: request.id)

        let requestID = request.id
        let target = request.target
        let shouldReduceMotion = reduceMotion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            guard highlightedSearchRequestID == requestID,
                  highlightedSearchTarget == target else {
                return
            }
            if shouldReduceMotion {
                highlightedSearchTarget = nil
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    highlightedSearchTarget = nil
                }
            }
        }
    }

    private func punctuationModeTitle(_ mode: PunctuationPostProcessingMode) -> String {
        switch mode {
        case .automatic:
            return localizer.text(.automaticPunctuationRecommended)
        case .keep:
            return localizer.text(.asTranscribed)
        case .replaceWithSpaces:
            return localizer.text(.replacePunctuationWithSpaces)
        }
    }

    private func chineseTextConversionModeTitle(_ mode: ChineseTextConversionMode) -> String {
        switch mode {
        case .keep:
            return localizer.text(.keepChineseText)
        case .simplified:
            return localizer.text(.convertChineseToSimplified)
        case .traditional:
            return localizer.text(.convertChineseToTraditional)
        }
    }
}

/// A compact editor for fixed text-replacement rules.
private struct ReplacementRulesEditor: View {
    private enum FocusedField: Hashable {
        case source(UUID)
        case replacement(UUID)
    }

    @Binding private var serializedRules: String
    @State private var document: FixedReplacementDocument
    @State private var showsInvalidLines = false
    @FocusState private var focusedField: FocusedField?

    private let localizer: AppLocalizer
    init(
        serializedRules: Binding<String>,
        localizer: AppLocalizer
    ) {
        _serializedRules = serializedRules
        _document = State(
            initialValue: FixedReplacementDocument(serialized: serializedRules.wrappedValue)
        )
        self.localizer = localizer
    }

    var body: some View {
        SettingsCollection(addLabel: addLabel, addAction: addRule) {
            if document.rules.isEmpty {
                SettingsCollectionEmptyRow(text: emptyLabel)
            } else {
                ForEach(Array(document.rules.enumerated()), id: \.element.id) { index, rule in
                    replacementRow(rule)
                        .padding(.vertical, 7)

                    if index < document.rules.count - 1 {
                        Divider()
                    }
                }
            }

            if !document.invalidLines.isEmpty {
                Divider()
                invalidLinesSection
                    .padding(.vertical, 7)
            }
        }
        .onChange(of: serializedRules) { _, updatedRules in
            guard updatedRules != document.serialized else {
                return
            }
            document = FixedReplacementDocument(serialized: updatedRules)
        }
    }

    @ViewBuilder
    private func replacementRow(_ rule: FixedReplacementRuleDraft) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            horizontalReplacementRow(rule)

            if rule.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !rule.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsRowFeedback(text: sourceRequiredLabel, style: .error)
            }
        }
    }

    private func horizontalReplacementRow(_ rule: FixedReplacementRuleDraft) -> some View {
        HStack(spacing: 10) {
            sourceField(rule)
                .frame(minWidth: 140, maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .accessibilityHidden(true)

            replacementField(rule)
                .frame(minWidth: 140, maxWidth: .infinity)

            deleteButton(rule)
        }
    }

    private func sourceField(_ rule: FixedReplacementRuleDraft) -> some View {
        TextField(
            sourcePlaceholder,
            text: sourceBinding(for: rule.id)
        )
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: .source(rule.id))
        .onSubmit {
            focusedField = .replacement(rule.id)
        }
        .accessibilityLabel(sourceLabel)
    }

    private func replacementField(_ rule: FixedReplacementRuleDraft) -> some View {
        TextField(
            valuePlaceholder,
            text: replacementBinding(for: rule.id)
        )
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: .replacement(rule.id))
        .onSubmit {
            if rule.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focusedField = .source(rule.id)
            } else {
                addRule()
            }
        }
        .accessibilityLabel(valueLabel)
    }

    private func deleteButton(_ rule: FixedReplacementRuleDraft) -> some View {
        Button {
            removeRule(rule.id)
        } label: {
            Image(systemName: "trash")
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .help(deleteLabel)
        .accessibilityLabel(deleteLabel)
    }

    private var invalidLinesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                SettingsRowFeedback(
                    text: localizer.unrecognizedReplacementLinesLabel(
                        document.invalidLines.count
                    ),
                    style: .warning
                )
                Spacer()
                Button(
                    showsInvalidLines
                        ? localizer.hideLegacyReplacementLinesLabel()
                        : localizer.showLegacyReplacementLinesLabel()
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsInvalidLines.toggle()
                    }
                }
                .buttonStyle(.borderless)
            }

            if showsInvalidLines {
                SettingsRowFeedback(
                    text: localizer.legacyReplacementLinesHint()
                )

                ForEach(document.invalidLines) { line in
                    HStack(spacing: 8) {
                        Text(line.raw)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            document.removePreservedLine(id: line.id)
                            persistDocument()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(localizer.text(.delete))
                        .accessibilityLabel(localizer.text(.delete))
                    }
                }
            }
        }
    }

    private func sourceBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                document.rules.first(where: { $0.id == id })?.source ?? ""
            },
            set: { updatedSource in
                document.updateRule(id: id, source: updatedSource)
                persistDocument()
            }
        )
    }

    private func replacementBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                document.rules.first(where: { $0.id == id })?.replacement ?? ""
            },
            set: { updatedReplacement in
                document.updateRule(id: id, replacement: updatedReplacement)
                persistDocument()
            }
        )
    }

    private func addRule() {
        let id = document.addRule()
        focusedField = .source(id)
    }

    private func removeRule(_ id: UUID) {
        if focusedField == .source(id) || focusedField == .replacement(id) {
            focusedField = nil
        }
        document.removeRule(id: id)
        persistDocument()
    }

    private func persistDocument() {
        let updatedRules = document.serialized
        if serializedRules != updatedRules {
            serializedRules = updatedRules
        }
    }

    private var sourceLabel: String {
        localizer.fixedReplacementSourceLabel()
    }

    private var sourcePlaceholder: String {
        localizer.fixedReplacementSourcePlaceholder()
    }

    private var valueLabel: String {
        localizer.fixedReplacementValueLabel()
    }

    private var valuePlaceholder: String {
        localizer.fixedReplacementValuePlaceholder()
    }

    private var addLabel: String {
        localizer.addFixedReplacementLabel()
    }

    private var deleteLabel: String {
        localizer.deleteFixedReplacementLabel()
    }

    private var emptyLabel: String {
        localizer.noFixedReplacementsLabel()
    }

    private var sourceRequiredLabel: String {
        localizer.fixedReplacementSourceRequiredLabel()
    }
}

struct PromptConfigurationSections: View {
    @EnvironmentObject private var appState: AppState

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    private var isUnavailableForSenseVoice: Bool {
        appState.settings.usesSenseVoiceLocalTranscription
    }

    var body: some View {
        if appState.isPluginEnabled(.smartPromptContext) {
            Section {
                if isUnavailableForSenseVoice {
                    SettingsRowFeedback(text: localizer.senseVoiceVocabularyUnavailableDetail())
                } else {
                    SettingsCollection(
                        addLabel: localizer.text(.addPromptContext),
                        addAction: addPromptContext
                    ) {
                        if appState.settings.promptContextItems.isEmpty {
                            SettingsCollectionEmptyRow(text: localizer.promptContextsEmptyDetail())
                        } else {
                            ForEach(appState.settings.promptContextItems) { item in
                                PromptContextSourceRow(
                                    item: bindingForPromptContext(id: item.id),
                                    localizer: localizer,
                                    remove: { removePromptContext(id: item.id) }
                                )
                                if item.id != appState.settings.promptContextItems.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: localizer.text(.customization),
                    target: .promptContexts
                )
            }
        }
    }

    private func bindingForPromptContext(id: UUID) -> Binding<PromptContextItem> {
        Binding(
            get: {
                appState.settings.promptContextItems.first { $0.id == id }
                    ?? PromptContextItem(title: "", prompt: "")
            },
            set: { updatedItem in
                guard let index = appState.settings.promptContextItems.firstIndex(where: { $0.id == id }) else {
                    return
                }
                appState.settings.promptContextItems[index] = updatedItem
            }
        )
    }

    private func addPromptContext() {
        let existingNames = Set(
            appState.settings.promptContextItems.map {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            }
        )
        var number = 1
        while existingNames.contains(
            localizer.newPromptContextName(number)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        ) {
            number += 1
        }
        appState.settings.promptContextItems.append(
            PromptContextItem(
                title: localizer.newPromptContextName(number),
                prompt: "",
                isEnabled: true
            )
        )
    }

    private func removePromptContext(id: UUID) {
        appState.settings.promptContextItems.removeAll { $0.id == id }
    }
}

#Preview {
    Form {
        PromptConfigurationSections()
    }
    .formStyle(.grouped)
    .padding(20)
        .environmentObject(AppState())
}
