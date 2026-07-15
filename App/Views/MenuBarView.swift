import AppKit
import SwiftUI

struct MenuBarDraftEditorMeasurement: Equatable {
    let height: CGFloat
    let showsScrollIndicator: Bool
}

enum MenuBarDraftEditorLayout {
    private static var font: NSFont {
        NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }
    private static let textWidth: CGFloat = 236
    private static let verticalChrome: CGFloat = 14
    private static let minimumHeight: CGFloat = 38
    private static let maximumHeight: CGFloat = 92

    static func measurement(for text: String) -> MenuBarDraftEditorMeasurement {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let desiredHeight = ceil(max(lineHeight, bounds.height) + verticalChrome)
        return MenuBarDraftEditorMeasurement(
            height: min(maximumHeight, max(minimumHeight, desiredHeight)),
            showsScrollIndicator: desiredHeight > maximumHeight
        )
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    let openSection: (AppPanelSection) -> Void
    let showErrorDetails: (String) -> Void

    init(
        openSection: @escaping (AppPanelSection) -> Void = { _ in },
        showErrorDetails: @escaping (String) -> Void = { _ in }
    ) {
        self.openSection = openSection
        self.showErrorDetails = showErrorDetails
    }

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            menuContent
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.vertical) {
                menuContent
                    .fixedSize(horizontal: false, vertical: true)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 280)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            quickToggleRow(
                title: localizer.text(.dictation),
                systemImage: appState.settings.pushToTalkEnabled ? "mic.fill" : "mic.slash",
                isOn: Binding(
                    get: { appState.settings.pushToTalkEnabled },
                    set: { appState.setPushToTalkEnabled($0) }
                )
            )

            quickToggleRow(
                title: localizer.text(.whisperMode),
                systemImage: appState.settings.whisperModeEnabled ? "mouth.fill" : "mouth",
                isOn: $appState.settings.whisperModeEnabled
            )
            .help(localizer.text(.whisperModeHint))

            quickToggleRow(
                title: localizer.floatingWindowLabel(),
                systemImage: "rectangle.and.pencil.and.ellipsis",
                isOn: Binding(
                    get: { appState.isPluginEnabled(.smartCorrectionWindow) },
                    set: { appState.setPluginEnabled(.smartCorrectionWindow, isEnabled: $0) }
                )
            )
            .help(localizer.floatingWindowDetail())

            if !appState.currentDraft.isEmpty {
                Divider()
                draftEditor
            }

            Divider()

            MenuActionRow(
                title: AppPanelSection.transcription.sidebarTitle(localizer: localizer),
                systemImage: AppPanelSection.transcription.systemImage
            ) {
                openSection(.transcription)
            }

            MenuActionRow(title: localizer.text(.history), systemImage: "clock.arrow.circlepath") {
                openSection(.history)
            }

            Divider()

            MenuActionRow(title: localizer.openShuoLabel(), systemImage: "house") {
                openSection(.general)
            }

            MenuActionRow(title: localizer.quitShuoLabel(), systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 280)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(AppBuildIdentity.displayName)
                    .font(.headline)
                Spacer()
                Text(operationalStatusText)
                    .font(.caption)
                    .foregroundStyle(operationalStatusColor)

