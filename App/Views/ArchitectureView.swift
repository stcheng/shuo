import Foundation
import SwiftUI

struct ArchitectureDestination: Equatable {
    let section: AppPanelSection
    let target: SettingsSearchTarget?
}

enum ArchitectureLayout {
    static let nodeWidth: CGFloat = 84
    static let connectorWidth: CGFloat = 20
    static let horizontalPadding: CGFloat = 18
    static let overviewNodeHeight: CGFloat = 118
    static let compactNodeHeight: CGFloat = 52
    static let overviewNavigationHeight: CGFloat = 150
    static let compactNavigationHeight: CGFloat = 66
    static let contentFadeDuration: TimeInterval = 0.14

    static var minimumSignalChainWidth: CGFloat {
        nodeWidth * CGFloat(ArchitectureStage.allCases.count)
            + connectorWidth * CGFloat(ArchitectureStage.allCases.count - 1)
            + horizontalPadding * 2
    }
}

struct ArchitectureNavigationState: Equatable {
    private(set) var selectedStage: ArchitectureStage?

    init(selectedStage: ArchitectureStage? = nil) {
        self.selectedStage = selectedStage
    }

    var usesCompactNavigation: Bool {
        selectedStage != nil
    }

    mutating func toggle(_ stage: ArchitectureStage) {
        selectedStage = selectedStage == stage ? nil : stage
    }

    mutating func open(_ stage: ArchitectureStage) {
        selectedStage = stage
    }

    mutating func showOverview() {
        selectedStage = nil
    }
}

typealias ArchitectureStage = SettingsPipelineStage

extension SettingsPipelineStage {
    var systemImage: String {
        switch self {
        case .voiceInput:
            return "waveform"
        case .audioProcessing:
            return "slider.horizontal.3"
        case .contextPreparation:
            return "text.badge.plus"
        case .aiInference:
            return "cpu"
        case .postProcessing:
            return "wand.and.stars"
        case .humanCorrection:
            return "pencil.and.outline"
        case .finalResult:
            return "text.line.last.and.arrowtriangle.forward"
        }
    }

    func destination(pluginConfiguration _: PluginConfiguration) -> ArchitectureDestination {
        switch self {
        case .voiceInput:
            return ArchitectureDestination(section: .architecture, target: .inputShortcut)
        case .audioProcessing:
            return ArchitectureDestination(section: .architecture, target: .whisperMode)
        case .contextPreparation:
            return ArchitectureDestination(section: .architecture, target: .manualTerms)
        case .aiInference:
            return ArchitectureDestination(section: .architecture, target: .transcriptionProvider)
        case .postProcessing:
            return ArchitectureDestination(section: .architecture, target: .featureTextCleanup)
        case .humanCorrection:
            return ArchitectureDestination(section: .architecture, target: .featureFloatingWindow)
        case .finalResult:
            return ArchitectureDestination(section: .architecture, target: nil)
        }
    }
}

