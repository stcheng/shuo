import Foundation

struct MetricsStoreState: Equatable {
    let records: [TranscriptMetricsRecord]
    let counters: MetricsCounters
    let issue: MetricsStoreLoadIssue?

    init(
        records: [TranscriptMetricsRecord],
        counters: MetricsCounters,
        issue: MetricsStoreLoadIssue? = nil
    ) {
        self.records = records
        self.counters = counters
        self.issue = issue
    }
}

enum MetricsStoreLoadIssue: LocalizedError, Equatable {
    case recoveryProblems([String])
    case recoveredFiles([String])

    var errorDescription: String? {
        switch self {
        case .recoveryProblems(let details):
            return "Shuo found damaged metrics data. It kept the affected files and did not overwrite data that could not be safely recovered: \(details.joined(separator: "; "))"
        case .recoveredFiles(let paths):
            return "Shuo recovered metrics data, preserved the damaged files, and repaired its active copies: \(paths.joined(separator: ", "))"
        }
    }
}

enum MetricsStoreSaveError: LocalizedError, Equatable {
    case unreadablePrimary(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePrimary(let path):
            return "Shuo refused to rotate an unreadable metrics file at \(path) over its backup. The existing files were left untouched."
        }
    }
}

struct MetricsStore {
    private let baseDirectory: URL
    private let fileManager: FileManager
    private let calculator: MetricsCalculator

    init(
        baseDirectory: URL = Self.defaultBaseDirectory(),
        fileManager: FileManager = .default,
        calculator: MetricsCalculator = MetricsCalculator()
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
        self.calculator = calculator
    }

    var historyDirectoryURL: URL {
        baseDirectory.appendingPathComponent("History", isDirectory: true)
    }

    var metricsHistoryFileURL: URL {
        historyDirectoryURL.appendingPathComponent("metrics-history.json")
    }

    var metricsHistoryBackupFileURL: URL {
        historyDirectoryURL.appendingPathComponent("metrics-history.backup.json")
    }

    var metricsDirectoryURL: URL {
        baseDirectory.appendingPathComponent("Metrics", isDirectory: true)
    }

    var countersFileURL: URL {
        metricsDirectoryURL.appendingPathComponent("counters.json")
    }

    var countersBackupFileURL: URL {
        metricsDirectoryURL.appendingPathComponent("counters.backup.json")
    }

    var legacyMetricsFileURL: URL {
        metricsDirectoryURL.appendingPathComponent("metrics.json")
    }

    var legacyMetricsBackupFileURL: URL {
        metricsDirectoryURL.appendingPathComponent("metrics.backup.json")
    }

    func load(seedHistory: [TranscriptItem]) -> MetricsStoreState {
        var recoveryProblems: [String] = []
        var preservedDamagedPaths: [String] = []
        let recordLoadResult = loadRecords(seedHistory: seedHistory)
        let loadedRecords = sort(recordLoadResult.records)
        let records = loadedRecords.map { $0.upgradedToCurrentSchema() }
        let recordsNeedWrite = recordLoadResult.source != .current
            || records != loadedRecords
            || recordLoadResult.unreadableURLs.contains(metricsHistoryBackupFileURL)

        let recordsCanBeRepaired = prepareForRepair(
            unreadableURLs: recordLoadResult.unreadableURLs,
            hasRecoverableSource: recordLoadResult.source != .seeded,
            recoveryProblems: &recoveryProblems,
            preservedDamagedPaths: &preservedDamagedPaths
        )

        if recordsNeedWrite, recordsCanBeRepaired {
            do {
                let rotatesBackup = recordLoadResult.source == .current
                try write(records: records, rotatesBackup: rotatesBackup)
            } catch {
                recoveryProblems.append("could not restore \(metricsHistoryFileURL.path): \(error.localizedDescription)")
            }
        }

        let rebuiltCounters = calculator.counters(from: records)
        let counterLoadResult = loadCounters(rebuiltCounters: rebuiltCounters)
        let counters = counterLoadResult.counters.mergedMonotonic(with: rebuiltCounters)
        let countersNeedWrite = counterLoadResult.source != .current
            || counters != counterLoadResult.counters
            || counterLoadResult.unreadableURLs.contains(countersBackupFileURL)
        let countersCanBeRepaired = prepareForRepair(
            unreadableURLs: counterLoadResult.unreadableURLs,
            hasRecoverableSource: counterLoadResult.source != .rebuilt,
            recoveryProblems: &recoveryProblems,
            preservedDamagedPaths: &preservedDamagedPaths
        )

        if countersNeedWrite, countersCanBeRepaired {
            do {
                try write(counters: counters, rotatesBackup: counterLoadResult.source == .current)
            } catch {
                recoveryProblems.append("could not restore \(countersFileURL.path): \(error.localizedDescription)")
            }
        }

        let issue: MetricsStoreLoadIssue?
        if !recoveryProblems.isEmpty {
            issue = .recoveryProblems(recoveryProblems)
        } else if !preservedDamagedPaths.isEmpty {
            issue = .recoveredFiles(Array(Set(preservedDamagedPaths)).sorted())
        } else {
            issue = nil
        }
        return MetricsStoreState(records: records, counters: counters, issue: issue)
    }

