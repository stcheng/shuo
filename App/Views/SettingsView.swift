import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CorrectionLearningPatternDisplayPolicy {
    static func visiblePatterns(
        from frequencySortedPatterns: [CorrectionLearningPattern],
        frequentLimit: Int = 12,
        enabledPatternIDs: Set<CorrectionLearningPattern.ID>
    ) -> [CorrectionLearningPattern] {
        let frequentPatternIDs = Set(
            frequencySortedPatterns.prefix(max(0, frequentLimit)).map(\.id)
        )
        return frequencySortedPatterns.filter {
            frequentPatternIDs.contains($0.id) || enabledPatternIDs.contains($0.id)
        }
    }
}

enum SettingsCategory: Equatable {
    case transcription
    case aiAndLLM
    case audio
    case architectureVoiceInput
    case architectureAudioProcessing
    case architectureAIInference
    case architectureHumanCorrection
}

struct SettingsPipelineMetadataPresentation: Equatable {
    var isEnabled = false
    var commonLabel = ""
    var advancedLabel = ""

    static let disabled = SettingsPipelineMetadataPresentation()
}

private struct SettingsPipelineMetadataPresentationKey: EnvironmentKey {
    static let defaultValue = SettingsPipelineMetadataPresentation.disabled
}

extension EnvironmentValues {
    var settingsPipelineMetadataPresentation: SettingsPipelineMetadataPresentation {
        get { self[SettingsPipelineMetadataPresentationKey.self] }
        set { self[SettingsPipelineMetadataPresentationKey.self] = newValue }
    }
}

extension View {
    func settingsSearchAnchor(
        _ target: SettingsSearchTarget,
        highlightedTarget: SettingsSearchTarget?
    ) -> some View {
        modifier(
            SettingsSearchAnchorModifier(
                target: target,
                highlightedTarget: highlightedTarget
            )
        )
    }

    func settingsPipelineMetadata(
        _ presentation: SettingsPipelineMetadataPresentation
    ) -> some View {
        environment(\.settingsPipelineMetadataPresentation, presentation)
    }
}

private struct SettingsSearchAnchorModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let target: SettingsSearchTarget
    let highlightedTarget: SettingsSearchTarget?

    func body(content: Content) -> some View {
        content
            .id(target)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        highlightedTarget == target
                            ? Color.accentColor.opacity(0.11)
                            : Color.clear
                    )
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        highlightedTarget == target
                            ? Color.accentColor.opacity(0.38)
                            : Color.clear,
                        lineWidth: 1
                    )
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
                    .allowsHitTesting(false)
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.2),
                value: highlightedTarget
            )
    }
}

struct SettingsSectionHeader: View {
    @Environment(\.settingsPipelineMetadataPresentation) private var metadata

    let title: String
    let target: SettingsSearchTarget

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
            Spacer(minLength: 10)