struct ArchitectureView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationState = ArchitectureNavigationState()
    @State private var hoveredStage: ArchitectureStage?
    @FocusState private var focusedStage: ArchitectureStage?

    private let stages = ArchitectureStage.allCases

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    private var inspectedStage: ArchitectureStage? {
        hoveredStage ?? navigationState.selectedStage
    }

    private var settingsMetadataPresentation: SettingsPipelineMetadataPresentation {
        SettingsPipelineMetadataPresentation(
            isEnabled: true,
            commonLabel: localizer.commonSettingLabel(),
            advancedLabel: localizer.advancedSettingLabel()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    signalChain(isCompact: navigationState.usesCompactNavigation)
                        .padding(.horizontal, ArchitectureLayout.horizontalPadding)
                        .frame(
                            minWidth: max(
                                ArchitectureLayout.minimumSignalChainWidth,
                                geometry.size.width
                            ),
                            minHeight: geometry.size.height,
                            alignment: .center
                        )
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            .frame(
                height: navigationState.usesCompactNavigation
                    ? ArchitectureLayout.compactNavigationHeight
                    : ArchitectureLayout.overviewNavigationHeight
            )
            .background(Color(nsColor: .windowBackgroundColor))
            .zIndex(1)

            Divider()

            ZStack(alignment: .topLeading) {
                selectedContent
                    .id(contentIdentity)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: ArchitectureLayout.contentFadeDuration),
                value: contentIdentity
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: ArchitectureLayout.contentFadeDuration),
            value: navigationState.usesCompactNavigation
        )
        .task(id: appState.settingsNavigationRequest?.id) {
            await handleSearchNavigation()
        }
    }

    private var contentIdentity: String {
        navigationState.selectedStage?.rawValue ?? "advanced-overview"
    }

    private func signalChain(isCompact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                Button {
                    toggle(stage)
                } label: {
                    ArchitectureStageNode(
                        number: index + 1,
                        title: localizer.architectureStageTitle(stage),
                        systemImage: stage.systemImage,
                        isActive: navigationState.selectedStage == stage
                            || inspectedStage == stage,
                        isCompact: isCompact
                    )
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focusedStage, equals: stage)
                .onHover { isHovering in
                    updateHover(stage, isHovering: isHovering)
                }
                .help(localizer.architectureStageDetail(stage))
                .accessibilityLabel(localizer.architectureStageTitle(stage))
                .accessibilityValue(localizer.architectureStageDetail(stage))
                .accessibilityAddTraits(
                    navigationState.selectedStage == stage ? .isSelected : []
                )
                .accessibilityHint(
                    navigationState.selectedStage == stage
                        ? localizer.architectureReturnToOverviewHint()
                        : localizer.architectureOpenDestinationHint(
                            localizer.architectureStageTitle(stage)
                        )
                )

                if index < stages.count - 1 {
                    ArchitectureSignalConnector(
                        isActive: navigationState.selectedStage == stage
                            || navigationState.selectedStage == stages[index + 1]
                            || inspectedStage == stage
                            || inspectedStage == stages[index + 1],
                        reduceMotion: reduceMotion
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.architectureLabel())
    }

    @ViewBuilder
    private func selectedStageSettings(_ stage: ArchitectureStage) -> some View {
        switch stage {
        case .voiceInput:
            SettingsView(category: .architectureVoiceInput)
        case .audioProcessing:
            SettingsView(category: .architectureAudioProcessing)
        case .contextPreparation:
            VocabularyView(
                controller: appState.projectVocabularyController,
                presentation: .architecture
            )
        case .aiInference:
            SettingsView(category: .architectureAIInference)
        case .postProcessing:
            PostProcessingView(
                presentation: .architectureProcessing,
                navigationSection: .architecture
            )
        case .humanCorrection:
            SettingsView(category: .architectureHumanCorrection)
        case .finalResult:
            ArchitectureFinalResultView()
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        if let selectedStage = navigationState.selectedStage {
            selectedStageSettings(selectedStage)
                .settingsPipelineMetadata(settingsMetadataPresentation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            AdvancedOverviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func updateHover(_ stage: ArchitectureStage, isHovering: Bool) {
        let update = {
            if isHovering {
                hoveredStage = stage
            } else if hoveredStage == stage {
                hoveredStage = nil
            }
        }

        if reduceMotion {
            update()
        } else {
            withAnimation(.easeOut(duration: 0.14), update)
        }
    }

    private func toggle(_ stage: ArchitectureStage) {
        let update = {
            navigationState.toggle(stage)
            if navigationState.selectedStage == nil {
                hoveredStage = nil
            }
        }

        if reduceMotion {
            update()
        } else {
            withAnimation(
                .easeOut(duration: ArchitectureLayout.contentFadeDuration),
                update
            )
        }
    }

    private func open(_ stage: ArchitectureStage) {
        let update = {
            navigationState.open(stage)
        }

        if reduceMotion {
            update()
        } else {
            withAnimation(
                .easeOut(duration: ArchitectureLayout.contentFadeDuration),
                update
            )
        }
    }

    private func showOverview() {
        let update = {
            navigationState.showOverview()
            focusedStage = nil
            hoveredStage = nil
        }

        if reduceMotion {
            update()
        } else {
            withAnimation(
                .easeOut(duration: ArchitectureLayout.contentFadeDuration),
                update
            )
        }
    }

    @MainActor
    private func handleSearchNavigation() async {
        guard let request = appState.settingsNavigationRequest,
              request.section == .architecture else {
            return
        }

        if request.target != .architectureOverview,
           let placement = request.target.pipelinePlacement {
            open(placement.stage)
            return
        }

        guard request.target == .architectureOverview else {
            return
        }

        showOverview()
        appState.consumeSettingsNavigationRequest(id: request.id)
    }
}

private struct AdvancedOverviewView: View {
    @EnvironmentObject private var appState: AppState

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localizer.advancedOverviewTitle())
                        .font(.title2.weight(.semibold))

                    Text(localizer.advancedOverviewDetail())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label {
                        Text(localizer.architecturePathVariationHint())
                    } icon: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                }
                .frame(maxWidth: 520, alignment: .leading)

                SettingsSearchView()
                    .padding(.top, 28)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ArchitectureFinalResultView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var signalArrived = false

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                FinalResultArrivalGraphic(signalArrived: signalArrived)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text(localizer.finalResultCongratulationsTitle())
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(localizer.finalResultCongratulationsDetail())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 520)

                VStack(spacing: 0) {
                    destinationRow(
                        title: localizer.text(.history),
                        systemImage: "clock.arrow.circlepath",
                        count: appState.history.count
                    ) {
                        appState.selectedPanelSection = .history
                    }

                    Divider()
                        .padding(.leading, 46)

                    destinationRow(
                        title: localizer.metricsLabel(),
                        systemImage: "chart.bar.xaxis",
                        count: appState.metricsCountersForDisplay.successfulTranscriptions
                    ) {
                        appState.selectedPanelSection = .metrics
                    }
                }
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.17), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 28)
        }
        .task {
            await Task.yield()
            if reduceMotion {
                signalArrived = true
            } else {
                withAnimation(.easeInOut(duration: 0.52)) {
                    signalArrived = true
                }
            }
        }
    }

    private func destinationRow(
        title: String,
        systemImage: String,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 16)

                Text(count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FinalResultArrivalGraphic: View {
    let signalArrived: Bool

    private let particleOffsets: [CGSize] = [
        CGSize(width: 10, height: -23),
        CGSize(width: 23, height: -11),
        CGSize(width: 25, height: 12),
        CGSize(width: 8, height: 25),
        CGSize(width: -8, height: -26)
    ]

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 120, height: 1.5)

            Capsule()
                .fill(Color.accentColor.opacity(0.8))
                .frame(width: 120, height: 1.5)
                .scaleEffect(x: signalArrived ? 1 : 0, y: 1, anchor: .leading)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.accentColor.opacity(0.2), radius: 6)
                .scaleEffect(signalArrived ? 1 : 0.72)
                .offset(x: signalArrived ? 60 : -60)

            ForEach(Array(particleOffsets.enumerated()), id: \.offset) { index, offset in
                Group {
                    if index.isMultiple(of: 2) {
                        Circle()
                            .frame(width: 3, height: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 1)
                            .frame(width: 2.5, height: 6)
                            .rotationEffect(.degrees(Double(index) * 29))
                    }
                }
                .foregroundStyle(Color.accentColor.opacity(0.55))
                .scaleEffect(signalArrived ? 1 : 0.2)
                .opacity(signalArrived ? 1 : 0)
                .offset(
                    x: signalArrived ? 60 + offset.width : 60,
                    y: signalArrived ? offset.height : 0
                )
            }
        }
        .frame(width: 190, height: 64)
    }
}