    func save(records: [TranscriptMetricsRecord], counters: MetricsCounters) throws {
        try write(records: records, rotatesBackup: true)
        try write(counters: counters, rotatesBackup: true)
    }

    /// Persists a statistics display-window change without rewriting transcript
    /// metrics history. The records remain the durable source of truth and can
    /// still be exported or used to rebuild lifetime counters.
    func save(counters: MetricsCounters) throws {
        try write(counters: counters, rotatesBackup: true)
    }

    /// A display reset is a checkpoint, not an ordinary counter update. Write
    /// the recoverable backup first and the primary second so a reset reported
    /// as successful always survives loss of either active copy.
    func saveDisplayReset(counters: MetricsCounters) throws {
        try fileManager.createDirectory(
            at: metricsDirectoryURL,
            withIntermediateDirectories: true
        )
        for url in [countersFileURL, countersBackupFileURL]
        where fileManager.fileExists(atPath: url.path) {
            let existing: MetricsFileReadResult<MetricsCounters> = read(
                MetricsCounters.self,
                at: url
            )
            guard !existing.isUnreadable else {
                throw MetricsStoreSaveError.unreadablePrimary(url.path)
            }
        }

        let data = try makeEncoder().encode(counters)
        try data.write(to: countersBackupFileURL, options: .atomic)
        try data.write(to: countersFileURL, options: .atomic)
    }

    private static func defaultBaseDirectory() -> URL {
        AppStoragePaths.applicationSupportDirectory()
    }

    private func loadRecords(seedHistory: [TranscriptItem]) -> MetricsRecordLoadResult {
        let primaryResult: MetricsFileReadResult<[TranscriptMetricsRecord]> = read(
            [TranscriptMetricsRecord].self,
            at: metricsHistoryFileURL
        )
        let backupResult: MetricsFileReadResult<[TranscriptMetricsRecord]> = read(
            [TranscriptMetricsRecord].self,
            at: metricsHistoryBackupFileURL
        )

        if let records = primaryResult.value {
            return MetricsRecordLoadResult(
                records: records,
                source: .current,
                unreadableURLs: backupResult.isUnreadable ? [metricsHistoryBackupFileURL] : []
            )
        }

        if let records = backupResult.value {
            return MetricsRecordLoadResult(
                records: records,
                source: .backup,
                unreadableURLs: primaryResult.isUnreadable ? [metricsHistoryFileURL] : []
            )
        }

        let legacyResult: MetricsFileReadResult<[TranscriptMetricsRecord]> = read(
            [TranscriptMetricsRecord].self,
            at: legacyMetricsFileURL
        )
        let legacyBackupResult: MetricsFileReadResult<[TranscriptMetricsRecord]> = read(
            [TranscriptMetricsRecord].self,
            at: legacyMetricsBackupFileURL
        )

        if let records = legacyResult.value ?? legacyBackupResult.value {
            let unreadableURLs = [
                primaryResult.isUnreadable ? metricsHistoryFileURL : nil,
                backupResult.isUnreadable ? metricsHistoryBackupFileURL : nil
            ].compactMap { $0 }
            return MetricsRecordLoadResult(
                records: records,
                source: .legacy,
                unreadableURLs: unreadableURLs
            )
        }

        let unreadableURLs = [
            primaryResult.isUnreadable ? metricsHistoryFileURL : nil,
            backupResult.isUnreadable ? metricsHistoryBackupFileURL : nil,
            legacyResult.isUnreadable ? legacyMetricsFileURL : nil,
            legacyBackupResult.isUnreadable ? legacyMetricsBackupFileURL : nil
        ].compactMap { $0 }
        return MetricsRecordLoadResult(
            records: seedHistory.map(calculator.record(for:)),
            source: .seeded,
            unreadableURLs: unreadableURLs
        )
    }