            if metadata.isEnabled,
               let placement = target.pipelinePlacement {
                Text(
                    placement.appearsInBasicSettings
                        ? metadata.commonLabel
                        : metadata.advancedLabel
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .textCase(nil)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsInlineLevelLabel: View {
    @Environment(\.settingsPipelineMetadataPresentation) private var metadata

    let target: SettingsSearchTarget

    var body: some View {
        if metadata.isEnabled,
           let placement = target.pipelinePlacement {
            Text(
                placement.appearsInBasicSettings
                    ? metadata.commonLabel
                    : metadata.advancedLabel
            )
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
        }
    }
}

struct SettingsRowLabel<Accessory: View>: View {
    let title: String
    let detail: String
    let accessory: Accessory

    init(
        title: String,
        detail: String = "",
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(title)
                accessory
            }

            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SettingsRowLabel where Accessory == EmptyView {
    init(title: String, detail: String = "") {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

struct SettingsRowFeedback: View {
    enum Style {
        case neutral
        case warning
        case error
    }

    let text: String
    var style: Style = .neutral
    var showsProgress = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(foregroundStyle)
    }

    private var systemImage: String? {
        switch style {
        case .neutral:
            return nil
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        }
    }

    private var foregroundStyle: Color {
        switch style {
        case .neutral:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

struct SettingsDisclosureRow<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let detail: String
    let metadataTarget: SettingsSearchTarget?
    let localizer: AppLocalizer
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        detail: String = "",
        metadataTarget: SettingsSearchTarget? = nil,
        localizer: AppLocalizer,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.metadataTarget = metadataTarget
        self.localizer = localizer
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    SettingsRowLabel(title: title, detail: detail)
                    Spacer(minLength: 12)
                    if let metadataTarget {
                        SettingsInlineLevelLabel(target: metadataTarget)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                isExpanded
                    ? localizer.expandedStateLabel()
                    : localizer.collapsedStateLabel()
            )

            if isExpanded {
                content
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct SettingsCollection<Content: View>: View {
    let addLabel: String?
    let addAction: (() -> Void)?
    let addSearchTarget: SettingsSearchTarget?
    let highlightedSearchTarget: SettingsSearchTarget?
    let content: Content

    init(
        addLabel: String,
        addAction: @escaping () -> Void,
        addSearchTarget: SettingsSearchTarget? = nil,
        highlightedSearchTarget: SettingsSearchTarget? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.addLabel = addLabel
        self.addAction = addAction
        self.addSearchTarget = addSearchTarget
        self.highlightedSearchTarget = highlightedSearchTarget
        self.content = content()
    }

    init(@ViewBuilder content: () -> Content) {
        addLabel = nil
        addAction = nil
        addSearchTarget = nil
        highlightedSearchTarget = nil
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let addLabel, let addAction {
                addButton(label: addLabel, action: addAction)

                Divider()
                    .padding(.top, 4)
            }

            content
        }
    }

    @ViewBuilder
    private func addButton(label: String, action: @escaping () -> Void) -> some View {
        if let addSearchTarget {
            baseAddButton(label: label, action: action)
                .settingsSearchAnchor(
                    addSearchTarget,
                    highlightedTarget: highlightedSearchTarget
                )
        } else {
            baseAddButton(label: label, action: action)
        }
    }

    private func baseAddButton(
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.vertical, 4)
    }
}

struct SettingsCollectionEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSearchTarget: SettingsSearchTarget?
    @State private var highlightedSearchRequestID: UUID?
    @State private var isOpenAIConnectionExpanded = false
    @State private var isLocalManualSetupExpanded = false
    @State private var isConfirmingCorrectionDataClear = false
    @State private var pendingLocalWhisperModelDeletion: LocalWhisperManagedModel?
    @State private var isConfirmingLocalWhisperModelDeletion = false

    let category: SettingsCategory

    init(category: SettingsCategory = .transcription) {
        self.category = category
    }

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                content
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: appState.settingsNavigationRequest?.id) {
                await handleSettingsNavigation(using: proxy)
            }
        }
        .onAppear {
            if category == .transcription || category == .architectureAIInference {
                appState.reloadLocalWhisperModels()
            }
            if shouldPrepareOpenAIModels {
                appState.loadOpenAIAPIKeyIfNeeded()
            }
            if shouldAutomaticallyRefreshOpenAIModels {
                appState.refreshOpenAIModelsIfNeeded()
            }
            if (category == .transcription || category == .architectureAIInference),
               appState.settings.provider == .elevenLabs {
                appState.loadElevenLabsAPIKeyIfNeeded()
            }
            if (category == .transcription || category == .architectureAIInference),
               appState.settings.provider == .alibaba {
                appState.loadAlibabaAPIKeyIfNeeded()
            }
            if (category == .transcription || category == .architectureAIInference),
               appState.settings.provider == .gemini {
                appState.loadGeminiAPIKeyIfNeeded()
            }
        }
        .onChange(of: appState.settings.provider) { _, provider in
            if shouldPrepareOpenAIModels {
                appState.loadOpenAIAPIKeyIfNeeded()
            }
            if shouldAutomaticallyRefreshOpenAIModels {
                appState.refreshOpenAIModelsIfNeeded()
            }
            if (category == .transcription || category == .architectureAIInference),
               provider == .elevenLabs {
                appState.loadElevenLabsAPIKeyIfNeeded()
            }
            if (category == .transcription || category == .architectureAIInference),
               provider == .alibaba {
                appState.loadAlibabaAPIKeyIfNeeded()
            }
            if (category == .transcription || category == .architectureAIInference),
               provider == .gemini {
                appState.loadGeminiAPIKeyIfNeeded()
            }
        }
        .confirmationDialog(
            localizer.clearCorrectionDataConfirmationTitle(),
            isPresented: $isConfirmingCorrectionDataClear,
            titleVisibility: .visible
        ) {
            Button(localizer.clearCorrectionDataActionLabel(), role: .destructive) {
                appState.clearCorrectionData()
            }
        } message: {
            Text(localizer.clearCorrectionDataConfirmationDetail())
        }
        .confirmationDialog(
            localizer.deleteLocalWhisperModelConfirmationTitle(
                pendingLocalWhisperModelDeletion
            ),
            isPresented: $isConfirmingLocalWhisperModelDeletion,
            titleVisibility: .visible
        ) {
            Button(localizer.text(.delete), role: .destructive) {
                if let model = pendingLocalWhisperModelDeletion {
                    appState.deleteManagedLocalWhisperModel(model)
                }
                pendingLocalWhisperModelDeletion = nil
            }
        } message: {
            Text(localizer.deleteLocalWhisperModelConfirmationDetail())
        }
    }

    private var panelSection: AppPanelSection {
        switch category {
        case .transcription:
            return .transcription
        case .aiAndLLM:
            return .aiAndLLM
        case .audio:
            return .audio
        case .architectureVoiceInput, .architectureAudioProcessing,
             .architectureAIInference, .architectureHumanCorrection:
            return .architecture
        }
    }

    private var architectureStage: SettingsPipelineStage? {
        switch category {
        case .architectureVoiceInput:
            return .voiceInput
        case .architectureAudioProcessing:
            return .audioProcessing
        case .architectureAIInference:
            return .aiInference
        case .architectureHumanCorrection:
            return .humanCorrection
        case .transcription, .aiAndLLM, .audio:
            return nil
        }
    }

    @MainActor
    private func handleSettingsNavigation(using proxy: ScrollViewProxy) async {
        guard let request = appState.settingsNavigationRequest,
              request.section == panelSection else {
            return
        }

        if let architectureStage,
           request.target.pipelinePlacement?.stage != architectureStage {
            return
        }

        switch request.target {
        case .openAIConnectionDetails, .openAIBaseURL, .openAIOrganizationID,
             .openAIProjectID:
            isOpenAIConnectionExpanded = true
        case .localManualSetup:
            isLocalManualSetupExpanded = true
        default:
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            guard highlightedSearchRequestID == requestID,
                  highlightedSearchTarget == target else {
                return
            }
            if reduceMotion {
                highlightedSearchTarget = nil
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    highlightedSearchTarget = nil
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch category {
        case .transcription:
            transcriptionContent
        case .aiAndLLM:
            aiAndLLMContent
        case .audio:
            advancedAudioContent
        case .architectureVoiceInput:
            architectureVoiceInputContent
        case .architectureAudioProcessing:
            architectureAudioProcessingContent
        case .architectureAIInference:
            architectureAIInferenceContent
        case .architectureHumanCorrection:
            architectureHumanCorrectionContent
        }
    }

    @ViewBuilder
    private var architectureVoiceInputContent: some View {
        voiceInputControlsContent(includesFloatingWindow: false)
        microphoneContent(includesAudioInputDevice: true, includesWhisperMode: false)
    }

    @ViewBuilder
    private var architectureAudioProcessingContent: some View {
        microphoneContent(includesAudioInputDevice: false, includesWhisperMode: true)
        silenceDetectionContent
    }

    @ViewBuilder
    private var architectureAIInferenceContent: some View {
        recognitionContent(includesAdvancedConfiguration: true)
        localPerformanceContent
        cloudTextModelSelectionSection
    }

    @ViewBuilder
    private var architectureHumanCorrectionContent: some View {
        floatingWindowContent
        voiceEditSettingsContent
        correctionDataContent
    }

    @ViewBuilder
    private var floatingWindowContent: some View {
        Section {
            floatingWindowSettingsRows
        } header: {
            SettingsSectionHeader(
                title: localizer.floatingWindowLabel(),
                target: .featureFloatingWindow
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: appState.isPluginEnabled(.smartCorrectionWindow)
        )
    }

    @ViewBuilder
    private var floatingWindowSettingsRows: some View {
        featureToggleRow(
            title: localizer.floatingWindowLabel(),
            detail: localizer.floatingWindowDetail(),
            pluginIDs: [.smartCorrectionWindow],
            searchTarget: .featureFloatingWindow
        )
    }

    @ViewBuilder
    private var voiceEditSettingsContent: some View {
        Section {
            voiceCommandToggleRow(
                pluginID: .commandModifyPrevious,
                title: localizer.text(.modifyPreviousCommand),
                detail: localizer.text(.modifyPreviousCommandHint),
                searchTarget: .featureVoiceEdit
            )

            voiceCommandToggleRow(
                pluginID: .commandDeletePrevious,
                title: localizer.text(.deletePreviousCommand),
                detail: localizer.text(.deletePreviousCommandHint),
                searchTarget: .deletePreviousCommand
            )
        } header: {
            SettingsSectionHeader(
                title: localizer.voiceCommandsSectionLabel(),
                target: .featureVoiceEdit
            )
        }

        if isModifyVoiceCommandEnabled {
            Section {
                voiceEditCommandModeRow
            } header: {
                SettingsSectionHeader(
                    title: localizer.advancedVoiceEditBetaLabel(),
                    target: .voiceEditMode
                )
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var correctionDataContent: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: {
                        appState.isPluginEnabled(.smartAdaptiveRecognition)
                            && appState.settings.adaptiveRecognitionEnabled
                    },
                    set: { appState.setAdaptiveRecognitionEnabled($0) }
                )
            ) {
                SettingsRowLabel(
                    title: localizer.useCorrectionLearningLabel(),
                    detail: localizer.correctionLearningToggleDetail()
                )
            }
            .toggleStyle(.switch)
            .settingsSearchAnchor(
                .featureAdaptiveRecognition,
                highlightedTarget: highlightedSearchTarget
            )

            if appState.settings.adaptiveRecognitionEnabled,
               appState.isPluginEnabled(.smartAdaptiveRecognition) {
                VStack(alignment: .leading, spacing: 7) {
                    Picker(
                        selection: Binding(
                            get: { appState.settings.adaptiveRecognitionMode },
                            set: { appState.setAdaptiveRecognitionMode($0) }
                        )
                    ) {
                        ForEach(AdaptiveRecognitionMode.allCases, id: \.self) { mode in
                            Text(localizer.adaptiveRecognitionModeTitle(mode)).tag(mode)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(localizer.correctionLearningModeLabel())
                            LLMRequirementBadge(
                                accessibilityLabel: localizer.mayUseCloudAILabel()
                            )
                        }
                    }
                    .pickerStyle(.segmented)

                    SettingsRowFeedback(
                        text: localizer.adaptiveRecognitionModeDetail(
                            appState.settings.adaptiveRecognitionMode
                        )
                    )

                    if correctionHintsLeaveThisMac {
                        SettingsRowFeedback(
                            text: localizer.correctionLearningCloudDetail()
                        )
                    }

                    if let limitation = correctionHintProviderLimitation {
                        SettingsRowFeedback(text: limitation, style: .warning)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(localizer.correctionDataLabel())
                    .font(.callout.weight(.medium))

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            localizer.correctionLearningSummary(
                                evidenceCount: correctionLearningSnapshot.evidenceEventCount,
                                patternCount: correctionLearningSnapshot.patterns.count
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if legacyCorrectionRecordCount > 0 {
                            Text(localizer.legacyCorrectionCountLabel(legacyCorrectionRecordCount))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        Button(localizer.exportCorrectionDataLabel()) {
                            exportCorrectionData()
                        }
                        .disabled(!hasCorrectionData)

                        Button(localizer.clearCorrectionDataLabel(), role: .destructive) {
                            isConfirmingCorrectionDataClear = true
                        }
                        .disabled(!hasCorrectionData)
                    }
                    .controlSize(.small)
                }

                SettingsRowFeedback(text: localizer.correctionDataDetail())
            }
            .settingsSearchAnchor(.correctionData, highlightedTarget: highlightedSearchTarget)

            if appState.settings.adaptiveRecognitionEnabled,
               appState.isPluginEnabled(.smartAdaptiveRecognition) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizer.frequentCorrectionMappingsLabel())
                        .font(.callout.weight(.medium))

                    SettingsCollection {
                        if visibleCorrectionLearningPatterns.isEmpty {
                            SettingsCollectionEmptyRow(
                                text: localizer.frequentCorrectionMappingsEmptyDetail()
                            )
                        } else {
                            ForEach(visibleCorrectionLearningPatterns) { pattern in
                                CorrectionLearningPatternRow(
                                    pattern: pattern,
                                    isEnabled: Binding(
                                        get: {
                                            appState.isCorrectionLearningPatternEnabled(pattern.id)
                                        },
                                        set: {
                                            appState.setCorrectionLearningPatternEnabled(
                                                $0,
                                                id: pattern.id
                                            )
                                        }
                                    ),
                                    localizer: localizer
                                )

                                if pattern.id != visibleCorrectionLearningPatterns.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.correctionLearningLabel(),
                target: .correctionData
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appState.settings.adaptiveRecognitionEnabled
        )
    }

    @ViewBuilder
    private func voiceInputControlsContent(includesFloatingWindow: Bool) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 7) {
                Picker(localizer.text(.shortcut), selection: Binding(
                    get: { appState.settings.pushToTalkShortcut },
                    set: { appState.setPushToTalkShortcut($0) }
                )) {
                    ForEach(PushToTalkShortcut.allCases) { shortcut in
                        Text(localizer.shortcutName(shortcut)).tag(shortcut)
                    }
                }

                if let controlsStatusFooter {
                    SettingsRowFeedback(text: controlsStatusFooter, style: .warning)
                }
            }
            .settingsSearchAnchor(.inputShortcut, highlightedTarget: highlightedSearchTarget)

            Toggle(isOn: $appState.settings.recordingStartSoundEnabled) {
                SettingsRowLabel(
                    title: localizer.text(.recordingStartSound),
                    detail: localizer.text(.recordingStartSoundHint)
                )
            }
            .settingsSearchAnchor(.inputRecordingCue, highlightedTarget: highlightedSearchTarget)

            if appState.settings.recordingStartSoundEnabled {
                HStack {
                    Picker(localizer.text(.recordingStartSoundStyle), selection: $appState.settings.recordingStartSound) {
                        ForEach(RecordingCueSound.allCases) { sound in
                            Text(localizer.recordingCueSoundName(sound)).tag(sound)
                        }
                    }
                    .disabled(!appState.settings.recordingStartSoundEnabled)

                    Button {
                        appState.previewRecordingStartSound()
                    } label: {
                        Label(localizer.text(.previewRecordingStartSound), systemImage: "speaker.wave.2")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .settingsSearchAnchor(.inputRecordingCueStyle, highlightedTarget: highlightedSearchTarget)
            }

            if includesFloatingWindow {
                floatingWindowSettingsRows
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.text(.controls),
                target: .inputShortcut
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: appState.settings.recordingStartSoundEnabled
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: appState.isPluginEnabled(.smartCorrectionWindow)
        )
    }

    private var controlsStatusFooter: String? {
        guard appState.settings.pushToTalkEnabled,
              appState.accessibilityPermissionGranted else {
            return nil
        }

        let readyMessage = localizer.holdToDictate(shortcut: appState.settings.pushToTalkShortcut)
        let message = appState.pushToTalkStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message != readyMessage else {
            return nil
        }
        return message
    }

    @ViewBuilder
    private var basicApplicationContent: some View {
        Section(localizer.applicationSettingsLabel()) {
            Picker(localizer.text(.appLanguage), selection: $appState.settings.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeDisplayName).tag(language)
                }
            }
            .settingsSearchAnchor(.appLanguage, highlightedTarget: highlightedSearchTarget)

            Toggle(
                localizer.launchAtLoginLabel(),
                isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.setLaunchAtLoginEnabled($0) }
                )
            )
            .settingsSearchAnchor(.launchAtLogin, highlightedTarget: highlightedSearchTarget)

            if appState.launchAtLoginRequiresApproval {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    SettingsRowFeedback(text: localizer.launchAtLoginApprovalDetail())

                    Spacer(minLength: 8)

                    Button(localizer.openLoginItemsLabel()) {
                        appState.openLoginItemsSettings()
                    }
                    .controlSize(.small)
                }
            }

            if appState.supportsDirectUpdates {
                Toggle(
                    localizer.text(.automaticUpdateChecks),
                    isOn: Binding(
                        get: { appState.automaticallyChecksForUpdates },
                        set: { appState.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                Toggle(
                    localizer.text(.automaticUpdates),
                    isOn: Binding(
                        get: { appState.automaticallyDownloadsUpdates },
                        set: { appState.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .disabled(!appState.automaticallyChecksForUpdates)

                VStack(alignment: .leading, spacing: 7) {
                    Button {
                        appState.checkForUpdates()
                    } label: {
                        Label(
                            localizer.text(.checkForUpdates),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(!appState.canCheckForUpdates)

                    if !appState.updateStatusMessage.isEmpty {
                        SettingsRowFeedback(text: appState.updateStatusMessage)
                    }
                }
                .settingsSearchAnchor(.updates, highlightedTarget: highlightedSearchTarget)
            } else if !AppRuntime.isCommunityBuild {
                SettingsRowFeedback(text: localizer.appStoreUpdateHint())
                    .settingsSearchAnchor(.updates, highlightedTarget: highlightedSearchTarget)
            }
        }
    }

    @ViewBuilder
    private var transcriptionContent: some View {
        basicApplicationContent
        voiceInputControlsContent(includesFloatingWindow: true)
        recognitionContent(includesAdvancedConfiguration: false)
        microphoneContent(includesAudioInputDevice: true, includesWhisperMode: true)
    }

    @ViewBuilder
    private func recognitionContent(includesAdvancedConfiguration: Bool) -> some View {
        Section {
            Picker(localizer.text(.provider), selection: $appState.settings.provider) {
                ForEach(availableTranscriptionProviders) { provider in
                    Text(localizer.providerName(provider)).tag(provider)
                }
            }
            .settingsSearchAnchor(.transcriptionProvider, highlightedTarget: highlightedSearchTarget)

            if appState.settings.provider == .local {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(localizer.text(.model))
                        Spacer()
                        Text(localModelDisplayName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if appState.settings.localWhisperLanguageCapability != .unknown {
                        SettingsRowFeedback(
                            text: localizer.localWhisperLanguageCapabilityName(
                                appState.settings.localWhisperLanguageCapability
                            )
                        )
                    }

                    if appState.settings.localTranscriptionEngine == .senseVoice {
                        SettingsRowFeedback(text: localizer.senseVoiceAutomaticDetectionDetail())
                    }
                }
                .settingsSearchAnchor(.transcriptionModel, highlightedTarget: highlightedSearchTarget)
            } else if appState.settings.provider == .openAI {
                Picker(
                    localizer.openAIModelSelectionLabel(),
                    selection: $appState.settings.openAITranscriptionModelSelectionMode
                ) {
                    ForEach(OpenAIModelSelectionMode.allCases) { mode in
                        Text(localizer.openAIModelSelectionModeName(mode)).tag(mode)
                    }
                }
                .settingsSearchAnchor(.transcriptionModel, highlightedTarget: highlightedSearchTarget)

                if appState.settings.openAITranscriptionModelSelectionMode == .automatic {
                    VStack(alignment: .leading, spacing: 7) {
                        LabeledContent(
                            localizer.text(.model),
                            value: appState.settings.effectiveModel
                        )

                        SettingsRowFeedback(
                            text: appState.openAIAutomaticTranscriptionModelMessage
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Picker(localizer.text(.model), selection: $appState.settings.selectedModel) {
                            ForEach(appState.openAITranscriptionModelOptions) { model in
                                Text(appState.openAIModelOptionLabel(model)).tag(model.id)
                            }
                        }

                        if !appState.isOpenAIModelAvailable(appState.settings.selectedModel) {
                            SettingsRowFeedback(
                                text: localizer.openAIModelUnavailableLabel(),
                                style: .warning
                            )
                        }
                    }
                }
            } else if appState.settings.provider == .elevenLabs {
                HStack {
                    Text(localizer.text(.model))
                    Spacer()
                    Text("Scribe v2")
                        .foregroundStyle(.secondary)
                }
                .settingsSearchAnchor(.transcriptionModel, highlightedTarget: highlightedSearchTarget)
            } else if appState.settings.provider == .alibaba {
                HStack {
                    Text(localizer.text(.model))
                    Spacer()
                    Text("Qwen3-ASR-Flash")
                        .foregroundStyle(.secondary)
                }
                .settingsSearchAnchor(.transcriptionModel, highlightedTarget: highlightedSearchTarget)
            } else if appState.settings.provider == .gemini {
                LabeledContent(
                    localizer.text(.model),
                    value: GeminiTranscriptionService.defaultModelID
                )
                .settingsSearchAnchor(.transcriptionModel, highlightedTarget: highlightedSearchTarget)
            } else {
                Picker(localizer.text(.model), selection: $appState.settings.selectedModel) {
                    ForEach(appState.settings.provider.modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .settingsSearchAnchor(.transcriptionModel, highlightedTarget: highlightedSearchTarget)

                if appState.settings.selectedModel == "custom" {
                    TextField(localizer.text(.customModel), text: $appState.settings.customModelName)
                }
            }

            transcriptionLanguageControl

        } header: {
            SettingsSectionHeader(
                title: localizer.recognitionLabel(),
                target: .transcriptionProvider
            )
        }
        if appState.settings.provider == .openAI || usesOpenAITextFeatures {
            openAISettingsSection(includesConnectionDetails: includesAdvancedConfiguration)
        }

        if appState.settings.provider == .elevenLabs {
            elevenLabsSettingsSection
        }

        if appState.settings.provider == .alibaba {
            alibabaSettingsSection
        }

        if appState.settings.provider == .gemini {
            geminiSettingsSection
        }

        if appState.settings.provider == .local {
            localModelManagementSection(includesManualSetup: includesAdvancedConfiguration)
        }
    }

    @ViewBuilder
    private var transcriptionLanguageControl: some View {
        let languages = appState.settings.availableTranscriptionLanguages

        if languages.count == 1, let language = languages.first {
            VStack(alignment: .leading, spacing: 5) {
                LabeledContent(
                    localizer.text(.transcriptionLanguage),
                    value: localizer.transcriptionLanguageName(language)
                )

                if appState.settings.provider == .local,
                   appState.settings.localWhisperLanguageCapability == .englishOnly {
                    SettingsRowFeedback(text: localizer.localWhisperEnglishOnlyLanguageHint())
                }
            }
            .settingsSearchAnchor(.transcriptionLanguage, highlightedTarget: highlightedSearchTarget)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text(localizer.text(.transcriptionLanguage))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        transcriptionLanguageToggles(languages)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        transcriptionLanguageToggles(languages)
                    }
                }

                SettingsRowFeedback(text: localizer.transcriptionLanguageSelectionDetail())
            }
            .settingsSearchAnchor(.transcriptionLanguage, highlightedTarget: highlightedSearchTarget)
        }
    }

    @ViewBuilder
    private func transcriptionLanguageToggles(_ languages: [TranscriptionLanguage]) -> some View {
        ForEach(languages) { language in
            Toggle(
                localizer.transcriptionLanguageName(language),
                isOn: transcriptionLanguageBinding(language)
            )
            .toggleStyle(.checkbox)
            .disabled(appState.settings.selectedTranscriptionLanguages == Set([language]))
        }
    }

    @ViewBuilder
    private func microphoneContent(
        includesAudioInputDevice: Bool,
        includesWhisperMode: Bool
    ) -> some View {
        Section {
            if includesAudioInputDevice {
                VStack(alignment: .leading, spacing: 5) {
                    Picker(localizer.text(.audioInputDevice), selection: $appState.settings.audioInputDeviceID) {
                        Text(localizer.text(.systemDefaultAudioInput))
                            .tag(AudioInputDeviceCatalog.systemDefaultDeviceID)

                        ForEach(appState.audioInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }

                        if shouldShowUnavailableAudioInputDevice {
                            Text(localizer.text(.unavailableAudioInputDevice))
                                .tag(appState.settings.audioInputDeviceID)
                        }
                    }

                    SettingsRowFeedback(text: localizer.text(.audioInputDeviceHint))
                }
                .settingsSearchAnchor(.audioInputDevice, highlightedTarget: highlightedSearchTarget)
            }

            if includesWhisperMode {
                Toggle(isOn: $appState.settings.whisperModeEnabled) {
                    SettingsRowLabel(
                        title: localizer.text(.whisperMode),
                        detail: localizer.text(.whisperModeHint)
                    )
                }
                .settingsSearchAnchor(.whisperMode, highlightedTarget: highlightedSearchTarget)
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.microphoneLabel(),
                target: includesAudioInputDevice ? .audioInputDevice : .whisperMode
            )
        }
    }

    @ViewBuilder
    private var aiAndLLMContent: some View {
        Section(localizer.transcriptionEnhancementsLabel()) {
            featureToggleRow(
                title: localizer.text(.promptContext),
                detail: appState.settings.usesSenseVoiceLocalTranscription
                    ? localizer.senseVoiceVocabularyUnavailableDetail()
                    : localizer.promptContextFeatureDetail(),
                pluginIDs: [.smartPromptContext],
                searchTarget: .featurePromptContext,
                isAvailable: !appState.settings.usesSenseVoiceLocalTranscription
            )
            featureToggleRow(
                title: localizer.text(.transcriptRetouch),
                detail: isCloudTextAIAvailable
                    ? localizer.text(.transcriptRetouchHint)
                    : cloudTextAIUnavailableDetail,
                pluginIDs: [.outputLLMRetouch],
                searchTarget: .featureTranscriptRetouch,
                requiresLLM: true,
                isAvailable: isCloudTextAIAvailable,
                isRuntimeEnabled: { appState.settings.transcriptRetouchEnabled },
                onChange: { appState.settings.transcriptRetouchEnabled = $0 }
            )
        }

        Section(localizer.voiceCommandsSectionLabel()) {
            voiceCommandToggleRow(
                pluginID: .commandModifyPrevious,
                title: localizer.text(.modifyPreviousCommand),
                detail: localizer.text(.modifyPreviousCommandHint),
                searchTarget: .featureVoiceEdit
            )

            voiceCommandToggleRow(
                pluginID: .commandDeletePrevious,
                title: localizer.text(.deletePreviousCommand),
                detail: localizer.text(.deletePreviousCommandHint),
                searchTarget: .deletePreviousCommand
            )
        }

        cloudTextModelSelectionSection

        if appState.isPluginEnabled(.outputEmoji) {
            Section(localizer.text(.specialCommands)) {
                specialCommandHelpRow(
                    title: localizer.text(.emojiCommand),
                    detail: localizer.text(.emojiCommandHint),
                    systemImage: "face.smiling"
                )
            }
        }

        if isModifyVoiceCommandEnabled {
            Section {
                voiceEditCommandModeRow
            } header: {
                SettingsSectionHeader(
                    title: localizer.advancedVoiceEditBetaLabel(),
                    target: .voiceEditMode
                )
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if appState.isPluginEnabled(.outputEmoji) {
            Section(localizer.text(.emojiCommand)) {
                Toggle(isOn: Binding(
                    get: {
                        isCloudTextAIAvailable
                            && appState.settings.aiEmojiResolverEnabled
                    },
                    set: { isEnabled in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            appState.settings.aiEmojiResolverEnabled = isEnabled
                        }
                    }
                )) {
                    SettingsRowLabel(
                        title: localizer.text(.aiEmojiResolver),
                        detail: !isCloudTextAIAvailable
                            ? cloudTextAIUnavailableDetail
                            : localizer.text(.aiEmojiResolverHint)
                    ) {
                        LLMRequirementBadge(accessibilityLabel: localizer.requiresCloudAILabel())
                    }
                }
                .disabled(
                    !isCloudTextAIAvailable
                        || !appState.settings.emojiPostProcessingEnabled
                )
                .settingsSearchAnchor(.aiEmojiResolver, highlightedTarget: highlightedSearchTarget)
            }
        }

        if appState.isPluginEnabled(.smartPromptContext) {
            PromptConfigurationSections()
                .settingsSearchAnchor(.promptContexts, highlightedTarget: highlightedSearchTarget)
        }

    }

    @ViewBuilder
    private var cloudTextModelSelectionSection: some View {
        if appState.settings.provider == .gemini {
            geminiTextEnhancementsSection
        } else {
            openAITextModelSelectionSection
        }
    }

    private var geminiTextEnhancementsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 7) {
                Toggle(
                    localizer.optionalCloudTextEnhancementsEnabledLabel(),
                    isOn: geminiTextEnhancementsEnabled
                )

                LabeledContent(
                    localizer.text(.model),
                    value: appState.settings.effectiveModel
                )
                SettingsRowFeedback(
                    text: appState.settings.openAITextModelSelectionMode == .disabled
                        ? localizer.disabledCloudTextEnhancementsHint()
                        : localizer.geminiTextEnhancementsDetail()
                )
            }
            .settingsSearchAnchor(.geminiAPIKey, highlightedTarget: highlightedSearchTarget)
        } header: {
            SettingsSectionHeader(
                title: localizer.geminiTextEnhancementsLabel(),
                target: .geminiAPIKey
            )
        }
    }

    private var geminiTextEnhancementsEnabled: Binding<Bool> {
        Binding(
            get: {
                appState.settings.openAITextModelSelectionMode != .disabled
            },
            set: { isEnabled in
                appState.settings.openAITextModelSelectionMode = isEnabled
                    ? .automatic
                    : .disabled
            }
        )
    }

    private var openAITextModelSelectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 7) {
                Picker(
                    localizer.openAIModelSelectionLabel(),
                    selection: $appState.settings.openAITextModelSelectionMode
                ) {
                    ForEach(OpenAITextModelSelectionMode.allCases) { mode in
                        Text(localizer.openAITextModelSelectionModeName(mode)).tag(mode)
                    }
                }
                .disabled(appState.settings.provider == .local)

                if appState.settings.provider == .local {
                    SettingsRowFeedback(
                        text: localizer.cloudAIUnavailableInLocalModeDetail()
                    )
                } else if appState.settings.openAITextModelSelectionMode == .automatic {
                    SettingsRowFeedback(text: appState.openAIAutomaticTextModelMessage)
                        .transition(.opacity)
                } else if appState.settings.openAITextModelSelectionMode == .disabled {
                    SettingsRowFeedback(text: localizer.disabledOpenAITextModelHint())
                        .transition(.opacity)
                }

                if appState.settings.provider != .local,
                   appState.isRefreshingOpenAIModels {
                    SettingsRowFeedback(
                        text: localizer.refreshingOpenAIModels(),
                        showsProgress: true
                    )
                } else if appState.settings.provider != .local,
                          let error = appState.openAIModelAvailabilityError {
                    SettingsRowFeedback(
                        text: localizer.openAIModelRefreshFailed(error),
                        style: .warning
                    )
                } else if appState.settings.provider != .local,
                          appState.settings.openAITextModelSelectionMode == .automatic,
                          appState.openAIModelAvailabilityFetchedAt != nil,
                          OpenAIModelCatalog.recommendedTextModelID(
                            availableModelIDs: appState.openAIAvailableModelIDs
                          ) == nil {
                    SettingsRowFeedback(
                        text: localizer.noCompatibleOpenAITextModels(),
                        style: .warning
                    )
                }
            }
            .settingsSearchAnchor(.openAITextModel, highlightedTarget: highlightedSearchTarget)

            if appState.settings.openAITextModelSelectionMode == .fixed,
               appState.settings.provider != .local {
                VStack(alignment: .leading, spacing: 7) {
                    TextField(
                        localizer.text(.model),
                        text: $appState.settings.fixedOpenAITextModel
                    )
                    SettingsRowFeedback(text: localizer.fixedOpenAITextModelHint())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(localizer.refreshOpenAIModelsLabel()) {
                appState.refreshOpenAIModels()
            }
            .disabled(
                appState.settings.provider == .local
                    || appState.isRefreshingOpenAIModels
                    || appState.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        } header: {
            SettingsSectionHeader(
                title: localizer.openAITextModelSelectionLabel(),
                target: .openAITextModel
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: appState.settings.openAITextModelSelectionMode
        )
    }

    private func openAISettingsSection(includesConnectionDetails: Bool) -> some View {
        Section {
            SecureField(localizer.text(.apiKey), text: Binding(
                get: { appState.openAIAPIKey },
                set: { appState.updateOpenAIAPIKey($0) }
            ))
            .settingsSearchAnchor(.openAIAPIKey, highlightedTarget: highlightedSearchTarget)
            .onSubmit {
                appState.refreshOpenAIModels()
            }

            if !includesConnectionDetails {
                VStack(alignment: .leading, spacing: 7) {
                    Button(localizer.refreshOpenAIModelsLabel()) {
                        appState.refreshOpenAIModels()
                    }
                    .disabled(
                        appState.isRefreshingOpenAIModels
                            || appState.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if appState.isRefreshingOpenAIModels {
                        SettingsRowFeedback(
                            text: localizer.refreshingOpenAIModels(),
                            showsProgress: true
                        )
                    } else if let error = appState.openAIModelAvailabilityError {
                        SettingsRowFeedback(
                            text: localizer.openAIModelRefreshFailed(error),
                            style: .warning
                        )
                    }
                }
            }

            apiKeyGuideLink(for: .openAI)

            if includesConnectionDetails {
                SettingsDisclosureRow(
                    title: localizer.connectionDetailsLabel(),
                    metadataTarget: .openAIConnectionDetails,
                    localizer: localizer,
                    isExpanded: $isOpenAIConnectionExpanded
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(localizer.openAIConnectionDetailsHint())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(localizer.text(.baseURL))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(
                            "",
                            text: $appState.settings.openAIBaseURL,
                            prompt: Text(AppSettings.defaultOpenAIBaseURL)
                        )
                            .labelsHidden()
                            .textContentType(.URL)
                            .accessibilityLabel(localizer.text(.baseURL))
                            .settingsSearchAnchor(.openAIBaseURL, highlightedTarget: highlightedSearchTarget)
                            .onSubmit {
                                appState.refreshOpenAIModels()
                            }

                        let organizationLabel = localizer.optionalFieldLabel(
                            localizer.text(.organizationID)
                        )
                        Text(organizationLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("", text: $appState.settings.openAIOrganizationID)
                            .accessibilityLabel(organizationLabel)
                            .settingsSearchAnchor(.openAIOrganizationID, highlightedTarget: highlightedSearchTarget)
                            .onSubmit {
                                appState.refreshOpenAIModels()
                            }

                        let projectLabel = localizer.optionalFieldLabel(
                            localizer.text(.projectID)
                        )
                        Text(projectLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("", text: $appState.settings.openAIProjectID)
                            .accessibilityLabel(projectLabel)
                            .settingsSearchAnchor(.openAIProjectID, highlightedTarget: highlightedSearchTarget)
                            .onSubmit {
                                appState.refreshOpenAIModels()
                            }

                        Button(localizer.restoreOpenAIConnectionDefaultsLabel()) {
                            var settings = appState.settings
                            settings.resetOpenAIConnectionDetails()
                            appState.settings = settings
                            appState.refreshOpenAIModels()
                        }
                        .controlSize(.small)
                    }
                }
                .settingsSearchAnchor(.openAIConnectionDetails, highlightedTarget: highlightedSearchTarget)
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.text(.openAI),
                target: .openAIAPIKey
            )
        }
    }

    private var elevenLabsSettingsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 7) {
                SecureField(localizer.text(.apiKey), text: Binding(
                    get: { appState.elevenLabsAPIKey },
                    set: { appState.updateElevenLabsAPIKey($0) }
                ))
                SettingsRowFeedback(text: localizer.elevenLabsKeytermDetail())
            }
            .settingsSearchAnchor(.elevenLabsAPIKey, highlightedTarget: highlightedSearchTarget)

            apiKeyGuideLink(for: .elevenLabs)
        } header: {
            SettingsSectionHeader(title: "ElevenLabs", target: .elevenLabsAPIKey)
        }
    }

    private var alibabaSettingsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 7) {
                SecureField(localizer.text(.apiKey), text: Binding(
                    get: { appState.alibabaAPIKey },
                    set: { appState.updateAlibabaAPIKey($0) }
                ))
                SettingsRowFeedback(text: localizer.alibabaProviderDetail())
            }
            .settingsSearchAnchor(.alibabaAPIKey, highlightedTarget: highlightedSearchTarget)

            apiKeyGuideLink(for: .alibaba)
        } header: {
            SettingsSectionHeader(
                title: localizer.providerName(.alibaba),
                target: .alibabaAPIKey
            )
        }
    }

    private var geminiSettingsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 7) {
                SecureField(localizer.text(.apiKey), text: Binding(
                    get: { appState.geminiAPIKey },
                    set: { appState.updateGeminiAPIKey($0) }
                ))
                SettingsRowFeedback(text: localizer.geminiAPIKeyDetail())
            }
            .settingsSearchAnchor(.geminiAPIKey, highlightedTarget: highlightedSearchTarget)

            apiKeyGuideLink(for: .gemini)
        } header: {
            SettingsSectionHeader(
                title: localizer.providerName(.gemini),
                target: .geminiAPIKey
            )
        }
    }

    @ViewBuilder
    private func apiKeyGuideLink(for provider: TranscriptionProvider) -> some View {
        if let destination = provider.apiKeyGuideURL {
            Link(destination: destination) {
                HStack(spacing: 5) {
                    Text(localizer.apiKeyGuideLabel())
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                }
            }
            .font(.caption)
        }
    }

    private func featureToggleRow(
        title: String,
        detail: String,
        pluginIDs: [PluginID],
        searchTarget: SettingsSearchTarget,
        requiresLLM: Bool = false,
        isAvailable: Bool = true,
        isRuntimeEnabled: @escaping () -> Bool = { true },
        onChange: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        Toggle(isOn: Binding(
            get: {
                isAvailable
                    && pluginIDs.contains(where: appState.isPluginEnabled)
                    && isRuntimeEnabled()
            },
            set: { isEnabled in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    for pluginID in pluginIDs {
                        appState.setPluginEnabled(pluginID, isEnabled: isEnabled)
                    }
                    onChange(isEnabled)
                }
            }
        )) {
            SettingsRowLabel(title: title, detail: detail) {
                if requiresLLM {
                    LLMRequirementBadge(accessibilityLabel: localizer.requiresCloudAILabel())
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(!isAvailable)
        .settingsSearchAnchor(searchTarget, highlightedTarget: highlightedSearchTarget)
    }

    private func voiceCommandToggleRow(
        pluginID: PluginID,
        title: String,
        detail: String,
        searchTarget: SettingsSearchTarget
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: {
                    appState.settings.voiceEditCommandsEnabled
                        && appState.isPluginEnabled(pluginID)
                },
                set: { isEnabled in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        appState.setPluginEnabled(pluginID, isEnabled: isEnabled)
                        if isEnabled {
                            appState.settings.voiceEditCommandsEnabled = true
                        } else {
                            let remainingPluginID: PluginID = pluginID == .commandModifyPrevious
                                ? .commandDeletePrevious
                                : .commandModifyPrevious
                            appState.settings.voiceEditCommandsEnabled = appState.isPluginEnabled(
                                remainingPluginID
                            )
                        }
                    }
                }
            )
        ) {
            SettingsRowLabel(title: title, detail: detail)
        }
        .toggleStyle(.switch)
        .settingsSearchAnchor(searchTarget, highlightedTarget: highlightedSearchTarget)
    }

    private var voiceEditCommandModeRow: some View {
        LabeledContent {
            Picker(
                localizer.text(.voiceEditCommandMode),
                selection: effectiveVoiceEditCommandModeBinding
            ) {
                ForEach(VoiceEditCommandMode.allCases) { mode in
                    Text(localizer.voiceEditCommandModeName(mode)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(!isCloudTextAIAvailable)
        } label: {
            SettingsRowLabel(
                title: localizer.text(.voiceEditCommandMode),
                detail: localizer.voiceEditCommandModeDetail(
                    effectiveVoiceEditCommandModeBinding.wrappedValue
                )
            ) {
                LLMRequirementBadge(accessibilityLabel: localizer.mayUseCloudAILabel())
            }
        }
        .settingsSearchAnchor(.voiceEditMode, highlightedTarget: highlightedSearchTarget)
    }

    private func specialCommandHelpRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            SettingsRowLabel(title: title, detail: detail)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func localModelManagementSection(includesManualSetup: Bool) -> some View {
        Section {
            ForEach(visibleManagedLocalWhisperModels) { model in
                if model.id == visibleManagedLocalWhisperModels.first?.id {
                    managedLocalWhisperModelRow(model)
                        .settingsSearchAnchor(
                            .localModelManagement,
                            highlightedTarget: highlightedSearchTarget
                        )
                } else {
                    managedLocalWhisperModelRow(model)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SettingsRowFeedback(text: localizer.localWhisperModelSizeExplanation())

                if shouldShowLocalWhisperSetupMessage {
                    SettingsRowFeedback(
                        text: appState.localWhisperSetupMessage,
                        style: appState.localWhisperSetupIsRunning ? .neutral : .error,
                        showsProgress: appState.localWhisperSetupIsRunning
                    )
                }
            }

            if includesManualSetup {
                SettingsDisclosureRow(
                    title: localizer.manualSetupLabel(),
                    metadataTarget: .localManualSetup,
                    localizer: localizer,
                    isExpanded: $isLocalManualSetupExpanded
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizer.text(.localWhisperEngine))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField(
                                localizer.text(.localWhisperExecutablePath),
                                text: $appState.settings.localWhisperExecutablePath
                            )
                            .textFieldStyle(.roundedBorder)

                            Button(localizer.text(.chooseFile)) {
                                chooseLocalWhisperExecutable()
                            }
                        }

                        SettingsRowFeedback(text: localizer.text(.localWhisperAutoDetectHint))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizer.text(.localWhisperModelDirectory))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField(
                                localizer.text(.localWhisperModelDirectoryPath),
                                text: $appState.settings.localWhisperModelDirectoryPath
                            )
                            .textFieldStyle(.roundedBorder)

                            Button(localizer.text(.chooseFile)) {
                                chooseLocalWhisperModelDirectory()
                            }
                        }

                        SettingsRowFeedback(text: localizer.text(.localWhisperModelDirectoryHint))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if localWhisperModelURLs.isEmpty {
                            SettingsCollectionEmptyRow(text: localizer.text(.noLocalModelsFound))
                        } else {
                            Picker(localizer.text(.localWhisperModel), selection: Binding(
                                get: { appState.settings.localWhisperModelPath },
                                set: { appState.setLocalWhisperModelPath($0) }
                            )) {
                                ForEach(localWhisperModelURLs, id: \.path) { modelURL in
                                    Text(modelURL.lastPathComponent).tag(modelURL.path)
                                }
                            }
                        }

                        if appState.settings.localWhisperLanguageCapability != .unknown {
                            SettingsRowFeedback(
                                text: localizer.localWhisperLanguageCapabilityName(
                                    appState.settings.localWhisperLanguageCapability
                                )
                            )
                        }
                    }
                    }
                }
                .settingsSearchAnchor(.localManualSetup, highlightedTarget: highlightedSearchTarget)
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.text(.modelManagement),
                target: .localModelManagement
            )
        }
    }

    private func managedLocalWhisperModelRow(_ model: LocalWhisperManagedModel) -> some View {
        let isInstalled = appState.isManagedLocalWhisperModelInstalled(model)
        let isActive = appState.localWhisperActiveManagedModelID == model.id
        let isBusy = appState.localWhisperSetupIsRunning || appState.localWhisperActiveManagedModelID != nil
        let isSelected = isSelectedManagedModel(model)
        let recommendation = localModelRecommendation

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(model.displayName)
                        .font(.body)

                    if model.id == recommendation.modelID {
                        Text(localizer.localModelRecommendationLabel(recommendation))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(localizer.localWhisperManagedModelSummary(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let note = localizer.localWhisperManagedModelNote(model)
                if !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isActive {
                VStack(alignment: .trailing, spacing: 6) {
                    if let progress = appState.localWhisperDownloadProgress {
                        ProgressView(value: progress.fractionCompleted)
                            .frame(width: 120)
                        Text("\(Int((progress.fractionCompleted * 100).rounded(.down)))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if appState.localWhisperDownloadProgress != nil {
                        Button(localizer.cancelTranscriptionLabel()) {
                            appState.cancelManagedLocalWhisperModelDownload()
                        }
                        .controlSize(.small)
                        .accessibilityLabel(localizer.cancelLocalWhisperModelDownloadLabel(model))
                    }
                }
            } else if isInstalled {
                Button {
                    if !isSelected {
                        appState.useManagedLocalWhisperModel(model)
                    }
                } label: {
                    if isSelected {
                        Label(localizer.text(.use), systemImage: "checkmark")
                    } else {
                        Text(localizer.text(.use))
                    }
                }
                .controlSize(.small)
                .disabled(isBusy || isSelected)
                .help(isSelected ? localizer.localWhisperModelInUseLabel() : localizer.text(.use))
                .accessibilityLabel(localizer.useLocalWhisperModelLabel(model))

                Button(role: .destructive) {
                    pendingLocalWhisperModelDeletion = model
                    isConfirmingLocalWhisperModelDeletion = true
                } label: {
                    Text(localizer.text(.delete))
                }
                .controlSize(.small)
                .disabled(isBusy)
                .help(localizer.removeLocalWhisperModelLabel(model))
                .accessibilityLabel(localizer.removeLocalWhisperModelLabel(model))
            } else {
                Button(localizer.text(.download)) {
                    appState.downloadManagedLocalWhisperModel(model)
                }
                .disabled(isBusy)
                .accessibilityLabel(localizer.downloadLocalWhisperModelLabel(model))
            }
        }
        .padding(.vertical, 4)
    }

    private var shouldShowLocalWhisperSetupMessage: Bool {
        let message = appState.localWhisperSetupMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return false
        }

        return appState.localWhisperSetupIsRunning
            || appState.errorMessage == appState.localWhisperSetupMessage
    }

    @ViewBuilder
    private var advancedAudioContent: some View {
        localPerformanceContent
        silenceDetectionContent
    }

    @ViewBuilder
    private var localPerformanceContent: some View {
        if appState.settings.provider == .local,
           appState.settings.localTranscriptionEngine?.supportsPerformanceMode != false {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Picker(
                        localizer.text(.localWhisperPerformance),
                        selection: $appState.settings.localWhisperPerformanceMode
                    ) {
                        ForEach(LocalWhisperPerformanceMode.allCases) { mode in
                            Text(localizer.localWhisperPerformanceModeName(mode)).tag(mode)
                        }
                    }

                    SettingsRowFeedback(text: localizer.text(.localWhisperPerformanceHint))
                }
                .settingsSearchAnchor(.localWhisperPerformance, highlightedTarget: highlightedSearchTarget)
            } header: {
                SettingsSectionHeader(
                    title: localizer.localPerformanceLabel(),
                    target: .localWhisperPerformance
                )
            }
        }
    }

    @ViewBuilder
    private var silenceDetectionContent: some View {
        Section {
            Toggle(localizer.text(.ignoreSilentRecordings), isOn: $appState.settings.voiceActivityGateEnabled)
                .settingsSearchAnchor(.ignoreSilentRecordings, highlightedTarget: highlightedSearchTarget)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(localizer.text(.speechThreshold))
                    Slider(
                        value: $appState.settings.silenceThresholdDBFS,
                        in: -60 ... -25,
                        step: 1
                    )
                    Text(
                        appState.settings.whisperModeEnabled
                            ? localizer.automaticSpeechThresholdLabel()
                            : "\(Int(appState.settings.silenceThresholdDBFS)) dB"
                    )
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }
                .disabled(
                    !appState.settings.voiceActivityGateEnabled
                        || appState.settings.whisperModeEnabled
                )

                SettingsRowFeedback(text: localizer.speechThresholdDetail())
            }
            .settingsSearchAnchor(.speechThreshold, highlightedTarget: highlightedSearchTarget)

            HStack {
                Text(localizer.text(.minimumSpeech))
                Slider(
                    value: $appState.settings.minimumSpeechDuration,
                    in: 0.05 ... 0.8,
                    step: 0.05
                )
                Text(appState.settings.minimumSpeechDuration, format: .number.precision(.fractionLength(2)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(localizer.text(.secondsUnit))
                    .foregroundStyle(.secondary)
            }
            .disabled(!appState.settings.voiceActivityGateEnabled)
            .settingsSearchAnchor(.minimumSpeech, highlightedTarget: highlightedSearchTarget)
        } header: {
            SettingsSectionHeader(
                title: localizer.silenceDetectionLabel(),
                target: .advancedAudio
            )
        }
        .settingsSearchAnchor(.advancedAudio, highlightedTarget: highlightedSearchTarget)
    }

    private var localModelDisplayName: String {
        let modelPath = appState.settings.localWhisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelPath.isEmpty else {
            return localizer.text(.noLocalModelSelected)
        }

        return URL(fileURLWithPath: modelPath).lastPathComponent
    }

    private var localModelRecommendation: LocalWhisperModelRecommendation {
        LocalWhisperModelCatalog.recommendedOnboardingModel(
            for: appState.settings.selectedTranscriptionLanguages
        )
    }

    private var localWhisperModelURLs: [URL] {
        LocalWhisperModelCatalog.modelURLs(in: appState.settings.localWhisperModelDirectoryPath)
    }

    private var visibleManagedLocalWhisperModels: [LocalWhisperManagedModel] {
        LocalWhisperModelCatalog.managedModels
    }

    private var availableTranscriptionProviders: [TranscriptionProvider] {
        var providers: [TranscriptionProvider] = []
        if appState.isPluginEnabled(.providerLocalWhisper) {
            providers.append(.local)
        }
        if appState.isPluginEnabled(.providerOpenAI) {
            providers.append(.openAI)
        }
        if appState.isPluginEnabled(.providerElevenLabs) {
            providers.append(.elevenLabs)
        }
        if appState.isPluginEnabled(.providerAlibaba) {
            providers.append(.alibaba)
        }
        if appState.isPluginEnabled(.providerGemini) {
            providers.append(.gemini)
        }
        if providers.isEmpty {
            providers = [.local, .openAI, .elevenLabs, .alibaba, .gemini]
        }
        return providers
    }

    private func transcriptionLanguageBinding(_ language: TranscriptionLanguage) -> Binding<Bool> {
        Binding(
            get: { appState.settings.selectedTranscriptionLanguages.contains(language) },
            set: { isEnabled in
                appState.settings.setTranscriptionLanguage(language, isEnabled: isEnabled)
            }
        )
    }

    private var usesOpenAITextFeatures: Bool {
        featureVisibility.usesOpenAITextFeatures
    }

    private var shouldPrepareOpenAIModels: Bool {
        guard appState.settings.provider != .gemini else {
            return false
        }

        switch category {
        case .aiAndLLM, .architectureAIInference:
            return appState.settings.provider != .local
        case .transcription:
            return appState.settings.provider == .openAI || usesOpenAITextFeatures
        case .audio, .architectureVoiceInput, .architectureAudioProcessing,
             .architectureHumanCorrection:
            return false
        }
    }

    private var shouldAutomaticallyRefreshOpenAIModels: Bool {
        shouldPrepareOpenAIModels
            && (appState.settings.provider == .openAI || usesOpenAITextFeatures)
    }

    private var isTranscriptRetouchEnabled: Bool {
        featureVisibility.isTranscriptRetouchEnabled
    }

    private var isAIEmojiResolverEnabled: Bool {
        featureVisibility.isAIEmojiResolverEnabled
    }

    private var isVoiceEditEnabled: Bool {
        featureVisibility.isVoiceEditEnabled
    }

    private var isModifyVoiceCommandEnabled: Bool {
        appState.settings.voiceEditCommandsEnabled
            && appState.isPluginEnabled(.commandModifyPrevious)
    }

    private var effectiveVoiceEditCommandModeBinding: Binding<VoiceEditCommandMode> {
        Binding(
            get: {
                !isCloudTextAIAvailable
                    ? .localOnly
                    : appState.settings.voiceEditCommandMode
            },
            set: { mode in
                guard isCloudTextAIAvailable else {
                    return
                }
                appState.settings.voiceEditCommandMode = mode
            }
        )
    }

    private var featureVisibility: SettingsFeatureVisibility {
        SettingsFeatureVisibility(
            pluginConfiguration: appState.pluginConfiguration,
            provider: appState.settings.provider,
            transcriptRetouchEnabled: appState.settings.transcriptRetouchEnabled,
            emojiPostProcessingEnabled: appState.settings.emojiPostProcessingEnabled,
            aiEmojiResolverEnabled: appState.settings.aiEmojiResolverEnabled,
            voiceEditCommandsEnabled: appState.settings.voiceEditCommandsEnabled,
            voiceEditCommandMode: appState.settings.voiceEditCommandMode,
            openAITextModelSelectionMode: appState.settings.openAITextModelSelectionMode
        )
    }

    private var isCloudTextAIAvailable: Bool {
        CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: appState.settings)
    }

