import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DiagnosticsPrivacyPolicy {
    static func redactedPath(
        _ url: URL,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let path = url.standardizedFileURL.path
        let homePath = homeDirectoryURL.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedHomePath = homePath.isEmpty ? "/" : "/\(homePath)"

        guard normalizedHomePath != "/" else {
            return path
        }
        if path == normalizedHomePath {
            return "~"
        }
        guard path.hasPrefix(normalizedHomePath + "/") else {
            return path
        }
        return "~" + path.dropFirst(normalizedHomePath.count)
    }

    static func audioInputSelection(deviceID: String) -> String {
        let trimmedID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty || trimmedID == AudioInputDeviceCatalog.automaticDeviceID
            ? "Automatic"
            : "Custom (identifier omitted)"
    }
}

struct AboutView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var informationPage: AboutInformationPage?
    @State private var isPresentingFeedbackComposer = false
    @State private var highlightedSearchTarget: SettingsSearchTarget?
    @State private var highlightedSearchRequestID: UUID?

    private let websiteURL = URL(string: "https://stcheng.github.io/shuo/")!
    private let feedbackEmailAddress = "contact@bo-rista.com"
    private let sourceCodeURL = URL(string: "https://github.com/stcheng/shuo")!

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    private var appSupportDirectoryURL: URL {
        AppStoragePaths.applicationSupportDirectory()
    }

    private var crashReportsDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("CrashReports", isDirectory: true)
    }

    private var recordingsDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("Recordings", isDirectory: true)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private var bundleIdentifier: String {
        AppBuildIdentity.bundleIdentifier
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section(localizer.text(.appInformation)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(AppBuildIdentity.displayName)
                            .font(.largeTitle.weight(.semibold))

                        Text("说")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(localizer.text(.aboutDescription))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                LabeledContent(localizer.text(.version), value: appVersion)
                LabeledContent(localizer.text(.build), value: buildNumber)
                LabeledContent(localizer.text(.bundleIdentifier), value: bundleIdentifier)
                LabeledContent(localizer.sourceCodeLabel()) {
                    Link("GitHub ↗", destination: sourceCodeURL)
                }
            }
            .settingsSearchAnchor(.aboutInformation, highlightedTarget: highlightedSearchTarget)

            permissionsSection

            Section(localizer.text(.support)) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Button {
                            NSWorkspace.shared.open(websiteURL)
                        } label: {
                            Label(localizer.text(.openWebsite), systemImage: "safari")
                        }

                        Button {
                            isPresentingFeedbackComposer = true
                        } label: {
                            Label(localizer.text(.reportFeedback), systemImage: "exclamationmark.bubble")
                        }
                        .settingsSearchAnchor(.reportFeedback, highlightedTarget: highlightedSearchTarget)

                        Button {
                            appState.copy(diagnosticsText)
                        } label: {
                            Label(localizer.text(.copyDiagnostics), systemImage: "doc.on.doc")
                        }
                    }

                    SettingsRowFeedback(text: localizer.text(.aboutDiagnosticsHint))
                }
            }

            Section(localizer.aboutResourcesLabel()) {
                HStack(spacing: 10) {
                    Button {
                        informationPage = .privacy
                    } label: {
                        Label(localizer.privacyLabel(), systemImage: "hand.raised")
                    }
                    .settingsSearchAnchor(.privacy, highlightedTarget: highlightedSearchTarget)

                    Button {
                        informationPage = .releaseNotes
                    } label: {
                        Label(localizer.releaseNotesLabel(), systemImage: "doc.text")
                    }
                    .settingsSearchAnchor(.releaseNotes, highlightedTarget: highlightedSearchTarget)

                    Button {
                        informationPage = .uninstallAndData
                    } label: {
                        Label(localizer.uninstallAndDataLabel(), systemImage: "externaldrive.badge.minus")
                    }
                    .settingsSearchAnchor(.uninstallAndData, highlightedTarget: highlightedSearchTarget)

                    Button {
                        appState.showOnboarding()
                    } label: {
                        Label(localizer.showWelcomeLabel(), systemImage: "sparkles")
                    }

                }
            }

            Section(localizer.text(.dataManagement)) {
                VStack(alignment: .leading, spacing: 7) {
                    Button {
                        exportSettings()
                    } label: {
                        Label(localizer.text(.exportSettings), systemImage: "square.and.arrow.up")
                    }

                    SettingsRowFeedback(text: localizer.text(.exportSettingsHint))
                }
            }
            .settingsSearchAnchor(.exportSettings, highlightedTarget: highlightedSearchTarget)

            Section(localizer.text(.localData)) {
                PathRow(title: localizer.text(.applicationSupportFolder), path: appSupportDirectoryURL.path)
                PathRow(title: localizer.recordingsFolderLabel(), path: recordingsDirectoryURL.path)
                PathRow(title: localizer.text(.crashReportsFolder), path: crashReportsDirectoryURL.path)

                HStack(spacing: 10) {
                    Button {
                        openDirectory(appSupportDirectoryURL)
                    } label: {
                        Label(localizer.text(.openDataFolder), systemImage: "folder")
                    }

                    Button {
                        openDirectory(recordingsDirectoryURL)
                    } label: {
                        Label(localizer.openRecordingsFolderLabel(), systemImage: "waveform")
                    }

                    Button {
                        openDirectory(crashReportsDirectoryURL)
                    } label: {
                        Label(localizer.text(.openCrashReportsFolder), systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .settingsSearchAnchor(.localData, highlightedTarget: highlightedSearchTarget)
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: appState.settingsNavigationRequest?.id) {
                await handleSettingsNavigation(using: proxy)
            }
        }
        .sheet(item: $informationPage) { page in
            AboutInformationSheet(
                page: page,
                localizer: localizer,
                appSupportDirectoryURL: appSupportDirectoryURL,
                clearAPIKey: appState.clearCloudAPIKeys,
                openDataFolder: { openDirectory(appSupportDirectoryURL) }
            )
        }
        .sheet(isPresented: $isPresentingFeedbackComposer) {
            FeedbackComposerSheet(
                localizer: localizer,
                diagnosticsText: diagnosticsText,
                recipient: feedbackEmailAddress,
                copy: { appState.copy($0) }
            )
        }
        .onAppear {
            appState.refreshSystemPermissions()
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        Section(localizer.permissionsLabel()) {
            permissionRow(
                localizer.onboardingMicrophoneLabel(),
                granted: appState.microphonePermissionGranted,
                request: appState.requestMicrophonePermission,
                manage: appState.openMicrophoneSettings
            )
            .settingsSearchAnchor(.microphonePermission, highlightedTarget: highlightedSearchTarget)

            permissionRow(
                localizer.onboardingAccessibilityLabel(),
                granted: appState.accessibilityPermissionGranted,
                request: appState.requestAccessibilityPermission,
                manage: appState.openAccessibilitySettings
            )
            .settingsSearchAnchor(.accessibilityPermission, highlightedTarget: highlightedSearchTarget)
        }
    }

    private func permissionRow(
        _ title: String,
        granted: Bool,
        request: @escaping () -> Void,
        manage: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .accessibilityHidden(true)

            Text(title)

            Spacer(minLength: 12)

            if granted {
                Text(localizer.permissionGrantedLabel())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(granted ? localizer.managePermissionLabel() : localizer.onboardingAllowLabel()) {
                if granted {
                    manage()
                } else {
                    request()
                }
            }
            .controlSize(.small)
        }
    }

    @MainActor
    private func handleSettingsNavigation(using proxy: ScrollViewProxy) async {
        guard let request = appState.settingsNavigationRequest else {
            return
        }

        let isCurrentAboutRequest = request.section == .about
        let isLegacySystemRequest = request.section == .advanced
            && request.target == .exportSettings
        guard isCurrentAboutRequest || isLegacySystemRequest else {
            return
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

        switch request.target {
        case .privacy:
            informationPage = .privacy
        case .releaseNotes:
            informationPage = .releaseNotes
        case .uninstallAndData:
            informationPage = .uninstallAndData
        default:
            break
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

    private var diagnosticsText: String {
        [
            "\(AppBuildIdentity.displayName) Diagnostics",
            "Version: \(appVersion)",
            "Build: \(buildNumber)",
            "Bundle Identifier: \(bundleIdentifier)",
            "OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Provider: \(appState.settings.provider.rawValue)",
            "Model: \(appState.settings.effectiveModel)",
            "Language Hint: \(appState.settings.languageHint.rawValue)",
            "Audio Input: \(DiagnosticsPrivacyPolicy.audioInputSelection(deviceID: appState.settings.audioInputDeviceID))",
            "History Count: \(appState.history.count)",
            "Application Support: \(DiagnosticsPrivacyPolicy.redactedPath(appSupportDirectoryURL))",
            "Crash Reports: \(DiagnosticsPrivacyPolicy.redactedPath(crashReportsDirectoryURL))"
        ].joined(separator: "\n")
    }

    private func openDirectory(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
            appState.clearError()
        } catch {
            appState.reportError(error)
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.title = localizer.text(.exportSettings)
        panel.nameFieldStringValue = "shuo-settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try appState.exportSettings(to: url)
        } catch {
            appState.reportError(error)
        }
    }
}

private struct FeedbackComposerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let localizer: AppLocalizer
    let diagnosticsText: String
    let recipient: String
    let copy: (String) -> Void

    @State private var message = ""
    @State private var includeDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(localizer.feedbackComposerTitle(), systemImage: "exclamationmark.bubble")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(localizer.closeLabel()) {
                    dismiss()
                }
            }

            Text(localizer.feedbackComposerPrompt())
                .foregroundStyle(.secondary)

            TextEditor(text: $message)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 150)
                .accessibilityLabel(localizer.feedbackComposerPrompt())

            Toggle(localizer.feedbackIncludeDiagnosticsLabel(), isOn: $includeDiagnostics)

            Text(localizer.feedbackComposerPrivacyHint())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(recipient)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(localizer.cancelLabel()) {
                    dismiss()
                }
                Button(localizer.feedbackSendEmailLabel()) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func submit() {
        let report = [
            message.trimmingCharacters(in: .whitespacesAndNewlines),
            includeDiagnostics ? "---\n\(diagnosticsText)" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
        copy(report)

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: localizer.feedbackEmailSubject()),
            URLQueryItem(name: "body", value: report)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}

private enum AboutInformationPage: String, Identifiable {
    case privacy
    case releaseNotes
    case uninstallAndData

    var id: String { rawValue }
}

private struct AboutInformationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let page: AboutInformationPage
    let localizer: AppLocalizer
    let appSupportDirectoryURL: URL
    let clearAPIKey: () -> Void
    let openDataFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(localizer.closeLabel()) {
                    dismiss()
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(bodyText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if page == .uninstallAndData {
                        Text(appSupportDirectoryURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        HStack {
                            Button(localizer.text(.openDataFolder), action: openDataFolder)
                            Button(localizer.clearAPIKeyLabel(), role: .destructive, action: clearAPIKey)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 620, height: 430)
    }

    private var title: String {
        switch page {
        case .privacy:
            return localizer.privacyLabel()
        case .releaseNotes:
            return localizer.releaseNotesLabel()
        case .uninstallAndData:
            return localizer.uninstallAndDataLabel()
        }
    }

    private var systemImage: String {
        switch page {
        case .privacy:
            return "hand.raised"
        case .releaseNotes:
            return "doc.text"
        case .uninstallAndData:
            return "externaldrive.badge.minus"
        }
    }

    private var bodyText: String {
        switch page {
        case .privacy:
            return localizer.privacyDetail()
        case .releaseNotes:
            return localizer.releaseNotesDetail()
        case .uninstallAndData:
            return localizer.uninstallAndDataDetail()
        }
    }
}

private struct PathRow: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body)

            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

#Preview {
    AboutView()
        .environmentObject(AppState())
}
