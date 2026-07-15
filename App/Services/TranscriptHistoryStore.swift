import Foundation

struct TranscriptHistoryLoadResult {
    let items: [TranscriptItem]
    let issue: TranscriptHistoryLoadIssue?
    let deletedItemIDs: Set<UUID>
    let pendingAudioFileNames: Set<String>
}

enum StartupHistoryReconciliationPolicy {
    static func allowsAutomaticMutation(after issue: TranscriptHistoryLoadIssue?) -> Bool {
        switch issue {
        case nil, .recoveredFiles, .completedPendingDeletion:
            return true
        case .unreadableFiles, .couldNotPreserveCorruptFile, .repairFailed:
            return false
        }
    }
}

enum TranscriptHistoryLoadIssue: LocalizedError, Equatable {
    case unreadableFiles([String])
    case couldNotPreserveCorruptFile(String)
    case repairFailed(String)
    case recoveredFiles([String])
    case completedPendingDeletion

    var errorDescription: String? {
        switch self {
        case .unreadableFiles(let paths):
            return "Shuo could not read the history files and left them untouched: \(paths.joined(separator: ", "))"
        case .couldNotPreserveCorruptFile(let path):
            return "Shuo recovered history data but could not safely preserve the corrupt file at \(path). The original file was left untouched."
        case .repairFailed(let detail):
            return "Shuo recovered history data in memory but could not safely repair its files: \(detail)"
        case .recoveredFiles(let paths):
            return "Shuo recovered and repaired transcript history after finding a damaged or missing history file: \(paths.joined(separator: ", "))"
        case .completedPendingDeletion:
            return "Shuo safely completed an interrupted transcript-history deletion."
        }
    }
}

enum TranscriptHistorySaveError: LocalizedError, Equatable {
    case unreadablePrimary(String)
    case unreadableDeletionLedger(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePrimary(let path):
            return "Shuo refused to overwrite unreadable history data at \(path). The existing history files were left untouched."
        case .unreadableDeletionLedger(let path):
            return "Shuo refused to change transcript history because its deletion ledger is unreadable at \(path). The existing files were left untouched."
        }
    }
}

struct TranscriptHistoryStore {
    private let baseDirectory: URL
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let legacyUserDefaultsKey: String

    init(
        baseDirectory: URL = Self.defaultBaseDirectory(),
        userDefaults: UserDefaults? = nil,
        fileManager: FileManager = .default,
        legacyUserDefaultsKey: String = "history"
    ) {
        self.baseDirectory = baseDirectory
        self.userDefaults = userDefaults ?? Self.defaultUserDefaults()
        self.fileManager = fileManager
        self.legacyUserDefaultsKey = legacyUserDefaultsKey
    }

    var historyDirectoryURL: URL {
        baseDirectory.appendingPathComponent("History", isDirectory: true)
    }

    var historyFileURL: URL {
        historyDirectoryURL.appendingPathComponent("transcripts.json")
    }

    var backupFileURL: URL {
        historyDirectoryURL.appendingPathComponent("transcripts.backup.json")
    }

    var deletionLedgerFileURL: URL {
        historyDirectoryURL.appendingPathComponent("transcripts.deleted.json")
    }

    var legacyMigrationMarkerURL: URL {
        historyDirectoryURL.appendingPathComponent("legacy-user-defaults-history.migrated")
    }

    func load() -> [TranscriptItem] {
        loadResult().items
    }