    private var cloudTextAIUnavailableDetail: String {
        appState.settings.provider == .local
            ? localizer.cloudAIUnavailableInLocalModeDetail()
            : localizer.disabledOpenAITextModelHint()
    }

    private var shouldShowUnavailableAudioInputDevice: Bool {
        let selectedID = appState.settings.audioInputDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !AudioInputDeviceCatalog.isSpecialDeviceID(selectedID) else {
            return false
        }

        return !appState.audioInputDevices.contains { $0.id == selectedID }
    }

    private func isSelectedManagedModel(_ model: LocalWhisperManagedModel) -> Bool {
        let selectedPath = appState.settings.localWhisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedPath.isEmpty else {
            return false
        }

        let selectedURL = URL(fileURLWithPath: selectedPath).standardizedFileURL
        return selectedURL == model.destinationURL(in: appState.settings.localWhisperModelDirectoryPath).standardizedFileURL
    }

    private var correctionLearningSnapshot: CorrectionLearningSnapshot {
        appState.correctionLearningSnapshot
    }

    private var visibleCorrectionLearningPatterns: [CorrectionLearningPattern] {
        CorrectionLearningPatternDisplayPolicy.visiblePatterns(
            from: correctionLearningSnapshot.patterns,
            enabledPatternIDs: appState.adaptiveRecognitionState.enabledCorrectionPatternIDs
        )
    }

