import AppKit
import SwiftUI

struct VocabularyView: View {
    enum Presentation: Equatable {
        case vocabulary
        case architecture
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var controller: ProjectVocabularyController
    private let presentation: Presentation
    private let navigationSection: AppPanelSection
    @State private var highlightedSearchTarget: SettingsSearchTarget?
    @State private var highlightedSearchRequestID: UUID?

    init(
        controller: ProjectVocabularyController,
        presentation: Presentation = .vocabulary,
        navigationSection: AppPanelSection? = nil
    ) {
        self.controller = controller
        self.presentation = presentation
        self.navigationSection = navigationSection
            ?? (presentation == .architecture ? .architecture : .vocabulary)
    }

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if presentation == .architecture {
                    promptContextSection
                }
                if appState.settings.provider == .alibaba {
                    vocabularyProviderNotice
                }
                vocabularySourcesSection
                projectSourcesSection
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: appState.settings.useDeveloperGlossary
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: controller.state.isProjectVocabularyEnabled
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: appState.isPluginEnabled(.smartPromptContext)
            )
            .task(id: appState.settingsNavigationRequest?.id) {
                await handleSettingsNavigation(using: proxy)
            }
        }
        .onAppear {
            controller.resumePendingIndexes()
        }
    }

    private var vocabularyProviderNotice: some View {
        Section {
            SettingsRowFeedback(text: localizer.alibabaVocabularyUnavailableDetail())
        }
    }

    private var promptContextSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { appState.isPluginEnabled(.smartPromptContext) },
                    set: { appState.setPluginEnabled(.smartPromptContext, isEnabled: $0) }
                )
            ) {
                SettingsRowLabel(
                    title: localizer.enablePromptContextLabel(),
                    detail: localizer.promptContextFeatureDetail()
                )
            }
            .toggleStyle(.switch)
            .settingsSearchAnchor(
                .featurePromptContext,
                highlightedTarget: highlightedSearchTarget
            )

            if appState.isPluginEnabled(.smartPromptContext) {
                SettingsCollection(
                    addLabel: localizer.text(.addPromptContext),
                    addAction: addPromptContext,
                    addSearchTarget: .promptContexts,
                    highlightedSearchTarget: highlightedSearchTarget
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.text(.promptContext),
                target: .featurePromptContext
            )
        }
    }

    private var vocabularySourcesSection: some View {
        Section {
            Toggle(isOn: $appState.settings.useDeveloperGlossary) {
                SettingsRowLabel(
                    title: localizer.text(.useGlossary),
                    detail: localizer.vocabularySourcesDetail()
                )
            }
                .settingsSearchAnchor(.manualTerms, highlightedTarget: highlightedSearchTarget)

            if appState.settings.useDeveloperGlossary {
                SettingsCollection(
                    addLabel: localizer.addVocabularyLabel(),
                    addAction: addNamedVocabulary
                ) {
                    if appState.settings.namedVocabularies.isEmpty {
                        SettingsCollectionEmptyRow(text: localizer.vocabularySourcesEmptyDetail())
                    } else {
                        ForEach(appState.settings.namedVocabularies) { vocabulary in
                            NamedVocabularySourceRow(
                                item: bindingForNamedVocabulary(id: vocabulary.id),
                                localizer: localizer,
                                remove: { removeNamedVocabulary(id: vocabulary.id) }
                            )
                            if vocabulary.id != appState.settings.namedVocabularies.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.manualTermsLabel(),
                target: .manualTerms
            )
        }
    }

    private var projectSourcesSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { controller.state.isProjectVocabularyEnabled },
                    set: { controller.setProjectVocabularyEnabled($0) }
                )
            ) {
                SettingsRowLabel(
                    title: localizer.enableProjectVocabularyLabel(),
                    detail: localizer.projectVocabularyBudgetDetail()
                )
            }
            .settingsSearchAnchor(.projectVocabulary, highlightedTarget: highlightedSearchTarget)

            if controller.state.isProjectVocabularyEnabled {
                SettingsCollection(
                    addLabel: localizer.linkProjectFolderLabel(),
                    addAction: chooseProjectFolders,
                    addSearchTarget: .linkProject,
                    highlightedSearchTarget: highlightedSearchTarget
                ) {
                    if controller.state.projects.isEmpty {
                        SettingsCollectionEmptyRow(text: localizer.projectVocabularyEmptyDetail())
                    } else {
                        ForEach(controller.state.projects) { project in
                            ProjectVocabularySourceRow(
                                project: project,
                                isIndexing: controller.indexingProjectIDs.contains(project.id),
                                localizer: localizer,
                                setEnabled: { controller.setProjectEnabled($0, id: project.id) },
                                setTermEnabled: {
                                    controller.setTermEnabled(
                                        $0,
                                        termID: $1,
                                        projectID: project.id
                                    )
                                },
                                refresh: { controller.refreshProject(id: project.id) },
                                remove: { controller.removeProject(id: project.id) }
                            )
                            if project.id != controller.state.projects.last?.id {
                                Divider()
                            }
                        }
                    }

                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = controller.lastErrorMessage {
                SettingsRowFeedback(text: error, style: .error)
                    .textSelection(.enabled)
            }
        } header: {
            SettingsSectionHeader(
                title: localizer.projectVocabularyBetaLabel(),
                target: .projectVocabulary
            )
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

    private func bindingForNamedVocabulary(id: UUID) -> Binding<NamedVocabularyItem> {
        Binding(
            get: {
                appState.settings.namedVocabularies.first { $0.id == id }
                    ?? NamedVocabularyItem(name: "")
            },
            set: { updatedItem in
                guard let index = appState.settings.namedVocabularies.firstIndex(where: { $0.id == id }) else {
                    return
                }
                appState.settings.namedVocabularies[index] = updatedItem
            }
        )
    }

    private func addNamedVocabulary() {
        let existingNames = Set(
            appState.settings.namedVocabularies.map {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            }
        )
        var number = 1
        while existingNames.contains(
            localizer.newVocabularyName(number)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        ) {
            number += 1
        }
        appState.settings.namedVocabularies.append(
            NamedVocabularyItem(
                name: localizer.newVocabularyName(number),
                terms: "",
                isEnabled: true
            )
        )
    }

    private func removeNamedVocabulary(id: UUID) {
        if let item = appState.settings.namedVocabularies.first(where: { $0.id == id }) {
            appState.settings.deletedTerminologyPresetIDs = TerminologyPresetCatalog
                .deletionTombstones(
                    afterRemoving: item,
                    existing: appState.settings.deletedTerminologyPresetIDs
                )
        }
        appState.settings.namedVocabularies.removeAll { $0.id == id }
    }

    @MainActor
    private func handleSettingsNavigation(using proxy: ScrollViewProxy) async {
        guard let request = appState.settingsNavigationRequest,
              request.section == navigationSection else {
            return
        }

        if presentation == .architecture,
           request.target.pipelinePlacement?.stage != .contextPreparation {
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

    private func chooseProjectFolders() {
        let panel = NSOpenPanel()
        panel.title = localizer.linkProjectFolderLabel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else {
            return
        }

        var linkedAnyProject = false
        for url in panel.urls {
            do {
                try controller.linkProject(at: url)
                linkedAnyProject = true
            } catch {
                appState.reportError(error)
            }
        }
        if linkedAnyProject {
            controller.setProjectVocabularyEnabled(true)
        }
    }
}

private struct ContextSourceModuleRow<ExpandedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let subtitle: String
    let systemImage: String
    let localizer: AppLocalizer
    var isEnabled: Binding<Bool>? = nil
    var isExpandable = false
    @Binding var isExpanded: Bool
    let expandedContent: ExpandedContent

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        localizer: AppLocalizer,
        isEnabled: Binding<Bool>? = nil,
        isExpandable: Bool = false,
        isExpanded: Binding<Bool> = .constant(false),
        @ViewBuilder expandedContent: () -> ExpandedContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.localizer = localizer
        self.isEnabled = isEnabled
        self.isExpandable = isExpandable
        _isExpanded = isExpanded
        self.expandedContent = expandedContent()
    }

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        localizer: AppLocalizer,
        isEnabled: Binding<Bool>? = nil
    ) where ExpandedContent == EmptyView {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            localizer: localizer,
            isEnabled: isEnabled,
            expandedContent: { EmptyView() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let isEnabled {
                    Toggle("", isOn: isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel(title)
                }

                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                if isExpandable {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.13)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        rowLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        isExpanded
                            ? localizer.expandedStateLabel()
                            : localizer.collapsedStateLabel()
                    )
                } else {
                    rowLabel
                }
            }
            .padding(.vertical, 9)

            if isExpandable, isExpanded {
                expandedContent
                    .padding(.bottom, 12)
                    .padding(.leading, isEnabled == nil ? 28 : 58)
                    .transition(.opacity)
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            SettingsRowLabel(title: title, detail: subtitle)
                .lineLimit(2)

            Spacer(minLength: 8)

            if isExpandable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct PromptContextSourceRow: View {
    @Binding var item: PromptContextItem
    let localizer: AppLocalizer
    let remove: () -> Void
    @State private var isExpanded: Bool
    @State private var isConfirmingRemoval = false

    init(
        item: Binding<PromptContextItem>,
        localizer: AppLocalizer,
        remove: @escaping () -> Void
    ) {
        _item = item
        self.localizer = localizer
        self.remove = remove
        _isExpanded = State(
            initialValue: item.wrappedValue.prompt
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var body: some View {
        ContextSourceModuleRow(
            title: displayTitle,
            subtitle: summary,
            systemImage: "text.quote",
            localizer: localizer,
            isEnabled: $item.isEnabled,
            isExpandable: true,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $item.prompt)
                    .font(.body)
                    .frame(minHeight: 82)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.22))
                    )

                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label(localizer.deleteContextSourceLabel(), systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .confirmationDialog(
            localizer.deleteContextConfirmationTitle(),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(localizer.deleteContextSourceLabel(), role: .destructive, action: remove)
            Button(localizer.cancelLabel(), role: .cancel) {}
        } message: {
            Text(localizer.deleteContextConfirmationDetail())
        }
    }

    private var displayTitle: String {
        let localizedTitle = localizer.promptContextDisplayTitle(item.title)
        return localizedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localizer.text(.promptContext)
            : localizedTitle
    }

    private var summary: String {
        let trimmed = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localizer.text(.promptInstruction) : trimmed
    }
}

private struct NamedVocabularySourceRow: View {
    @Binding var item: NamedVocabularyItem
    let localizer: AppLocalizer
    let remove: () -> Void
    @State private var isExpanded: Bool
    @State private var isConfirmingRemoval = false

    init(
        item: Binding<NamedVocabularyItem>,
        localizer: AppLocalizer,
        remove: @escaping () -> Void
    ) {
        _item = item
        self.localizer = localizer
        self.remove = remove
        _isExpanded = State(
            initialValue: item.wrappedValue.terms
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var body: some View {
        ContextSourceModuleRow(
            title: displayName,
            subtitle: localizer.preferredTermsCount(item.normalizedTerms.count),
            systemImage: "text.book.closed",
            localizer: localizer,
            isEnabled: $item.isEnabled,
            isExpandable: true,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(localizer.vocabularyNameLabel(), text: nameBinding)

                TextEditor(text: $item.terms)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 112)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.22))
                    )

                HStack {
                    SettingsRowFeedback(text: localizer.preferredTermsOnePerLineHint())
                    Spacer()
                    Button(role: .destructive) {
                        isConfirmingRemoval = true
                    } label: {
                        Label(localizer.deleteVocabularyLabel(), systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
        }
        .confirmationDialog(
            localizer.deleteVocabularyConfirmationTitle(),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(localizer.deleteVocabularyLabel(), role: .destructive, action: remove)
            Button(localizer.cancelLabel(), role: .cancel) {}
        } message: {
            Text(localizer.deleteVocabularyConfirmationDetail())
        }
    }

    private var displayName: String {
        let trimmed = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localizer.unnamedVocabularyLabel() : trimmed
    }

    private var localizedName: String {
        if item.id == NamedVocabularyItem.importedLegacyGlossaryID,
           normalizedName(item.name) == normalizedName(
                NamedVocabularyItem.importedLegacyGlossaryName
           ) {
            return localizer.importedPreferredTermsLabel()
        }

        guard let presetID = item.presetID,
              let seed = TerminologyPresetCatalog.seedItems.first(where: {
                  $0.presetID == presetID
              }),
              normalizedName(item.name) == normalizedName(seed.name) else {
            return item.name
        }
        return localizer.terminologyPresetTitle(presetID)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { localizedName },
            set: { item.name = $0 }
        )
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}

private struct ProjectVocabularySourceRow: View {
    let project: LinkedProjectVocabulary
    let isIndexing: Bool
    let localizer: AppLocalizer
    let setEnabled: (Bool) -> Void
    let setTermEnabled: (Bool, String) -> Void
    let refresh: () -> Void
    let remove: () -> Void
    @State private var isExpanded = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        ContextSourceModuleRow(
            title: project.displayName,
            subtitle: statusText,
            systemImage: "folder",
            localizer: localizer,
            isEnabled: Binding(get: { project.isEnabled }, set: { setEnabled($0) }),
            isExpandable: true,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(project.lastKnownPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button(action: refresh) {
                        Label(localizer.refreshVocabularyLabel(), systemImage: "arrow.clockwise")
                    }
                    .disabled(isIndexing)

                    Button(role: .destructive) {
                        isConfirmingRemoval = true
                    } label: {
                        Label(localizer.removeProjectLabel(), systemImage: "trash")
                    }
                }
                .controlSize(.small)

                if project.terms.isEmpty {
                    SettingsCollectionEmptyRow(
                        text: isIndexing
                            ? localizer.indexingProjectLabel()
                            : localizer.noProjectTermsLabel()
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(project.terms) { term in
                            Toggle(
                                isOn: Binding(
                                    get: { !project.disabledTermIDs.contains(term.id) },
                                    set: { setTermEnabled($0, term.id) }
                                )
                            ) {
                                HStack {
                                    Text(term.value)
                                    Spacer()
                                    Text(localizer.projectTermSourceLabel(term.sources))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 4)

                            if term.id != project.terms.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            localizer.unlinkProjectConfirmationTitle(project.displayName),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(localizer.removeProjectLabel(), role: .destructive, action: remove)
            Button(localizer.cancelLabel(), role: .cancel) {}
        } message: {
            Text(localizer.unlinkProjectConfirmationDetail())
        }
    }

    private var statusText: String {
        if isIndexing {
            return localizer.indexingProjectLabel()
        }
        let count = project.terms.count
        guard let lastIndexedAt = project.lastIndexedAt else {
            return localizer.projectNotIndexedLabel()
        }
        return localizer.projectTermCountLabel(
            count,
            date: lastIndexedAt.formatted(date: .abbreviated, time: .shortened)
        )
    }
}
