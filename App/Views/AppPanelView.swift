import AppKit
import SwiftUI

enum AppPanelSection: String, CaseIterable, Identifiable {
    case general
    case transcription
    case vocabulary
    case aiAndLLM
    case postProcessing
    case audio
    case metrics
    case history
    case about
    case advanced
    case architecture

    var id: String { rawValue }

    var legacyNavigationDestination: AppPanelSection {
        self == .advanced ? .about : self
    }

    var defaultNavigationTarget: SettingsSearchTarget? {
        self == .architecture ? .architectureOverview : nil
    }

    static let sidebarNavigationOrder: [AppPanelSection] = [
        .general,
        .transcription,
        .history,
        .metrics,
        .architecture
    ]

    var systemImage: String {
        switch self {
        case .general:
            return "house"
        case .transcription:
            return "slider.horizontal.3"
        case .vocabulary:
            return "text.book.closed"
        case .aiAndLLM:
            return "sparkles"
        case .postProcessing:
            return "line.3.horizontal.decrease.circle"
        case .audio:
            return "waveform.badge.magnifyingglass"
        case .metrics:
            return "chart.bar.xaxis"
        case .history:
            return "clock.arrow.circlepath"
        case .about:
            return "info.circle"
        case .advanced:
            return "gearshape"
        case .architecture:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    func title(localizer: AppLocalizer) -> String {
        switch self {
        case .general:
            return localizer.homeLabel()
        case .transcription:
            return localizer.voiceInputLabel()
        case .vocabulary:
            return localizer.vocabularyLabel()
        case .aiAndLLM:
            return localizer.aiAndCommandsLabel()
        case .postProcessing:
            return localizer.textOutputLabel()
        case .audio:
            return localizer.advancedAudioLabel()
        case .metrics:
            return localizer.metricsLabel()
        case .history:
            return localizer.text(.history)
        case .about:
            return localizer.text(.about)
        case .advanced:
            return localizer.systemLabel()
        case .architecture:
            return localizer.advancedLabel()
        }
    }

    func sidebarTitle(localizer: AppLocalizer) -> String {
        switch self {
        case .architecture:
            return localizer.advancedLabel()
        case .postProcessing:
            return localizer.textOutputNavigationLabel()
        case .aiAndLLM:
            return localizer.aiNavigationLabel()
        case .audio:
            return localizer.audioNavigationLabel()
        default:
            return title(localizer: localizer)
        }
    }

    func isVisible(pluginConfiguration _: PluginConfiguration) -> Bool {
        switch self {
        case .advanced:
            return false
        case .general, .transcription, .vocabulary, .aiAndLLM, .postProcessing, .audio,
             .metrics, .history, .about, .architecture:
            return true
        }
    }
}

struct AppPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAdvancedTitleHovered = false

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    private var selectedSection: AppPanelSection {
        switch appState.selectedPanelSection {
        case .audio, .vocabulary, .aiAndLLM, .postProcessing:
            return .architecture
        case .advanced:
            return appState.selectedPanelSection.legacyNavigationDestination
        default:
            return visibleSections.contains(appState.selectedPanelSection)
                ? appState.selectedPanelSection
                : .general
        }
    }

    private var visibleSections: [AppPanelSection] {
        AppPanelSection.allCases.filter {
            $0.isVisible(pluginConfiguration: appState.pluginConfiguration)
        }
    }

    private var primarySections: [AppPanelSection] {
        AppPanelSection.sidebarNavigationOrder.filter {
            visibleSections.contains($0)
        }
    }

    var body: some View {
        Group {
            if appState.shouldShowOnboarding {
                ShuoOnboardingView()
            } else {
                mainPanel
            }
        }
        .frame(minWidth: 980, minHeight: 680)
    }

    private var mainPanel: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            ZStack(alignment: .topLeading) {
                rightPanel
                    .id(selectedSection.rawValue)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: selectedSection.rawValue
            )
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppBuildIdentity.displayName)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.top, 14)

            VStack(spacing: 4) {
                ForEach(primarySections) { section in
                    PanelSidebarRow(
                        title: section.sidebarTitle(localizer: localizer),
                        systemImage: section.systemImage,
                        isSelected: selectedSection == section
                    ) {
                        selectPanelSection(section)
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            PanelSidebarRow(
                title: AppPanelSection.about.title(localizer: localizer),
                systemImage: AppPanelSection.about.systemImage,
                isSelected: selectedSection == .about
            ) {
                selectPanelSection(.about)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedSection.systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            if selectedSection == .architecture {
                Button {
                    appState.navigateToSetting(
                        section: .architecture,
                        target: .architectureOverview
                    )
                } label: {
                    Text(localizer.advancedLabel())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            isAdvancedTitleHovered ? Color.accentColor : Color.primary
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isAdvancedTitleHovered = $0 }
                .help(localizer.architectureReturnToOverviewHint())
                .accessibilityHint(localizer.architectureReturnToOverviewHint())
            } else {
                Text(selectedSection.title(localizer: localizer))
                    .font(.title3.weight(.semibold))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func selectPanelSection(_ section: AppPanelSection) {
        let update = {
            if let target = section.defaultNavigationTarget {
                appState.navigateToSetting(
                    section: section,
                    target: target
                )
            } else {
                appState.selectedPanelSection = section
            }
        }

        if reduceMotion {
            update()
        } else {
            withAnimation(.easeOut(duration: 0.14), update)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .general:
            ShuoHomeView()
        case .transcription:
            SettingsView(category: .transcription)
        case .vocabulary:
            VocabularyView(controller: appState.projectVocabularyController)
        case .aiAndLLM:
            SettingsView(category: .aiAndLLM)
        case .postProcessing:
            PostProcessingView()
        case .audio:
            SettingsView(category: .audio)
        case .metrics:
            MetricsView()
        case .history:
            HistoryView()
        case .about, .advanced:
            AboutView()
        case .architecture:
            ArchitectureView()
        }
    }
}

private struct ShuoHomeView: View {
    @EnvironmentObject private var appState: AppState

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            Image(nsImage: StatusIconArtwork.image(style: .ready))
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .frame(width: 58, height: 58)

            Text(localizer.holdSpeakReleaseTitle())
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .padding(.top, 24)

            HStack(spacing: 6) {
                let prefix = localizer.homeShortcutInstructionPrefix()
                if !prefix.isEmpty {
                    Text(prefix)
                }

                Picker(
                    localizer.text(.shortcut),
                    selection: Binding(
                        get: { appState.settings.pushToTalkShortcut },
                        set: { appState.setPushToTalkShortcut($0) }
                    )
                ) {
                    ForEach(PushToTalkShortcut.pickerCases) { shortcut in
                        Text(localizer.shortcutName(shortcut)).tag(shortcut)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                Text(localizer.homeShortcutInstructionSuffix())
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.top, 20)

            if appState.settings.pushToTalkShortcut == .custom {
                CustomPushToTalkShortcutRecorder(
                    currentShortcut: appState.settings.customPushToTalkShortcut,
                    localizer: localizer,
                    onRecord: appState.setCustomPushToTalkShortcut
                )
                .frame(maxWidth: 520)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if shouldShowPushToTalkStatus {
                Text(appState.pushToTalkStatusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.top, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowPushToTalkStatus: Bool {
        let readyMessage = localizer.holdToDictate(
            shortcut: appState.settings.pushToTalkShortcut,
            customShortcut: appState.settings.customPushToTalkShortcut
        )
        return !appState.pushToTalkStatusMessage.isEmpty
            && appState.pushToTalkStatusMessage != readyMessage
    }
}

struct SettingsSearchView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var selectedItemID: String?
    @FocusState private var isSearchFocused: Bool

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
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

    private var items: [SettingsSearchItem] {
        SettingsSearchIndex.items(
            localizer: localizer,
            context: SettingsSearchContext(
                provider: appState.settings.provider,
                pluginConfiguration: appState.pluginConfiguration,
                supportsDirectUpdates: appState.supportsDirectUpdates,
                showsUpdateSettings: appState.supportsDirectUpdates || !AppRuntime.isCommunityBuild,
                recordingStartSoundEnabled: appState.settings.recordingStartSoundEnabled,
                projectVocabularyEnabled: appState.projectVocabularyController.state.isProjectVocabularyEnabled,
                selectedTranscriptionLanguages: appState.settings.selectedTranscriptionLanguages,
                useCustomCorrections: appState.settings.useCustomCorrections,
                transcriptRetouchEnabled: appState.settings.transcriptRetouchEnabled,
                emojiPostProcessingEnabled: appState.settings.emojiPostProcessingEnabled,
                aiEmojiResolverEnabled: appState.settings.aiEmojiResolverEnabled,
                voiceEditCommandsEnabled: appState.settings.voiceEditCommandsEnabled,
                voiceEditCommandMode: appState.settings.voiceEditCommandMode,
                openAITextModelSelectionMode: appState.settings.openAITextModelSelectionMode
            )
        )
    }

    private var results: [SettingsSearchItem] {
        SettingsSearchIndex.search(query, in: items, limit: 6)
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            searchField

            if hasQuery {
                searchResults
                    .transition(reduceMotion ? .identity : .opacity)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: 520)
        .zIndex(hasQuery ? 10 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hasQuery)
        .background {
            Button {
                isSearchFocused = true
            } label: {
                Text(localizer.settingsSearchPlaceholder())
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onChange(of: query) { _, _ in
            selectedItemID = results.first?.id
        }
        .onChange(of: appState.settings.appLanguage) { _, _ in
            selectedItemID = results.first?.id
        }
        .onChange(of: appState.pluginConfiguration) { _, _ in
            selectedItemID = results.first?.id
        }
        .onChange(of: appState.settings.provider) { _, _ in
            selectedItemID = results.first?.id
        }
        .onChange(of: appState.projectVocabularyController.state.isProjectVocabularyEnabled) { _, _ in
            selectedItemID = results.first?.id
        }
        .onChange(of: featureVisibility) { _, _ in
            selectedItemID = results.first?.id
        }
        .onChange(of: appState.settings.openAITextModelSelectionMode) { _, _ in
            selectedItemID = results.first?.id
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(localizer.settingsSearchPlaceholder(), text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel(localizer.settingsSearchPlaceholder())
                .onSubmit(activateSelectedResult)
                .onKeyPress(keys: [.upArrow, .downArrow, .escape], phases: .down) { keyPress in
                    handleKeyPress(keyPress.key)
                }

            if hasQuery {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localizer.text(.clear))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isSearchFocused
                        ? Color.accentColor.opacity(0.58)
                        : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                Text(localizer.settingsSearchNoResults())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 13)
            .frame(height: 42)
            .settingsSearchResultsSurface()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 42)
                    }

                    Button {
                        activate(item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.section.systemImage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            Text(item.title)
                                .lineLimit(1)

                            Spacer(minLength: 12)

                            Text(item.pageTitle)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)

                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(
                            selectedItemID == item.id
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        if isHovering {
                            selectedItemID = item.id
                        }
                    }
                    .accessibilityLabel("\(item.title), \(item.pageTitle)")
                }
            }
            .settingsSearchResultsSurface()
        }
    }

    private func handleKeyPress(_ key: KeyEquivalent) -> KeyPress.Result {
        guard hasQuery else {
            return .ignored
        }

        switch key {
        case .upArrow:
            moveSelection(by: -1)
            return results.isEmpty ? .ignored : .handled
        case .downArrow:
            moveSelection(by: 1)
            return results.isEmpty ? .ignored : .handled
        case .escape:
            clearSearch()
            return .handled
        default:
            return .ignored
        }
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            selectedItemID = nil
            return
        }

        let currentIndex = results.firstIndex { $0.id == selectedItemID } ?? 0
        let nextIndex = (currentIndex + offset + results.count) % results.count
        selectedItemID = results[nextIndex].id
    }

    private func activateSelectedResult() {
        let selected = results.first { $0.id == selectedItemID } ?? results.first
        if let selected {
            activate(selected)
        }
    }

    private func activate(_ item: SettingsSearchItem) {
        appState.navigateToSetting(item)
        clearSearch()
    }

    private func clearSearch() {
        query = ""
        selectedItemID = nil
    }
}

private extension View {
    func settingsSearchResultsSurface() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct ShuoOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var onboardingLocalModelID = LocalWhisperModelCatalog.defaultOnboardingModelID
    @State private var usesAutomaticOnboardingModelRecommendation = true
    @State private var onboardingChineseMode: ChineseTextConversionMode = .simplified
    @State private var hasInitializedChineseMode = false
    @State private var hasChosenChineseMode = false

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppBuildIdentity.displayName)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(localizer.onboardingSubtitle())
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker(localizer.text(.appLanguage), selection: $appState.settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeDisplayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            Divider().padding(.vertical, 24)

            HStack(alignment: .top, spacing: 42) {
                VStack(alignment: .leading, spacing: 22) {
                    onboardingSectionTitle("1", localizer.onboardingShortcutTitle())

                    Text(localizer.holdSpeakReleaseTitle())
                        .font(.title2.weight(.semibold))
                    Text(localizer.onboardingShortcutDetail())
                        .foregroundStyle(.secondary)

                    Picker(localizer.text(.shortcut), selection: Binding(
                        get: { appState.settings.pushToTalkShortcut },
                        set: { appState.setPushToTalkShortcut($0) }
                    )) {
                        ForEach(PushToTalkShortcut.pickerCases) { shortcut in
                            Text(localizer.shortcutName(shortcut)).tag(shortcut)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    if appState.settings.pushToTalkShortcut == .custom {
                        CustomPushToTalkShortcutRecorder(
                            currentShortcut: appState.settings.customPushToTalkShortcut,
                            localizer: localizer,
                            onRecord: appState.setCustomPushToTalkShortcut
                        )
                        .frame(maxWidth: 360)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    onboardingSectionTitle("2", localizer.onboardingPermissionsTitle())
                    permissionRow(
                        localizer.onboardingMicrophoneLabel(),
                        granted: appState.microphonePermissionGranted,
                        action: appState.requestMicrophonePermission
                    )
                    permissionRow(
                        localizer.onboardingAccessibilityLabel(),
                        granted: appState.accessibilityPermissionGranted,
                        action: appState.requestAccessibilityPermission
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    onboardingSectionTitle("3", localizer.onboardingProviderTitle())

                    Picker(localizer.text(.provider), selection: $appState.settings.provider) {
                        ForEach(onboardingProviders) { provider in
                            Text(localizer.providerName(provider)).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(appState.localWhisperSetupIsRunning)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizer.onboardingLanguageLabel())
                            .font(.callout.weight(.medium))

                        if appState.settings.availableTranscriptionLanguages.count == 1,
                           let language = appState.settings.availableTranscriptionLanguages.first {
                            Label(
                                localizer.transcriptionLanguageName(language),
                                systemImage: "lock.fill"
                            )
                            .foregroundStyle(.secondary)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 18) {
                                    onboardingLanguageToggles
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    onboardingLanguageToggles
                                }
                            }
                        }

                        Text(
                            appState.settings.availableTranscriptionLanguages.count == 1
                                ? localizer.localWhisperEnglishOnlyLanguageHint()
                                : localizer.transcriptionLanguageSelectionDetail()
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if appState.settings.provider == .local {
                        providerExplanation(
                            systemImage: "lock.laptopcomputer",
                            title: localizer.onboardingLocalTitle(),
                            detail: localizer.onboardingLocalDetail()
                        )

                        onboardingLocalModelSetup
                    } else if appState.settings.provider == .openAI {
                        providerExplanation(
                            systemImage: "cloud",
                            title: localizer.openAICompatibleProviderLabel(),
                            detail: localizer.onboardingCloudDetail()
                        )

                        SecureField(localizer.text(.apiKey), text: Binding(
                            get: { appState.openAIAPIKey },
                            set: { appState.updateOpenAIAPIKey($0) }
                        ))

                        apiKeyGuideLink(for: .openAI)
                    } else if appState.settings.provider == .elevenLabs {
                        providerExplanation(
                            systemImage: "cloud",
                            title: localizer.providerName(.elevenLabs),
                            detail: localizer.onboardingElevenLabsDetail()
                        )

                        SecureField(localizer.text(.apiKey), text: Binding(
                            get: { appState.elevenLabsAPIKey },
                            set: { appState.updateElevenLabsAPIKey($0) }
                        ))

                        apiKeyGuideLink(for: .elevenLabs)
                    } else if appState.settings.provider == .alibaba {
                        providerExplanation(
                            systemImage: "cloud",
                            title: localizer.providerName(.alibaba),
                            detail: localizer.onboardingAlibabaDetail()
                        )

                        SecureField(localizer.text(.apiKey), text: Binding(
                            get: { appState.alibabaAPIKey },
                            set: { appState.updateAlibabaAPIKey($0) }
                        ))

                        apiKeyGuideLink(for: .alibaba)
                    } else if appState.settings.provider == .gemini {
                        providerExplanation(
                            systemImage: "cloud",
                            title: localizer.providerName(.gemini),
                            detail: localizer.onboardingGeminiDetail()
                        )

                        SecureField(localizer.text(.apiKey), text: Binding(
                            get: { appState.geminiAPIKey },
                            set: { appState.updateGeminiAPIKey($0) }
                        ))

                        apiKeyGuideLink(for: .gemini)
                    }

                    Spacer(minLength: 8)

                    Text(localizer.onboardingRecordingRetentionHint())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        onboardingStatusMessage,
                        systemImage: onboardingStatusSystemImage
                    )
                    .font(.caption)
                    .foregroundStyle(onboardingStatusColor)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if appState.settings.includesChineseTranscription {
                            appState.setPreferredChineseTextConversionMode(
                                onboardingChineseMode
                            )
                        }
                        if appState.completeOnboarding(if: onboardingReadiness) {
                            appState.selectedPanelSection = .general
                        }
                    } label: {
                        Text(localizer.onboardingContinueLabel())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!onboardingReadiness.canStart || appState.localWhisperSetupIsRunning)

                    if !onboardingReadiness.canStart {
                        Button(localizer.onboardingSetUpLaterLabel()) {
                            appState.skipOnboardingSetup()
                            appState.selectedPanelSection = .general
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .disabled(appState.localWhisperSetupIsRunning)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            }
            .padding(38)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .onAppear {
            appState.refreshSystemPermissions()
            appState.reloadLocalWhisperModels()
            synchronizeOnboardingLocalModelSelection()
            synchronizeOnboardingChineseMode()
            loadCredentialForSelectedProvider()
        }
        .onChange(of: appState.settings.appLanguage) { _, _ in
            synchronizeOnboardingChineseMode(forLanguageChange: true)
        }
        .onChange(of: appState.settings.provider) { _, _ in
            loadCredentialForSelectedProvider()
            synchronizeOnboardingLocalModelSelection()
        }
        .onChange(of: appState.settings.selectedTranscriptionLanguages) { _, _ in
            updateOnboardingModelRecommendationIfNeeded()
        }
        .onChange(of: onboardingLocalModelID) { _, _ in
            useSelectedOnboardingModelIfInstalled()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshSystemPermissions()
        }
    }

    private var onboardingReadiness: OnboardingReadiness {
        OnboardingReadiness.evaluate(
            provider: appState.settings.provider,
            openAIAPIKey: appState.openAIAPIKey,
            elevenLabsAPIKey: appState.elevenLabsAPIKey,
            localModelIsReady: selectedOnboardingLocalModelIsReady,
            microphonePermissionGranted: appState.microphonePermissionGranted,
            accessibilityPermissionGranted: appState.accessibilityPermissionGranted,
            alibabaAPIKey: appState.alibabaAPIKey,
            geminiAPIKey: appState.geminiAPIKey
        )
    }

    private var onboardingStatusMessage: String {
        if !onboardingReadiness.providerIsReady {
            return appState.settings.provider == .local
                ? localizer.onboardingLocalModelRequiredHint()
                : localizer.onboardingAPIKeyRequiredHint()
        }
        if !onboardingReadiness.permissionsAreReady {
            return localizer.onboardingPermissionsRequiredHint()
        }
        return appState.settings.provider == .local
            ? localizer.onboardingReadyLabel()
            : localizer.onboardingCloudCredentialPendingVerificationLabel()
    }

    private var onboardingStatusSystemImage: String {
        guard onboardingReadiness.canStart else {
            return "exclamationmark.circle"
        }
        return appState.settings.provider == .local
            ? "checkmark.circle.fill"
            : "key.horizontal"
    }

    private var onboardingStatusColor: Color {
        guard onboardingReadiness.canStart else {
            return .orange
        }
        return appState.settings.provider == .local ? .green : .secondary
    }

    private var onboardingLocalModels: [LocalWhisperManagedModel] {
        LocalWhisperModelCatalog.onboardingModels
    }

    private var selectedOnboardingLocalModel: LocalWhisperManagedModel? {
        onboardingLocalModels.first { $0.id == onboardingLocalModelID }
    }

    private var selectedOnboardingLocalModelIsReady: Bool {
        guard let model = selectedOnboardingLocalModel,
              appState.isManagedLocalWhisperModelInstalled(model) else {
            return false
        }

        let selectedPath = appState.settings.localWhisperModelPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedPath.isEmpty else {
            return false
        }

        return URL(fileURLWithPath: selectedPath).standardizedFileURL
            == model.destinationURL(
                in: appState.settings.localWhisperModelDirectoryPath
            ).standardizedFileURL
    }

    @ViewBuilder
    private var onboardingLocalModelSetup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker(
                localizer.onboardingLocalModelLabel(),
                selection: Binding(
                    get: { onboardingLocalModelID },
                    set: { selectedID in
                        usesAutomaticOnboardingModelRecommendation = false
                        onboardingLocalModelID = selectedID
                    }
                )
            ) {
                ForEach(onboardingLocalModels) { model in
                    Text(onboardingModelPickerLabel(model)).tag(model.id)
                }
            }
            .disabled(appState.localWhisperSetupIsRunning)

            if let model = selectedOnboardingLocalModel {
                Text(localizer.localWhisperManagedModelSummary(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(localizer.localWhisperManagedModelNote(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appState.localWhisperActiveManagedModelID == model.id {
                    if let progress = appState.localWhisperDownloadProgress {
                        ProgressView(value: progress.fractionCompleted)
                        HStack {
                            Text("\(Int((progress.fractionCompleted * 100).rounded(.down)))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(localizer.cancelTranscriptionLabel()) {
                                appState.cancelManagedLocalWhisperModelDownload()
                            }
                            .controlSize(.small)
                            .accessibilityLabel(
                                localizer.cancelLocalWhisperModelDownloadLabel(model)
                            )
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if selectedOnboardingLocalModelIsReady {
                    Label(localizer.onboardingReadyLabel(), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if appState.isManagedLocalWhisperModelInstalled(model) {
                    Button(localizer.text(.use)) {
                        appState.useManagedLocalWhisperModel(model)
                    }
                    .controlSize(.small)
                    .accessibilityLabel(localizer.useLocalWhisperModelLabel(model))
                } else {
                    Button(localizer.text(.download)) {
                        appState.downloadManagedLocalWhisperModel(model)
                    }
                    .controlSize(.small)
                    .disabled(appState.localWhisperSetupIsRunning)
                    .accessibilityLabel(localizer.downloadLocalWhisperModelLabel(model))
                }
            }

            if !appState.localWhisperSetupMessage.isEmpty {
                Text(appState.localWhisperSetupMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func onboardingModelPickerLabel(_ model: LocalWhisperManagedModel) -> String {
        let label = "\(model.displayName) — \(localizer.localWhisperManagedModelPickerNote(model))"
        guard model.id == recommendedOnboardingLocalModelID else {
            return label
        }
        return "\(label) · \(localizer.localModelRecommendationLabel(recommendedOnboardingLocalModelRecommendation))"
    }

    private var recommendedOnboardingLocalModelID: String {
        recommendedOnboardingLocalModelRecommendation.modelID
    }

    private var recommendedOnboardingLocalModelRecommendation: LocalWhisperModelRecommendation {
        LocalWhisperModelCatalog.recommendedOnboardingModel(
            for: appState.settings.selectedTranscriptionLanguages
        )
    }

    private func synchronizeOnboardingLocalModelSelection() {
        guard appState.settings.provider == .local else {
            return
        }

        let currentModelPath = appState.settings.localWhisperModelPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentModelPath.isEmpty,
           let currentModel = onboardingLocalModels.first(where: {
               $0.destinationURL(in: appState.settings.localWhisperModelDirectoryPath)
                   .standardizedFileURL
                   == URL(fileURLWithPath: currentModelPath).standardizedFileURL
           }) {
            usesAutomaticOnboardingModelRecommendation = false
            onboardingLocalModelID = currentModel.id
            return
        }

        // Reopening Welcome is also a supported settings flow. Never replace a
        // valid retired or manually selected model merely because it is not
        // one of the three curated onboarding choices.
        if !currentModelPath.isEmpty,
           FileManager.default.fileExists(atPath: currentModelPath) {
            return
        }

        if let installedModel = onboardingLocalModels.first(where: {
            appState.isManagedLocalWhisperModelInstalled($0)
        }) {
            usesAutomaticOnboardingModelRecommendation = false
            onboardingLocalModelID = installedModel.id
            appState.useManagedLocalWhisperModel(installedModel)
            return
        }

        if !onboardingLocalModels.contains(where: { $0.id == onboardingLocalModelID }) {
            onboardingLocalModelID = recommendedOnboardingLocalModelID
        }
    }

    private func updateOnboardingModelRecommendationIfNeeded() {
        guard appState.settings.provider == .local,
              usesAutomaticOnboardingModelRecommendation,
              !selectedOnboardingLocalModelIsReady,
              !appState.localWhisperSetupIsRunning else {
            return
        }
        onboardingLocalModelID = recommendedOnboardingLocalModelID
    }

    private func useSelectedOnboardingModelIfInstalled() {
        guard appState.settings.provider == .local,
              !appState.localWhisperSetupIsRunning,
              let model = selectedOnboardingLocalModel,
              appState.isManagedLocalWhisperModelInstalled(model),
              !selectedOnboardingLocalModelIsReady else {
            return
        }
        appState.useManagedLocalWhisperModel(model)
    }

    private func loadCredentialForSelectedProvider() {
        switch appState.settings.provider {
        case .openAI:
            appState.loadOpenAIAPIKeyIfNeeded()
        case .elevenLabs:
            appState.loadElevenLabsAPIKeyIfNeeded()
        case .alibaba:
            appState.loadAlibabaAPIKeyIfNeeded()
        case .gemini:
            appState.loadGeminiAPIKeyIfNeeded()
        case .local, .custom:
            break
        }
    }

    private var onboardingProviders: [TranscriptionProvider] {
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
        return providers.isEmpty ? [.local, .openAI, .elevenLabs, .alibaba, .gemini] : providers
    }

    @ViewBuilder
    private var onboardingLanguageToggles: some View {
        ForEach(appState.settings.availableTranscriptionLanguages) { language in
            if language == .chinese {
                HStack(spacing: 8) {
                    onboardingLanguageToggle(language)

                    if appState.settings.includesChineseTranscription {
                        Picker(
                            localizer.chineseScriptOutputLabel(),
                            selection: Binding(
                                get: { onboardingChineseMode },
                                set: { mode in
                                    onboardingChineseMode = mode
                                    hasChosenChineseMode = true
                                }
                            )
                        ) {
                            ForEach(ChineseTextConversionMode.explicitCases) { mode in
                                Text(localizer.chineseTextConversionModeName(mode))
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 156)
                        .transition(.opacity)
                    }
                }
            } else {
                onboardingLanguageToggle(language)
            }
        }
    }

    private func onboardingLanguageToggle(
        _ language: TranscriptionLanguage
    ) -> some View {
        Toggle(
            localizer.transcriptionLanguageName(language),
            isOn: Binding(
                get: {
                    appState.settings.selectedTranscriptionLanguages.contains(language)
                },
                set: { isEnabled in
                    appState.settings.setTranscriptionLanguage(
                        language,
                        isEnabled: isEnabled
                    )
                }
            )
        )
        .toggleStyle(.checkbox)
        .disabled(
            appState.settings.selectedTranscriptionLanguages == Set([language])
        )
    }

    private func synchronizeOnboardingChineseMode(
        forLanguageChange: Bool = false
    ) {
        if forLanguageChange,
           (hasChosenChineseMode
            || appState.settings.chineseTextConversionMode != .keep
            || appState.settings.chineseScriptPreference != .automatic) {
            return
        }

        guard !hasInitializedChineseMode || forLanguageChange else {
            return
        }
        onboardingChineseMode = appState.settings.resolvedChineseTextConversionMode
        hasInitializedChineseMode = true
    }

    private func onboardingSectionTitle(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            Text(title)
                .font(.headline)
        }
    }

    private func permissionRow(
        _ title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            if granted {
                Text(localizer.permissionGrantedLabel())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(localizer.onboardingAllowLabel(), action: action)
                    .controlSize(.small)
            }
        }
    }

    private func providerExplanation(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func apiKeyGuideLink(for provider: TranscriptionProvider) -> some View {
        if let destination = CloudTranscriptionProviderConfiguration.apiKeyGuideURL(for: provider) {
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
}

private struct PanelSidebarRow: View {
    @Environment(\.controlActiveState) private var controlActiveState

    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)

                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .foregroundStyle(
                isSelected
                    ? selectedForeground
                    : Color.primary
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return controlActiveState == .inactive
                ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                : Color(nsColor: .selectedContentBackgroundColor)
        }

        if isHovered {
            return Color.secondary.opacity(0.12)
        }

        return Color.clear
    }

    private var selectedForeground: Color {
        controlActiveState == .inactive
            ? Color.primary
            : Color(nsColor: .selectedMenuItemTextColor)
    }
}

#Preview {
    AppPanelView()
        .environmentObject(AppState())
}