    private var hasCorrectionData: Bool {
        correctionLearningSnapshot.evidenceEventCount > 0
            || !appState.adaptiveRecognitionState.correctionEvents.isEmpty
            || legacyCorrectionRecordCount > 0
    }

    private var correctionHintsLeaveThisMac: Bool {
        guard appState.settings.adaptiveRecognitionMode.usesVocabularyHints else {
            return false
        }
        switch appState.settings.provider {
        case .openAI:
            return appState.settings.effectiveModel != "gpt-4o-transcribe-diarize"
        case .elevenLabs, .gemini:
            return true
        case .local, .alibaba, .custom:
            return false
        }
    }

    private var correctionHintProviderLimitation: String? {
        guard appState.settings.adaptiveRecognitionMode.usesVocabularyHints else {
            return nil
        }
        switch appState.settings.provider {
        case .local:
            return localizer.cloudAIUnavailableInLocalModeDetail()
        case .alibaba:
            return localizer.correctionHintsUnavailableForAlibabaDetail()
        case .openAI where appState.settings.effectiveModel == "gpt-4o-transcribe-diarize":
            return localizer.correctionHintsUnavailableForDiarizationDetail()
        case .openAI, .elevenLabs, .gemini, .custom:
            return nil
        }
    }

    private var legacyCorrectionRecordCount: Int {
        max(
            appState.adaptiveRecognitionState.feedbackEvents.count,
            appState.adaptiveRecognitionState.learnedPreferences.count
        )
    }

