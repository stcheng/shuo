import Foundation

struct ProjectVocabularyStoreLoadResult {
    let state: ProjectVocabularyState
    let issue: ProjectVocabularyStoreLoadIssue?
}

enum ProjectVocabularyStoreLoadIssue: LocalizedError, Equatable {
    case unreadableFiles([String])
    case recoveredFromBackup(String)
    case couldNotPreserveCorruptFile(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFiles(let paths):
            return "Shuo could not read the project vocabulary files and left them untouched: \(paths.joined(separator: ", "))"
        case .recoveredFromBackup(let preservedPath):
            return "Shuo recovered project vocabulary from its backup and preserved the damaged file at \(preservedPath)."
        case .couldNotPreserveCorruptFile(let path):
            return "Shuo found damaged project vocabulary at \(path) but could not preserve it safely, so the file was left untouched."
        }
    }
}

enum ProjectVocabularyStoreSaveError: LocalizedError, Equatable {
    case unreadablePrimary(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePrimary(let path):
            return "Shuo refused to overwrite unreadable project vocabulary at \(path). The existing files were left untouched."
        }
    }
}

struct ProjectVocabularyStore {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = Self.defaultBaseDirectory(),
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    var directoryURL: URL {
        baseDirectory.appendingPathComponent("ProjectVocabulary", isDirectory: true)
    }

    var stateFileURL: URL {
        directoryURL.appendingPathComponent("projects.json")
    }

    var backupFileURL: URL {
        directoryURL.appendingPathComponent("projects.backup.json")
    }

    func load() -> ProjectVocabularyStoreLoadResult {
        let primary = read(at: stateFileURL)
        let backup = read(at: backupFileURL)

        switch primary {
        case .readable(var state, let requiresIndexLimitMigration):
            state.normalize()
            if requiresIndexLimitMigration {
                try? write(state, rotatesBackup: true)
            }
            return ProjectVocabularyStoreLoadResult(state: state, issue: nil)

        case .missing:
            switch backup {
            case .readable(var state, _):
                state.normalize()
                try? write(state, rotatesBackup: false)
                return ProjectVocabularyStoreLoadResult(state: state, issue: nil)
            case .missing:
                return ProjectVocabularyStoreLoadResult(state: ProjectVocabularyState(), issue: nil)
            case .unreadable:
                return ProjectVocabularyStoreLoadResult(
                    state: ProjectVocabularyState(),
                    issue: .unreadableFiles([backupFileURL.path])
                )
            }

        case .unreadable:
            guard case .readable(var state, _) = backup else {
                let paths = [
                    stateFileURL.path,
                    backup.isUnreadable ? backupFileURL.path : nil
                ].compactMap { $0 }
                return ProjectVocabularyStoreLoadResult(
                    state: ProjectVocabularyState(),
                    issue: .unreadableFiles(paths)
                )
            }

            state.normalize()
            guard let preservedURL = preserveCorruptPrimaryFile() else {
                return ProjectVocabularyStoreLoadResult(
                    state: state,
                    issue: .couldNotPreserveCorruptFile(stateFileURL.path)
                )
            }
            try? write(state, rotatesBackup: false)
            return ProjectVocabularyStoreLoadResult(
                state: state,
                issue: .recoveredFromBackup(preservedURL.path)
            )
        }
    }

    func save(_ state: ProjectVocabularyState) throws {
        var normalized = state
        normalized.normalize()
        try write(normalized, rotatesBackup: true)
    }

    private func write(_ state: ProjectVocabularyState, rotatesBackup: Bool) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if rotatesBackup, fileManager.fileExists(atPath: stateFileURL.path) {
            guard !read(at: stateFileURL).isUnreadable else {
                throw ProjectVocabularyStoreSaveError.unreadablePrimary(stateFileURL.path)
            }
            try fileManager.shuoUpdateBackup(from: stateFileURL, to: backupFileURL)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(state).write(to: stateFileURL, options: .atomic)
    }

    private func read(at url: URL) -> ProjectVocabularyFileReadResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .readable(
                try decoder.decode(ProjectVocabularyState.self, from: data),
                requiresIndexLimitMigration: containsOversizedProjectIndex(in: data)
            )
        } catch {
            return .unreadable
        }
    }

    private func containsOversizedProjectIndex(in data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = root["projects"] as? [[String: Any]] else {
            return false
        }
        return projects.contains { project in
            guard let terms = project["terms"] as? [Any] else {
                return false
            }
            return terms.count > ProjectVocabularyLimits.maximumIndexedTermCount
        }
    }

    private func preserveCorruptPrimaryFile() -> URL? {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let preservedURL = directoryURL
            .appendingPathComponent("projects.corrupt-\(stamp).json")

        do {
            try fileManager.copyItem(at: stateFileURL, to: preservedURL)
            return preservedURL
        } catch {
            return nil
        }
    }

    private static func defaultBaseDirectory() -> URL {
        AppStoragePaths.applicationSupportDirectory()
    }
}

private enum ProjectVocabularyFileReadResult {
    case missing
    case readable(
        ProjectVocabularyState,
        requiresIndexLimitMigration: Bool
    )
    case unreadable

    var isUnreadable: Bool {
        if case .unreadable = self {
            return true
        }
        return false
    }
}
