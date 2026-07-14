import Foundation

struct AdaptiveRecognitionStoreLoadResult {
    let state: AdaptiveRecognitionState
    let issue: RecoverableJSONStoreLoadIssue?
}

struct AdaptiveRecognitionStore {
    private let key: String
    private let userDefaults: UserDefaults
    private let fileStore: RecoverableJSONStore<AdaptiveRecognitionState>

    private var fileRevisionKey: String { "\(key).fileRevision" }
    private var mirrorRevisionKey: String { "\(key).mirrorRevision" }

    var stateFileURL: URL { fileStore.fileURL }
    var backupFileURL: URL { fileStore.backupFileURL }
    var directoryURL: URL { fileStore.directoryURL }

    init(
        key: String = "adaptiveRecognitionState",
        userDefaults: UserDefaults = .standard,
        baseDirectory: URL = AppStoragePaths.applicationSupportDirectory(),
        fileManager: FileManager = .default
    ) {
        self.key = key
        self.userDefaults = userDefaults
        fileStore = RecoverableJSONStore(
            baseDirectory: baseDirectory,
            directoryName: "Personalization",
            fileName: "adaptive-recognition.json",
            backupFileName: "adaptive-recognition.backup.json",
            fileManager: fileManager
        )
    }

    func load() -> AdaptiveRecognitionState {
        loadResult().state
    }

    func loadResult() -> AdaptiveRecognitionStoreLoadResult {
        let fileResult = fileStore.load()
        let fileRevision = revision(forKey: fileRevisionKey) ?? 0
        if let mirrorRevision = revision(forKey: mirrorRevisionKey),
           shouldPreferMirror(
               mirrorRevision: mirrorRevision,
               fileRevision: fileRevision,
               fileSource: fileResult.source
           ),
           let mirrorState = stateInUserDefaults() {
            return loadNewerMirror(
                mirrorState,
                revision: mirrorRevision,
                fileResult: fileResult
            )
        }

        if let state = fileResult.value {
            return AdaptiveRecognitionStoreLoadResult(state: state, issue: fileResult.issue)
        }

        guard let legacyState = stateInUserDefaults() else {
            return AdaptiveRecognitionStoreLoadResult(
                state: AdaptiveRecognitionState(),
                issue: fileResult.issue
            )
        }

        // If durable files are damaged, keep using the intact UserDefaults
        // mirror without overwriting either damaged file. Otherwise this is a
        // first-run migration and a file-backed copy can be created safely.
        if fileResult.source == .missing {
            do {
                try fileStore.save(legacyState)
                recordSynchronizedRevision(nextRevision())
            } catch {
                return AdaptiveRecognitionStoreLoadResult(
                    state: legacyState,
                    issue: .repairFailed(error.localizedDescription)
                )
            }
        }
        return AdaptiveRecognitionStoreLoadResult(state: legacyState, issue: fileResult.issue)
    }

    private func shouldPreferMirror(
        mirrorRevision: Int,
        fileRevision: Int,
        fileSource: RecoverableJSONStoreSource
    ) -> Bool {
        if mirrorRevision > fileRevision {
            return true
        }

        // A successful save keeps the primary file and UserDefaults mirror at
        // the same revision, while the rotated backup necessarily contains an
        // older state. If the primary is later damaged and the generic store
        // recovers that backup, the equal-revision mirror is still the newest
        // authoritative copy. This also prevents data cleared in the latest
        // revision from being resurrected by its pre-clear backup.
        return fileSource == .backup
            && mirrorRevision > 0
            && mirrorRevision == fileRevision
    }

    func save(_ state: AdaptiveRecognitionState) throws {
        let mirrorData = try JSONEncoder().encode(state)
        let revision = nextRevision()
        do {
            try fileStore.save(state)
            saveInUserDefaults(mirrorData)
            recordSynchronizedRevision(revision)
        } catch {
            // If the durable file cannot be updated, retain the newest state in
            // the mirror as an emergency fallback. Advancing only its revision
            // ensures a readable but stale primary cannot resurrect old state.
            saveInUserDefaults(mirrorData)
            userDefaults.set(revision, forKey: mirrorRevisionKey)
            throw error
        }
    }

    private func loadNewerMirror(
        _ mirrorState: AdaptiveRecognitionState,
        revision: Int,
        fileResult: RecoverableJSONStoreLoadResult<AdaptiveRecognitionState>
    ) -> AdaptiveRecognitionStoreLoadResult {
        // A failed RecoverableJSONStore repair may leave an unreadable primary
        // beside the only readable backup. Calling save in that state would
        // rotate the damaged primary over the backup, so keep both untouched.
        guard canSafelyRepair(fileResult) else {
            return AdaptiveRecognitionStoreLoadResult(
                state: mirrorState,
                issue: fileResult.issue
                    ?? .repairFailed("The existing personalization files could not be repaired safely.")
            )
        }

        do {
            try fileStore.save(mirrorState)
            userDefaults.set(revision, forKey: fileRevisionKey)
            return AdaptiveRecognitionStoreLoadResult(
                state: mirrorState,
                issue: fileResult.issue
            )
        } catch {
            return AdaptiveRecognitionStoreLoadResult(
                state: mirrorState,
                issue: .repairFailed(error.localizedDescription)
            )
        }
    }

    private func canSafelyRepair(
        _ fileResult: RecoverableJSONStoreLoadResult<AdaptiveRecognitionState>
    ) -> Bool {
        if case .repairFailed = fileResult.issue {
            return false
        }
        return fileResult.source != .unrecoverable
    }

    private func stateInUserDefaults() -> AdaptiveRecognitionState? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(AdaptiveRecognitionState.self, from: data)
    }

    private func saveInUserDefaults(_ data: Data) {
        userDefaults.set(data, forKey: key)
    }

    private func revision(forKey key: String) -> Int? {
        guard let number = userDefaults.object(forKey: key) as? NSNumber else {
            return nil
        }
        return max(0, number.intValue)
    }

    private func nextRevision() -> Int {
        let currentRevision = max(
            revision(forKey: fileRevisionKey) ?? 0,
            revision(forKey: mirrorRevisionKey) ?? 0
        )
        return currentRevision == Int.max ? Int.max : currentRevision + 1
    }

    private func recordSynchronizedRevision(_ revision: Int) {
        userDefaults.set(revision, forKey: fileRevisionKey)
        userDefaults.set(revision, forKey: mirrorRevisionKey)
    }
}