    private func exportCorrectionData() {
        guard let url = chooseSaveFile(
            title: localizer.exportCorrectionDataLabel(),
            defaultFilename: "shuo-correction-data.json"
        ) else {
            return
        }

        do {
            try appState.exportCorrectionData(to: url)
        } catch {
            appState.reportError(error)
        }
    }

    private func chooseLocalWhisperExecutable() {
        guard let url = chooseFile(
            title: localizer.text(.localWhisperEngine),
            currentPath: appState.settings.localWhisperExecutablePath
        ) else {
            return
        }

        appState.settings.localWhisperExecutablePath = url.path
    }

    private func chooseLocalWhisperModelDirectory() {
        guard let url = chooseDirectory(
            title: localizer.text(.localWhisperModelDirectory),
            currentPath: appState.settings.localWhisperModelDirectoryPath
        ) else {
            return
        }

        appState.settings.localWhisperModelDirectoryPath = url.path
        appState.reloadLocalWhisperModels()
    }

    private func chooseFile(
        title: String,
        currentPath: String,
        allowedExtensions: [String] = []
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let trimmedPath = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: trimmedPath).deletingLastPathComponent()
        }

        let contentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        if !contentTypes.isEmpty {
            panel.allowedContentTypes = contentTypes
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseSaveFile(title: String, defaultFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseDirectory(title: String, currentPath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        let trimmedPath = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        }

        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct CorrectionLearningPatternRow: View {
    let pattern: CorrectionLearningPattern
    @Binding var isEnabled: Bool
    let localizer: AppLocalizer

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(localizer.useCorrectionPatternLabel())
                .accessibilityLabel(
                    localizer.useCorrectionPatternAccessibilityLabel(
                        observed: pattern.observedText,
                        preferred: pattern.preferredText
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(pattern.observedText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    Text(pattern.preferredText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(localizer.correctionLearningPatternStatus(pattern))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .textSelection(.enabled)

            Spacer(minLength: 12)

            Text("×\(pattern.observationCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