    private func loadCounters(rebuiltCounters: MetricsCounters) -> MetricsCounterLoadResult {
        let primaryResult: MetricsFileReadResult<MetricsCounters> = read(
            MetricsCounters.self,
            at: countersFileURL
        )
        let backupResult: MetricsFileReadResult<MetricsCounters> = read(
            MetricsCounters.self,
            at: countersBackupFileURL
        )

        if let counters = primaryResult.value {
            return MetricsCounterLoadResult(
                counters: counters,
                source: .current,
                unreadableURLs: backupResult.isUnreadable ? [countersBackupFileURL] : []
            )
        }

        if let counters = backupResult.value {
            return MetricsCounterLoadResult(
                counters: counters,
                source: .backup,
                unreadableURLs: primaryResult.isUnreadable ? [countersFileURL] : []
            )
        }

        let unreadableURLs = [
            primaryResult.isUnreadable ? countersFileURL : nil,
            backupResult.isUnreadable ? countersBackupFileURL : nil
        ].compactMap { $0 }
        return MetricsCounterLoadResult(
            counters: rebuiltCounters,
            source: .rebuilt,
            unreadableURLs: unreadableURLs
        )
    }

    private func read<Value: Decodable>(_ type: Value.Type, at url: URL) -> MetricsFileReadResult<Value> {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        guard let data = try? Data(contentsOf: url) else {
            return .unreadable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(type, from: data) else {
            return .unreadable
        }
        return .readable(value)
    }

    private func prepareForRepair(
        unreadableURLs: [URL],
        hasRecoverableSource: Bool,
        recoveryProblems: inout [String],
        preservedDamagedPaths: inout [String]
    ) -> Bool {
        guard !unreadableURLs.isEmpty else {
            return true
        }

        guard hasRecoverableSource else {
            recoveryProblems.append(
                "unreadable files left untouched: \(unreadableURLs.map(\.path).joined(separator: ", "))"
            )
            return false
        }

        for url in unreadableURLs {
            do {
                try preserveCorruptFile(at: url)
                preservedDamagedPaths.append(url.path)
            } catch {
                recoveryProblems.append(
                    "could not preserve \(url.path): \(error.localizedDescription)"
                )
                return false
            }
        }
        return true
    }

    private func preserveCorruptFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        let fileExtension = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let preservedFilename = fileExtension.isEmpty
            ? "\(stem).corrupt-\(UUID().uuidString)"
            : "\(stem).corrupt-\(UUID().uuidString).\(fileExtension)"
        let preservedURL = url.deletingLastPathComponent().appendingPathComponent(preservedFilename)
        try fileManager.copyItem(at: url, to: preservedURL)
    }

    private func write(records: [TranscriptMetricsRecord], rotatesBackup: Bool) throws {
        try fileManager.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
        if rotatesBackup, fileManager.fileExists(atPath: metricsHistoryFileURL.path) {
            let primary: MetricsFileReadResult<[TranscriptMetricsRecord]> = read(
                [TranscriptMetricsRecord].self,
                at: metricsHistoryFileURL
            )
            guard !primary.isUnreadable else {
                throw MetricsStoreSaveError.unreadablePrimary(metricsHistoryFileURL.path)
            }
            try updateBackup(from: metricsHistoryFileURL, to: metricsHistoryBackupFileURL)
        }

        try makeEncoder()
            .encode(sort(records))
            .write(to: metricsHistoryFileURL, options: .atomic)
    }

    private func write(counters: MetricsCounters, rotatesBackup: Bool) throws {
        try fileManager.createDirectory(at: metricsDirectoryURL, withIntermediateDirectories: true)
        if rotatesBackup, fileManager.fileExists(atPath: countersFileURL.path) {
            let primary: MetricsFileReadResult<MetricsCounters> = read(
                MetricsCounters.self,
                at: countersFileURL
            )
            guard !primary.isUnreadable else {
                throw MetricsStoreSaveError.unreadablePrimary(countersFileURL.path)
            }
            try updateBackup(from: countersFileURL, to: countersBackupFileURL)
        }

        try makeEncoder()
            .encode(counters)
            .write(to: countersFileURL, options: .atomic)
    }

    private func updateBackup(from primaryURL: URL, to backupURL: URL) throws {
        try fileManager.shuoUpdateBackup(from: primaryURL, to: backupURL)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func sort(_ records: [TranscriptMetricsRecord]) -> [TranscriptMetricsRecord] {
        records.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

private struct MetricsRecordLoadResult {
    let records: [TranscriptMetricsRecord]
    let source: MetricsRecordSource
    let unreadableURLs: [URL]
}

private struct MetricsCounterLoadResult {
    let counters: MetricsCounters
    let source: MetricsCounterSource
    let unreadableURLs: [URL]
}

private enum MetricsRecordSource: Equatable {
    case current
    case backup
    case legacy
    case seeded
}

private enum MetricsCounterSource: Equatable {
    case current
    case backup
    case rebuilt
}

private enum MetricsFileReadResult<Value> {
    case missing
    case readable(Value)
    case unreadable

    var value: Value? {
        guard case .readable(let value) = self else {
            return nil
        }
        return value
    }

    var isUnreadable: Bool {
        if case .unreadable = self {
            return true
        }
        return false
    }
}
