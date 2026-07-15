import Combine
import Foundation

enum ProjectVocabularyControllerError: LocalizedError {
    case directoryUnavailable(String)
    case securityScopeDenied(String)

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let path):
            return "The project directory is unavailable: \(path)"
        case .securityScopeDenied(let path):
            return "Shuo could not get read access to the project directory: \(path)"
        }
    }
}

@MainActor
final class ProjectVocabularyController: ObservableObject {
    @Published private(set) var state: ProjectVocabularyState
    @Published private(set) var indexingProjectIDs = Set<UUID>()
    @Published private(set) var lastErrorMessage: String?

    private let store: ProjectVocabularyStore?
    private let indexer: ProjectVocabularyIndexer
    private let composer: TranscriptionVocabularyComposer
    private var indexingTasks: [UUID: Task<Void, Never>] = [:]

    init(
        store: ProjectVocabularyStore? = ProjectVocabularyStore(),
        initialState: ProjectVocabularyState? = nil,
        indexer: ProjectVocabularyIndexer = ProjectVocabularyIndexer(),
        composer: TranscriptionVocabularyComposer = TranscriptionVocabularyComposer()
    ) {
        self.store = store
        self.indexer = indexer
        self.composer = composer

        if var initialState {
            initialState.normalize()
            state = initialState
            lastErrorMessage = nil
        } else if let store {
            let loadResult = store.load()
            state = loadResult.state
            lastErrorMessage = loadResult.issue?.localizedDescription
        } else {
            state = ProjectVocabularyState()
            lastErrorMessage = nil
        }
    }

    deinit {
        for task in indexingTasks.values {
            task.cancel()
        }
    }

    func linkProject(at directoryURL: URL) throws {
        let standardizedURL = directoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: standardizedURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ProjectVocabularyControllerError.directoryUnavailable(standardizedURL.path)
        }

        let bookmarkData = try ProjectDirectoryBookmark.makeBookmarkData(for: standardizedURL)
        let existingIndex = state.projects.firstIndex {
            URL(fileURLWithPath: $0.lastKnownPath, isDirectory: true).standardizedFileURL == standardizedURL
        }

        let projectID: UUID
        if let existingIndex {
            state.projects[existingIndex].bookmarkData = bookmarkData
            state.projects[existingIndex].lastKnownPath = standardizedURL.path
            state.projects[existingIndex].displayName = standardizedURL.lastPathComponent
            state.projects[existingIndex].isEnabled = true
            projectID = state.projects[existingIndex].id
        } else {
            let project = LinkedProjectVocabulary(
                displayName: standardizedURL.lastPathComponent,
                lastKnownPath: standardizedURL.path,
                bookmarkData: bookmarkData
            )
            state.projects.append(project)
            projectID = project.id
        }