                if appState.isCheckingAudio || appState.isTranscribing {
                    Button(localizer.cancelTranscriptionLabel()) {
                        appState.cancelCurrentTranscription()
                    }
                    .controlSize(.mini)
                }
            }

            if let errorMessage = appState.errorMessage,
               let errorSummary = appState.errorSummaryMessage {
                errorBanner(summary: errorSummary, details: errorMessage)
            } else if let learningNoticeMessage = appState.learningNoticeMessage {
                Label(learningNoticeMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else if shouldShowPushToTalkDetail {
                Text(appState.pushToTalkStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !appState.canPasteIntoFocusedApp {
                Text(localizer.text(.accessibilityPermissionMayBeNeeded))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var operationalStatusText: String {
        if appState.isPreparingMicrophone
            || appState.isRecording
            || appState.isCheckingAudio
            || appState.isTranscribing {
            return appState.statusMessage
        }
        if !appState.settings.pushToTalkEnabled {
            return localizer.dictationOffStatusLabel()
        }
        if !appState.isPushToTalkRunning {
            return localizer.setupNeededStatusLabel()
        }
        return appState.statusMessage
    }

    private var operationalStatusColor: Color {
        if appState.isRecording {
            return .red
        }
        if appState.settings.pushToTalkEnabled, !appState.isPushToTalkRunning {
            return .orange
        }
        return .secondary
    }

    private var shouldShowPushToTalkDetail: Bool {
        appState.settings.pushToTalkEnabled
            && !appState.isPushToTalkRunning
            && !appState.pushToTalkStatusMessage.isEmpty
    }

    private func quickToggleRow(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18, alignment: .center)
                    .accessibilityHidden(true)

                Text(title)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.body)
        .padding(.horizontal, 5)
        .frame(height: 24)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }

    private func errorBanner(summary: String, details: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.text(.lastError))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 7) {
                Button {
                    showErrorDetails(details)
                } label: {
                    Label(localizer.text(.details), systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    appState.copy(details)
                } label: {
                    Label(localizer.text(.copy), systemImage: "doc.on.doc")
                }

                Spacer(minLength: 0)

                Button {
                    appState.clearError()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help(localizer.text(.clear))
                .accessibilityLabel(localizer.text(.clear))
            }
            .font(.caption)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var draftEditor: some View {
        let measurement = MenuBarDraftEditorLayout.measurement(
            for: appState.currentDraft
        )

        return VStack(alignment: .leading, spacing: 5) {
            Text(localizer.text(.latestTranscript))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $appState.currentDraft)
                .font(.body)
                .accessibilityLabel(localizer.text(.latestTranscript))
                .scrollContentBackground(.hidden)
                .scrollIndicators(
                    measurement.showsScrollIndicator ? .visible : .hidden
                )
                .frame(height: measurement.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack(spacing: 8) {
                Button {
                    appState.copyCurrentDraft()
                } label: {
                    Label(localizer.compactCopyLabel(), systemImage: "doc.on.doc")
                }

                Button {
                    appState.replacePreviousInsertionWithCurrentDraft()
                } label: {
                    Label(localizer.compactReplaceLabel(), systemImage: "arrow.left.arrow.right")
                }
                .disabled(!appState.canReplacePreviousInsertion)
                .help(localizer.replacePreviousInsertionHelp())

                Button {
                    appState.toggleLatestTranscriptAudioPlayback()
                } label: {
                    Label(
                        appState.isPlayingLatestTranscriptAudio
                            ? localizer.compactStopLabel()
                            : localizer.compactPlayLabel(),
                        systemImage: appState.isPlayingLatestTranscriptAudio ? "stop.fill" : "play.fill"
                    )
                }
                .disabled(!appState.canPlayLatestTranscriptAudio)
                .help(localizer.text(appState.isPlayingLatestTranscriptAudio ? .stopAudio : .playAudio))

                Button {
                    appState.retranscribeLatestTranscriptAudio()
                } label: {
                    Label(localizer.compactRetranscribeLabel(), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!appState.canRetranscribeLatestTranscriptAudio)
                .help(localizer.text(.retranscribeAudio))

                Spacer()
            }
            .controlSize(.small)
        }
    }

}

private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var trailingText: String? = nil
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var isHighlighted: Bool {
        isEnabled && (isHovered || isFocused)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18, alignment: .center)
                Text(title)
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .foregroundStyle(
                            isHighlighted
                                ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.8)
                                : Color.secondary
                        )
                        .monospacedDigit()
                }
            }
            .font(.body)
            .padding(.horizontal, 5)
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .foregroundStyle(
                isHighlighted
                    ? Color(nsColor: .selectedMenuItemTextColor)
                    : Color.primary
            )
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isHighlighted
                            ? Color(nsColor: .selectedContentBackgroundColor)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityLabel(accessibilityTitle)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            isHovered = hovering && isEnabled
        }
    }

    private var accessibilityTitle: String {
        guard let trailingText else {
            return title
        }
        return "\(title), \(trailingText)"
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