    func loadResult() -> TranscriptHistoryLoadResult {
        let deletionLedgerResult = readDeletionLedger()
        guard !deletionLedgerResult.isUnreadable else {
            return TranscriptHistoryLoadResult(
                items: [],
                issue: .unreadableFiles([deletionLedgerFileURL.path]),
                deletedItemIDs: [],
                pendingAudioFileNames: []
            )
        }
        let deletedItemIDs = deletionLedgerResult.deletedItemIDs
        let pendingAudioFileNames = deletionLedgerResult.pendingAudioFileNames

        let primaryResult = readHistoryFile(at: historyFileURL)
        let backupResult = readHistoryFile(at: backupFileURL)
        let shouldMarkLegacyMigrationCompleted = !fileManager.fileExists(
            atPath: legacyMigrationMarkerURL.path
        )
        // Dedicated history files predate the explicit migration marker. Their
        // presence proves migration already happened, so importing the legacy
        // defaults again could resurrect records deleted in an older build.
        let shouldImportLegacyHistory = shouldMarkLegacyMigrationCompleted
            && primaryResult.isMissing
            && backupResult.isMissing
        let hasLegacyHistoryData = shouldImportLegacyHistory
            && userDefaults.data(forKey: legacyUserDefaultsKey) != nil
        let legacyItems = shouldImportLegacyHistory
            ? readLegacyUserDefaultsHistory()
            : nil
        if hasLegacyHistoryData, legacyItems == nil {
            return TranscriptHistoryLoadResult(
                items: [],
                issue: .unreadableFiles(["UserDefaults:\(legacyUserDefaultsKey)"]),
                deletedItemIDs: deletedItemIDs,
                pendingAudioFileNames: pendingAudioFileNames
            )
        }

        let recoveredFileItems: [TranscriptItem]?
        if let primaryItems = primaryResult.items {
            recoveredFileItems = primaryItems
        } else if let backupItems = backupResult.items {
            recoveredFileItems = backupItems
        } else if legacyItems != nil {
            recoveredFileItems = []
        } else if primaryResult.isUnreadable || backupResult.isUnreadable {
            let unreadablePaths = [
                primaryResult.isUnreadable ? historyFileURL.path : nil,
                backupResult.isUnreadable ? backupFileURL.path : nil
            ].compactMap { $0 }
            return TranscriptHistoryLoadResult(
                items: [],
                issue: .unreadableFiles(unreadablePaths),
                deletedItemIDs: deletedItemIDs,
                pendingAudioFileNames: pendingAudioFileNames
            )
        } else {
            recoveredFileItems = []
        }

        let mergedItems = merge(
            fileItems: recoveredFileItems ?? [],
            legacyItems: legacyItems ?? []
        )
        .map { $0.upgradedToCurrentSchema() }
        .filter { !deletedItemIDs.contains($0.id) }

        let normalizedPrimaryItems = primaryResult.items?.map {
            $0.upgradedToCurrentSchema()
        }
        let normalizedBackupItems = backupResult.items?.map {
            $0.upgradedToCurrentSchema()
        }
        let primaryContainsDeletedItem = normalizedPrimaryItems?.contains {
            deletedItemIDs.contains($0.id)
        } == true
        let backupContainsDeletedItem = normalizedBackupItems?.contains {
            deletedItemIDs.contains($0.id)
        } == true
        let completedPendingDeletion = primaryContainsDeletedItem || backupContainsDeletedItem

        var recoveryPaths: [String] = []
        if primaryResult.isUnreadable
            || (primaryResult.isMissing && backupResult.items != nil) {
            recoveryPaths.append(historyFileURL.path)
        }
        if backupResult.isUnreadable {
            recoveryPaths.append(backupFileURL.path)
        }

        let corruptURLs = [
            primaryResult.isUnreadable ? historyFileURL : nil,
            backupResult.isUnreadable ? backupFileURL : nil
        ].compactMap { $0 }
        for url in corruptURLs {
            guard preserveCorruptFile(at: url) else {
                return TranscriptHistoryLoadResult(
                    items: mergedItems,
                    issue: .couldNotPreserveCorruptFile(url.path),
                    deletedItemIDs: deletedItemIDs,
                    pendingAudioFileNames: pendingAudioFileNames
                )
            }
        }

        let normalizedPrimaryWithoutDeleted = normalizedPrimaryItems?.filter {
            !deletedItemIDs.contains($0.id)
        }
        let needsSnapshotRepair = primaryResult.items == nil
            || normalizedPrimaryWithoutDeleted != mergedItems
            || backupResult.isUnreadable
            || completedPendingDeletion

        if needsSnapshotRepair {
            do {
                try writeSnapshotToPrimaryAndBackup(mergedItems)
            } catch {
                return TranscriptHistoryLoadResult(
                    items: mergedItems,
                    issue: .repairFailed(error.localizedDescription),
                    deletedItemIDs: deletedItemIDs,
                    pendingAudioFileNames: pendingAudioFileNames
                )
            }
        }

        if shouldMarkLegacyMigrationCompleted {
            do {
                try markLegacyMigrationCompleted()
            } catch {
                return TranscriptHistoryLoadResult(
                    items: mergedItems,
                    issue: .repairFailed(error.localizedDescription),
                    deletedItemIDs: deletedItemIDs,
                    pendingAudioFileNames: pendingAudioFileNames
                )
            }
        }

        // The dedicated primary, backup, and migration marker are now the
        // durable copies. Keeping the old defaults payload would let an older
        // build resurrect records that the user later deletes.
        userDefaults.removeObject(forKey: legacyUserDefaultsKey)

        let issue: TranscriptHistoryLoadIssue?
        if !recoveryPaths.isEmpty {
            issue = .recoveredFiles(recoveryPaths)
        } else if completedPendingDeletion {
            issue = .completedPendingDeletion
        } else {
            issue = nil
        }
        return TranscriptHistoryLoadResult(
            items: mergedItems,
            issue: issue,
            deletedItemIDs: deletedItemIDs,
            pendingAudioFileNames: pendingAudioFileNames
        )
    }