        persistState()
        refreshProject(id: projectID)
    }

    func refreshProject(id: UUID) {
        guard state.isProjectVocabularyEnabled,
              !indexingProjectIDs.contains(id),
              let project = state.projects.first(where: { $0.id == id }) else {
            return
        }

        do {
            let resolvedDirectory = try ProjectDirectoryBookmark.resolve(project)
            let startedSecurityScope = resolvedDirectory.requiresSecurityScope
                ? resolvedDirectory.url.startAccessingSecurityScopedResource()
                : false
            if resolvedDirectory.requiresSecurityScope, !startedSecurityScope {
                throw ProjectVocabularyControllerError.securityScopeDenied(resolvedDirectory.url.path)
            }

            if resolvedDirectory.bookmarkIsStale,
               let projectIndex = state.projects.firstIndex(where: { $0.id == id }) {
                state.projects[projectIndex].bookmarkData = try ProjectDirectoryBookmark.makeBookmarkData(
                    for: resolvedDirectory.url
                )
                state.projects[projectIndex].lastKnownPath = resolvedDirectory.url.path
                persistState()
            }

            indexingProjectIDs.insert(id)
            lastErrorMessage = nil
            let indexer = self.indexer
            let directoryURL = resolvedDirectory.url
            let task = Task { [weak self] in
                defer {
                    if startedSecurityScope {
                        directoryURL.stopAccessingSecurityScopedResource()
                    }
                    self?.indexingProjectIDs.remove(id)
                    self?.indexingTasks[id] = nil
                }

                do {
                    let result = try await Task.detached(priority: .utility) {
                        try indexer.indexProject(at: directoryURL)
                    }.value
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.applyIndexResult(result, to: id)
                } catch is CancellationError {
                    // Project removal or a replacement refresh intentionally cancels indexing.
                } catch {
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
            indexingTasks[id] = task
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeProject(id: UUID) {
        indexingTasks[id]?.cancel()
        indexingTasks[id] = nil
        indexingProjectIDs.remove(id)
        state.projects.removeAll { $0.id == id }
        persistState()
    }

    func setProjectVocabularyEnabled(_ isEnabled: Bool) {
        state.isProjectVocabularyEnabled = isEnabled
        if isEnabled {
            let projectsNeedingIndex = state.projects
                .filter { $0.isEnabled && $0.lastIndexedAt == nil }
                .map(\.id)
            persistState()
            for projectID in projectsNeedingIndex {
                refreshProject(id: projectID)
            }
        } else {
            for task in indexingTasks.values {
                task.cancel()
            }
            indexingTasks.removeAll()
            indexingProjectIDs.removeAll()
            persistState()
        }
    }

    func resumePendingIndexes() {
        guard state.isProjectVocabularyEnabled else {
            return
        }
        let projectIDs = state.projects
            .filter { $0.isEnabled && $0.lastIndexedAt == nil }
            .map(\.id)
        for projectID in projectIDs {
            refreshProject(id: projectID)
        }
    }

    func setProjectEnabled(_ isEnabled: Bool, id: UUID) {
        guard let index = state.projects.firstIndex(where: { $0.id == id }) else {
            return
        }
        state.projects[index].isEnabled = isEnabled
        if isEnabled {
            persistState()
            if state.projects[index].lastIndexedAt == nil {
                refreshProject(id: id)
            }
            return
        }

        indexingTasks[id]?.cancel()
        indexingTasks[id] = nil
        indexingProjectIDs.remove(id)
        persistState()
    }

    func setTermEnabled(_ isEnabled: Bool, termID: String, projectID: UUID) {
        guard let projectIndex = state.projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }
        if isEnabled {
            state.projects[projectIndex].disabledTermIDs.remove(termID)
        } else {
            state.projects[projectIndex].disabledTermIDs.insert(termID)
        }
        persistState()
    }

    func captureTranscriptionVocabulary(
        manualGlossary: String,
        learnedCorrectionTerms: [String] = [],
        presetTerms: [String] = [],
        isEnabled: Bool
    ) -> TranscriptionVocabularySnapshot {
        guard isEnabled else {
            return composer.compose(
                manualGlossary: "",
                learnedCorrectionTerms: [],
                projectTerms: [],
                presetTerms: []
            )
        }

        let projectTerms = state.isProjectVocabularyEnabled
            ? state.projects.filter(\.isEnabled).flatMap(\.enabledTerms)
            : []
        return composer.compose(
            manualGlossary: manualGlossary,
            learnedCorrectionTerms: learnedCorrectionTerms,
            projectTerms: projectTerms,
            presetTerms: presetTerms
        )
    }

    private func applyIndexResult(_ result: ProjectVocabularyIndexResult, to projectID: UUID) {
        guard let projectIndex = state.projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }
        let limitedTerms = ProjectVocabularyLimits.limitedIndexedTerms(result.terms)
        let availableTermIDs = Set(limitedTerms.map(\.id))
        state.projects[projectIndex].terms = limitedTerms
        state.projects[projectIndex].disabledTermIDs.formIntersection(availableTermIDs)
        state.projects[projectIndex].lastIndexedAt = Date()
        persistState()
    }

    private func persistState() {
        state.normalize()
        guard let store else {
            return
        }
        do {
            try store.save(state)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
