import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Foundation
import OSLog
import ServiceManagement

private struct LastShuoInsertion {
    let id: UUID = UUID()
    var text: String
    var historyID: UUID?
    var date: Date
    var bundleIdentifier: String?
    var applicationProcessIdentifier: pid_t?
    var focusedTextTarget: FocusedTextTarget?
    var observedExternalInteraction: Bool
    var preservesTrailingNewline: Bool

    func canSafelyRewrite(in currentBundleIdentifier: String?, shuoBundleIdentifier: String?) -> Bool {
        guard Date().timeIntervalSince(date) <= 180 else {
            return false
        }

        guard let bundleIdentifier, let currentBundleIdentifier else {
            return false
        }

        return bundleIdentifier == currentBundleIdentifier
    }
}

struct ReplacementTransactionToken: Equatable {
    let revision: UInt64
}

struct ReplacementTransactionGate {
    private(set) var revision: UInt64 = 0
    private(set) var activeToken: ReplacementTransactionToken?

    var hasActiveTransaction: Bool {
        activeToken != nil
    }

    mutating func begin() -> ReplacementTransactionToken? {
        guard activeToken == nil else {
            return nil
        }
        revision &+= 1
        let token = ReplacementTransactionToken(revision: revision)
        activeToken = token
        return token
    }

    mutating func invalidate() {
        revision &+= 1
    }

    func isCurrent(_ token: ReplacementTransactionToken) -> Bool {
        activeToken == token && token.revision == revision
    }

    mutating func finish(_ token: ReplacementTransactionToken) {
        guard activeToken == token else {
            return
        }
        activeToken = nil
    }
}

private struct PendingReplacementTransaction {
    let token: ReplacementTransactionToken
    let task: Task<Bool, Never>
}

private struct PreparedReplacementTarget {
    let processIdentifier: pid_t
    let allowsGuardedBackspaceFallback: Bool
}

private enum ReplacementTargetFailureFallback {
    case correction(
        text: String,
        source: AdaptiveRecognitionFeedbackSource
    )
    case deletion
}

private struct RecordingInputTarget {
    let applicationProcessIdentifier: pid_t
    let bundleIdentifier: String?
    let focusedTextTarget: FocusedTextTarget?
}

private enum VoiceEditResolution {
    case local(String)
    case llm(String)
}

private enum PluginFeatureError: LocalizedError {
    case disabledProvider(String)

    var errorDescription: String? {
        switch self {
        case .disabledProvider(let provider):
            return "The \(provider) transcription provider is disabled by the current plugin configuration."
        }
    }
}

private struct DraftFeedbackBaseline {
    var text: String
    var context: AdaptiveRecognitionFeedbackContext
}

struct FloatingCorrectionSession: Identifiable, Equatable {
    let id: UUID
    let originalText: String
    let hidesTrailingNewline: Bool
    let punctuationMode: PunctuationPostProcessingMode
    let boundaryMode: TranscriptInsertionBoundaryMode

    init(
        id: UUID = UUID(),
        originalText: String,
        hidesTrailingNewline: Bool = false,
        punctuationMode: PunctuationPostProcessingMode = .keep,
        boundaryMode: TranscriptInsertionBoundaryMode? = nil
    ) {
        let resolvedBoundaryMode = boundaryMode
            ?? (hidesTrailingNewline
                ? .newline
                : (originalText.hasSuffix(" ") ? .smartSpace : .none))
        self.id = id
        self.originalText = originalText
        self.hidesTrailingNewline = resolvedBoundaryMode == .newline
        self.punctuationMode = punctuationMode
        self.boundaryMode = resolvedBoundaryMode
    }

    var correctionText: String {
        guard let trailingHiddenSeparator else {
            return originalText
        }
        return String(originalText.dropLast(trailingHiddenSeparator.count))
    }

    func replacementText(for correctedText: String) -> String {
        // The correction editor is authoritative. Automatic punctuation is a
        // transcription default, so it must not restore punctuation that the
        // user deliberately removed while editing. Explicit remove/replace
        // modes still apply as configured.
        let correctionPunctuationMode: PunctuationPostProcessingMode =
            punctuationMode == .automatic ? .keep : punctuationMode
        let replacement = TranscriptInsertionBoundaryPolicy.apply(
            to: correctedText,
            punctuationMode: correctionPunctuationMode,
            mode: boundaryMode
        )
        guard boundaryMode == .newline,
              originalText.hasSuffix("\r\n"),
              replacement.hasSuffix("\n") else {
            return replacement
        }
        return String(replacement.dropLast()) + "\r\n"
    }

    func advancingAfterSuccessfulReplacement(
        from previousText: String,
        to replacementText: String
    ) -> FloatingCorrectionSession? {
        guard originalText == previousText else {
            return nil
        }

        return FloatingCorrectionSession(
            id: id,
            originalText: replacementText,
            punctuationMode: punctuationMode,
            boundaryMode: boundaryMode
        )
    }

    private var trailingHiddenSeparator: String? {
        if boundaryMode == .newline, originalText.hasSuffix("\r\n") {
            return "\r\n"
        }
        if boundaryMode == .newline,
           let last = originalText.last,
           last.isNewline {
            return String(last)
        }
        return boundaryMode == .smartSpace && originalText.hasSuffix(" ") ? " " : nil
    }
}

private struct ProcessedTranscription {
    var rawText: String
    var locallyProcessedText: String
    var text: String
    var provider: TranscriptionProvider
    var model: String
    var languageHint: LanguageHint
    var detectedLanguageCode: String?
    var appendsTrailingNewline: Bool
    var punctuationMode: PunctuationPostProcessingMode
    var insertionBoundaryMode: TranscriptInsertionBoundaryMode
}

private struct HandledVoiceCommandTranscription {
    var rawText: String
    var locallyProcessedText: String
    var provider: TranscriptionProvider
    var model: String
    var languageHint: LanguageHint
    var detectedLanguageCode: String?
}

private enum AudioProcessingResult {
    case transcription(ProcessedTranscription)
    case handledVoiceCommand(HandledVoiceCommandTranscription)
}