    func save(_ items: [TranscriptItem]) throws {
        let deletionLedgerResult = readDeletionLedger()
        guard !deletionLedgerResult.isUnreadable else {
            throw TranscriptHistorySaveError.unreadableDeletionLedger(
                deletionLedgerFileURL.path
            )
        }
        let filteredItems = items.filter {
            !deletionLedgerResult.deletedItemIDs.contains($0.id)
        }
        try write(filteredItems, rotatesBackup: true)
    }

    /// Commits a user-visible deletion. The ledger is written first, so stale
    /// primary or backup files cannot resurrect a deleted transcript after a
    /// crash. A returned issue means deletion is committed but file cleanup
    /// needs attention; a thrown error means no deletion was committed.
    func deleteHistoryItems(
        ids: Set<UUID>,
        pendingAudioFileNames: Set<String> = [],
        remainingItems: [TranscriptItem]
    ) throws -> TranscriptHistoryLoadIssue? {
        guard !ids.isEmpty else {
            return nil
        }

        let deletionLedgerResult = readDeletionLedger()
        guard !deletionLedgerResult.isUnreadable else {
            throw TranscriptHistorySaveError.unreadableDeletionLedger(
                deletionLedgerFileURL.path
            )
        }

        let allDeletedItemIDs = deletionLedgerResult.deletedItemIDs.union(ids)
        let allPendingAudioFileNames = deletionLedgerResult.pendingAudioFileNames
            .union(pendingAudioFileNames)
        try writeDeletionLedger(
            allDeletedItemIDs,
            pendingAudioFileNames: allPendingAudioFileNames
        )

        let filteredItems = remainingItems.filter {
            !allDeletedItemIDs.contains($0.id)
        }
        for url in [historyFileURL, backupFileURL]
        where readHistoryFile(at: url).isUnreadable {
            guard preserveCorruptFile(at: url) else {
                return .couldNotPreserveCorruptFile(url.path)
            }
        }

        do {
            try writeSnapshotToPrimaryAndBackup(filteredItems)
            return nil
        } catch {
            return .repairFailed(error.localizedDescription)
        }
    }

    func completePendingAudioDeletion(fileNames: Set<String>) throws {
        guard !fileNames.isEmpty else {
            return
        }
        let deletionLedgerResult = readDeletionLedger()
        guard !deletionLedgerResult.isUnreadable else {
            throw TranscriptHistorySaveError.unreadableDeletionLedger(
                deletionLedgerFileURL.path
            )
        }
        try writeDeletionLedger(
            deletionLedgerResult.deletedItemIDs,
            pendingAudioFileNames: deletionLedgerResult.pendingAudioFileNames
                .subtracting(fileNames)
        )
    }

