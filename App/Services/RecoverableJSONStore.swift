import Foundation

enum RecoverableJSONStoreSource: Equatable {
    case current
    case backup
    case missing
    case unrecoverable
}

struct RecoverableJSONStoreLoadResult<Value> {
    let value: Value?
    let source: RecoverableJSONStoreSource
    let issue: RecoverableJSONStoreLoadIssue?
}

enum RecoverableJSONStoreLoadIssue: LocalizedError, Equatable {
    case recoveredFromBackup(preservedPath: String)
    case preservedDamagedBackup(String)
    case unreadableFiles([String])
    case repairFailed(String)

    var errorDescription: String? {
        switch self {
        case .recoveredFromBackup(let preservedPath):
            return "Shuo recovered local data from its backup and preserved the damaged file at \(preservedPath)."
        case .preservedDamagedBackup(let path):
            return "Shuo found a damaged backup and preserved it at \(path). The current local data is still readable."
        case .unreadableFiles(let paths):
            return "Shuo could not read local data and left the affected files untouched: \(paths.joined(separator: ", "))"
        case .repairFailed(let detail):
            return "Shuo found recoverable local data but could not safely repair its files: \(detail)"
        }
    }
}

/// Saving must never turn an unreadable primary file into the next backup.
/// In that state the backup may be the user's only intact copy, so callers
/// need an explicit recovery/reset path instead of silently rotating files.
enum RecoverableJSONStoreSaveError: LocalizedError, Equatable {
    case unreadablePrimary(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePrimary(let path):
            return "Shuo refused to overwrite unreadable local data at \(path). The existing files were left untouched."
        }
    }
}

struct RecoverableJSONStore<Value: Codable> {
    let directoryURL: URL
    let fileURL: URL
    let backupFileURL: URL

    private let fileManager: FileManager

    init(
        baseDirectory: URL = AppStoragePaths.applicationSupportDirectory(),
        directoryName: String,
        fileName: String,
        backupFileName: String,
        fileManager: FileManager = .default
    ) {
        directoryURL = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        fileURL = directoryURL.appendingPathComponent(fileName)
        backupFileURL = directoryURL.appendingPathComponent(backupFileName)
        self.fileManager = fileManager
    }

    func load() -> RecoverableJSONStoreLoadResult<Value> {
        let primary = read(at: fileURL)
        let backup = read(at: backupFileURL)

        switch primary {
        case .readable(let value):
            if backup.isUnreadable {
                do {
                    let preservedURL = try preserveDamagedFile(at: backupFileURL)
                    return RecoverableJSONStoreLoadResult(
                        value: value,
                        source: .current,
                        issue: .preservedDamagedBackup(preservedURL.path)
                    )
                } catch {
                    return RecoverableJSONStoreLoadResult(
                        value: value,
                        source: .current,
                        issue: .repairFailed(error.localizedDescription)
                    )
                }
            }
            return RecoverableJSONStoreLoadResult(value: value, source: .current, issue: nil)

        case .missing:
            guard case .readable(let value) = backup else {
                if backup.isUnreadable {
                    return RecoverableJSONStoreLoadResult(
                        value: nil,
                        source: .unrecoverable,
                        issue: .unreadableFiles([backupFileURL.path])
                    )
                }
                return RecoverableJSONStoreLoadResult(value: nil, source: .missing, issue: nil)
            }

            do {
                try write(value, rotatesBackup: false)
                return RecoverableJSONStoreLoadResult(value: value, source: .backup, issue: nil)
            } catch {
                return RecoverableJSONStoreLoadResult(
                    value: value,
                    source: .backup,
                    issue: .repairFailed(error.localizedDescription)
                )
            }

        case .unreadable:
            guard case .readable(let value) = backup else {
                let paths = [
                    fileURL.path,
                    backup.isUnreadable ? backupFileURL.path : nil
                ].compactMap { $0 }
                return RecoverableJSONStoreLoadResult(
                    value: nil,
                    source: .unrecoverable,
                    issue: .unreadableFiles(paths)
                )
            }

            do {
                let preservedURL = try preserveDamagedFile(at: fileURL)
                try write(value, rotatesBackup: false)
                return RecoverableJSONStoreLoadResult(
                    value: value,
                    source: .backup,
                    issue: .recoveredFromBackup(preservedPath: preservedURL.path)
                )
            } catch {
                return RecoverableJSONStoreLoadResult(
                    value: value,
                    source: .backup,
                    issue: .repairFailed(error.localizedDescription)
                )
            }
        }
    }

    func save(_ value: Value) throws {
        try write(value, rotatesBackup: true)
    }

    private func write(_ value: Value, rotatesBackup: Bool) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if rotatesBackup, fileManager.fileExists(atPath: fileURL.path) {
            guard !read(at: fileURL).isUnreadable else {
                throw RecoverableJSONStoreSaveError.unreadablePrimary(fileURL.path)
            }
            try fileManager.shuoUpdateBackup(from: fileURL, to: backupFileURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }

    private func read(at url: URL) -> RecoverableJSONFileReadResult<Value> {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let decoder = JSONDecoder()
            return .readable(try decoder.decode(Value.self, from: Data(contentsOf: url)))
        } catch {
            return .unreadable
        }
    }

    private func preserveDamagedFile(at url: URL) throws -> URL {
        let fileExtension = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let preservedName = fileExtension.isEmpty
            ? "\(stem).corrupt-\(UUID().uuidString)"
            : "\(stem).corrupt-\(UUID().uuidString).\(fileExtension)"
        let preservedURL = url.deletingLastPathComponent().appendingPathComponent(preservedName)
        try fileManager.copyItem(at: url, to: preservedURL)
        return preservedURL
    }
}

private enum RecoverableJSONFileReadResult<Value> {
    case missing
    case readable(Value)
    case unreadable

    var isUnreadable: Bool {
        if case .unreadable = self {
            return true
        }
        return false
    }
}