@MainActor
final class AppState: ObservableObject {
    private static let insertionTargetLogger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "InsertionTarget"
    )
    private static let correctionLogger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "FloatingCorrection"
    )

    @Published var settings: AppSettings {
        didSet {
            var normalized = settings
            normalized.normalizeSelections()
            if normalized != settings {
                settings = normalized
                return
            }
            persist(settings, key: Self.settingsKey)

            if settings.openAIBaseURL != oldValue.openAIBaseURL
                || settings.openAIOrganizationID != oldValue.openAIOrganizationID
                || settings.openAIProjectID != oldValue.openAIProjectID {
                resetOpenAIModelAvailability()
                if settings.provider != .gemini {
                    scheduleOpenAIModelRefresh(forceRefresh: false)
                }
            }

            if settings.provider == .gemini,
               oldValue.provider != .gemini {
                // A switch to Gemini must leave no pending OpenAI model
                // availability request running in the background.
                resetOpenAIModelAvailability()
            }

            if settings.pushToTalkEnabled != oldValue.pushToTalkEnabled
                || settings.pushToTalkShortcut != oldValue.pushToTalkShortcut
                || settings.customPushToTalkShortcut != oldValue.customPushToTalkShortcut
                || settings.appLanguage != oldValue.appLanguage {
                configurePushToTalkMonitor()
            }
            if settings.showDockIcon != oldValue.showDockIcon {
                AppDockIconController.apply(showDockIcon: settings.showDockIcon)
            }
            appUpdateController.appLanguage = settings.appLanguage
        }
    }

    @Published var pluginConfiguration: PluginConfiguration {
        didSet {
            PluginConfigurationStore.save(pluginConfiguration)
            normalizeProviderForPluginConfiguration()
        }
    }

    @Published var history: [TranscriptItem] {
        didSet {
            do {
                try transcriptHistoryStore.save(history)
                historyStorageIsWritable = true
            } catch {
                historyStorageIsWritable = false
                errorMessage = localizer.historySaveFailed(error.localizedDescription)
            }
            scheduleCorrectionLearningSnapshotRefresh()
        }
    }

    @Published private(set) var metricsRecords: [TranscriptMetricsRecord] {
        didSet {
            metricsCounters = metricsCounters.mergedMonotonic(
                with: metricsCalculator.counters(from: metricsRecords)
            )

            guard !AppRuntime.isRunningUnderXCTest else {
                return
            }

            do {
                try metricsStore.save(records: metricsRecords, counters: metricsCounters)
            } catch {
                errorMessage = localizer.metricsSaveFailed(error.localizedDescription)
            }
        }
    }

    @Published private(set) var metricsCounters: MetricsCounters

    var metricsRecordsForDisplay: [TranscriptMetricsRecord] {
        metricsCalculator.recordsForDisplay(
            metricsRecords,
            cutoff: metricsCounters.displayCutoff
        )
    }

    var metricsCountersForDisplay: MetricsCounters {
        metricsCalculator.counters(from: metricsRecordsForDisplay)
    }

    @Published private(set) var adaptiveRecognitionState: AdaptiveRecognitionState {
        didSet {
            do {
                try adaptiveRecognitionStore.save(adaptiveRecognitionState)
            } catch {
                errorMessage = localizer.personalizationSaveFailed(error.localizedDescription)
            }
            scheduleCorrectionLearningSnapshotRefresh()
        }
    }

    @Published private(set) var correctionLearningSnapshot = CorrectionLearningSnapshot.empty

    @Published var selectedPanelSection = AppPanelSection.general
    @Published private(set) var settingsNavigationRequest: SettingsNavigationRequest?
    @Published var currentDraft = ""
    @Published var errorMessage: String?
    @Published private(set) var learningNoticeMessage: String?
    @Published private(set) var floatingCorrectionSession: FloatingCorrectionSession?
    @Published private(set) var replacementSafetySessionID: UUID?
    @Published private(set) var openAIAPIKey = ""
    @Published private(set) var elevenLabsAPIKey = ""
    @Published private(set) var alibabaAPIKey = ""
    @Published private(set) var geminiAPIKey = ""
    @Published private(set) var openAIAvailableModelIDs = Set<String>()
    @Published private(set) var openAIModelAvailabilityFetchedAt: Date?
    @Published private(set) var openAIModelAvailabilityError: String?
    @Published private(set) var isRefreshingOpenAIModels = false
    @Published private(set) var pushToTalkStatusMessage = ""
    @Published private(set) var isPreparingMicrophone = false
    @Published private(set) var isRecording = false
    @Published private(set) var localWhisperSetupMessage = ""
    @Published private(set) var localWhisperSetupIsRunning = false
    @Published private(set) var localWhisperActiveManagedModelID: String?
    @Published private(set) var localWhisperDownloadProgress: LocalWhisperDownloadProgress?
    @Published private(set) var updateStatusMessage = ""
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published private(set) var playingAudioHistoryID: UUID?
    @Published private(set) var latestTranscriptAudioHistoryID: UUID?
    @Published private(set) var historyStorageIsWritable = true
    @Published private(set) var microphonePermissionGranted =
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published private(set) var accessibilityPermissionGranted =
        RightOptionPushToTalkMonitor.hasAccessibilityPermission
    @Published private var status: AppStatus = .ready

    private static let settingsKey = "settings"
    private let recordingSession = RecordingSessionCoordinator()
    private let audioActivityAnalyzer = AudioActivityAnalyzer()
    private let whisperAudioNormalizer = WhisperAudioNormalizer()
    private let transcriptAudioStore = TranscriptAudioStore()
    private let transcriptHistoryStore = TranscriptHistoryStore()
    private let metricsStore = MetricsStore()
    private let metricsCalculator = MetricsCalculator()
    private let transcriptAudioPlayer = TranscriptAudioPlayer()
    private let pasteboardInjector = PasteboardInjector()
    private let voiceEditLLMService = VoiceEditLLMService()
    private let voiceEditCommandParser = VoiceEditCommandParser()
    private let voiceEditLocalResolver = VoiceEditLocalResolver()
    private let transcriptProcessingWorkflow = TranscriptProcessingWorkflow()
    private let openAIModelAvailabilityService = OpenAIModelAvailabilityService()
    private let localWhisperSetupService = LocalWhisperSetupService()
    private let adaptiveRecognitionService = AdaptiveRecognitionService()
    private let adaptiveRecognitionStore = AdaptiveRecognitionStore()
    private let recordingCuePlayer = RecordingCuePlayer()
    private let crashReportService = CrashReportService()
    private let appUpdateController = AppUpdateController()
    private var deletedHistoryIDs = Set<UUID>()
    private var activeTranscriptionAttemptID: UUID?
    let projectVocabularyController = ProjectVocabularyController(
        store: AppRuntime.isRunningUnderXCTest ? nil : ProjectVocabularyStore()
    )
    private var pushToTalkMonitor: RightOptionPushToTalkMonitor?
    private var pushToTalkIsHeld = false
    private var pushToTalkIntentGeneration: UInt64 = 0
    private var hasLoadedOpenAIAPIKey = false
    private var hasLoadedElevenLabsAPIKey = false
    private var hasLoadedAlibabaAPIKey = false
    private var hasLoadedGeminiAPIKey = false
    private var lastInsertion: LastShuoInsertion? {
        didSet {
            replacementSafetySessionID = lastInsertion?.id
        }
    }
    private var replacementTransactionGate = ReplacementTransactionGate()
    private var pendingReplacementTransaction: PendingReplacementTransaction?
    private var draftFeedbackBaseline: DraftFeedbackBaseline?
    private var learningNoticeTask: Task<Void, Never>?
    private var appActivationObserver: NSObjectProtocol?
    private var permissionRetryTimer: Timer?
    private var permissionRetryDeadline: Date?
    private var transcriptionTask: Task<Void, Never>?
    private var localWhisperDownloadTask: Task<Void, Never>?
    private var openAIModelRefreshTask: Task<Void, Never>?
    private var openAIModelRefreshGeneration: UInt64 = 0
    private var correctionLearningSnapshotTask: Task<Void, Never>?
    private var correctionLearningSnapshotRevision = 0
    private var recordingVocabularySnapshot: TranscriptionVocabularySnapshot?
    private var recordingCorrectionLearningSnapshot: CorrectionLearningSnapshot?
    private var recordingInputTarget: RecordingInputTarget?
    private var recordingReachedDurationLimit = false
    private var cancellables = Set<AnyCancellable>()

    var statusMessage: String {
        localizer.status(status)
    }

    var errorSummaryMessage: String? {
        guard let errorMessage else {
            return nil
        }

        let summary = Self.summarizedErrorMessage(errorMessage)
        return summary.isEmpty ? nil : summary
    }

    var isCheckingAudio: Bool {
        status == .checkingAudio
    }

    var isTranscribing: Bool {
        status == .transcribing
    }

    var openAITranscriptionModelOptions: [OpenAIModelDescriptor] {
        OpenAIModelCatalog.transcriptionModels
    }

    var openAITextModelOptions: [OpenAIModelDescriptor] {
        OpenAIModelCatalog.textModels
    }

    var openAIModelAvailabilityMessage: String {
        if OpenAICompatibleRequestBuilder.normalizedAPIKey(openAIAPIKey) == nil {
            return localizer.openAIModelRefreshNeedsAPIKey()
        }
        if isRefreshingOpenAIModels {
            return localizer.refreshingOpenAIModels()
        }
        if let openAIModelAvailabilityError {
            return localizer.openAIModelRefreshFailed(openAIModelAvailabilityError)
        }
        guard openAIModelAvailabilityFetchedAt != nil else {
            return localizer.openAIModelsNotChecked()
        }

        let compatibleCount = OpenAIModelCatalog.transcriptionModelIDs
            .filter(openAIAvailableModelIDs.contains)
            .count
        guard compatibleCount > 0 else {
            return localizer.noCompatibleOpenAIModels()
        }
        return localizer.openAIModelsAvailable(
            count: compatibleCount,
            automaticModelID: settings.automaticOpenAITranscriptionModel
        )
    }

    var openAIAutomaticTranscriptionModelMessage: String {
        guard openAIModelAvailabilityFetchedAt != nil,
              openAIAvailableModelIDs.contains(settings.effectiveModel) else {
            return openAIModelAvailabilityMessage
        }
        return localizer.openAIAutomaticModelHint(settings.effectiveModel)
    }

    var openAIAutomaticTextModelMessage: String {
        return localizer.openAIAutomaticTextModelHint(settings.automaticOpenAITextModel)
    }

    private var localizer: AppLocalizer {
        AppLocalizer(language: settings.appLanguage)
    }

    var shouldShowOnboarding: Bool {
        !settings.hasCompletedOnboarding
    }

    @discardableResult
    func completeOnboarding(if readiness: OnboardingReadiness) -> Bool {
        guard readiness.canStart else {
            return false
        }

        settings.hasCompletedOnboarding = true
        selectedPanelSection = .general
        configurePushToTalkMonitor()
        return true
    }

    func skipOnboardingSetup() {
        settings.hasCompletedOnboarding = true
        selectedPanelSection = .general
        configurePushToTalkMonitor()
    }

    func showOnboarding() {
        settings.hasCompletedOnboarding = false
    }

    func navigateToSetting(_ item: SettingsSearchItem) {
        navigateToSetting(section: item.section, target: item.target)
    }

    func navigateToSetting(section: AppPanelSection, target: SettingsSearchTarget) {
        let resolvedSection: AppPanelSection
        if section == .architecture {
            resolvedSection = .architecture
        } else if let placement = target.pipelinePlacement {
            resolvedSection = placement.appearsInBasicSettings ? .transcription : .architecture
        } else {
            switch section {
            case .audio, .vocabulary, .aiAndLLM, .postProcessing:
                resolvedSection = .architecture
            default:
                resolvedSection = section.legacyNavigationDestination
            }
        }

        settingsNavigationRequest = SettingsNavigationRequest(
            section: resolvedSection,
            target: target
        )
        selectedPanelSection = resolvedSection
    }

    func consumeSettingsNavigationRequest(id: UUID) {
        guard settingsNavigationRequest?.id == id else {
            return
        }
        settingsNavigationRequest = nil
    }

    init() {
        var loadedSettings = Self.load(AppSettings.self, key: Self.settingsKey) ?? AppSettings()
        loadedSettings.normalizeSelections()
        settings = loadedSettings
        pluginConfiguration = PluginConfigurationStore.load(
            preservingConfiguredProvider: loadedSettings.provider
        )
        let historyLoadResult = transcriptHistoryStore.loadResult()
        let allowsStartupHistoryMutation = StartupHistoryReconciliationPolicy
            .allowsAutomaticMutation(after: historyLoadResult.issue)
        deletedHistoryIDs = historyLoadResult.deletedItemIDs
        historyStorageIsWritable = allowsStartupHistoryMutation
        let loadedHistory = allowsStartupHistoryMutation
            ? Self.reconcileInterruptedRecordings(
                historyLoadResult.items,
                settings: loadedSettings,
                localizer: AppLocalizer(language: loadedSettings.appLanguage),
                excludedRecordingIDs: historyLoadResult.deletedItemIDs
            )
            : historyLoadResult.items
        history = loadedHistory
        let pendingAudioCleanupErrors = AppRuntime.isRunningUnderXCTest
            ? []
            : TranscriptHistoryDeletionTransaction(
                historyStore: transcriptHistoryStore,
                audioStore: transcriptAudioStore
            ).resumePendingAudioCleanup(fileNames: historyLoadResult.pendingAudioFileNames)
        let loadedMetricsState: MetricsStoreState
        if AppRuntime.isRunningUnderXCTest {
            let loadedMetricsRecords = loadedHistory.map(MetricsCalculator().record(for:))
            loadedMetricsState = MetricsStoreState(
                records: loadedMetricsRecords,
                counters: MetricsCalculator().counters(from: loadedMetricsRecords)
            )
        } else {
            loadedMetricsState = metricsStore.load(seedHistory: loadedHistory)
        }
        metricsRecords = loadedMetricsState.records
        metricsCounters = loadedMetricsState.counters
        let adaptiveRecognitionLoadResult = adaptiveRecognitionStore.loadResult()
        adaptiveRecognitionState = adaptiveRecognitionLoadResult.state
        refreshLaunchAtLoginStatus()
        appUpdateController.appLanguage = loadedSettings.appLanguage
        var startupStorageIssues = [
            historyLoadResult.issue?.localizedDescription,
            loadedMetricsState.issue?.localizedDescription,
            adaptiveRecognitionLoadResult.issue?.localizedDescription,
            pendingAudioCleanupErrors.isEmpty
                ? nil
                : AppLocalizer(language: loadedSettings.appLanguage)
                    .historyAudioCleanupPending(
                        pendingAudioCleanupErrors.joined(separator: "; ")
                    )
        ].compactMap { $0 }
        if allowsStartupHistoryMutation,
           loadedHistory != historyLoadResult.items,
           !AppRuntime.isRunningUnderXCTest {
            do {
                try transcriptHistoryStore.save(loadedHistory)
            } catch {
                historyStorageIsWritable = false
                startupStorageIssues.append(
                    AppLocalizer(language: loadedSettings.appLanguage)
                        .historySaveFailed(error.localizedDescription)
                )
            }
        }
        if !startupStorageIssues.isEmpty {
            errorMessage = startupStorageIssues.joined(separator: "\n\n")
        }
        do {
            try localWhisperSetupService.applyManagedModelBackupPolicy(
                directoryPath: settings.localWhisperModelDirectoryPath
            )
        } catch {
            errorMessage = [
                errorMessage,
                localizer.modelBackupPolicyFailed(error.localizedDescription)
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        }
        recoverPreviousCrashIfNeeded()
        configurePushToTalkMonitor()
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.refreshSystemPermissions()
                self.refreshLaunchAtLoginStatus()
                guard self.settings.pushToTalkEnabled,
                      !self.isPushToTalkRunning else {
                    return
                }
                self.configurePushToTalkMonitor()
            }
        }
        appUpdateController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        appUpdateController.$statusMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.updateStatusMessage = message
            }
            .store(in: &cancellables)
        projectVocabularyController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        recordingSession.onMaximumDurationReached = { [weak self] in
            guard let self, self.isRecording else {
                return
            }
            self.recordingReachedDurationLimit = true
            self.errorMessage = self.localizer.maximumRecordingDurationReached(
                minutes: Int(AudioRecorder.maximumRecordingDuration / 60)
            )
            self.beginTranscriptionTask()
        }
        scheduleCorrectionLearningSnapshotRefresh()
    }

    deinit {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
        permissionRetryTimer?.invalidate()
        transcriptionTask?.cancel()
        correctionLearningSnapshotTask?.cancel()
    }

    func markCleanExit() {
        guard !AppRuntime.isRunningUnderXCTest else {
            return
        }

        crashReportService.markCleanExit()
    }

    func shouldAllowApplicationTermination() -> Bool {
        appUpdateController.shouldAllowApplicationTermination()
    }

    func startUpdateController() {
        appUpdateController.start()
    }

    func toggleRecording() {
        if recordingSession.isStarting {
            cancelActiveRecording()
            return
        }

        if isRecording {
            beginTranscriptionTask()
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func beginPushToTalkRecording() {
        guard settings.pushToTalkEnabled else {
            return
        }

        guard !pushToTalkIsHeld else {
            return
        }

        pushToTalkIsHeld = true
        pushToTalkIntentGeneration &+= 1
        let intentGeneration = pushToTalkIntentGeneration

        Task {
            guard pushToTalkIsHeld,
                  pushToTalkIntentGeneration == intentGeneration else {
                return
            }

            if !isRecording {
                await startRecording(requiredPushToTalkGeneration: intentGeneration)
            }

            if !pushToTalkIsHeld, isRecording {
                beginTranscriptionTask()
            }
        }
    }

    func endPushToTalkRecording() {
        guard pushToTalkIsHeld else {
            return
        }

        pushToTalkIsHeld = false
        pushToTalkIntentGeneration &+= 1

        if recordingSession.isStarting {
            cancelActiveRecording()
            return
        }

        guard isRecording else {
            return
        }
        beginTranscriptionTask()
    }

    func cancelCurrentTranscription() {
        transcriptionTask?.cancel()
    }

    private func beginTranscriptionTask() {
        guard transcriptionTask == nil else {
            return
        }

        transcriptionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.stopRecordingAndTranscribe()
            self.transcriptionTask = nil
        }
    }

    func startRecording(requiredPushToTalkGeneration: UInt64? = nil) async {
        if recordingSession.isStarting {
            guard requiredPushToTalkGeneration != nil,
                  await recordingSession.waitForPendingStartToFinish() else {
                return
            }
        }
        guard !isRecording,
              recordingSession.phase == .idle,
              !isCheckingAudio,
              !isTranscribing else {
            return
        }
        guard requiredPushToTalkGeneration.map({ generation in
            pushToTalkIsHeld && pushToTalkIntentGeneration == generation
        }) ?? true else {
            return
        }
        guard historyStorageIsWritable else {
            errorMessage = localizer.historyStorageUnavailableForRecording()
            return
        }
        do {
            try transcriptHistoryStore.validateWritableState()
        } catch {
            historyStorageIsWritable = false
            errorMessage = localizer.historyStorageUnavailableForRecording(
                error.localizedDescription
            )
            return
        }

        await invalidateReplacementTransactionAndWait()
        guard requiredPushToTalkGeneration.map({ generation in
            pushToTalkIsHeld && pushToTalkIntentGeneration == generation
        }) ?? true else {
            return
        }
        recordingReachedDurationLimit = false
        floatingCorrectionSession = nil
        recordingInputTarget = captureCurrentInputTarget()
        let learningSnapshot = correctionLearningSnapshotForExecution()
        recordingCorrectionLearningSnapshot = learningSnapshot
        recordingVocabularySnapshot = captureTranscriptionVocabulary(
            correctionLearningSnapshot: learningSnapshot
        )

        do {
            errorMessage = nil
            isPreparingMicrophone = true
            status = .preparingMicrophone
            guard try await recordingSession.start(inputDeviceID: settings.audioInputDeviceID) != nil else {
                recordingVocabularySnapshot = nil
                recordingCorrectionLearningSnapshot = nil
                recordingInputTarget = nil
                isPreparingMicrophone = false
                isRecording = false
                status = .ready
                return
            }

            isPreparingMicrophone = false
            isRecording = true
            status = .recording
            playRecordingStartSoundIfNeeded()
        } catch {
            recordingVocabularySnapshot = nil
            recordingCorrectionLearningSnapshot = nil
            recordingInputTarget = nil
            isPreparingMicrophone = false
            isRecording = false
            status = .ready

            if Self.isCancellation(error) {
                return
            }

            let localizedError = localizedErrorMessage(error)
            let requestSettings = pluginCapabilityPolicy.applying(to: settings)
            appendAttempt(TranscriptItem(
                text: "",
                provider: requestSettings.provider,
                model: requestSettings.effectiveModel,
                languageHint: requestSettings.languageHint,
                outcome: .failed,
                errorSummary: Self.summarizedErrorMessage(localizedError)
            ))
            errorMessage = localizedError
        }
    }

    func stopRecordingAndTranscribe() async {
        guard isRecording, recordingSession.isRecording else {
            return
        }

        defer {
            recordingVocabularySnapshot = nil
            recordingCorrectionLearningSnapshot = nil
            recordingInputTarget = nil
        }

        isRecording = false
        let audioURL = await recordingSession.stop()

        guard let audioURL else {
            status = .ready
            errorMessage = localizer.noRecordingAvailable()
            return
        }

        var shouldRemoveTemporaryAudio = true
        defer {
            if shouldRemoveTemporaryAudio {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        if !recordingReachedDurationLimit {
            errorMessage = nil
        }
        let attemptID = UUID()
        activeTranscriptionAttemptID = attemptID
        defer {
            if activeTranscriptionAttemptID == attemptID {
                activeTranscriptionAttemptID = nil
            }
        }
        let attemptCreatedAt = Date()
        let requestSettings = pluginCapabilityPolicy.applying(to: settings)
        let selectedTranscriptionLanguages = TranscriptionLanguage.allCases.filter(
            requestSettings.selectedTranscriptionLanguages.contains
        )
        var recordingDuration: TimeInterval?
        var audioFileName: String?
        var transcriptionAudioURL = audioURL
        var normalizedTranscriptionAudioURL: URL?
        var transcriptionStartedAt: Date?
        defer {
            if let normalizedTranscriptionAudioURL {
                try? FileManager.default.removeItem(at: normalizedTranscriptionAudioURL)
            }
        }

        do {
            do {
                audioFileName = try transcriptAudioStore.storeRecording(
                    at: audioURL,
                    for: attemptID
                )
                shouldRemoveTemporaryAudio = false
                if let audioFileName,
                   let storedAudioURL = transcriptAudioStore.url(forFileName: audioFileName) {
                    transcriptionAudioURL = storedAudioURL
                    beginPendingAttempt(TranscriptItem(
                        id: attemptID,
                        text: "",
                        createdAt: attemptCreatedAt,
                        provider: requestSettings.provider,
                        model: requestSettings.effectiveModel,
                        languageHint: requestSettings.languageHint,
                        selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                        audioFileName: audioFileName,
                        outcome: .processing
                    ))
                }
            } catch {
                errorMessage = localizer.recordingSaveFailed(error.localizedDescription)
            }

            if settings.voiceActivityGateEnabled {
                status = .checkingAudio
            }

            let analysis = try audioActivityAnalyzer.analyze(
                transcriptionAudioURL,
                silenceThresholdDBFS: settings.silenceThresholdDBFS,
                adaptsToNoiseFloor: settings.whisperModeEnabled
            )
            recordingDuration = analysis.duration
            updatePendingAttemptRecordingDuration(
                id: attemptID,
                recordingDuration: analysis.duration
            )

            if settings.voiceActivityGateEnabled {
                guard analysis.containsSpeech(settings: settings) else {
                    var retainedAudioFileName = audioFileName
                    var audioDeletionFailed = false
                    if let audioFileName {
                        do {
                            try transcriptAudioStore.deleteAudio(forFileName: audioFileName)
                            retainedAudioFileName = nil
                            self.latestTranscriptAudioHistoryID = history.first(where: {
                                $0.id != attemptID && $0.audioFileName != nil
                            })?.id
                        } catch {
                            audioDeletionFailed = true
                            errorMessage = localizer.historySaveFailed(
                                error.localizedDescription
                            )
                        }
                    }
                    audioFileName = retainedAudioFileName
                    let item = TranscriptItem(
                        id: attemptID,
                        text: "",
                        createdAt: attemptCreatedAt,
                        provider: requestSettings.provider,
                        model: requestSettings.effectiveModel,
                        languageHint: requestSettings.languageHint,
                        selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                        audioFileName: retainedAudioFileName,
                        outcome: .ignoredSilence,
                        errorSummary: localizer.status(.ignoredSilence),
                        recordingDuration: analysis.duration
                    )
                    finalizeAttempt(item)
                    status = .ignoredSilence
                    if !audioDeletionFailed {
                        errorMessage = nil
                    }
                    return
                }
            }

            try Task.checkCancellation()

            if settings.whisperModeEnabled,
               let normalizedURL = try? whisperAudioNormalizer.normalizedCopy(
                   of: transcriptionAudioURL,
                   analysis: analysis
               ) {
                normalizedTranscriptionAudioURL = normalizedURL
                transcriptionAudioURL = normalizedURL
            }

            status = .transcribing
            transcriptionStartedAt = Date()
            let processingResult = try await transcribeAndProcessAudio(
                at: transcriptionAudioURL,
                settings: requestSettings,
                allowsVoiceEditCommands: true
            )
            try Task.checkCancellation()
            let processedTranscription: ProcessedTranscription
            switch processingResult {
            case .transcription(let transcription):
                processedTranscription = transcription
            case .handledVoiceCommand(let command):
                let transcriptionLatency = transcriptionStartedAt.map { Date().timeIntervalSince($0) }
                let metricsItem = TranscriptItem(
                    id: attemptID,
                    text: "",
                    rawText: command.rawText,
                    locallyProcessedText: command.locallyProcessedText,
                    createdAt: attemptCreatedAt,
                    provider: command.provider,
                    model: command.model,
                    languageHint: command.languageHint,
                    selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                    detectedLanguageCode: command.detectedLanguageCode,
                    audioFileName: audioFileName,
                    outcome: .handledVoiceCommand,
                    recordingDuration: recordingDuration,
                    transcriptionLatency: transcriptionLatency
                )
                if let pendingItem = history.first(where: { $0.id == attemptID }),
                   permanentlyDeleteHistoryItems(
                    [pendingItem],
                    cancelsActiveAttempt: false
                   ) {
                    recordMetrics(for: metricsItem)
                } else {
                    finalizeAttempt(metricsItem)
                }
                status = .ready
                return
            }
            let transcriptionLatency = transcriptionStartedAt.map { Date().timeIntervalSince($0) }

            let text = processedTranscription.text

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                currentDraft = ""
                draftFeedbackBaseline = nil
                let item = TranscriptItem(
                    id: attemptID,
                    text: "",
                    rawText: processedTranscription.rawText,
                    locallyProcessedText: processedTranscription.locallyProcessedText,
                    createdAt: attemptCreatedAt,
                    provider: processedTranscription.provider,
                    model: processedTranscription.model,
                    languageHint: processedTranscription.languageHint,
                    selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                    detectedLanguageCode: processedTranscription.detectedLanguageCode,
                    audioFileName: audioFileName,
                    outcome: .ignoredEmptyTranscript,
                    errorSummary: localizer.status(.ignoredEmptyTranscript),
                    recordingDuration: recordingDuration,
                    transcriptionLatency: transcriptionLatency
                )
                guard finalizeAttempt(item) else {
                    status = .ready
                    return
                }
                status = .ignoredEmptyTranscript
                return
            }

            currentDraft = text

            let item = TranscriptItem(
                id: attemptID,
                text: text,
                rawText: processedTranscription.rawText,
                locallyProcessedText: processedTranscription.locallyProcessedText,
                createdAt: attemptCreatedAt,
                provider: processedTranscription.provider,
                model: processedTranscription.model,
                languageHint: processedTranscription.languageHint,
                selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                detectedLanguageCode: processedTranscription.detectedLanguageCode,
                audioFileName: audioFileName,
                recordingDuration: recordingDuration,
                transcriptionLatency: transcriptionLatency
            )
            guard finalizeAttempt(item) else {
                status = .ready
                return
            }
            draftFeedbackBaseline = DraftFeedbackBaseline(
                text: text,
                context: AdaptiveRecognitionFeedbackContext(
                    provider: item.provider,
                    model: item.model,
                    languageHint: item.languageHint,
                    historyID: item.id,
                    audioFileName: item.audioFileName
                )
            )

            try Task.checkCancellation()
            await paste(
                text,
                historyID: item.id,
                recordingTarget: recordingInputTarget,
                preservesTrailingNewline: processedTranscription.appendsTrailingNewline,
                punctuationMode: processedTranscription.punctuationMode,
                boundaryMode: processedTranscription.insertionBoundaryMode
            )

            status = .ready
        } catch {
            let localizedError = localizedErrorMessage(error)
            if Self.isCancellation(error) {
                if deletedHistoryIDs.contains(attemptID) {
                    status = .ready
                    errorMessage = nil
                    return
                }
                let item = TranscriptItem(
                    id: attemptID,
                    text: "",
                    createdAt: attemptCreatedAt,
                    provider: requestSettings.provider,
                    model: requestSettings.effectiveModel,
                    languageHint: requestSettings.languageHint,
                    selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                    audioFileName: audioFileName,
                    outcome: .cancelled,
                    errorSummary: localizer.transcriptionCancelled(),
                    recordingDuration: recordingDuration,
                    transcriptionLatency: transcriptionStartedAt.map { Date().timeIntervalSince($0) }
                )
                _ = finalizeAttempt(item)
                status = .ready
                errorMessage = nil
                return
            }
            let item = TranscriptItem(
                id: attemptID,
                text: "",
                createdAt: attemptCreatedAt,
                provider: requestSettings.provider,
                model: requestSettings.effectiveModel,
                languageHint: requestSettings.languageHint,
                selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                audioFileName: audioFileName,
                outcome: .failed,
                errorSummary: Self.summarizedErrorMessage(localizedError),
                recordingDuration: recordingDuration,
                transcriptionLatency: transcriptionStartedAt.map { Date().timeIntervalSince($0) }
            )
            guard finalizeAttempt(item) else {
                status = .ready
                return
            }
            status = .ready
            errorMessage = localizedError
        }
    }

    private func appendAttempt(_ item: TranscriptItem) {
        guard !deletedHistoryIDs.contains(item.id) else {
            return
        }
        history.insert(item, at: 0)
        recordMetrics(for: item)
        if item.audioFileName != nil {
            latestTranscriptAudioHistoryID = item.id
        }
    }

    private func beginPendingAttempt(_ item: TranscriptItem) {
        guard item.outcome == .processing,
              !deletedHistoryIDs.contains(item.id),
              !history.contains(where: { $0.id == item.id }) else {
            return
        }
        history.insert(item, at: 0)
        if item.audioFileName != nil {
            latestTranscriptAudioHistoryID = item.id
        }
    }

    @discardableResult
    private func finalizeAttempt(_ item: TranscriptItem) -> Bool {
        guard !deletedHistoryIDs.contains(item.id) else {
            return false
        }
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index] = item
        } else {
            history.insert(item, at: 0)
        }
        recordMetrics(for: item)
        if item.audioFileName != nil {
            latestTranscriptAudioHistoryID = item.id
        }
        return true
    }

    private func updatePendingAttemptRecordingDuration(
        id: UUID,
        recordingDuration: TimeInterval
    ) {
        guard let index = history.firstIndex(where: {
            $0.id == id && $0.outcome == .processing
        }) else {
            return
        }
        history[index].recordingDuration = recordingDuration
    }

    private func transcribeAndProcessAudio(
        at audioURL: URL,
        settings requestSettings: AppSettings,
        allowsVoiceEditCommands: Bool
    ) async throws -> AudioProcessingResult {
        let effectiveSettings = CloudTextAICapabilityPolicy.applying(
            to: pluginCapabilityPolicy.applying(to: requestSettings)
        )
        let provider = effectiveSettings.provider
        guard pluginCapabilityPolicy.isTranscriptionProviderEnabled(provider) else {
            throw PluginFeatureError.disabledProvider(provider.displayName)
        }

        if provider == .openAI,
           effectiveSettings.openAITranscriptionModelSelectionMode == .automatic,
           openAIModelAvailabilityFetchedAt != nil,
           OpenAIModelCatalog.recommendedTranscriptionModelID(
               availableModelIDs: openAIAvailableModelIDs
           ) == nil {
            throw OpenAIModelSelectionError.noCompatibleTranscriptionModel
        }

        let model = effectiveSettings.effectiveModel
        let languageHint = effectiveSettings.languageHint
        let service = TranscriptionServiceFactory.makeService(for: provider)
        let apiKey = apiKey(for: provider)
        let correctionLearningSnapshot = recordingCorrectionLearningSnapshot
            ?? correctionLearningSnapshotForExecution(settings: effectiveSettings)
        let vocabulary = recordingVocabularySnapshot ?? captureTranscriptionVocabulary(
            settings: effectiveSettings,
            correctionLearningSnapshot: correctionLearningSnapshot
        )
        let result: TranscriptionResult
        do {
            result = try await service.transcribe(
                TranscriptionRequest(
                    audioFileURL: audioURL,
                    settings: effectiveSettings,
                    context: effectiveSettings.usesSenseVoiceLocalTranscription
                        ? ""
                        : effectiveSettings.effectiveContextPrompt,
                    vocabulary: vocabulary,
                    apiKey: apiKey
                )
            )
        } catch {
            if provider == .openAI {
                refreshOpenAIModelsAfterFailureIfNeeded(error)
            }
            throw error
        }
        let preparedTranscript = transcriptProcessingWorkflow.prepare(
            result.text,
            settings: effectiveSettings,
            correctionLearningSnapshot: correctionLearningSnapshot
        )

        if allowsVoiceEditCommands,
           pluginCapabilityPolicy.voiceEditCommandsEnabled,
           effectiveSettings.voiceEditCommandsEnabled,
           try await handleVoiceEditCommand(
               preparedTranscript.rawText,
               fallbackText: preparedTranscript.locallyProcessedText,
               settings: effectiveSettings
           ) {
            return .handledVoiceCommand(HandledVoiceCommandTranscription(
                rawText: preparedTranscript.rawText,
                locallyProcessedText: preparedTranscript.locallyProcessedText,
                provider: provider,
                model: model,
                languageHint: languageHint,
                detectedLanguageCode: result.detectedLanguage
            ))
        }

        let finalizedText = await transcriptProcessingWorkflow.finalize(
            preparedTranscript,
            settings: effectiveSettings,
            apiKey: apiKeyForPostTranscriptionProcessing(settings: effectiveSettings),
            correctionLearningSnapshot: correctionLearningSnapshot
        )
        let text = TranscriptInsertionBoundaryPolicy.apply(
            to: finalizedText,
            punctuationMode: effectiveSettings.punctuationPostProcessingMode,
            mode: effectiveSettings.transcriptInsertionBoundaryMode
        )
        try Task.checkCancellation()
        if errorMessage == nil,
           let warning = transcriptProcessingWorkflow.lastWarning {
            errorMessage = localizer.aiPostProcessingFellBack(warning)
        }

        return .transcription(ProcessedTranscription(
            rawText: preparedTranscript.rawText,
            locallyProcessedText: preparedTranscript.locallyProcessedText,
            text: text,
            provider: provider,
            model: model,
            languageHint: languageHint,
            detectedLanguageCode: result.detectedLanguage,
            appendsTrailingNewline: effectiveSettings.appendNewlineAfterTranscription,
            punctuationMode: effectiveSettings.punctuationPostProcessingMode,
            insertionBoundaryMode: effectiveSettings.transcriptInsertionBoundaryMode
        ))
    }

    func copy(_ text: String) {
        pasteboardInjector.copy(text)
    }

    func copyCurrentDraft() {
        recordDraftCorrectionIfNeeded(
            finalText: currentDraft,
            source: .quickCopy
        )
        pasteboardInjector.copy(currentDraft)
    }

    func clearError() {
        errorMessage = nil
    }

    func reportError(_ error: Error) {
        errorMessage = localizedErrorMessage(error)
    }

    private func recoverPreviousCrashIfNeeded() {
        guard !AppRuntime.isRunningUnderXCTest,
              let report = crashReportService.startSession() else {
            return
        }

        let crashMessage = [
            localizer.recoveredFromUnexpectedExit(reportPath: report.reportURL.path),
            report.reportText
        ].joined(separator: "\n\n")
        errorMessage = [errorMessage, crashMessage]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    func previewRecordingStartSound() {
        do {
            try recordingCuePlayer.play(
                settings.recordingStartSound,
                volumeScale: RecordingCuePlaybackLevel.scale(
                    whisperModeEnabled: settings.whisperModeEnabled
                ),
                outputDeviceID: preferredAudioOutputDeviceID
            )
            errorMessage = nil
        } catch {
            errorMessage = localizedErrorMessage(error)
        }
    }

    func exportSettings(to url: URL) throws {
        let data = try AppExportService.settingsExportData(settings: settings)
        try data.write(to: url, options: .atomic)
        errorMessage = nil
    }

    func exportCorrectionData(to url: URL) throws {
        let data = try AppExportService.correctionDataExportData(
            state: adaptiveRecognitionState,
            history: history,
            learningSnapshot: correctionLearningSnapshot
        )
        try data.write(to: url, options: .atomic)
        errorMessage = nil
    }

    func clearCorrectionData() {
        correctionLearningSnapshotTask?.cancel()
        correctionLearningSnapshotTask = nil
        correctionLearningSnapshotRevision += 1
        correctionLearningSnapshot = .empty
        adaptiveRecognitionState = AdaptiveRecognitionState(learningResetAt: Date())
        learningNoticeTask?.cancel()
        learningNoticeMessage = nil
        errorMessage = nil
    }

    func importPluginConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        pluginConfiguration = try PluginConfigurationStore.configuration(from: data)
        errorMessage = nil
    }

    func exportPluginConfiguration(to url: URL) throws {
        let data = try PluginConfigurationStore.exportData(configuration: pluginConfiguration)
        try data.write(to: url, options: .atomic)
        errorMessage = nil
    }

    func resetPluginConfigurationToMVP() {
        pluginConfiguration = .mvp
        errorMessage = nil
    }

    func resetPluginConfigurationToFullDevelopment() {
        pluginConfiguration = .fullDevelopment
        errorMessage = nil
    }

    func setPluginEnabled(_ pluginID: PluginID, isEnabled: Bool) {
        var updated = pluginConfiguration
        updated.setEnabled(isEnabled, for: pluginID)
        pluginConfiguration = updated
        if pluginID == .smartCorrectionWindow, !isEnabled {
            floatingCorrectionSession = nil
        }
    }

    func setAdaptiveRecognitionEnabled(_ isEnabled: Bool) {
        if isEnabled {
            setPluginEnabled(.smartPreferredTerms, isEnabled: true)
        }
        setPluginEnabled(.smartAdaptiveRecognition, isEnabled: isEnabled)
        settings.adaptiveRecognitionEnabled = isEnabled
    }

    func setAdaptiveRecognitionMode(_ mode: AdaptiveRecognitionMode) {
        settings.adaptiveRecognitionMode = mode
    }

    func isCorrectionLearningPatternEnabled(_ id: CorrectionLearningPattern.ID) -> Bool {
        adaptiveRecognitionState.enabledCorrectionPatternIDs.contains(id)
    }

    func setCorrectionLearningPatternEnabled(
        _ isEnabled: Bool,
        id: CorrectionLearningPattern.ID
    ) {
        var updatedState = adaptiveRecognitionState
        if isEnabled {
            updatedState.enabledCorrectionPatternIDs.insert(id)
        } else {
            updatedState.enabledCorrectionPatternIDs.remove(id)
        }
        guard updatedState != adaptiveRecognitionState else {
            return
        }

        adaptiveRecognitionState = updatedState
        correctionLearningSnapshot = adaptiveRecognitionService.applyingEnabledPatterns(
            to: correctionLearningSnapshot,
            enabledPatternIDs: updatedState.enabledCorrectionPatternIDs
        )
    }

    func setPreferredChineseTextConversionMode(
        _ mode: ChineseTextConversionMode
    ) {
        settings.setPreferredChineseTextConversionMode(mode)
        setPluginEnabled(.outputChineseConversion, isEnabled: true)
    }

    func isPluginEnabled(_ pluginID: PluginID) -> Bool {
        pluginConfiguration.isEnabled(pluginID)
    }

    var pluginStatusItems: [PluginStatusItem] {
        PluginConfigurationStore.statusItems(for: pluginConfiguration)
    }

    func exportHistoricalMetrics(to url: URL) throws {
        let data = try AppExportService.metricsExportData(records: metricsRecords)
        try data.write(to: url, options: .atomic)
        errorMessage = nil
    }

    func resetMetricsDisplay(at cutoff: Date = Date()) {
        let updatedCounters = metricsCounters.resettingDisplay(at: cutoff)

        do {
            if !AppRuntime.isRunningUnderXCTest {
                try metricsStore.saveDisplayReset(counters: updatedCounters)
            }
            metricsCounters = updatedCounters
            errorMessage = nil
        } catch {
            errorMessage = localizer.metricsSaveFailed(error.localizedDescription)
        }
    }

    func checkForUpdates() {
        appUpdateController.checkForUpdates()
        updateStatusMessage = appUpdateController.statusMessage ?? localizer.text(.checkForUpdates)
        errorMessage = nil
    }

    var supportsDirectUpdates: Bool {
        appUpdateController.supportsDirectUpdates
    }

    var canCheckForUpdates: Bool {
        appUpdateController.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        appUpdateController.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        appUpdateController.automaticallyDownloadsUpdates
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        appUpdateController.setAutomaticallyChecksForUpdates(enabled)
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        appUpdateController.setAutomaticallyDownloadsUpdates(enabled)
    }

    func refreshLaunchAtLoginStatus() {
        guard !AppRuntime.isRunningUnderXCTest else {
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            return
        }

        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginRequiresApproval = status == .requiresApproval
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard !AppRuntime.isRunningUnderXCTest else {
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = localizer.launchAtLoginUpdateFailed(error.localizedDescription)
        }
        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func paste(_ text: String) {
        Task { [weak self] in
            await self?.paste(text, historyID: nil)
        }
    }

    func saveDraftToHistory() {
        let trimmed = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        recordDraftCorrectionIfNeeded(
            finalText: trimmed,
            source: .manualDraftEdit
        )

        let item = TranscriptItem(
            text: trimmed,
            provider: settings.provider,
            model: settings.effectiveModel,
            languageHint: settings.languageHint
        )
        history.insert(item, at: 0)
        recordMetrics(for: item)
    }

    func updateOpenAIAPIKey(_ apiKey: String) {
        openAIAPIKey = apiKey
        hasLoadedOpenAIAPIKey = true
        resetOpenAIModelAvailability()

        do {
            try OpenAIAPIKeyStore.save(apiKey)
        } catch {
            errorMessage = localizedErrorMessage(error)
        }

        if settings.provider != .gemini {
            scheduleOpenAIModelRefresh(forceRefresh: false)
        }
    }

    func loadOpenAIAPIKeyIfNeeded() {
        guard !hasLoadedOpenAIAPIKey else {
            return
        }

        hasLoadedOpenAIAPIKey = true
        do {
            openAIAPIKey = try OpenAIAPIKeyStore.load()
            restoreCachedOpenAIModelAvailability()
        } catch {
            openAIAPIKey = ""
            errorMessage = localizedErrorMessage(error)
        }
    }

    func updateElevenLabsAPIKey(_ apiKey: String) {
        elevenLabsAPIKey = apiKey
        hasLoadedElevenLabsAPIKey = true

        do {
            try ElevenLabsAPIKeyStore.save(apiKey)
        } catch {
            errorMessage = localizedErrorMessage(error)
        }
    }

    func loadElevenLabsAPIKeyIfNeeded() {
        guard !hasLoadedElevenLabsAPIKey else {
            return
        }

        hasLoadedElevenLabsAPIKey = true
        do {
            elevenLabsAPIKey = try ElevenLabsAPIKeyStore.load()
        } catch {
            elevenLabsAPIKey = ""
            errorMessage = localizedErrorMessage(error)
        }
    }

    func updateAlibabaAPIKey(_ apiKey: String) {
        alibabaAPIKey = apiKey
        hasLoadedAlibabaAPIKey = true

        do {
            try AlibabaAPIKeyStore.save(apiKey)
        } catch {
            errorMessage = localizedErrorMessage(error)
        }
    }

    func loadAlibabaAPIKeyIfNeeded() {
        guard !hasLoadedAlibabaAPIKey else {
            return
        }

        hasLoadedAlibabaAPIKey = true
        do {
            alibabaAPIKey = try AlibabaAPIKeyStore.load()
        } catch {
            alibabaAPIKey = ""
            errorMessage = localizedErrorMessage(error)
        }
    }

    func updateGeminiAPIKey(_ apiKey: String) {
        geminiAPIKey = apiKey
        hasLoadedGeminiAPIKey = true

        do {
            try GeminiAPIKeyStore.save(apiKey)
        } catch {
            errorMessage = localizedErrorMessage(error)
        }
    }

    func loadGeminiAPIKeyIfNeeded() {
        guard !hasLoadedGeminiAPIKey else {
            return
        }

        hasLoadedGeminiAPIKey = true
        do {
            geminiAPIKey = try GeminiAPIKeyStore.load()
        } catch {
            geminiAPIKey = ""
            errorMessage = localizedErrorMessage(error)
        }
    }

    func clearCloudAPIKeys() {
        updateOpenAIAPIKey("")
        updateElevenLabsAPIKey("")
        updateAlibabaAPIKey("")
        updateGeminiAPIKey("")
    }

    func refreshOpenAIModelsIfNeeded() {
        guard settings.provider != .gemini else {
            return
        }
        loadOpenAIAPIKeyIfNeeded()
        scheduleOpenAIModelRefresh(forceRefresh: false, delayNanoseconds: 0)
    }

    func refreshOpenAIModels() {
        guard settings.provider != .gemini else {
            return
        }
        loadOpenAIAPIKeyIfNeeded()
        scheduleOpenAIModelRefresh(forceRefresh: true, delayNanoseconds: 0)
    }

    func isOpenAIModelAvailable(_ modelID: String) -> Bool {
        guard openAIModelAvailabilityFetchedAt != nil else {
            return true
        }
        return openAIAvailableModelIDs.contains(modelID)
    }

    func openAIModelOptionLabel(_ model: OpenAIModelDescriptor) -> String {
        let base = "\(model.displayName) — \(localizer.openAIModelPurposeName(model.purpose))"
        guard isOpenAIModelAvailable(model.id) else {
            return "\(base) · \(localizer.openAIModelUnavailableLabel())"
        }
        return base
    }

    private func scheduleOpenAIModelRefresh(
        forceRefresh: Bool,
        delayNanoseconds: UInt64 = 900_000_000
    ) {
        openAIModelRefreshTask?.cancel()
        openAIModelRefreshGeneration &+= 1
        let refreshGeneration = openAIModelRefreshGeneration
        guard settings.provider != .gemini else {
            return
        }
        guard OpenAICompatibleRequestBuilder.normalizedAPIKey(openAIAPIKey) != nil else {
            return
        }

        openAIModelRefreshTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, let self else {
                return
            }
            await self.performOpenAIModelRefresh(
                forceRefresh: forceRefresh,
                generation: refreshGeneration
            )
        }
    }

    private func performOpenAIModelRefresh(
        forceRefresh: Bool,
        generation: UInt64
    ) async {
        // A new request may arrive while a cancelled URLSession task is still
        // unwinding. Wait for that task rather than dropping the newest
        // refresh, but never let an obsolete task publish UI state.
        while isRefreshingOpenAIModels {
            guard !Task.isCancelled,
                  generation == openAIModelRefreshGeneration else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: 25_000_000)
            } catch {
                return
            }
        }

        guard !Task.isCancelled,
              generation == openAIModelRefreshGeneration,
              settings.provider != .gemini,
              let normalizedAPIKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(openAIAPIKey) else {
            return
        }

        let requestSettings = settings
        let expectedScopeID = OpenAIModelAvailabilityService.scopeID(
            settings: requestSettings,
            apiKey: normalizedAPIKey
        )
        isRefreshingOpenAIModels = true
        openAIModelAvailabilityError = nil
        defer { isRefreshingOpenAIModels = false }

        do {
            let result = try await openAIModelAvailabilityService.models(
                settings: requestSettings,
                apiKey: normalizedAPIKey,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled,
                  generation == openAIModelRefreshGeneration,
                  result.snapshot.scopeID == expectedScopeID,
                  OpenAIModelAvailabilityService.scopeID(
                    settings: settings,
                    apiKey: openAIAPIKey
                  ) == expectedScopeID else {
                return
            }
            applyOpenAIModelAvailability(result.snapshot)
        } catch is CancellationError {
            // A newer refresh superseded this one; it owns visible state.
        } catch {
            guard !Task.isCancelled,
                  generation == openAIModelRefreshGeneration else {
                return
            }
            openAIModelAvailabilityError = error.localizedDescription
        }
    }

    private func restoreCachedOpenAIModelAvailability() {
        guard let snapshot = openAIModelAvailabilityService.cachedSnapshot(
            settings: settings,
            apiKey: openAIAPIKey
        ) else {
            return
        }
        applyOpenAIModelAvailability(snapshot)
    }

    private func applyOpenAIModelAvailability(_ snapshot: OpenAIModelAvailabilitySnapshot) {
        openAIAvailableModelIDs = snapshot.modelIDSet
        openAIModelAvailabilityFetchedAt = snapshot.fetchedAt
        openAIModelAvailabilityError = nil

        if settings.openAITranscriptionModelSelectionMode == .automatic,
           let recommendedModelID = OpenAIModelCatalog.recommendedTranscriptionModelID(
               availableModelIDs: snapshot.modelIDSet
           ),
           settings.automaticOpenAITranscriptionModel != recommendedModelID {
            settings.automaticOpenAITranscriptionModel = recommendedModelID
        }

        if settings.openAITextModelSelectionMode == .automatic,
           let recommendedModelID = OpenAIModelCatalog.recommendedTextModelID(
               availableModelIDs: snapshot.modelIDSet
           ),
           settings.automaticOpenAITextModel != recommendedModelID {
            settings.automaticOpenAITextModel = recommendedModelID
        }
    }

    private func resetOpenAIModelAvailability() {
        openAIModelRefreshTask?.cancel()
        openAIModelRefreshGeneration &+= 1
        openAIAvailableModelIDs = []
        openAIModelAvailabilityFetchedAt = nil
        openAIModelAvailabilityError = nil
    }

    private func refreshOpenAIModelsAfterFailureIfNeeded(_ error: Error) {
        let failure: (statusCode: Int, message: String)?
        switch error {
        case OpenAITranscriptionError.requestFailed(let statusCode, let message):
            failure = (statusCode, message)
        case VoiceEditLLMError.requestFailed(let statusCode, let message):
            failure = (statusCode, message)
        default:
            failure = nil
        }

        guard let failure,
              OpenAIModelCatalog.errorIndicatesUnavailableModel(
                  statusCode: failure.statusCode,
                  message: failure.message
              ) else {
            return
        }
        scheduleOpenAIModelRefresh(forceRefresh: true, delayNanoseconds: 0)
    }

    func reloadLocalWhisperModels() {
        do {
            try localWhisperSetupService.applyManagedModelBackupPolicy(
                directoryPath: settings.localWhisperModelDirectoryPath
            )
        } catch {
            errorMessage = localizer.modelBackupPolicyFailed(error.localizedDescription)
        }
        var normalized = settings
        normalized.normalizeSelections()
        settings = normalized
    }

    var audioInputDevices: [AudioInputDeviceOption] {
        AudioInputDeviceCatalog.devices()
    }

    func detectLocalWhisperEngine() {
        if let executableURL = localWhisperSetupService.detectEngine() {
            settings.localWhisperExecutablePath = executableURL.path
            localWhisperSetupMessage = localizer.localWhisperEngineReady(executableURL.path)
        } else {
            localWhisperSetupMessage = localizer.localWhisperEngineNotFound()
        }
    }

    func installLocalWhisperEngine() {
        guard !localWhisperSetupIsRunning,
              localWhisperActiveManagedModelID == nil else {
            return
        }

        localWhisperSetupIsRunning = true
        localWhisperSetupMessage = localizer.installingLocalWhisperEngine()

        Task {
            do {
                let executableURL = try await localWhisperSetupService.installEngine()
                settings.localWhisperExecutablePath = executableURL.path
                localWhisperSetupMessage = localizer.localWhisperEngineReady(executableURL.path)
                errorMessage = nil
            } catch {
                let message = localizedErrorMessage(error)
                localWhisperSetupMessage = message
                errorMessage = message
            }

            localWhisperSetupIsRunning = false
        }
    }

    func isManagedLocalWhisperModelInstalled(_ model: LocalWhisperManagedModel) -> Bool {
        localWhisperSetupService.isModelInstalled(
            model,
            directoryPath: settings.localWhisperModelDirectoryPath
        )
    }

    func setLocalWhisperModelPath(_ path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            settings.localWhisperModelPath = ""
            return
        }

        settings = localWhisperSetupService.settingsSelectingModel(
            at: URL(fileURLWithPath: trimmedPath),
            currentSettings: settings
        )
    }

    func useManagedLocalWhisperModel(_ model: LocalWhisperManagedModel) {
        let modelURL = model.destinationURL(in: settings.localWhisperModelDirectoryPath)
        guard let updatedSettings = localWhisperSetupService.settingsSelectingInstalledModel(
            model,
            currentSettings: settings
        ) else {
            localWhisperSetupMessage = localizer.localWhisperModelNotFound(modelURL.path)
            return
        }

        settings = updatedSettings
        localWhisperSetupMessage = localizer.localWhisperModelReady(model.filename)
    }

    func downloadManagedLocalWhisperModel(_ model: LocalWhisperManagedModel) {
        guard !localWhisperSetupIsRunning,
              localWhisperActiveManagedModelID == nil else {
            return
        }

        localWhisperSetupIsRunning = true
        localWhisperActiveManagedModelID = model.id
        localWhisperDownloadProgress = LocalWhisperDownloadProgress(
            receivedByteCount: 0,
            totalByteCount: model.totalDownloadByteCount
        )
        localWhisperSetupMessage = localizer.downloadingLocalWhisperModel(model.displayName)
        let directoryPath = settings.localWhisperModelDirectoryPath

        localWhisperDownloadTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let modelURL = try await localWhisperSetupService.downloadModel(
                    model,
                    directoryPath: directoryPath
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.localWhisperActiveManagedModelID == model.id else {
                            return
                        }
                        self.localWhisperDownloadProgress = progress
                        self.localWhisperSetupMessage = self.localizer.localWhisperDownloadProgress(
                            modelName: model.displayName,
                            progress: progress
                        )
                    }
                }
                try Task.checkCancellation()
                settings = localWhisperSetupService.settingsSelectingModel(
                    at: modelURL,
                    currentSettings: settings
                )
                localWhisperSetupMessage = localizer.localWhisperModelReady(model.filename)
                errorMessage = nil
            } catch {
                if Self.isCancellation(error) {
                    localWhisperSetupMessage = localizer.localWhisperDownloadCancelled()
                    errorMessage = nil
                } else {
                    let message = localizedErrorMessage(error)
                    localWhisperSetupMessage = message
                    errorMessage = message
                }
            }

            localWhisperDownloadProgress = nil
            localWhisperActiveManagedModelID = nil
            localWhisperSetupIsRunning = false
            localWhisperDownloadTask = nil
        }
    }

    func cancelManagedLocalWhisperModelDownload() {
        guard localWhisperDownloadTask != nil else {
            return
        }
        localWhisperSetupMessage = localizer.cancellingLocalWhisperDownload()
        localWhisperDownloadTask?.cancel()
    }

    func deleteManagedLocalWhisperModel(_ model: LocalWhisperManagedModel) {
        guard !localWhisperSetupIsRunning,
              localWhisperActiveManagedModelID == nil else {
            return
        }

        localWhisperSetupIsRunning = true
        localWhisperActiveManagedModelID = model.id

        do {
            settings = try localWhisperSetupService.deleteModel(
                model,
                currentSettings: settings
            )
            localWhisperSetupMessage = localizer.localWhisperModelDeleted(model.filename)
            errorMessage = nil
        } catch {
            let message = localizedErrorMessage(error)
            localWhisperSetupMessage = message
            errorMessage = message
        }

        localWhisperActiveManagedModelID = nil
        localWhisperSetupIsRunning = false
    }

    func updateHistoryItem(id: UUID, text: String) {
        guard historyStorageIsWritable else {
            errorMessage = localizer.historyStorageUnavailableForRecording()
            return
        }
        guard let index = history.firstIndex(where: { $0.id == id }) else {
            return
        }
        let previousText = history[index].text
        recordExplicitCorrection(
            before: previousText,
            after: text,
            source: .historyEdit,
            context: AdaptiveRecognitionFeedbackContext(
                provider: history[index].provider,
                model: history[index].model,
                languageHint: history[index].languageHint,
                historyID: history[index].id,
                audioFileName: history[index].audioFileName
            )
        )
        history[index].applyUserCorrection(text)
    }

    @discardableResult
    func deleteHistoryItems(at offsets: IndexSet) -> Bool {
        let deletedItems = offsets.compactMap { index in
            history.indices.contains(index) ? history[index] : nil
        }
        return permanentlyDeleteHistoryItems(deletedItems)
    }

    @discardableResult
    private func permanentlyDeleteHistoryItems(
        _ deletedItems: [TranscriptItem],
        cancelsActiveAttempt: Bool = true
    ) -> Bool {
        guard !deletedItems.isEmpty else {
            return true
        }

        let deletedIDs = Set(deletedItems.map(\.id))
        stopAudioPlaybackIfNeeded(for: deletedIDs)
        do {
            let remainingItems = history.filter { !deletedIDs.contains($0.id) }
            let deletionResult = try TranscriptHistoryDeletionTransaction(
                historyStore: transcriptHistoryStore,
                audioStore: transcriptAudioStore
            ).commit(
                deletedItems: deletedItems,
                remainingItems: remainingItems,
                onHistoryCommitted: { [self] in
                    deletedHistoryIDs.formUnion(deletedIDs)
                    if cancelsActiveAttempt,
                       let activeTranscriptionAttemptID,
                       deletedIDs.contains(activeTranscriptionAttemptID) {
                        transcriptionTask?.cancel()
                    }
                }
            )
            clearLatestTranscriptAudioIfNeeded(for: deletedIDs)
            history.removeAll { deletedIDs.contains($0.id) }
            let cleanupMessages = [
                deletionResult.historyCleanupIssue?.localizedDescription,
                deletionResult.audioCleanupErrors.isEmpty
                    ? nil
                    : localizer.historyAudioCleanupPending(
                        deletionResult.audioCleanupErrors.joined(separator: "; ")
                    )
            ].compactMap { $0 }
            if !cleanupMessages.isEmpty {
                errorMessage = cleanupMessages.joined(separator: "\n\n")
            }
            return true
        } catch {
            errorMessage = localizer.historySaveFailed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteHistoryItem(id: UUID) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == id }) else {
            return false
        }

        return deleteHistoryItems(at: IndexSet(integer: index))
    }

    private func recordMetrics(for item: TranscriptItem) {
        guard !metricsRecords.contains(where: { $0.id == item.id }) else {
            return
        }

        metricsRecords.insert(metricsCalculator.record(for: item), at: 0)
    }

    func canPlayAudio(for item: TranscriptItem) -> Bool {
        transcriptAudioStore.audioExists(for: item)
    }

    var canPlayLatestTranscriptAudio: Bool {
        guard let item = latestTranscriptAudioItem else {
            return false
        }

        return canPlayAudio(for: item)
    }

    var canRetranscribeLatestTranscriptAudio: Bool {
        canPlayLatestTranscriptAudio
            && !isRecording
            && !recordingSession.isStarting
            && !recordingSession.isStopping
            && !isCheckingAudio
            && !isTranscribing
    }

    var canReplacePreviousInsertion: Bool {
        guard let lastInsertion,
              Date().timeIntervalSince(lastInsertion.date) <= 180,
              lastInsertion.bundleIdentifier != nil else {
            return false
        }

        return !currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentDraft != lastInsertion.text
            && !isRecording
            && !recordingSession.isStarting
            && !recordingSession.isStopping
            && !isTranscribing
            && !replacementTransactionGate.hasActiveTransaction
    }

    var isPlayingLatestTranscriptAudio: Bool {
        guard let item = latestTranscriptAudioItem else {
            return false
        }

        return playingAudioHistoryID == item.id
    }

    func toggleLatestTranscriptAudioPlayback() {
        guard let item = latestTranscriptAudioItem else {
            errorMessage = localizer.text(.recordedAudioUnavailable)
            return
        }

        toggleAudioPlayback(for: item)
    }

    func retranscribeLatestTranscriptAudio() {
        guard transcriptionTask == nil else {
            return
        }
        transcriptionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.retranscribeLatestTranscriptAudioNow()
            self.transcriptionTask = nil
        }
    }

    func replacePreviousInsertionWithCurrentDraft() {
        guard canReplacePreviousInsertion,
              let lastInsertion else {
            errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
            return
        }

        let replacementText = currentDraft
        guard startPreviousInsertionReplacement(
            lastInsertion,
            with: replacementText
        ) != nil else {
            Self.correctionLogger.notice(
                "Quick replacement ignored while another replacement is pending"
            )
            return
        }
    }

    func dismissFloatingCorrection(sessionID: UUID) {
        guard floatingCorrectionSession?.id == sessionID else {
            return
        }
        floatingCorrectionSession = nil
    }

    @discardableResult
    func confirmFloatingCorrection(sessionID: UUID, correctedText: String) -> Bool {
        guard let session = floatingCorrectionSession else {
            Self.correctionLogger.notice(
                "Confirmation ignored: floating session unavailable"
            )
            return false
        }
        guard session.id == sessionID else {
            Self.correctionLogger.notice(
                "Confirmation ignored: floating session changed"
            )
            return false
        }

        let replacementText = session.replacementText(for: correctedText)
        guard !replacementTransactionGate.hasActiveTransaction else {
            currentDraft = replacementText
            Self.correctionLogger.notice(
                "Confirmation ignored while a replacement transaction is pending"
            )
            return false
        }
        guard replacementText != session.originalText else {
            Self.correctionLogger.info(
                "Confirmation made no text change; originalGraphemes=\(session.originalText.count, privacy: .public) preservesTrailingNewline=\(session.hidesTrailingNewline, privacy: .public)"
            )
            if let insertion = lastInsertion,
               insertion.text == session.originalText {
                Task { [weak self] in
                    await self?.restoreInsertionTargetFocus(insertion)
                }
            }
            return true
        }

        currentDraft = replacementText
        guard let insertion = lastInsertion,
              insertion.text == session.originalText else {
            Self.correctionLogger.notice(
                "Confirmation copied for safety: latest insertion no longer matches session; hasInsertion=\(self.lastInsertion != nil, privacy: .public)"
            )
            recordDraftCorrectionIfNeeded(
                finalText: replacementText,
                source: .floatingCorrection
            )
            pasteboardInjector.copy(replacementText)
            errorMessage = localizer.voiceEditCorrectionCopiedForSafety()
            return true
        }

        Self.correctionLogger.notice(
            "Confirmation scheduled replacement; originalGraphemes=\(session.originalText.count, privacy: .public) replacementGraphemes=\(replacementText.count, privacy: .public) preservesTrailingNewline=\(insertion.preservesTrailingNewline, privacy: .public) observedExternalInteraction=\(insertion.observedExternalInteraction, privacy: .public)"
        )
        guard startPreviousInsertionReplacement(
            insertion,
            with: replacementText,
            feedbackSource: .floatingCorrection,
            floatingSessionID: session.id
        ) != nil else {
            return false
        }
        return true
    }

    func restoreFloatingCorrectionTarget(sessionID: UUID) {
        guard let session = floatingCorrectionSession,
              session.id == sessionID,
              let insertion = lastInsertion,
              insertion.text == session.originalText else {
            return
        }

        Task { [weak self] in
            await self?.restoreInsertionTargetFocus(insertion)
        }
    }

    func notePreviousInsertionTargetInteraction(sessionID: UUID) {
        guard lastInsertion?.id == sessionID else {
            return
        }
        lastInsertion?.observedExternalInteraction = true
        invalidateReplacementTransaction()
    }

    private func startReplacementTransaction(
        operation: @escaping @MainActor (ReplacementTransactionToken) async -> Bool
    ) -> Task<Bool, Never>? {
        guard let token = replacementTransactionGate.begin() else {
            return nil
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return false
            }
            let succeeded = await operation(token)
            self.finishReplacementTransaction(token)
            return succeeded
        }
        pendingReplacementTransaction = PendingReplacementTransaction(
            token: token,
            task: task
        )
        return task
    }

    private func startPreviousInsertionReplacement(
        _ insertion: LastShuoInsertion,
        with replacementText: String,
        feedbackSource: AdaptiveRecognitionFeedbackSource = .quickReplace,
        floatingSessionID: UUID? = nil
    ) -> Task<Bool, Never>? {
        startReplacementTransaction { [weak self] token in
            guard let self else {
                return false
            }
            return await self.replacePreviousInsertion(
                insertion,
                with: replacementText,
                feedbackSource: feedbackSource,
                floatingSessionID: floatingSessionID,
                transactionToken: token
            )
        }
    }

    private func startVoiceEditCorrection(
        _ correctedText: String,
        replacing insertion: LastShuoInsertion
    ) -> Task<Bool, Never>? {
        startReplacementTransaction { [weak self] token in
            guard let self else {
                return false
            }
            return await self.replacePreviousInsertion(
                insertion,
                with: correctedText,
                feedbackSource: .voiceEditCommand,
                floatingSessionID: nil,
                transactionToken: token
            )
        }
    }

    private func startVoiceEditDeletion(
        replacing insertion: LastShuoInsertion
    ) -> Task<Bool, Never>? {
        startReplacementTransaction { [weak self] token in
            guard let self else {
                return false
            }
            return await self.deletePreviousInsertion(
                replacing: insertion,
                transactionToken: token
            )
        }
    }

    private func finishReplacementTransaction(_ token: ReplacementTransactionToken) {
        replacementTransactionGate.finish(token)
        guard pendingReplacementTransaction?.token == token else {
            return
        }
        pendingReplacementTransaction = nil
    }

    private func invalidateReplacementTransaction() {
        replacementTransactionGate.invalidate()
        pendingReplacementTransaction?.task.cancel()
    }

    private func invalidateReplacementTransactionAndWait() async {
        invalidateReplacementTransaction()
        if let task = pendingReplacementTransaction?.task {
            _ = await task.value
        }
    }

    private func currentInsertion(
        matching insertion: LastShuoInsertion,
        transactionToken: ReplacementTransactionToken,
        floatingSessionID: UUID?
    ) -> LastShuoInsertion? {
        guard !Task.isCancelled,
              replacementTransactionGate.isCurrent(transactionToken),
              let currentInsertion = lastInsertion,
              currentInsertion.id == insertion.id,
              currentInsertion.text == insertion.text,
              !currentInsertion.observedExternalInteraction else {
            return nil
        }

        if let floatingSessionID {
            guard let session = floatingCorrectionSession,
                  session.id == floatingSessionID,
                  session.originalText == insertion.text else {
                return nil
            }
        }
        return currentInsertion
    }

    private func replacePreviousInsertion(
        _ insertion: LastShuoInsertion,
        with replacementText: String,
        feedbackSource: AdaptiveRecognitionFeedbackSource,
        floatingSessionID: UUID?,
        transactionToken: ReplacementTransactionToken
    ) async -> Bool {
        guard let target = await prepareReplacementTarget(
            for: insertion,
            failureFallback: .correction(
                text: replacementText,
                source: feedbackSource
            ),
            floatingSessionID: floatingSessionID,
            transactionToken: transactionToken
        ) else {
            return false
        }

        guard currentInsertion(
            matching: insertion,
            transactionToken: transactionToken,
            floatingSessionID: floatingSessionID
        ) != nil else {
            return false
        }
        return await applyVoiceEditCorrection(
            replacementText,
            replacing: insertion,
            targetProcessIdentifier: target.processIdentifier,
            feedbackSource: feedbackSource,
            allowsGuardedBackspaceFallback: target.allowsGuardedBackspaceFallback,
            floatingSessionID: floatingSessionID,
            transactionToken: transactionToken
        )
    }

    private func deletePreviousInsertion(
        replacing insertion: LastShuoInsertion,
        transactionToken: ReplacementTransactionToken
    ) async -> Bool {
        guard let target = await prepareReplacementTarget(
            for: insertion,
            failureFallback: .deletion,
            floatingSessionID: nil,
            transactionToken: transactionToken
        ) else {
            return false
        }

        return await applyVoiceEditDeletion(
            replacing: insertion,
            targetProcessIdentifier: target.processIdentifier,
            allowsGuardedBackspaceFallback: target.allowsGuardedBackspaceFallback,
            transactionToken: transactionToken
        )
    }

    private func prepareReplacementTarget(
        for insertion: LastShuoInsertion,
        failureFallback: ReplacementTargetFailureFallback,
        floatingSessionID: UUID?,
        transactionToken: ReplacementTransactionToken
    ) async -> PreparedReplacementTarget? {
        guard currentInsertion(
            matching: insertion,
            transactionToken: transactionToken,
            floatingSessionID: floatingSessionID
        ) != nil else {
            return nil
        }
        guard let targetBundleIdentifier = insertion.bundleIdentifier else {
            errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
            return nil
        }

        let targetApplication: NSRunningApplication?
        if let targetProcessIdentifier = insertion.applicationProcessIdentifier {
            let exactApplication = NSRunningApplication(
                processIdentifier: targetProcessIdentifier
            )
            targetApplication = exactApplication?.bundleIdentifier == targetBundleIdentifier
                ? exactApplication
                : nil
        } else {
            targetApplication = NSRunningApplication
                .runningApplications(withBundleIdentifier: targetBundleIdentifier)
                .first
        }
        guard let targetApplication, !targetApplication.isTerminated else {
            errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
            return nil
        }

        if currentFrontmostApplicationProcessIdentifier != targetApplication.processIdentifier {
            guard targetApplication.activate(options: [.activateAllWindows]) else {
                if currentInsertion(
                    matching: insertion,
                    transactionToken: transactionToken,
                    floatingSessionID: floatingSessionID
                ) != nil {
                    handleReplacementTargetFailure(failureFallback)
                }
                return nil
            }
        }

        let targetProcessIdentifier = targetApplication.processIdentifier
        var isVerified = false
        var usesGuardedBackspaceFallback = false
        for attempt in 0..<10 {
            guard let currentInsertion = currentInsertion(
                matching: insertion,
                transactionToken: transactionToken,
                floatingSessionID: floatingSessionID
            ) else {
                return nil
            }
            if let focusedTextTarget = insertion.focusedTextTarget,
               focusedTextTarget.applicationProcessIdentifier == targetProcessIdentifier {
                _ = pasteboardInjector.restoreFocus(to: focusedTextTarget)
            }

            let guardedBackspaceAllowed = GuardedBackspaceRewritePolicy.allowsRewrite(
                bundleIdentifier: insertion.bundleIdentifier,
                currentBundleIdentifier: currentFrontmostApplicationBundleIdentifier,
                targetProcessIdentifier: targetProcessIdentifier,
                currentProcessIdentifier: currentFrontmostApplicationProcessIdentifier,
                observedExternalInteraction: currentInsertion.observedExternalInteraction,
                previousText: currentInsertion.text
            )
            if currentInsertion.canSafelyRewrite(
                in: currentFrontmostApplicationBundleIdentifier,
                shuoBundleIdentifier: shuoBundleIdentifier
            ), guardedBackspaceAllowed {
                isVerified = true
                usesGuardedBackspaceFallback = true
                Self.correctionLogger.notice(
                    "Guarded backspace path selected; bundle=\(insertion.bundleIdentifier ?? "unknown", privacy: .public) pid=\(String(targetProcessIdentifier), privacy: .public) preservesTrailingNewline=\(insertion.preservesTrailingNewline, privacy: .public)"
                )
                break
            }

            if attempt < 9 {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return nil
                }
            }
        }

        guard isVerified else {
            guard currentInsertion(
                matching: insertion,
                transactionToken: transactionToken,
                floatingSessionID: floatingSessionID
            ) != nil else {
                return nil
            }
            Self.correctionLogger.notice(
                "Replacement target verification failed: app identity or interaction guard changed; bundle=\(insertion.bundleIdentifier ?? "unknown", privacy: .public) pid=\(String(targetProcessIdentifier), privacy: .public) observedExternalInteraction=\(insertion.observedExternalInteraction, privacy: .public)"
            )
            handleReplacementTargetFailure(failureFallback)
            return nil
        }

        return PreparedReplacementTarget(
            processIdentifier: targetProcessIdentifier,
            allowsGuardedBackspaceFallback: usesGuardedBackspaceFallback
        )
    }

    private func handleReplacementTargetFailure(
        _ fallback: ReplacementTargetFailureFallback
    ) {
        switch fallback {
        case .correction(let text, let source):
            guard !text.isEmpty else {
                // An empty correction represents deletion. There is no safe
                // clipboard fallback, and an unapplied deletion must not be
                // recorded as learned feedback.
                errorMessage = localizer.voiceEditDeletionNotVerified()
                return
            }
            recordDraftCorrectionIfNeeded(
                finalText: text,
                source: source
            )
            pasteboardInjector.copy(text)
            errorMessage = localizer.voiceEditCorrectionCopiedForSafety()
        case .deletion:
            // There is no safe clipboard fallback for deletion. Preserve both
            // the target text and the existing clipboard unchanged.
            errorMessage = localizer.voiceEditDeletionNotVerified()
        }
    }

    private func restoreInsertionTargetFocus(_ insertion: LastShuoInsertion) async {
        guard let targetBundleIdentifier = insertion.bundleIdentifier else {
            return
        }

        let targetApplication: NSRunningApplication?
        if let targetProcessIdentifier = insertion.applicationProcessIdentifier {
            let exactApplication = NSRunningApplication(
                processIdentifier: targetProcessIdentifier
            )
            targetApplication = exactApplication?.bundleIdentifier == targetBundleIdentifier
                ? exactApplication
                : nil
        } else {
            targetApplication = NSRunningApplication
                .runningApplications(withBundleIdentifier: targetBundleIdentifier)
                .first
        }
        guard let targetApplication, !targetApplication.isTerminated else {
            return
        }

        if currentFrontmostApplicationProcessIdentifier != targetApplication.processIdentifier {
            guard targetApplication.activate(options: [.activateAllWindows]) else {
                return
            }
        }

        let targetProcessIdentifier = targetApplication.processIdentifier
        for attempt in 0..<8 {
            if let focusedTextTarget = insertion.focusedTextTarget,
               focusedTextTarget.applicationProcessIdentifier == targetProcessIdentifier {
                _ = pasteboardInjector.restoreFocus(to: focusedTextTarget)
            }

            let accessibilityVerified = pasteboardInjector.canSafelyReplacePreviousInsertion(
                insertion.text,
                targetProcessIdentifier: targetProcessIdentifier,
                focusedTextTarget: insertion.focusedTextTarget,
                allowsValueSuffixFallback: !insertion.observedExternalInteraction
            )
            if currentFrontmostApplicationProcessIdentifier == targetProcessIdentifier,
               accessibilityVerified {
                return
            }

            if attempt < 7 {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func retranscribeLatestTranscriptAudioNow() async {
        guard canRetranscribeLatestTranscriptAudio,
              let item = latestTranscriptAudioItem,
              let audioURL = transcriptAudioStore.url(for: item) else {
            errorMessage = localizer.text(.recordedAudioUnavailable)
            return
        }

        stopAudioPlaybackIfNeeded(for: Set([item.id]))

        let requestSettings = pluginCapabilityPolicy.applying(to: settings)
        let selectedTranscriptionLanguages = TranscriptionLanguage.allCases.filter(
            requestSettings.selectedTranscriptionLanguages.contains
        )
        status = .transcribing
        errorMessage = nil
        let attemptID = UUID()
        let transcriptionStartedAt = Date()
        var normalizedTranscriptionAudioURL: URL?
        defer {
            if let normalizedTranscriptionAudioURL {
                try? FileManager.default.removeItem(at: normalizedTranscriptionAudioURL)
            }
        }

        do {
            let transcriptionAudioURL: URL
            if settings.whisperModeEnabled,
               let analysis = try? audioActivityAnalyzer.analyze(
                   audioURL,
                   silenceThresholdDBFS: settings.silenceThresholdDBFS,
                   adaptsToNoiseFloor: true
               ),
               let normalizedURL = try? whisperAudioNormalizer.normalizedCopy(
                   of: audioURL,
                   analysis: analysis
               ) {
                normalizedTranscriptionAudioURL = normalizedURL
                transcriptionAudioURL = normalizedURL
            } else {
                transcriptionAudioURL = audioURL
            }

            let processingResult = try await transcribeAndProcessAudio(
                at: transcriptionAudioURL,
                settings: requestSettings,
                allowsVoiceEditCommands: false
            )
            guard case .transcription(let processedTranscription) = processingResult else {
                status = .ready
                return
            }

            let text = processedTranscription.text
            let transcriptionLatency = Date().timeIntervalSince(transcriptionStartedAt)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                currentDraft = ""
                draftFeedbackBaseline = nil
                let metricsItem = TranscriptItem(
                    id: attemptID,
                    text: "",
                    rawText: processedTranscription.rawText,
                    locallyProcessedText: processedTranscription.locallyProcessedText,
                    provider: processedTranscription.provider,
                    model: processedTranscription.model,
                    languageHint: processedTranscription.languageHint,
                    outcome: .ignoredEmptyTranscript,
                    recordingDuration: item.recordingDuration,
                    transcriptionLatency: transcriptionLatency
                )
                recordMetrics(for: metricsItem)
                status = .ignoredEmptyTranscript
                return
            }

            currentDraft = text
            latestTranscriptAudioHistoryID = item.id

            let feedbackContext = AdaptiveRecognitionFeedbackContext(
                provider: processedTranscription.provider,
                model: processedTranscription.model,
                languageHint: processedTranscription.languageHint,
                historyID: item.id,
                audioFileName: item.audioFileName
            )
            draftFeedbackBaseline = DraftFeedbackBaseline(
                text: text,
                context: feedbackContext
            )

            if let index = history.firstIndex(where: { $0.id == item.id }) {
                history[index].rawText = processedTranscription.rawText
                history[index].locallyProcessedText = processedTranscription.locallyProcessedText
                history[index].text = text
                history[index].initialText = nil
                history[index].provider = processedTranscription.provider
                history[index].model = processedTranscription.model
                history[index].languageHint = processedTranscription.languageHint
                history[index].selectedTranscriptionLanguages = selectedTranscriptionLanguages
                history[index].detectedLanguageCode = processedTranscription.detectedLanguageCode
                history[index].outcome = .succeeded
                history[index].errorSummary = nil
                history[index].transcriptionLatency = transcriptionLatency
            }

            let metricsItem = TranscriptItem(
                id: attemptID,
                text: text,
                rawText: processedTranscription.rawText,
                locallyProcessedText: processedTranscription.locallyProcessedText,
                provider: processedTranscription.provider,
                model: processedTranscription.model,
                languageHint: processedTranscription.languageHint,
                selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                detectedLanguageCode: processedTranscription.detectedLanguageCode,
                recordingDuration: item.recordingDuration,
                transcriptionLatency: transcriptionLatency
            )
            recordMetrics(for: metricsItem)

            status = .ready
        } catch {
            let localizedError = localizedErrorMessage(error)
            let transcriptionLatency = Date().timeIntervalSince(transcriptionStartedAt)
            if Self.isCancellation(error) {
                let metricsItem = TranscriptItem(
                    id: attemptID,
                    text: "",
                    provider: requestSettings.provider,
                    model: requestSettings.effectiveModel,
                    languageHint: requestSettings.languageHint,
                    selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                    outcome: .cancelled,
                    errorSummary: localizer.transcriptionCancelled(),
                    recordingDuration: item.recordingDuration,
                    transcriptionLatency: transcriptionLatency
                )
                recordMetrics(for: metricsItem)
                status = .ready
                errorMessage = nil
                return
            }
            let metricsItem = TranscriptItem(
                id: attemptID,
                text: "",
                provider: requestSettings.provider,
                model: requestSettings.effectiveModel,
                languageHint: requestSettings.languageHint,
                selectedTranscriptionLanguages: selectedTranscriptionLanguages,
                outcome: .failed,
                errorSummary: Self.summarizedErrorMessage(localizedError),
                recordingDuration: item.recordingDuration,
                transcriptionLatency: transcriptionLatency
            )
            recordMetrics(for: metricsItem)
            status = .ready
            errorMessage = localizedError
        }
    }

    func toggleAudioPlayback(for item: TranscriptItem) {
        if playingAudioHistoryID == item.id {
            transcriptAudioPlayer.stop()
            playingAudioHistoryID = nil
            return
        }

        guard let url = transcriptAudioStore.url(for: item),
              transcriptAudioStore.audioExists(for: item) else {
            errorMessage = localizer.text(.recordedAudioUnavailable)
            return
        }

        do {
            playingAudioHistoryID = item.id
            try transcriptAudioPlayer.play(
                url,
                outputDeviceID: lastAudioRouteOutputDeviceID
            ) { [weak self] in
                self?.playingAudioHistoryID = nil
            }
            errorMessage = nil
        } catch {
            playingAudioHistoryID = nil
            errorMessage = localizedErrorMessage(error)
        }
    }

    private var latestTranscriptAudioItem: TranscriptItem? {
        if let latestTranscriptAudioHistoryID,
           let item = history.first(where: { $0.id == latestTranscriptAudioHistoryID }),
           transcriptAudioStore.audioExists(for: item) {
            return item
        }

        return history.first { transcriptAudioStore.audioExists(for: $0) }
    }

    var canPasteIntoFocusedApp: Bool {
        pasteboardInjector.isAccessibilityTrusted
    }

    var isPushToTalkRunning: Bool {
        pushToTalkMonitor?.isRunning == true
    }

    private func apiKey(for provider: TranscriptionProvider) -> String {
        switch provider {
        case .openAI, .custom:
            loadOpenAIAPIKeyIfNeeded()
            return openAIAPIKey
        case .elevenLabs:
            loadElevenLabsAPIKeyIfNeeded()
            return elevenLabsAPIKey
        case .alibaba:
            loadAlibabaAPIKeyIfNeeded()
            return alibabaAPIKey
        case .gemini:
            loadGeminiAPIKeyIfNeeded()
            return geminiAPIKey
        case .local:
            return ""
        }
    }

    private func apiKeyForPostTranscriptionProcessing(settings requestSettings: AppSettings) -> String {
        let requestSettings = CloudTextAICapabilityPolicy.applying(
            to: pluginCapabilityPolicy.applying(to: requestSettings)
        )
        guard CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: requestSettings) else {
            return ""
        }
        guard requestSettings.transcriptRetouchEnabled
            || (requestSettings.emojiPostProcessingEnabled && requestSettings.aiEmojiResolverEnabled) else {
            return ""
        }

        if requestSettings.provider == .gemini {
            loadGeminiAPIKeyIfNeeded()
            return geminiAPIKey
        }

        loadOpenAIAPIKeyIfNeeded()
        if requestSettings.openAITextModelSelectionMode == .automatic,
           openAIModelAvailabilityFetchedAt != nil,
           OpenAIModelCatalog.recommendedTextModelID(
               availableModelIDs: openAIAvailableModelIDs
           ) == nil {
            errorMessage = OpenAIModelSelectionError.noCompatibleTextModel.localizedDescription
            return ""
        }
        return openAIAPIKey
    }

    private func scheduleCorrectionLearningSnapshotRefresh() {
        correctionLearningSnapshotTask?.cancel()
        correctionLearningSnapshotRevision += 1
        let revision = correctionLearningSnapshotRevision
        let historySnapshot = history
        let stateSnapshot = adaptiveRecognitionState

        if AppRuntime.isRunningUnderXCTest {
            correctionLearningSnapshot = adaptiveRecognitionService.learningSnapshot(
                history: historySnapshot,
                state: stateSnapshot
            )
            return
        }

        let service = adaptiveRecognitionService
        correctionLearningSnapshotTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            let work = Task.detached(priority: .utility) {
                service.learningSnapshot(
                    history: historySnapshot,
                    state: stateSnapshot
                )
            }
            let snapshot = await withTaskCancellationHandler(
                operation: { await work.value },
                onCancel: { work.cancel() }
            )
            guard !Task.isCancelled,
                  let self,
                  self.correctionLearningSnapshotRevision == revision else {
                return
            }
            self.correctionLearningSnapshot = snapshot
        }
    }

    private func captureTranscriptionVocabulary(
        settings requestSettings: AppSettings? = nil,
        correctionLearningSnapshot: CorrectionLearningSnapshot? = nil
    ) -> TranscriptionVocabularySnapshot {
        let effectiveSettings = pluginCapabilityPolicy.applying(to: requestSettings ?? settings)
        guard !effectiveSettings.usesSenseVoiceLocalTranscription else {
            return .empty
        }
        let learningSnapshot = correctionLearningSnapshot
            ?? correctionLearningSnapshotForExecution(settings: effectiveSettings)
        return projectVocabularyController.captureTranscriptionVocabulary(
            manualGlossary: effectiveSettings.useDeveloperGlossary
                ? effectiveSettings.effectiveManualVocabularyGlossary
                : "",
            learnedCorrectionTerms: effectiveSettings.adaptiveRecognitionEnabled
                && effectiveSettings.adaptiveRecognitionMode.usesVocabularyHints
                && effectiveSettings.provider != .local
                ? learningSnapshot.vocabularyHints
                : [],
            presetTerms: effectiveSettings.useDeveloperGlossary
                ? effectiveSettings.effectivePresetVocabularyTerms
                : [],
            isEnabled: isPluginEnabled(.smartPreferredTerms)
        )
    }

    private func correctionLearningSnapshotForExecution(
        settings requestSettings: AppSettings? = nil
    ) -> CorrectionLearningSnapshot {
        let effectiveSettings = pluginCapabilityPolicy.applying(to: requestSettings ?? settings)
        guard effectiveSettings.adaptiveRecognitionEnabled else {
            return .empty
        }
        return adaptiveRecognitionService.applyingEnabledPatterns(
            to: correctionLearningSnapshot,
            enabledPatternIDs: adaptiveRecognitionState.enabledCorrectionPatternIDs
        )
    }

    private func recordDraftCorrectionIfNeeded(
        finalText: String,
        source: AdaptiveRecognitionFeedbackSource
    ) {
        guard let baseline = draftFeedbackBaseline else {
            return
        }

        recordExplicitCorrection(
            before: baseline.text,
            after: finalText,
            source: source,
            context: baseline.context
        )

        draftFeedbackBaseline = DraftFeedbackBaseline(
            text: finalText,
            context: baseline.context
        )
    }

    private func recordExplicitCorrection(
        before beforeText: String,
        after afterText: String,
        source: AdaptiveRecognitionFeedbackSource,
        context: AdaptiveRecognitionFeedbackContext
    ) {
        let updatedState = adaptiveRecognitionService.recordFeedback(
            before: beforeText,
            after: afterText,
            source: source,
            context: context,
            state: adaptiveRecognitionState
        )
        guard updatedState != adaptiveRecognitionState else {
            return
        }

        adaptiveRecognitionState = updatedState
        showCorrectionCapturedNotice()
    }

    private func showCorrectionCapturedNotice() {
        learningNoticeTask?.cancel()
        learningNoticeMessage = localizer.correctionCapturedLabel()
        learningNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.learningNoticeMessage = nil
        }
    }

    private func adaptiveRecognitionFeedbackContext(
        historyID: UUID?
    ) -> AdaptiveRecognitionFeedbackContext {
        if let historyID,
           let item = history.first(where: { $0.id == historyID }) {
            return AdaptiveRecognitionFeedbackContext(
                provider: item.provider,
                model: item.model,
                languageHint: item.languageHint,
                historyID: item.id,
                audioFileName: item.audioFileName
            )
        }

        return AdaptiveRecognitionFeedbackContext(
            provider: settings.provider,
            model: settings.effectiveModel,
            languageHint: settings.languageHint
        )
    }

    private func handleVoiceEditCommand(
        _ rawText: String,
        fallbackText: String,
        settings effectiveSettings: AppSettings
    ) async throws -> Bool {
        if isPluginEnabled(.commandDeletePrevious),
           voiceEditCommandParser.isDeletePreviousInsertionCommand(rawText)
            || voiceEditCommandParser.isDeletePreviousInsertionCommand(fallbackText) {
            guard let lastInsertion else {
                errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
                return true
            }

            guard lastInsertion.canSafelyRewrite(
                in: currentFrontmostApplicationBundleIdentifier,
                shuoBundleIdentifier: shuoBundleIdentifier
            ) else {
                errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
                return true
            }

            if let task = startVoiceEditDeletion(replacing: lastInsertion) {
                _ = await task.value
            }
            return true
        }

        let command = voiceEditCommandParser.parse(rawText) ?? voiceEditCommandParser.parse(fallbackText)
        let commandText = voiceEditLocalResolver.commandText(
            rawText: rawText,
            fallbackText: fallbackText,
            parser: voiceEditCommandParser
        )

        guard isPluginEnabled(.commandModifyPrevious) else {
            return false
        }

        guard let command else {
            if voiceEditCommandParser.looksLikeEditCommand(rawText)
                || voiceEditCommandParser.looksLikeEditCommand(fallbackText) {
                guard effectiveSettings.voiceEditCommandMode != .localOnly else {
                    errorMessage = localizer.voiceEditCommandFormatHint()
                    return true
                }

                guard let lastInsertion else {
                    errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
                    return true
                }

                guard lastInsertion.canSafelyRewrite(
                    in: currentFrontmostApplicationBundleIdentifier,
                    shuoBundleIdentifier: shuoBundleIdentifier
                ) else {
                    errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
                    return true
                }

                do {
                    let correctedText = try await rewriteVoiceEditWithLLM(
                        previousText: lastInsertion.text,
                        commandText: commandText,
                        settings: effectiveSettings
                    )
                    if let task = startVoiceEditCorrection(
                        correctedText,
                        replacing: lastInsertion
                    ) {
                        _ = await task.value
                    }
                } catch {
                    if Self.isCancellation(error) {
                        throw error
                    }
                    errorMessage = localizedErrorMessage(error)
                }
                return true
            }
            return false
        }

        guard let lastInsertion else {
            errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
            return true
        }

        guard lastInsertion.canSafelyRewrite(
            in: currentFrontmostApplicationBundleIdentifier,
            shuoBundleIdentifier: shuoBundleIdentifier
        ) else {
            errorMessage = localizer.voiceEditCommandNeedsRecentPaste()
            return true
        }

        let correctedText = voiceEditLocalResolver.replacing(
            command.source,
            with: command.replacement,
            in: lastInsertion.text
        )
        let resolution = try await resolveVoiceEdit(
            command: command,
            commandText: commandText,
            previousText: lastInsertion.text,
            localCorrectedText: correctedText,
            settings: effectiveSettings
        )

        guard let resolution else {
            return true
        }

        switch resolution {
        case .local(let correctedText):
            if let task = startVoiceEditCorrection(
                correctedText,
                replacing: lastInsertion
            ) {
                _ = await task.value
            }
        case .llm(let correctedText):
            if let task = startVoiceEditCorrection(
                correctedText,
                replacing: lastInsertion
            ) {
                _ = await task.value
            }
        }

        return true
    }

    private func applyVoiceEditDeletion(
        replacing lastInsertion: LastShuoInsertion,
        targetProcessIdentifier: pid_t,
        allowsGuardedBackspaceFallback: Bool,
        transactionToken: ReplacementTransactionToken
    ) async -> Bool {
        guard currentInsertion(
            matching: lastInsertion,
            transactionToken: transactionToken,
            floatingSessionID: nil
        ) != nil else {
            return false
        }
        guard !lastInsertion.text.isEmpty else {
            errorMessage = localizer.voiceEditCommandCouldNotApply()
            return false
        }

        let result = await pasteboardInjector.replacePreviousInsertion(
            previousText: lastInsertion.text,
            with: "",
            restoreClipboard: true,
            targetProcessIdentifier: targetProcessIdentifier,
            focusedTextTarget: lastInsertion.focusedTextTarget,
            allowsValueSuffixFallback: !lastInsertion.observedExternalInteraction,
            allowsGuardedBackspaceFallback: allowsGuardedBackspaceFallback,
            preservesTrailingNewline: lastInsertion.preservesTrailingNewline,
            terminalApplicationBundleIdentifier: lastInsertion.bundleIdentifier,
            validateBeforeDestructiveAction: { [weak self] in
                self?.currentInsertion(
                    matching: lastInsertion,
                    transactionToken: transactionToken,
                    floatingSessionID: nil
                ) != nil
            }
        )

        switch result {
        case .replaced:
            break
        case .eventAccessDenied:
            errorMessage = localizer.text(.accessibilityPermissionMayBeNeeded)
            return false
        case .clipboardSnapshotUnavailable:
            errorMessage = localizer.clipboardSnapshotUnavailable()
            return false
        case .partialModification:
            self.lastInsertion = nil
            errorMessage = localizer.replacementPartiallyModified()
            return false
        case .notVerified, .copiedForSafety:
            errorMessage = localizer.voiceEditDeletionNotVerified()
            return false
        }

        guard currentInsertion(
            matching: lastInsertion,
            transactionToken: transactionToken,
            floatingSessionID: nil
        ) != nil else {
            self.lastInsertion = nil
            return false
        }

        currentDraft = ""
        draftFeedbackBaseline = nil
        errorMessage = nil

        if let historyID = lastInsertion.historyID,
           let item = history.first(where: { $0.id == historyID }) {
            _ = permanentlyDeleteHistoryItems([item])
        }

        self.lastInsertion = nil
        return true
    }

    private func resolveVoiceEdit(
        command: VoiceEditCommand,
        commandText: String,
        previousText: String,
        localCorrectedText: String,
        settings effectiveSettings: AppSettings
    ) async throws -> VoiceEditResolution? {
        if voiceEditLocalResolver.shouldUseLocalResolution(
            mode: effectiveSettings.voiceEditCommandMode
        ) {
            guard localCorrectedText != previousText else {
                errorMessage = localizer.voiceEditCommandSourceNotFound(command.source)
                return nil
            }

            return .local(localCorrectedText)
        }

        guard effectiveSettings.voiceEditCommandMode != .localOnly else {
            if localCorrectedText == previousText {
                errorMessage = localizer.voiceEditCommandSourceNotFound(command.source)
            } else {
                errorMessage = localizer.voiceEditCommandCouldNotApply()
            }
            return nil
        }

        do {
            let correctedText = try await rewriteVoiceEditWithLLM(
                previousText: previousText,
                commandText: commandText,
                settings: effectiveSettings
            )
            return .llm(correctedText)
        } catch {
            if Self.isCancellation(error) {
                throw error
            }
            errorMessage = localizedErrorMessage(error)
            return nil
        }
    }

    private func applyVoiceEditCorrection(
        _ correctedText: String,
        replacing lastInsertion: LastShuoInsertion,
        targetProcessIdentifier: pid_t? = nil,
        feedbackSource: AdaptiveRecognitionFeedbackSource = .voiceEditCommand,
        allowsGuardedBackspaceFallback: Bool = false,
        floatingSessionID: UUID?,
        transactionToken: ReplacementTransactionToken
    ) async -> Bool {
        guard currentInsertion(
            matching: lastInsertion,
            transactionToken: transactionToken,
            floatingSessionID: floatingSessionID
        ) != nil else {
            return false
        }
        guard correctedText != lastInsertion.text else {
            errorMessage = localizer.voiceEditCommandMadeNoChange()
            return false
        }

        let result = await pasteboardInjector.replacePreviousInsertion(
            previousText: lastInsertion.text,
            with: correctedText,
            restoreClipboard: true,
            targetProcessIdentifier: targetProcessIdentifier,
            focusedTextTarget: lastInsertion.focusedTextTarget,
            allowsValueSuffixFallback: !lastInsertion.observedExternalInteraction,
            allowsGuardedBackspaceFallback: allowsGuardedBackspaceFallback,
            preservesTrailingNewline: lastInsertion.preservesTrailingNewline,
            terminalApplicationBundleIdentifier: lastInsertion.bundleIdentifier,
            validateBeforeDestructiveAction: { [weak self] in
                self?.currentInsertion(
                    matching: lastInsertion,
                    transactionToken: transactionToken,
                    floatingSessionID: floatingSessionID
                ) != nil
            }
        )

        switch result {
        case .replaced:
            break
        case .eventAccessDenied:
            errorMessage = localizer.text(.accessibilityPermissionMayBeNeeded)
            return false
        case .clipboardSnapshotUnavailable:
            errorMessage = localizer.clipboardSnapshotUnavailable()
            return false
        case .partialModification:
            self.lastInsertion = nil
            errorMessage = localizer.replacementPartiallyModified()
            return false
        case .copiedForSafety, .notVerified:
            pasteboardInjector.copy(correctedText)
            errorMessage = localizer.voiceEditCorrectionCopiedForSafety()
            return false
        }

        guard currentInsertion(
            matching: lastInsertion,
            transactionToken: transactionToken,
            floatingSessionID: floatingSessionID
        ) != nil else {
            self.lastInsertion = nil
            return false
        }

        let feedbackContext = adaptiveRecognitionFeedbackContext(historyID: lastInsertion.historyID)
        recordExplicitCorrection(
            before: lastInsertion.text,
            after: correctedText,
            source: feedbackSource,
            context: feedbackContext
        )

        currentDraft = correctedText
        draftFeedbackBaseline = DraftFeedbackBaseline(
            text: correctedText,
            context: feedbackContext
        )
        errorMessage = nil

        if let historyID = lastInsertion.historyID,
           let index = history.firstIndex(where: { $0.id == historyID }) {
            history[index].applyUserCorrection(correctedText)
        }

        self.lastInsertion = LastShuoInsertion(
            text: correctedText,
            historyID: lastInsertion.historyID,
            date: Date(),
            bundleIdentifier: lastInsertion.bundleIdentifier,
            applicationProcessIdentifier: lastInsertion.applicationProcessIdentifier,
            focusedTextTarget: lastInsertion.focusedTextTarget,
            observedExternalInteraction: false,
            preservesTrailingNewline: lastInsertion.preservesTrailingNewline
        )

        if feedbackSource == .floatingCorrection,
           let session = floatingCorrectionSession,
           let advancedSession = session.advancingAfterSuccessfulReplacement(
               from: lastInsertion.text,
               to: correctedText
           ) {
            floatingCorrectionSession = advancedSession
            Self.correctionLogger.info(
                "Retained floating correction session after replacement; graphemes=\(correctedText.count, privacy: .public)"
            )
        }
        return true
    }

    private func rewriteVoiceEditWithLLM(
        previousText: String,
        commandText: String,
        settings requestSettings: AppSettings
    ) async throws -> String {
        let effectiveSettings = CloudTextAICapabilityPolicy.applying(to: requestSettings)
        guard CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: effectiveSettings) else {
            throw effectiveSettings.provider == .local
                ? VoiceEditLLMError.unavailableInLocalMode
                : VoiceEditLLMError.disabledInSettings
        }

        let apiKey: String
        if effectiveSettings.provider == .gemini {
            loadGeminiAPIKeyIfNeeded()
            apiKey = geminiAPIKey
        } else {
            loadOpenAIAPIKeyIfNeeded()
            if effectiveSettings.openAITextModelSelectionMode == .automatic,
               openAIModelAvailabilityFetchedAt != nil,
               OpenAIModelCatalog.recommendedTextModelID(
                   availableModelIDs: openAIAvailableModelIDs
               ) == nil {
                throw OpenAIModelSelectionError.noCompatibleTextModel
            }
            apiKey = openAIAPIKey
        }

        do {
            let rewritten = try await voiceEditLLMService.rewrite(
                VoiceEditLLMRequest(
                    previousText: previousText,
                    commandText: commandText,
                    settings: effectiveSettings,
                    apiKey: apiKey
                )
            )
            return TranscriptPostProcessor().process(rewritten, settings: effectiveSettings)
        } catch {
            if effectiveSettings.provider == .openAI {
                refreshOpenAIModelsAfterFailureIfNeeded(error)
            }
            throw error
        }
    }

    private func captureCurrentInputTarget() -> RecordingInputTarget? {
        guard let targetApplication = NSWorkspace.shared.frontmostApplication,
              !targetApplication.isTerminated,
              targetApplication.bundleIdentifier != shuoBundleIdentifier else {
            Self.insertionTargetLogger.notice(
                "Could not capture a non-Shuo input target at recording start"
            )
            return nil
        }

        let processIdentifier = targetApplication.processIdentifier
        let focusedTextTarget = pasteboardInjector.focusedTextTarget(
            applicationProcessIdentifier: processIdentifier
        )
        Self.insertionTargetLogger.info(
            "Captured recording input target; bundle=\(targetApplication.bundleIdentifier ?? "unknown", privacy: .public) pid=\(String(processIdentifier), privacy: .public) role=\(focusedTextTarget?.accessibilityRole ?? "unavailable", privacy: .public)"
        )
        return RecordingInputTarget(
            applicationProcessIdentifier: processIdentifier,
            bundleIdentifier: targetApplication.bundleIdentifier,
            focusedTextTarget: focusedTextTarget
        )
    }

    private func prepareRecordingInputTarget(
        _ target: RecordingInputTarget
    ) async -> NSRunningApplication? {
        guard let targetApplication = NSRunningApplication(
            processIdentifier: target.applicationProcessIdentifier
        ),
              !targetApplication.isTerminated,
              targetApplication.bundleIdentifier == target.bundleIdentifier else {
            Self.insertionTargetLogger.notice(
                "Recorded input target is no longer running; bundle=\(target.bundleIdentifier ?? "unknown", privacy: .public) pid=\(String(target.applicationProcessIdentifier), privacy: .public)"
            )
            return nil
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            != target.applicationProcessIdentifier {
            _ = targetApplication.activate(options: [.activateAllWindows])
        }

        for attempt in 0..<10 {
            if let focusedTextTarget = target.focusedTextTarget {
                _ = pasteboardInjector.restoreFocus(to: focusedTextTarget)
            }

            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == target.applicationProcessIdentifier {
                Self.insertionTargetLogger.info(
                    "Prepared recorded input target for paste; bundle=\(target.bundleIdentifier ?? "unknown", privacy: .public) pid=\(String(target.applicationProcessIdentifier), privacy: .public)"
                )
                return targetApplication
            }

            if attempt < 9 {
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }

        Self.insertionTargetLogger.notice(
            "Could not reactivate recorded input target; bundle=\(target.bundleIdentifier ?? "unknown", privacy: .public) pid=\(String(target.applicationProcessIdentifier), privacy: .public)"
        )
        return nil
    }

    private func paste(
        _ text: String,
        historyID: UUID?,
        recordingTarget: RecordingInputTarget? = nil,
        preservesTrailingNewline: Bool = false,
        punctuationMode: PunctuationPostProcessingMode = .keep,
        boundaryMode: TranscriptInsertionBoundaryMode = .none
    ) async {
        guard !Task.isCancelled,
              historyID.map({ !deletedHistoryIDs.contains($0) }) ?? true else {
            return
        }
        await invalidateReplacementTransactionAndWait()
        guard !Task.isCancelled,
              historyID.map({ !deletedHistoryIDs.contains($0) }) ?? true else {
            return
        }
        lastInsertion = nil
        floatingCorrectionSession = nil

        let targetApplication: NSRunningApplication?
        if let recordingTarget {
            targetApplication = await prepareRecordingInputTarget(recordingTarget)
            guard targetApplication != nil else {
                pasteboardInjector.copy(text)
                lastInsertion = nil
                errorMessage = localizer.voiceEditCorrectionCopiedForSafety()
                return
            }
        } else {
            targetApplication = NSWorkspace.shared.frontmostApplication
        }
        guard !Task.isCancelled,
              historyID.map({ !deletedHistoryIDs.contains($0) }) ?? true else {
            return
        }

        let targetBundleIdentifier = targetApplication?.bundleIdentifier
        let targetProcessIdentifier = targetApplication?.processIdentifier
        let focusedTextTarget = targetApplication.flatMap {
            pasteboardInjector.focusedTextTarget(
                applicationProcessIdentifier: $0.processIdentifier
            )
        }
        switch await pasteboardInjector.paste(
            text,
            restoreClipboard: true
        ) {
        case .pasteEventPosted:
            lastInsertion = LastShuoInsertion(
                text: text,
                historyID: historyID,
                date: Date(),
                bundleIdentifier: targetBundleIdentifier,
                applicationProcessIdentifier: targetProcessIdentifier,
                focusedTextTarget: focusedTextTarget,
                observedExternalInteraction: false,
                preservesTrailingNewline: preservesTrailingNewline
            )
            Self.insertionTargetLogger.info(
                "Posted paste to captured target; bundle=\(targetBundleIdentifier ?? "unknown", privacy: .public) pid=\(String(targetProcessIdentifier ?? 0), privacy: .public) role=\(focusedTextTarget?.accessibilityRole ?? "unavailable", privacy: .public)"
            )
            if isPluginEnabled(.smartCorrectionWindow) {
                floatingCorrectionSession = FloatingCorrectionSession(
                    originalText: text,
                    hidesTrailingNewline: preservesTrailingNewline,
                    punctuationMode: punctuationMode,
                    boundaryMode: boundaryMode
                )
                Self.correctionLogger.notice(
                    "Created floating correction session; graphemes=\(text.count, privacy: .public) preservesTrailingNewline=\(preservesTrailingNewline, privacy: .public)"
                )
            }
        case .copiedOnly:
            lastInsertion = nil
            errorMessage = localizer.text(.accessibilityPermissionMayBeNeeded)
        case .clipboardSnapshotUnavailable:
            lastInsertion = nil
            errorMessage = localizer.clipboardSnapshotUnavailable()
        case .cancelled:
            lastInsertion = nil
        }
    }

    private func clearLatestTranscriptAudioIfNeeded(for historyIDs: Set<UUID>) {
        guard let latestTranscriptAudioHistoryID,
              historyIDs.contains(latestTranscriptAudioHistoryID) else {
            return
        }

        self.latestTranscriptAudioHistoryID = nil
    }

    private func stopAudioPlaybackIfNeeded(for historyIDs: Set<UUID>) {
        guard let playingAudioHistoryID,
              historyIDs.contains(playingAudioHistoryID) else {
            return
        }

        transcriptAudioPlayer.stop(notify: false)
        self.playingAudioHistoryID = nil
    }

    private var currentFrontmostApplicationBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private var currentFrontmostApplicationProcessIdentifier: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private var shuoBundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    private var preferredAudioOutputDeviceID: String? {
        AudioOutputDeviceCatalog.preferredOutputDevice(matchingInputDeviceID: settings.audioInputDeviceID)?.id
    }

    private var currentAudioRouteOutputDeviceID: String? {
        recordingSession.currentRoute?.outputDeviceID ?? preferredAudioOutputDeviceID
    }

    private var lastAudioRouteOutputDeviceID: String? {
        recordingSession.lastRoute?.outputDeviceID ?? preferredAudioOutputDeviceID
    }

    private var pluginCapabilityPolicy: PluginCapabilityPolicy {
        PluginCapabilityPolicy(configuration: pluginConfiguration)
    }

    private func normalizeProviderForPluginConfiguration() {
        guard let provider = pluginCapabilityPolicy.availableProvider(fallingBackFrom: settings.provider),
              provider != settings.provider else {
            return
        }
        settings.provider = provider
    }

    private func playRecordingStartSoundIfNeeded() {
        guard settings.recordingStartSoundEnabled else {
            return
        }

        do {
            try recordingCuePlayer.play(
                settings.recordingStartSound,
                volumeScale: RecordingCuePlaybackLevel.scale(
                    whisperModeEnabled: settings.whisperModeEnabled
                ),
                outputDeviceID: currentAudioRouteOutputDeviceID
            )
        } catch {
            NSSound.beep()
        }
    }

    func setPushToTalkEnabled(_ enabled: Bool) {
        guard settings.pushToTalkEnabled != enabled else {
            return
        }

        if !enabled {
            cancelActiveRecording()
        }

        settings.pushToTalkEnabled = enabled
    }

    func setPushToTalkShortcut(_ shortcut: PushToTalkShortcut) {
        guard settings.pushToTalkShortcut != shortcut else {
            return
        }

        // A shortcut can be changed while its old modifier is still held.
        // Clear the held/recording transaction before replacing the event tap
        // so the next press always begins from a clean state.
        cancelActiveRecording()
        settings.pushToTalkShortcut = shortcut
    }

    func setCustomPushToTalkShortcut(_ shortcut: CustomPushToTalkShortcut) {
        guard settings.customPushToTalkShortcut != shortcut
            || settings.pushToTalkShortcut != .custom else {
            return
        }

        cancelActiveRecording()
        settings.customPushToTalkShortcut = shortcut
        settings.pushToTalkShortcut = .custom
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        startPermissionRetryTimer()
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func requestMicrophonePermission() {
        Task {
            let granted = await AudioRecorder.requestMicrophoneAccess()
            refreshSystemPermissions()

            if granted {
                errorMessage = nil
                status = .microphonePermissionGranted
            } else {
                errorMessage = localizer.microphonePermissionDenied()
                openMicrophoneSettings()
            }
        }
    }

    func requestAccessibilityPermission() {
        let granted = RightOptionPushToTalkMonitor.requestAccessibilityPermission()
        refreshSystemPermissions()
        if granted {
            configurePushToTalkMonitor()
        } else {
            // AXIsProcessTrustedWithOptions may not show another prompt after a
            // prior denial. Always provide visible progress by opening the exact
            // pane where the user can grant access; the bounded retry timer
            // reconnects the shortcut automatically after they return.
            openAccessibilitySettings()
        }
    }

    func refreshSystemPermissions() {
        microphonePermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityPermissionGranted = RightOptionPushToTalkMonitor.hasAccessibilityPermission
    }

    private func configurePushToTalkMonitor() {
        pushToTalkMonitor?.stop()
        pushToTalkMonitor = nil

        guard !AppRuntime.isRunningUnderXCTest else {
            pushToTalkStatusMessage = localizer.pushToTalkDisabled(
                shortcut: settings.pushToTalkShortcut,
                customShortcut: settings.customPushToTalkShortcut
            )
            return
        }

        guard settings.pushToTalkEnabled else {
            pushToTalkStatusMessage = localizer.pushToTalkDisabled(
                shortcut: settings.pushToTalkShortcut,
                customShortcut: settings.customPushToTalkShortcut
            )
            return
        }

        if settings.pushToTalkShortcut == .custom,
           settings.customPushToTalkShortcut == nil {
            pushToTalkStatusMessage = localizer.customShortcutNotRecorded()
            return
        }

        pushToTalkMonitor = RightOptionPushToTalkMonitor(
            shortcut: settings.pushToTalkShortcut,
            customShortcut: settings.customPushToTalkShortcut,
            onPress: { [weak self] in
                Task { @MainActor in
                    self?.beginPushToTalkRecording()
                }
            },
            onRelease: { [weak self] in
                Task { @MainActor in
                    self?.endPushToTalkRecording()
                }
            }
        )

        if pushToTalkMonitor?.start() == true {
            stopPermissionRetryTimer()
            pushToTalkStatusMessage = localizer.holdToDictate(
                shortcut: settings.pushToTalkShortcut,
                customShortcut: settings.customPushToTalkShortcut
            )
        } else if !RightOptionPushToTalkMonitor.hasAccessibilityPermission {
            pushToTalkStatusMessage = localizer.waitingForAccessibility(
                shortcut: settings.pushToTalkShortcut,
                customShortcut: settings.customPushToTalkShortcut
            )
        } else {
            pushToTalkStatusMessage = localizer.shortcutMonitorCouldNotStart(
                shortcut: settings.pushToTalkShortcut,
                customShortcut: settings.customPushToTalkShortcut
            )
        }
    }

    private func startPermissionRetryTimer() {
        permissionRetryDeadline = Date().addingTimeInterval(120)
        guard permissionRetryTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.refreshSystemPermissions()
                guard self.permissionRetryDeadline.map({ Date() < $0 }) == true else {
                    self.stopPermissionRetryTimer()
                    return
                }

                guard self.settings.pushToTalkEnabled,
                      !self.isPushToTalkRunning,
                      self.accessibilityPermissionGranted else {
                    return
                }
                self.configurePushToTalkMonitor()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        permissionRetryTimer = timer
    }

    private func stopPermissionRetryTimer() {
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        permissionRetryDeadline = nil
    }

    private func cancelActiveRecording() {
        pushToTalkIsHeld = false
        pushToTalkIntentGeneration &+= 1

        guard recordingSession.isStarting || isRecording else {
            return
        }

        let audioURL = recordingSession.cancel()
        recordingVocabularySnapshot = nil
        recordingCorrectionLearningSnapshot = nil
        recordingInputTarget = nil
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }

        isPreparingMicrophone = false
        isRecording = false
        status = .ready
    }

    private static func reconcileInterruptedRecordings(
        _ loadedHistory: [TranscriptItem],
        settings: AppSettings,
        localizer: AppLocalizer,
        excludedRecordingIDs: Set<UUID>
    ) -> [TranscriptItem] {
        guard !AppRuntime.isRunningUnderXCTest else {
            return loadedHistory
        }

        var reconciled = loadedHistory
        var changed = false
        for index in reconciled.indices where reconciled[index].outcome == .processing {
            reconciled[index].outcome = .cancelled
            reconciled[index].errorSummary = localizer.recoveredInterruptedRecording()
            changed = true
        }

        let referencedFileNames = Set(reconciled.compactMap(\.audioFileName))
        guard let unreferenced = try? TranscriptAudioStore().unreferencedRecordings(
            referencedFileNames: referencedFileNames
        ), !unreferenced.isEmpty else {
            return changed
                ? reconciled.sorted { $0.createdAt > $1.createdAt }
                : loadedHistory
        }

        var usedIDs = Set(reconciled.map(\.id))
        let selectedLanguages = TranscriptionLanguage.allCases.filter(
            settings.selectedTranscriptionLanguages.contains
        )
        for recording in unreferenced {
            let stem = URL(fileURLWithPath: recording.fileName)
                .deletingPathExtension()
                .lastPathComponent
            let parsedID = UUID(uuidString: stem)
            if let parsedID, excludedRecordingIDs.contains(parsedID) {
                continue
            }
            let recoveredID = parsedID.flatMap { usedIDs.contains($0) ? nil : $0 }
                ?? UUID()
            usedIDs.insert(recoveredID)
            reconciled.append(TranscriptItem(
                id: recoveredID,
                text: "",
                createdAt: recording.createdAt,
                provider: settings.provider,
                model: settings.effectiveModel,
                languageHint: settings.languageHint,
                selectedTranscriptionLanguages: selectedLanguages,
                audioFileName: recording.fileName,
                outcome: .cancelled,
                errorSummary: localizer.recoveredInterruptedRecording()
            ))
            changed = true
        }

        return changed
            ? reconciled.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
            : loadedHistory
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    nonisolated private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    nonisolated static func summarizedErrorMessage(_ message: String, maxLength: Int = 160) -> String {
        let compactMessage = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard maxLength > 3,
              compactMessage.count > maxLength else {
            return compactMessage
        }

        let endIndex = compactMessage.index(compactMessage.startIndex, offsetBy: maxLength - 3)
        return String(compactMessage[..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func localizedErrorMessage(_ error: Error) -> String {
        switch error {
        case AudioRecorderError.microphonePermissionDenied:
            return localizer.microphonePermissionDenied()
        case AudioRecorderError.failedToStart:
            return localizer.recordingCouldNotStart()
        case AudioRecorderError.inputDidNotBecomeReady:
            return localizer.audioInputDidNotBecomeReady()
        case OpenAITranscriptionError.missingAPIKey:
            return localizer.missingOpenAIAPIKey()
        case OpenAITranscriptionError.invalidBaseURL(let baseURL):
            return localizer.invalidOpenAIBaseURL(baseURL)
        case OpenAITranscriptionError.requestFailed(let statusCode, let message):
            return localizer.openAIRequestFailed(statusCode: statusCode, message: message)
        case LocalWhisperTranscriptionError.missingExecutable:
            return localizer.missingLocalWhisperExecutable()
        case LocalWhisperTranscriptionError.executableNotFound(let path):
            return localizer.localWhisperExecutableNotFound(path)
        case LocalWhisperTranscriptionError.missingModel:
            return localizer.missingLocalWhisperModel()
        case LocalWhisperTranscriptionError.modelNotFound(let path):
            return localizer.localWhisperModelNotFound(path)
        case LocalWhisperTranscriptionError.unsupportedModel(let path):
            return localizer.unsupportedLocalModel(path)
        case LocalWhisperTranscriptionError.processFailed(let statusCode, let output):
            return localizer.localWhisperFailed(statusCode: statusCode, output: output)
        case LocalWhisperTranscriptionError.processTimedOut(let timeout):
            return localizer.localWhisperTimedOut(timeout)
        case LocalSenseVoiceTranscriptionError.missingExecutable:
            return localizer.missingSenseVoiceRuntime()
        case LocalSenseVoiceTranscriptionError.missingVADAsset:
            return localizer.missingSenseVoiceVADAsset()
        case LocalSenseVoiceTranscriptionError.processFailed(let statusCode, let output):
            return localizer.senseVoiceFailed(statusCode: statusCode, output: output)
        case LocalSenseVoiceTranscriptionError.processTimedOut(let timeout):
            return localizer.senseVoiceTimedOut(timeout)
        case LocalWhisperAssetInstallerError.homebrewNotFound:
            return localizer.localWhisperHomebrewNotFound()
        case LocalWhisperAssetInstallerError.processFailed(let command, let statusCode, let output):
            return localizer.localWhisperSetupProcessFailed(
                command: command,
                statusCode: statusCode,
                output: output
            )
        case LocalWhisperAssetInstallerError.installedExecutableNotFound(let output):
            return localizer.localWhisperInstalledExecutableNotFound(output)
        case LocalWhisperAssetInstallerError.invalidDownloadResponse(let message):
            return localizer.localWhisperDownloadFailed(message)
        case LocalWhisperAssetInstallerError.insufficientDiskSpace(let requiredBytes, let availableBytes):
            return localizer.localWhisperInsufficientDiskSpace(
                requiredBytes: requiredBytes,
                availableBytes: availableBytes
            )
        case VoiceEditLLMError.missingAPIKey:
            return localizer.missingOpenAIAPIKey()
        case VoiceEditLLMError.invalidBaseURL(let baseURL):
            return localizer.invalidOpenAIBaseURL(baseURL)
        case VoiceEditLLMError.requestFailed(let statusCode, let message):
            return localizer.voiceEditLLMFailed(statusCode: statusCode, message: message)
        case VoiceEditLLMError.emptyResponse:
            return localizer.voiceEditLLMEmptyResponse()
        default:
            return error.localizedDescription
        }
    }
}