    func validateWritableState() throws {
        let deletionLedgerResult = readDeletionLedger()
        guard !deletionLedgerResult.isUnreadable else {
            throw TranscriptHistorySaveError.unreadableDeletionLedger(
                deletionLedgerFileURL.path
            )
        }
        guard !readHistoryFile(at: historyFileURL).isUnreadable else {
            throw TranscriptHistorySaveError.unreadablePrimary(historyFileURL.path)
        }
    }

    private func write(_ items: [TranscriptItem], rotatesBackup: Bool) throws {
        try fileManager.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
        if rotatesBackup, fileManager.fileExists(atPath: historyFileURL.path) {
            guard !readHistoryFile(at: historyFileURL).isUnreadable else {
                throw TranscriptHistorySaveError.unreadablePrimary(historyFileURL.path)
            }
            try fileManager.shuoUpdateBackup(from: historyFileURL, to: backupFileURL)
        }

        try encodedHistory(items).write(to: historyFileURL, options: .atomic)
    }

    private func writeSnapshotToPrimaryAndBackup(_ items: [TranscriptItem]) throws {
        try fileManager.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
        let data = try encodedHistory(items)
        try data.write(to: historyFileURL, options: .atomic)
        try data.write(to: backupFileURL, options: .atomic)
    }

    private func encodedHistory(_ items: [TranscriptItem]) throws -> Data {
        try JSONEncoder().encode(items)
    }

    private static func defaultBaseDirectory() -> URL {
        if AppRuntime.isRunningUnderXCTest {
            return FileManager.default.temporaryDirectory.appendingPathComponent(
                "ShuoTests-History-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
                isDirectory: true
            )
        }
        return AppStoragePaths.applicationSupportDirectory()
    }

    private static func defaultUserDefaults() -> UserDefaults {
        guard AppRuntime.isRunningUnderXCTest else {
            return .standard
        }
        return UserDefaults(
            suiteName: "dev.shuotian.Shuo.tests.history.\(UUID().uuidString)"
        ) ?? .standard
    }

    private func readHistoryFile(at url: URL) -> HistoryFileReadResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([TranscriptItem].self, from: data) else {
            return .unreadable
        }