private struct ArchitectureStageNode: View {
    let number: Int
    let title: String
    let systemImage: String
    let isActive: Bool
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                VStack(spacing: 4) {
                    HStack(spacing: 5) {
                        Text(String(format: "%02d", number))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(
                                isActive ? Color.accentColor : Color.secondary.opacity(0.62)
                            )

                        Spacer(minLength: 0)

                        Circle()
                            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.32))
                            .frame(width: 3, height: 3)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                        Text(title)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            } else {
                VStack(spacing: 9) {
                    HStack {
                        Text(String(format: "%02d", number))
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(
                                isActive ? Color.accentColor : Color.secondary.opacity(0.62)
                            )

                        Spacer(minLength: 0)

                        Circle()
                            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.32))
                            .frame(width: 4, height: 4)
                    }

                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        .frame(height: 24)

                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                        .frame(maxWidth: .infinity, minHeight: 31, alignment: .top)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
            }
        }
        .frame(
            width: ArchitectureLayout.nodeWidth,
            height: isCompact
                ? ArchitectureLayout.compactNodeHeight
                : ArchitectureLayout.overviewNodeHeight
        )
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 11, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.075) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 11, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.78) : Color.secondary.opacity(0.28),
                    lineWidth: isActive ? 1.35 : 1
                )
        )
        .contentShape(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 11, style: .continuous)
        )
    }
}

private struct ArchitectureSignalConnector: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 2) {
            Rectangle()
                .frame(width: 3, height: 1)

            Circle()
                .frame(width: 2, height: 2)

            Rectangle()
                .frame(width: 3, height: 1)

            Image(systemName: "chevron.right")
                .font(.system(size: 6, weight: .bold))
        }
        .foregroundStyle(isActive ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.34))
        .frame(width: ArchitectureLayout.connectorWidth)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isActive)
        .accessibilityHidden(true)
    }
}