        return .readable(items)
    }

    private func readLegacyUserDefaultsHistory() -> [TranscriptItem]? {
        guard let data = userDefaults.data(forKey: legacyUserDefaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode([TranscriptItem].self, from: data)
    }

    private func readDeletionLedger() -> DeletionLedgerReadResult {
        guard fileManager.fileExists(atPath: deletionLedgerFileURL.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: deletionLedgerFileURL),
              let ledger = try? JSONDecoder().decode(
                TranscriptHistoryDeletionLedger.self,
                from: data
              ),
              (1...TranscriptHistoryDeletionLedger.currentSchemaVersion)
                .contains(ledger.schemaVersion) else {
            return .unreadable
        }
        return .readable(ledger)
    }

    private func writeDeletionLedger(
        _ deletedItemIDs: Set<UUID>,
        pendingAudioFileNames: Set<String>
    ) throws {
        try fileManager.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
        let ledger = TranscriptHistoryDeletionLedger(
            schemaVersion: TranscriptHistoryDeletionLedger.currentSchemaVersion,
            deletedItemIDs: deletedItemIDs.sorted {
                $0.uuidString < $1.uuidString
            },
            pendingAudioFileNames: pendingAudioFileNames.sorted()
        )
        try JSONEncoder().encode(ledger).write(
            to: deletionLedgerFileURL,
            options: .atomic
        )
    }

    private func markLegacyMigrationCompleted() throws {
        try fileManager.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
        try Data("1\n".utf8).write(to: legacyMigrationMarkerURL, options: .atomic)
    }

    private func merge(fileItems: [TranscriptItem], legacyItems: [TranscriptItem]) -> [TranscriptItem] {
        var mergedByID = [UUID: TranscriptItem]()
        for item in legacyItems {
            mergedByID[item.id] = item
        }
        for item in fileItems {
            mergedByID[item.id] = item
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func preserveCorruptFile(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return true
        }

        let stem = url.deletingPathExtension().lastPathComponent
        let preservedURL = historyDirectoryURL.appendingPathComponent(
            "\(stem).corrupt-\(UUID().uuidString).json"
        )
        do {
            try fileManager.copyItem(at: url, to: preservedURL)
            return true
        } catch {
            return false
        }
    }
}

struct TranscriptHistoryDeletionResult {
    let historyCleanupIssue: TranscriptHistoryLoadIssue?
    let audioCleanupErrors: [String]
}

/// Commits the durable tombstone before touching recordings. Once the ledger
/// accepts a deletion, an audio cleanup failure is retryable and can never
/// leave a visible History row pointing at an already removed recording.
struct TranscriptHistoryDeletionTransaction {
    let historyStore: TranscriptHistoryStore
    let audioStore: TranscriptAudioStore

    func commit(
        deletedItems: [TranscriptItem],
        remainingItems: [TranscriptItem],
        onHistoryCommitted: () -> Void = {}
    ) throws -> TranscriptHistoryDeletionResult {
        let deletedIDs = Set(deletedItems.map(\.id))
        let pendingAudioFileNames = Set(deletedItems.compactMap(\.audioFileName))
        let historyCleanupIssue = try historyStore.deleteHistoryItems(
            ids: deletedIDs,
            pendingAudioFileNames: pendingAudioFileNames,
            remainingItems: remainingItems
        )
        onHistoryCommitted()
        let audioCleanupErrors = cleanupPendingAudio(fileNames: pendingAudioFileNames)
        return TranscriptHistoryDeletionResult(
            historyCleanupIssue: historyCleanupIssue,
            audioCleanupErrors: audioCleanupErrors
        )
    }

    func resumePendingAudioCleanup(fileNames: Set<String>) -> [String] {
        cleanupPendingAudio(fileNames: fileNames)
    }

    private func cleanupPendingAudio(fileNames: Set<String>) -> [String] {
        guard !fileNames.isEmpty else {
            return []
        }

        var completedFileNames = Set<String>()
        var errors: [String] = []
        for fileName in fileNames.sorted() {
            do {
                try audioStore.deleteAudio(forFileName: fileName)
                completedFileNames.insert(fileName)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        if !completedFileNames.isEmpty {
            do {
                try historyStore.completePendingAudioDeletion(
                    fileNames: completedFileNames
                )
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return errors
    }
}

private struct TranscriptHistoryDeletionLedger: Codable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let deletedItemIDs: [UUID]
    let pendingAudioFileNames: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case deletedItemIDs
        case pendingAudioFileNames
    }

    init(
        schemaVersion: Int,
        deletedItemIDs: [UUID],
        pendingAudioFileNames: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.deletedItemIDs = deletedItemIDs
        self.pendingAudioFileNames = pendingAudioFileNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        deletedItemIDs = try container.decode([UUID].self, forKey: .deletedItemIDs)
        pendingAudioFileNames = try container.decodeIfPresent(
            [String].self,
            forKey: .pendingAudioFileNames
        ) ?? []
    }
}

private enum HistoryFileReadResult {
    case missing
    case readable([TranscriptItem])
    case unreadable

    var items: [TranscriptItem]? {
        guard case .readable(let items) = self else {
            return nil
        }
        return items
    }

    var isMissing: Bool {
        if case .missing = self {
            return true
        }
        return false
    }

    var isUnreadable: Bool {
        if case .unreadable = self {
            return true
        }
        return false
    }
}

private enum DeletionLedgerReadResult {
    case missing
    case readable(TranscriptHistoryDeletionLedger)
    case unreadable

    var deletedItemIDs: Set<UUID> {
        guard case .readable(let ledger) = self else {
            return []
        }
        return Set(ledger.deletedItemIDs)
    }

    var pendingAudioFileNames: Set<String> {
        guard case .readable(let ledger) = self else {
            return []
        }
        return Set(ledger.pendingAudioFileNames)
    }

    var isUnreadable: Bool {
        if case .unreadable = self {
            return true
        }
        return false
    }
}
