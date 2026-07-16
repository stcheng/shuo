import AppKit
import ApplicationServices
import XCTest
@testable import Shuo

final class ThirdPartyNoticeBundleTests: XCTestCase {
    func testRequiredThirdPartyNoticesAreBundled() throws {
        let resourcesURL = try XCTUnwrap(Bundle.main.resourceURL)
        let requiredPaths = [
            "LICENSE",
            "THIRD_PARTY_NOTICES.md",
            "ThirdParty/Sparkle-LICENSE.txt",
            "ThirdParty/OpenAI-Whisper-LICENSE.txt",
            "ThirdParty/Unicode-CLDR-LICENSE.txt"
        ]

        for path in requiredPaths {
            let resourceURL = resourcesURL.appendingPathComponent(path)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resourceURL.path),
                "Missing bundled third-party notice: \(path)"
            )
        }
    }
}

@MainActor
final class PasteboardContentsSnapshotTests: XCTestCase {
    func testSnapshotRestoresAllItemsAndRepresentations() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let customType = NSPasteboard.PasteboardType("dev.shuotian.Shuo.test-data")
        let firstItem = NSPasteboardItem()
        firstItem.setString("formatted text", forType: .string)
        firstItem.setData(Data([0x01, 0x02, 0x03]), forType: customType)
        let secondItem = NSPasteboardItem()
        secondItem.setString("second item", forType: .string)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([firstItem, secondItem]))

        let snapshot = try XCTUnwrap(PasteboardContentsSnapshot.capture(from: pasteboard))
        pasteboard.clearContents()
        pasteboard.setString("Shuo transcript", forType: .string)
        let injectedChangeCount = pasteboard.changeCount

        XCTAssertTrue(snapshot.restore(to: pasteboard, ifUnchangedSince: injectedChangeCount))
        let restoredItems = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restoredItems.count, 2)
        XCTAssertEqual(restoredItems[0].string(forType: .string), "formatted text")
        XCTAssertEqual(restoredItems[0].data(forType: customType), Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(restoredItems[1].string(forType: .string), "second item")
    }

    func testSnapshotDoesNotOverwriteAUserClipboardChange() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = try XCTUnwrap(PasteboardContentsSnapshot.capture(from: pasteboard))

        pasteboard.clearContents()
        pasteboard.setString("Shuo transcript", forType: .string)
        let injectedChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("new user copy", forType: .string)

        XCTAssertFalse(snapshot.restore(to: pasteboard, ifUnchangedSince: injectedChangeCount))
        XCTAssertEqual(pasteboard.string(forType: .string), "new user copy")
    }

    func testMalformedPrivatePasteboardTypesAreSkippedOnlyWhenUnreadable() {
        let malformed = NSPasteboard.PasteboardType(
            "com.trolltech.anymime.WeChat_RichEdit_Format"
        )

        XCTAssertTrue(PasteboardContentsSnapshot.shouldSkipUnreadableMalformedType(malformed))
        XCTAssertFalse(PasteboardContentsSnapshot.shouldSkipUnreadableMalformedType(.string))
        XCTAssertEqual(PasteboardContentsSnapshot.captureTimeout, 0.35, accuracy: 0.001)
    }

    func testSlowPasteboardOwnerTimesOutWithoutBlockingMainActor() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let coordinator = PasteboardSnapshotCaptureCoordinator()
        let provider = SlowPasteboardDataProvider(delay: 0.5)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let startedAt = Date()

        let snapshot = await PasteboardContentsSnapshot.captureWithoutBlockingMain(
            from: pasteboard,
            timeout: 0.05,
            coordinator: coordinator
        )

        XCTAssertNil(snapshot)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.25)
        withExtendedLifetime(provider) {}
    }

    func testTimedOutPasteboardOwnerAllowsOnlyOneOutstandingCapture() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let coordinator = PasteboardSnapshotCaptureCoordinator()
        let provider = SlowPasteboardDataProvider(delay: 0.5)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        _ = await PasteboardContentsSnapshot.captureWithoutBlockingMain(
            from: pasteboard,
            timeout: 0.05,
            coordinator: coordinator
        )
        let secondStartedAt = Date()
        let second = await PasteboardContentsSnapshot.captureWithoutBlockingMain(
            from: pasteboard,
            timeout: 0.05,
            coordinator: coordinator
        )

        XCTAssertNil(second)
        XCTAssertLessThan(Date().timeIntervalSince(secondStartedAt), 0.05)
        XCTAssertLessThanOrEqual(provider.requestCount, 1)
        withExtendedLifetime(provider) {}
    }

    func testPasteRefusesToOverwriteClipboardWhenSlowOwnerCannotBeCaptured() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let coordinator = PasteboardSnapshotCaptureCoordinator()
        let provider = SlowPasteboardDataProvider(delay: 0.5)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let result = await PasteboardInjector(
            pasteboard: pasteboard,
            snapshotCaptureCoordinator: coordinator
        ).paste(
            "Shuo transcript",
            restoreClipboard: true
        )

        XCTAssertEqual(result, .clipboardSnapshotUnavailable)
        XCTAssertEqual(pasteboard.string(forType: .string), "delayed value")
        withExtendedLifetime(provider) {}
    }

    func testCopyDoesNotRaceAnOutstandingPasteboardSnapshot() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let coordinator = PasteboardSnapshotCaptureCoordinator()
        let provider = SlowPasteboardDataProvider(delay: 0.5)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let originalChangeCount = pasteboard.changeCount

        _ = await PasteboardContentsSnapshot.captureWithoutBlockingMain(
            from: pasteboard,
            timeout: 0.05,
            coordinator: coordinator
        )
        XCTAssertTrue(coordinator.isCaptureInFlight)

        PasteboardInjector(
            pasteboard: pasteboard,
            snapshotCaptureCoordinator: coordinator
        ).copy("must not overwrite a resolving owner")

        XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
        withExtendedLifetime(provider) {}
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("dev.shuotian.Shuo.tests.\(UUID().uuidString)"))
    }
}

private final class SlowPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    private let delay: TimeInterval
    private let lock = NSLock()
    private var requests = 0

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        lock.lock()
        requests += 1
        lock.unlock()
        Thread.sleep(forTimeInterval: delay)
        item.setString("delayed value", forType: type)
    }
}

final class TranscriptHistoryCorruptionTests: XCTestCase {
    func testStartupRecoveryNeverMutatesHistoryAfterAnyLoadIssue() {
        XCTAssertTrue(
            StartupHistoryReconciliationPolicy.allowsAutomaticMutation(after: nil)
        )
        XCTAssertFalse(
            StartupHistoryReconciliationPolicy.allowsAutomaticMutation(
                after: .unreadableFiles(["transcripts.json"])
            )
        )
        XCTAssertFalse(
            StartupHistoryReconciliationPolicy.allowsAutomaticMutation(
                after: .couldNotPreserveCorruptFile("transcripts.json")
            )
        )
        XCTAssertFalse(
            StartupHistoryReconciliationPolicy.allowsAutomaticMutation(
                after: .repairFailed("disk full")
            )
        )
        XCTAssertTrue(
            StartupHistoryReconciliationPolicy.allowsAutomaticMutation(
                after: .recoveredFiles(["transcripts.json"])
            )
        )
        XCTAssertTrue(
            StartupHistoryReconciliationPolicy.allowsAutomaticMutation(
                after: .completedPendingDeletion
            )
        )
    }

    func testRecoveredHistoryReportsWhenRepairCannotBePersisted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("blocks-history-directory".utf8).write(
            to: directory.appendingPathComponent("History")
        )

        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recoveredItem = TranscriptItem(
            text: "recover me",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        defaults.set(try JSONEncoder().encode([recoveredItem]), forKey: "history")

        let result = TranscriptHistoryStore(
            baseDirectory: directory,
            userDefaults: defaults
        ).loadResult()

        XCTAssertEqual(result.items, [recoveredItem])
        guard case .repairFailed = result.issue else {
            return XCTFail("Expected a visible repair failure")
        }
    }

    func testUnrecoverableHistoryFilesAreNeverOverwrittenWithAnEmptyHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TranscriptHistoryStore(baseDirectory: directory, userDefaults: defaults)
        try FileManager.default.createDirectory(
            at: store.historyDirectoryURL,
            withIntermediateDirectories: true
        )
        let primaryData = Data("corrupt-primary".utf8)
        let backupData = Data("corrupt-backup".utf8)
        try primaryData.write(to: store.historyFileURL)
        try backupData.write(to: store.backupFileURL)

        let result = store.loadResult()

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNotNil(result.issue)
        XCTAssertEqual(try Data(contentsOf: store.historyFileURL), primaryData)
        XCTAssertEqual(try Data(contentsOf: store.backupFileURL), backupData)
    }

    func testSaveRefusesToRotateUnreadablePrimaryOverGoodHistoryBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranscriptHistoryStore(baseDirectory: directory)
        let first = TranscriptItem(
            text: "good backup",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let second = TranscriptItem(
            text: "previous primary",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        try store.save([first])
        try store.save([second])
        let goodBackup = try Data(contentsOf: store.backupFileURL)
        let corruptPrimary = Data("corrupt-primary".utf8)
        try corruptPrimary.write(to: store.historyFileURL, options: .atomic)

        XCTAssertThrowsError(try store.save([])) { error in
            guard case TranscriptHistorySaveError.unreadablePrimary = error else {
                return XCTFail("Expected fail-closed unreadable-primary error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: store.historyFileURL), corruptPrimary)
        XCTAssertEqual(try Data(contentsOf: store.backupFileURL), goodBackup)
    }

    func testRecoveredHistoryPreservesTheCorruptPrimaryForDiagnostics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TranscriptHistoryStore(baseDirectory: directory, userDefaults: defaults)
        let recoveredItem = TranscriptItem(
            text: "recover me",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        try store.save([recoveredItem])
        try store.save([])
        let corruptData = Data("corrupt-primary".utf8)
        try corruptData.write(to: store.historyFileURL, options: .atomic)

        let result = store.loadResult()

        XCTAssertEqual(result.items, [recoveredItem])
        guard case .recoveredFiles(let paths) = result.issue else {
            return XCTFail("Expected a visible successful-recovery warning")
        }
        XCTAssertEqual(paths, [store.historyFileURL.path])
        let files = try FileManager.default.contentsOfDirectory(
            at: store.historyDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let preservedURL = try XCTUnwrap(
            files.first { $0.lastPathComponent.hasPrefix("transcripts.corrupt-") }
        )
        XCTAssertEqual(try Data(contentsOf: preservedURL), corruptData)
    }

    func testRecoveredHistoryReportsAndRepairsCorruptBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranscriptHistoryStore(baseDirectory: directory)
        let item = TranscriptItem(
            text: "primary remains good",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        _ = store.loadResult()
        try store.save([item])
        try Data("corrupt-backup".utf8).write(
            to: store.backupFileURL,
            options: .atomic
        )

        let result = store.loadResult()

        XCTAssertEqual(result.items, [item])
        guard case .recoveredFiles(let paths) = result.issue else {
            return XCTFail("Expected a visible backup-recovery warning")
        }
        XCTAssertEqual(paths, [store.backupFileURL.path])
        let repairedBackup = try JSONDecoder().decode(
            [TranscriptItem].self,
            from: Data(contentsOf: store.backupFileURL)
        )
        XCTAssertEqual(repairedBackup, [item])
    }
}

final class MetricsStoreCorruptionTests: XCTestCase {
    func testUnrecoverableMetricsFilesAreLeftUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(baseDirectory: directory)
        try FileManager.default.createDirectory(
            at: store.historyDirectoryURL,
            withIntermediateDirectories: true
        )
        let primaryData = Data("corrupt-metrics-primary".utf8)
        let backupData = Data("corrupt-metrics-backup".utf8)
        try primaryData.write(to: store.metricsHistoryFileURL)
        try backupData.write(to: store.metricsHistoryBackupFileURL)

        let result = store.load(seedHistory: [])

        XCTAssertNotNil(result.issue)
        XCTAssertEqual(try Data(contentsOf: store.metricsHistoryFileURL), primaryData)
        XCTAssertEqual(try Data(contentsOf: store.metricsHistoryBackupFileURL), backupData)
    }

    func testRecoveredMetricsPreserveCorruptPrimaryForDiagnostics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(baseDirectory: directory)
        let item = TranscriptItem(
            text: "recover metrics",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        )
        let calculator = MetricsCalculator()
        let record = calculator.record(for: item)
        try store.save(records: [record], counters: calculator.counters(from: [record]))
        try store.save(records: [], counters: calculator.counters(from: []))
        let corruptData = Data("corrupt-metrics-primary".utf8)
        try corruptData.write(to: store.metricsHistoryFileURL, options: .atomic)

        let result = store.load(seedHistory: [])

        XCTAssertEqual(result.records.map(\.id), [record.id])
        guard case .recoveredFiles(let paths) = result.issue else {
            return XCTFail("Expected visible successful metrics recovery")
        }
        XCTAssertTrue(paths.contains(store.metricsHistoryFileURL.path))
        let files = try FileManager.default.contentsOfDirectory(
            at: store.historyDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let preservedURL = try XCTUnwrap(
            files.first { $0.lastPathComponent.hasPrefix("metrics-history.corrupt-") }
        )
        XCTAssertEqual(try Data(contentsOf: preservedURL), corruptData)
    }

    func testSaveRefusesToRotateUnreadableMetricsPrimaryOverGoodBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(baseDirectory: directory)
        let calculator = MetricsCalculator()
        let firstRecord = calculator.record(for: TranscriptItem(
            text: "good backup",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        ))
        let secondRecord = calculator.record(for: TranscriptItem(
            text: "previous primary",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed
        ))
        try store.save(
            records: [firstRecord],
            counters: calculator.counters(from: [firstRecord])
        )
        try store.save(
            records: [secondRecord],
            counters: calculator.counters(from: [secondRecord])
        )
        let goodBackup = try Data(contentsOf: store.metricsHistoryBackupFileURL)
        let corruptPrimary = Data("corrupt-metrics-primary".utf8)
        try corruptPrimary.write(to: store.metricsHistoryFileURL, options: .atomic)

        XCTAssertThrowsError(try store.save(
            records: [],
            counters: calculator.counters(from: [])
        )) { error in
            guard case MetricsStoreSaveError.unreadablePrimary = error else {
                return XCTFail("Expected fail-closed unreadable-primary error: \(error)")
            }
        }
        XCTAssertEqual(
            try Data(contentsOf: store.metricsHistoryFileURL),
            corruptPrimary
        )
        XCTAssertEqual(
            try Data(contentsOf: store.metricsHistoryBackupFileURL),
            goodBackup
        )
    }

    func testUnrecoverableCounterFilesAreLeftUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(baseDirectory: directory)
        try FileManager.default.createDirectory(
            at: store.metricsDirectoryURL,
            withIntermediateDirectories: true
        )
        let primaryData = Data("corrupt-counters-primary".utf8)
        let backupData = Data("corrupt-counters-backup".utf8)
        try primaryData.write(to: store.countersFileURL)
        try backupData.write(to: store.countersBackupFileURL)

        let result = store.load(seedHistory: [])

        XCTAssertNotNil(result.issue)
        XCTAssertEqual(try Data(contentsOf: store.countersFileURL), primaryData)
        XCTAssertEqual(try Data(contentsOf: store.countersBackupFileURL), backupData)
    }

    func testSaveRefusesToRotateUnreadableCountersPrimaryOverGoodBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(baseDirectory: directory)
        let first = MetricsCounters.empty.resettingDisplay(
            at: Date(timeIntervalSince1970: 100)
        )
        let second = MetricsCounters.empty.resettingDisplay(
            at: Date(timeIntervalSince1970: 200)
        )
        try store.save(counters: first)
        try store.save(counters: second)
        let goodBackup = try Data(contentsOf: store.countersBackupFileURL)
        let corruptPrimary = Data("corrupt-counters-primary".utf8)
        try corruptPrimary.write(to: store.countersFileURL, options: .atomic)

        XCTAssertThrowsError(try store.save(counters: .empty)) { error in
            guard case MetricsStoreSaveError.unreadablePrimary = error else {
                return XCTFail("Expected fail-closed unreadable-primary error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: store.countersFileURL), corruptPrimary)
        XCTAssertEqual(try Data(contentsOf: store.countersBackupFileURL), goodBackup)
    }

    func testCounterBackupRecoveryPreservesDisplayCutoff() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(baseDirectory: directory)
        let cutoff = Date(timeIntervalSince1970: 200)
        let resetCounters = MetricsCounters.empty.resettingDisplay(at: cutoff)

        try store.saveDisplayReset(counters: resetCounters)
        let corruptData = Data("corrupt-reset-counters".utf8)
        try corruptData.write(to: store.countersFileURL, options: .atomic)

        let result = store.load(seedHistory: [])

        XCTAssertEqual(result.counters.displayCutoff, cutoff)
        guard case .recoveredFiles(let paths) = result.issue else {
            return XCTFail("Expected visible successful counter recovery")
        }
        XCTAssertTrue(paths.contains(store.countersFileURL.path))
        let files = try FileManager.default.contentsOfDirectory(
            at: store.metricsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let preservedURL = try XCTUnwrap(
            files.first { $0.lastPathComponent.hasPrefix("counters.corrupt-") }
        )
        XCTAssertEqual(try Data(contentsOf: preservedURL), corruptData)
    }
}

final class AdaptiveRecognitionStoreReliabilityTests: XCTestCase {
    func testSuccessfulSaveUpdatesFileAndCompatibilityMirrorTogether() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        let state = makeState(preferredText: "synchronized")

        try store.save(state)

        let mirrorData = try XCTUnwrap(
            defaults.defaults.data(forKey: "adaptiveRecognitionState")
        )
        XCTAssertEqual(
            try JSONDecoder().decode(AdaptiveRecognitionState.self, from: mirrorData),
            state
        )
        XCTAssertEqual(
            defaults.defaults.integer(forKey: "adaptiveRecognitionState.fileRevision"),
            1
        )
        XCTAssertEqual(
            defaults.defaults.integer(forKey: "adaptiveRecognitionState.mirrorRevision"),
            1
        )
        XCTAssertEqual(store.load(), state)
    }

    func testNewerEmergencyMirrorWinsOverReadableStalePrimaryAndRepairsIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        let staleState = makeState(preferredText: "stale-file")
        let emergencyState = makeState(preferredText: "newer-mirror")
        try store.save(staleState)
        defaults.defaults.set(
            try JSONEncoder().encode(emergencyState),
            forKey: "adaptiveRecognitionState"
        )
        defaults.defaults.set(
            2,
            forKey: "adaptiveRecognitionState.mirrorRevision"
        )

        let result = store.loadResult()

        XCTAssertEqual(result.state, emergencyState)
        XCTAssertNil(result.issue)
        XCTAssertEqual(
            defaults.defaults.integer(forKey: "adaptiveRecognitionState.fileRevision"),
            2
        )
        let repairedData = try Data(contentsOf: store.stateFileURL)
        XCTAssertEqual(
            try JSONDecoder().decode(AdaptiveRecognitionState.self, from: repairedData),
            emergencyState
        )
    }

    func testReadableFileWinsOverUnversionedLegacyMirror() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        let fileState = makeState(preferredText: "durable-file")
        let legacyMirrorState = makeState(preferredText: "legacy-mirror")
        try FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(fileState).write(to: store.stateFileURL)
        defaults.defaults.set(
            try JSONEncoder().encode(legacyMirrorState),
            forKey: "adaptiveRecognitionState"
        )

        let result = store.loadResult()

        XCTAssertEqual(result.state, fileState)
        XCTAssertNil(result.issue)
        XCTAssertNil(
            defaults.defaults.object(forKey: "adaptiveRecognitionState.fileRevision")
        )
        XCTAssertNil(
            defaults.defaults.object(forKey: "adaptiveRecognitionState.mirrorRevision")
        )
    }

    func testFailedFileSaveKeepsNewerMirrorAndReportsFailedRepair() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-a-directory".utf8).write(to: directory)
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        let emergencyState = makeState(preferredText: "emergency")

        XCTAssertThrowsError(try store.save(emergencyState))
        XCTAssertEqual(
            defaults.defaults.integer(forKey: "adaptiveRecognitionState.mirrorRevision"),
            1
        )
        XCTAssertNil(
            defaults.defaults.object(forKey: "adaptiveRecognitionState.fileRevision")
        )

        let result = store.loadResult()

        XCTAssertEqual(result.state, emergencyState)
        guard case .repairFailed = result.issue else {
            return XCTFail("Expected the emergency mirror repair failure to remain visible")
        }
    }

    func testMigratesUserDefaultsStateWithoutRemovingCompatibilityCopy() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let state = makeState(preferredText: "Shuo")
        defaults.defaults.set(try JSONEncoder().encode(state), forKey: "adaptiveRecognitionState")
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )

        let result = store.loadResult()

        XCTAssertEqual(result.state, state)
        XCTAssertNil(result.issue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stateFileURL.path))
        XCTAssertNotNil(defaults.defaults.data(forKey: "adaptiveRecognitionState"))
    }

    func testVersionedMirrorWinsAfterBackupRecoveryAndPreservesDamagedPrimary() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        let recoverableState = makeState(preferredText: "recoverable")
        let newerState = makeState(preferredText: "newer")
        try store.save(recoverableState)
        try store.save(newerState)
        let damagedData = Data("damaged-primary".utf8)
        try damagedData.write(to: store.stateFileURL, options: .atomic)

        let result = store.loadResult()

        XCTAssertEqual(result.state, newerState)
        XCTAssertNotNil(result.issue)
        let preservedURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: store.directoryURL,
                includingPropertiesForKeys: nil
            ).first { $0.lastPathComponent.hasPrefix("adaptive-recognition.corrupt-") }
        )
        XCTAssertEqual(try Data(contentsOf: preservedURL), damagedData)
        XCTAssertEqual(
            try JSONDecoder().decode(
                AdaptiveRecognitionState.self,
                from: Data(contentsOf: store.stateFileURL)
            ),
            newerState
        )
    }

    func testClearedCorrectionStateCannotBeResurrectedByBackupRecovery() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        try store.save(makeState(preferredText: "old-correction"))
        let cutoff = Date(timeIntervalSince1970: 1_750_000_000)
        let clearedState = AdaptiveRecognitionState(learningResetAt: cutoff)
        try store.save(clearedState)
        try Data("damaged-primary".utf8).write(to: store.stateFileURL, options: .atomic)

        let result = store.loadResult()

        XCTAssertEqual(result.state, clearedState)
        XCTAssertTrue(result.state.correctionEvents.isEmpty)
        XCTAssertTrue(result.state.feedbackEvents.isEmpty)
        XCTAssertTrue(result.state.learnedPreferences.isEmpty)
        XCTAssertEqual(
            try JSONDecoder().decode(
                AdaptiveRecognitionState.self,
                from: Data(contentsOf: store.stateFileURL)
            ),
            clearedState
        )
    }

    func testDamagedFilesAreNotOverwrittenWhenUserDefaultsMirrorIsReadable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let mirrorState = makeState(preferredText: "mirror")
        defaults.defaults.set(try JSONEncoder().encode(mirrorState), forKey: "adaptiveRecognitionState")
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        try FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
        let primaryData = Data("damaged-primary".utf8)
        let backupData = Data("damaged-backup".utf8)
        try primaryData.write(to: store.stateFileURL)
        try backupData.write(to: store.backupFileURL)

        let result = store.loadResult()

        XCTAssertEqual(result.state, mirrorState)
        XCTAssertNotNil(result.issue)
        XCTAssertEqual(try Data(contentsOf: store.stateFileURL), primaryData)
        XCTAssertEqual(try Data(contentsOf: store.backupFileURL), backupData)
    }

    func testSaveRefusesToRotateUnreadablePrimaryOverReadableBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeDefaults()
        defer { defaults.defaults.removePersistentDomain(forName: defaults.name) }
        let store = AdaptiveRecognitionStore(
            userDefaults: defaults.defaults,
            baseDirectory: directory
        )
        try store.save(makeState(preferredText: "older"))
        try store.save(makeState(preferredText: "newer"))
        let intactBackup = try Data(contentsOf: store.backupFileURL)
        let damagedPrimary = Data("damaged-primary".utf8)
        try damagedPrimary.write(to: store.stateFileURL, options: .atomic)

        XCTAssertThrowsError(try store.save(makeState(preferredText: "must-not-rotate"))) { error in
            guard case RecoverableJSONStoreSaveError.unreadablePrimary = error else {
                return XCTFail("Expected unreadable-primary protection, got: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: store.stateFileURL), damagedPrimary)
        XCTAssertEqual(try Data(contentsOf: store.backupFileURL), intactBackup)
    }

    private func makeState(preferredText: String) -> AdaptiveRecognitionState {
        AdaptiveRecognitionState(
            feedbackEvents: [],
            learnedPreferences: [
                AdaptiveRecognitionPreference(
                    kind: .correction,
                    observedText: "shuo",
                    preferredText: preferredText,
                    confidence: 0.9,
                    observationCount: 2
                )
            ]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }
}

final class FocusedTextRewriteSafetyTests: XCTestCase {
    func testAcceptsCollapsedCursorImmediatelyAfterMatchingText() {
        let snapshot = FocusedTextSnapshot(
            text: "Earlier text. 最新一句🙂",
            selectedRange: NSRange(location: "Earlier text. 最新一句🙂".utf16.count, length: 0)
        )

        XCTAssertTrue(snapshot.hasCollapsedCursorImmediatelyAfter("最新一句🙂"))
    }

    func testAcceptsMatchingTextBeforeCursorWhenTheControlHasTrailingContent() {
        let text = "Previous text and trailing content"
        let snapshot = FocusedTextSnapshot(
            text: text,
            selectedRange: NSRange(location: "Previous text".utf16.count, length: 0)
        )

        XCTAssertTrue(snapshot.hasCollapsedCursorImmediatelyAfter("Previous text"))
    }

    func testAcceptsEquivalentAccessibilityLineBreakRepresentations() {
        let paragraphSeparatorSnapshot = FocusedTextSnapshot(
            text: "Earlier\u{2029}Previous text\u{2029}Trailing",
            selectedRange: NSRange(
                location: "Earlier\u{2029}Previous text\u{2029}".utf16.count,
                length: 0
            )
        )
        let windowsLineBreakSnapshot = FocusedTextSnapshot(
            text: "Earlier\r\nPrevious text\r\nTrailing",
            selectedRange: NSRange(
                location: "Earlier\r\nPrevious text\r\n".utf16.count,
                length: 0
            )
        )

        XCTAssertTrue(
            paragraphSeparatorSnapshot.hasCollapsedCursorImmediatelyAfter("Previous text\n")
        )
        XCTAssertTrue(
            windowsLineBreakSnapshot.hasCollapsedCursorImmediatelyAfter("Previous text\n")
        )
    }

    func testRejectsMovedCursorWhenTextImmediatelyBeforeItDoesNotMatch() {
        let text = "Previous text and trailing content"
        let snapshot = FocusedTextSnapshot(
            text: text,
            selectedRange: NSRange(location: "Previous text and".utf16.count, length: 0)
        )

        XCTAssertFalse(snapshot.hasCollapsedCursorImmediatelyAfter("Previous text"))
    }

    func testRejectsSelectionAndMismatchedSuffix() {
        let selectedSnapshot = FocusedTextSnapshot(
            text: "Previous text",
            selectedRange: NSRange(location: "Previous text".utf16.count, length: 1)
        )
        let changedSnapshot = FocusedTextSnapshot(
            text: "Previous changed",
            selectedRange: NSRange(location: "Previous changed".utf16.count, length: 0)
        )

        XCTAssertFalse(selectedSnapshot.hasCollapsedCursorImmediatelyAfter("Previous text"))
        XCTAssertFalse(changedSnapshot.hasCollapsedCursorImmediatelyAfter("Previous text"))
    }

    func testFocusedTextVerificationCanBeScopedToTheTargetApplication() {
        let targetProcessIdentifier: pid_t = 4_242
        let text = "Existing text followed by replacement target"
        let provider = ProcessScopedFocusedTextSnapshotProvider(
            processIdentifier: targetProcessIdentifier,
            snapshot: FocusedTextSnapshot(
                text: text,
                selectedRange: NSRange(location: text.utf16.count, length: 0)
            )
        )

        XCTAssertTrue(provider.hasCollapsedCursorImmediatelyAfter(
            "replacement target",
            applicationProcessIdentifier: targetProcessIdentifier
        ))
        XCTAssertFalse(provider.hasCollapsedCursorImmediatelyAfter(
            "replacement target",
            applicationProcessIdentifier: targetProcessIdentifier + 1
        ))
    }

    @MainActor
    func testPasteboardInjectorForwardsCapturedTargetAndFocusRestoration() throws {
        let target = FocusedTextTarget(
            applicationProcessIdentifier: 4_242,
            element: AXUIElementCreateSystemWide()
        )
        let probe = FocusRestorationProbe()
        let provider = FocusRestoringTextSnapshotProvider(
            target: target,
            probe: probe
        )
        let injector = PasteboardInjector(
            pasteboard: NSPasteboard(name: .init("dev.shuotian.Shuo.focus-test")),
            focusedTextSnapshotProvider: provider
        )

        let captured = try XCTUnwrap(
            injector.focusedTextTarget(applicationProcessIdentifier: 4_242)
        )
        XCTAssertEqual(captured.applicationProcessIdentifier, 4_242)
        XCTAssertTrue(injector.restoreFocus(to: captured))
        XCTAssertEqual(probe.restoreCount, 1)
    }

    @MainActor
    func testUnreliableCursorFallbackMustBeExplicitlyAllowed() {
        let target = FocusedTextTarget(
            applicationProcessIdentifier: 4_242,
            element: AXUIElementCreateSystemWide()
        )
        let probe = FocusRestorationProbe()
        let provider = FocusRestoringTextSnapshotProvider(
            target: target,
            probe: probe
        )
        let injector = PasteboardInjector(
            pasteboard: NSPasteboard(name: .init("dev.shuotian.Shuo.fallback-test")),
            focusedTextSnapshotProvider: provider
        )

        XCTAssertFalse(injector.canSafelyReplacePreviousInsertion(
            "previous",
            targetProcessIdentifier: 4_242,
            focusedTextTarget: target
        ))
        XCTAssertTrue(injector.canSafelyReplacePreviousInsertion(
            "previous",
            targetProcessIdentifier: 4_242,
            focusedTextTarget: target,
            allowsValueSuffixFallback: true
        ))
        XCTAssertEqual(probe.fallbackAllowances, [false, true])
    }

    func testGuardedBackspaceRequiresSameApplicationNoInteractionAndBoundedText() {
        let targetProcessIdentifier: pid_t = 4_242

        XCTAssertTrue(GuardedBackspaceRewritePolicy.allowsRewrite(
            bundleIdentifier: "com.mitchellh.ghostty",
            currentBundleIdentifier: "com.mitchellh.ghostty",
            targetProcessIdentifier: targetProcessIdentifier,
            currentProcessIdentifier: targetProcessIdentifier,
            observedExternalInteraction: false,
            previousText: "latest sentence\n"
        ))
        XCTAssertTrue(GuardedBackspaceRewritePolicy.allowsRewrite(
            bundleIdentifier: "com.example.editor",
            currentBundleIdentifier: "com.example.editor",
            targetProcessIdentifier: targetProcessIdentifier,
            currentProcessIdentifier: targetProcessIdentifier,
            observedExternalInteraction: false,
            previousText: "latest sentence\n"
        ))
        XCTAssertTrue(GuardedBackspaceRewritePolicy.prefersDirectEventDelivery(
            bundleIdentifier: "com.googlecode.iterm2"
        ))
        XCTAssertFalse(GuardedBackspaceRewritePolicy.prefersDirectEventDelivery(
            bundleIdentifier: "com.mitchellh.ghostty"
        ))
        XCTAssertFalse(GuardedBackspaceRewritePolicy.allowsRewrite(
            bundleIdentifier: "com.example.editor",
            currentBundleIdentifier: "com.example.other",
            targetProcessIdentifier: targetProcessIdentifier,
            currentProcessIdentifier: targetProcessIdentifier,
            observedExternalInteraction: false,
            previousText: "latest sentence\n"
        ))
        XCTAssertFalse(GuardedBackspaceRewritePolicy.allowsRewrite(
            bundleIdentifier: "com.mitchellh.ghostty",
            currentBundleIdentifier: "com.mitchellh.ghostty",
            targetProcessIdentifier: targetProcessIdentifier,
            currentProcessIdentifier: targetProcessIdentifier,
            observedExternalInteraction: true,
            previousText: "latest sentence\n"
        ))
        XCTAssertFalse(GuardedBackspaceRewritePolicy.allowsRewrite(
            bundleIdentifier: "com.mitchellh.ghostty",
            currentBundleIdentifier: "com.mitchellh.ghostty",
            targetProcessIdentifier: targetProcessIdentifier,
            currentProcessIdentifier: targetProcessIdentifier,
            observedExternalInteraction: false,
            previousText: String(repeating: "a", count: 1_001)
        ))
        XCTAssertTrue(GuardedBackspaceRewritePolicy.targetOmitsConfiguredTrailingNewline(
            bundleIdentifier: "com.google.Chrome",
            accessibilityRole: kAXTextFieldRole as String
        ))
        XCTAssertFalse(GuardedBackspaceRewritePolicy.targetOmitsConfiguredTrailingNewline(
            bundleIdentifier: "com.mitchellh.ghostty",
            accessibilityRole: kAXTextFieldRole as String
        ))
        XCTAssertTrue(GuardedBackspaceRewritePolicy.hasBlockingReplacementModifiers(.maskCommand))
        XCTAssertTrue(GuardedBackspaceRewritePolicy.hasBlockingReplacementModifiers(.maskAlternate))
        XCTAssertFalse(GuardedBackspaceRewritePolicy.hasBlockingReplacementModifiers([]))
    }

    func testSyntheticKeyboardEventsCarryShuoMarker() throws {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: CGEventSource(stateID: .privateState),
            virtualKey: 0x09,
            keyDown: true
        ))
        ShuoSyntheticEventMarker.mark(event)
        let appKitEvent = try XCTUnwrap(NSEvent(cgEvent: event))

        XCTAssertTrue(ShuoSyntheticEventMarker.isMarked(appKitEvent))
    }

    func testReplacementPlanPreservesLongestCommonGraphemePrefix() {
        let plan = BackspaceReplacementPlan(
            previousText: "prefix old tail",
            replacementText: "prefix new tail",
            preservesTrailingNewline: false
        )

        XCTAssertEqual(plan.commonPrefixCount, "prefix ".count)
        XCTAssertEqual(plan.backspaceCount, "old tail".count)
        XCTAssertEqual(plan.pastedText, "new tail")
        XCTAssertEqual(plan.verificationText, "prefix old tail")
        XCTAssertTrue(plan.hasChanges)
    }

    func testReplacementPlanHandlesPureAppendDeletionAndFullRewrite() {
        let append = BackspaceReplacementPlan(
            previousText: "hello",
            replacementText: "hello world",
            preservesTrailingNewline: false
        )
        let deletion = BackspaceReplacementPlan(
            previousText: "hello world",
            replacementText: "hello",
            preservesTrailingNewline: false
        )
        let fullRewrite = BackspaceReplacementPlan(
            previousText: "alpha",
            replacementText: "Alpha",
            preservesTrailingNewline: false
        )

        XCTAssertEqual(append.backspaceCount, 0)
        XCTAssertEqual(append.pastedText, " world")
        XCTAssertEqual(deletion.backspaceCount, " world".count)
        XCTAssertEqual(deletion.pastedText, "")
        XCTAssertEqual(fullRewrite.backspaceCount, "alpha".count)
        XCTAssertEqual(fullRewrite.pastedText, "Alpha")
    }

    func testReplacementPlanCountsChineseAndExtendedGraphemeClusters() {
        let chinese = BackspaceReplacementPlan(
            previousText: "我今天要去上海开会",
            replacementText: "我今天要去深圳开会",
            preservesTrailingNewline: false
        )
        let emoji = BackspaceReplacementPlan(
            previousText: "你好👨‍👩‍👧‍👦旧词",
            replacementText: "你好👨‍👩‍👧‍👦新词",
            preservesTrailingNewline: false
        )

        XCTAssertEqual(chinese.commonPrefixCount, "我今天要去".count)
        XCTAssertEqual(chinese.backspaceCount, "上海开会".count)
        XCTAssertEqual(chinese.pastedText, "深圳开会")
        XCTAssertEqual(emoji.commonPrefixCount, "你好👨‍👩‍👧‍👦".count)
        XCTAssertEqual(emoji.backspaceCount, "旧词".count)
        XCTAssertEqual(emoji.pastedText, "新词")
    }

    func testReplacementPlanKeepsCanonicallyEquivalentCombiningPrefix() {
        let plan = BackspaceReplacementPlan(
            previousText: "Cafe\u{301}",
            replacementText: "Café noir",
            preservesTrailingNewline: false
        )

        XCTAssertEqual(plan.commonPrefixCount, "Café".count)
        XCTAssertEqual(plan.backspaceCount, 0)
        XCTAssertEqual(plan.pastedText, " noir")
    }

    func testReplacementPlanAppliesLongestPrefixAfterTrailingNewlinePolicy() {
        let plan = BackspaceReplacementPlan(
            previousText: "hello old\n",
            replacementText: "hello new\n",
            preservesTrailingNewline: true
        )
        let windowsPlan = BackspaceReplacementPlan(
            previousText: "hello old\r\n",
            replacementText: "hello new\r\n",
            preservesTrailingNewline: true
        )
        let plainPlan = BackspaceReplacementPlan(
            previousText: "hello old\n",
            replacementText: "hello new\n",
            preservesTrailingNewline: false
        )
        let omittedNewlinePlan = BackspaceReplacementPlan(
            previousText: "hello old\n",
            replacementText: "hello new\n",
            preservesTrailingNewline: false,
            omitsTrailingNewline: true
        )
        let doubleNewlinePlan = BackspaceReplacementPlan(
            previousText: "hello old\n\n",
            replacementText: "hello new\n\n",
            preservesTrailingNewline: true
        )
        let implicitReplacementNewlinePlan = BackspaceReplacementPlan(
            previousText: "hello old\n",
            replacementText: "hello new",
            preservesTrailingNewline: true
        )

        XCTAssertEqual(plan.backspaceCount, "old".count)
        XCTAssertEqual(plan.pastedText, "new")
        XCTAssertTrue(plan.preservesTrailingNewline)
        XCTAssertEqual(plan.verificationText, "hello old\n")
        XCTAssertEqual(windowsPlan.backspaceCount, "old".count)
        XCTAssertEqual(windowsPlan.pastedText, "new")
        XCTAssertTrue(windowsPlan.preservesTrailingNewline)
        XCTAssertEqual(plainPlan.backspaceCount, "old\n".count)
        XCTAssertEqual(plainPlan.pastedText, "new\n")
        XCTAssertFalse(plainPlan.preservesTrailingNewline)
        XCTAssertEqual(omittedNewlinePlan.backspaceCount, "old".count)
        XCTAssertEqual(omittedNewlinePlan.pastedText, "new")
        XCTAssertFalse(omittedNewlinePlan.preservesTrailingNewline)
        XCTAssertEqual(omittedNewlinePlan.verificationText, "hello old")
        XCTAssertEqual(doubleNewlinePlan.backspaceCount, "old\n".count)
        XCTAssertEqual(doubleNewlinePlan.pastedText, "new\n")
        XCTAssertTrue(doubleNewlinePlan.preservesTrailingNewline)
        XCTAssertEqual(implicitReplacementNewlinePlan.backspaceCount, "old".count)
        XCTAssertEqual(implicitReplacementNewlinePlan.pastedText, "new")
        XCTAssertTrue(implicitReplacementNewlinePlan.preservesTrailingNewline)
    }

    func testReplacementTransactionGateRejectsOverlapAndInvalidatesStaleRevision() throws {
        var gate = ReplacementTransactionGate()
        let first = try XCTUnwrap(gate.begin())

        XCTAssertTrue(gate.isCurrent(first))
        XCTAssertTrue(gate.hasActiveTransaction)
        XCTAssertNil(gate.begin())

        gate.invalidate()

        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.hasActiveTransaction)
        XCTAssertNil(gate.begin())

        gate.finish(first)
        let second = try XCTUnwrap(gate.begin())
        XCTAssertGreaterThan(second.revision, first.revision)
        XCTAssertTrue(gate.isCurrent(second))
    }

    @MainActor
    func testAccessibilityReplacementReturnsOnlyAfterDelayedPasteIsPosted() async {
        let plan = BackspaceReplacementPlan(
            previousText: "prefix old",
            replacementText: "prefix new",
            preservesTrailingNewline: false
        )
        var events: [String] = []

        let result = await ReplacementEventSequence.performAccessibilityReplacement(
            plan,
            validate: {
                events.append("validate")
                return true
            },
            sendBackspaces: { count in
                events.append("delete:\(count)")
                return true
            },
            wait: { _ in
                events.append("wait")
            },
            paste: { text in
                events.append("paste:\(text)")
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(
            events,
            [
                "validate",
                "wait", "validate", "delete:1",
                "wait", "validate", "delete:1",
                "wait", "validate", "delete:1",
                "wait", "validate",
                "paste:new"
            ]
        )
    }

    @MainActor
    func testAccessibilityReplacementRevalidatesAfterDelayBeforePaste() async {
        let plan = BackspaceReplacementPlan(
            previousText: "prefix old",
            replacementText: "prefix new",
            preservesTrailingNewline: false
        )
        var validationCount = 0
        var pasted = false

        let result = await ReplacementEventSequence.performAccessibilityReplacement(
            plan,
            validate: {
                validationCount += 1
                return validationCount == 1
            },
            sendBackspaces: { _ in true },
            wait: { _ in },
            paste: { _ in
                pasted = true
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertFalse(pasted)
        XCTAssertEqual(validationCount, 2)
    }

    @MainActor
    func testAccessibilityReplacementRollsBackSuffixWhenPasteFails() async {
        let plan = BackspaceReplacementPlan(
            previousText: "prefix old",
            replacementText: "prefix new",
            preservesTrailingNewline: false
        )
        var didMutate = false
        var rollbackText: String?

        let result = await ReplacementEventSequence.performAccessibilityReplacement(
            plan,
            validate: { true },
            sendBackspaces: { _ in true },
            wait: { _ in },
            paste: { _ in false },
            mutationOccurred: { didMutate = true },
            rollback: { text in
                rollbackText = text
                didMutate = false
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertFalse(didMutate)
        XCTAssertEqual(rollbackText, "old")
    }

    @MainActor
    func testTerminalReplacementWaitsForEntireEventSequenceBeforeSuccess() async {
        let plan = BackspaceReplacementPlan(
            previousText: "prefix old\n",
            replacementText: "prefix new\n",
            preservesTrailingNewline: true
        )
        var events: [String] = []

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: 4_242,
            validate: { true },
            postKey: { keyCode, processIdentifier in
                events.append("key:\(keyCode):\(processIdentifier ?? 0)")
                return true
            },
            wait: { _ in
                events.append("wait")
            },
            paste: { text in
                events.append("paste:\(text)")
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(events.filter { $0.contains("key:51:") }.count, 3)
        XCTAssertEqual(events.suffix(3), ["paste:new", "wait", "key:124:4242"])
    }

    @MainActor
    func testTerminalReplacementStopsBeforeNextDestructiveEventWhenInvalidated() async {
        let plan = BackspaceReplacementPlan(
            previousText: "abc",
            replacementText: "replacement",
            preservesTrailingNewline: false
        )
        var validationCount = 0
        var deletedCount = 0
        var pasted = false

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: nil,
            validate: {
                validationCount += 1
                return validationCount <= 2
            },
            postKey: { keyCode, _ in
                if keyCode == 0x33 {
                    deletedCount += 1
                }
                return true
            },
            wait: { _ in },
            paste: { _ in
                pasted = true
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(deletedCount, 1)
        XCTAssertFalse(pasted)
    }

    @MainActor
    func testTerminalDeletionStopsBeforeAnyMutationWhenTargetApplicationChanges() async {
        let targetProcessIdentifier: pid_t = 4_242
        let plan = BackspaceReplacementPlan(
            previousText: "terminal draft",
            replacementText: "",
            preservesTrailingNewline: false
        )
        var currentProcessIdentifier = targetProcessIdentifier
        var postedKeys: [CGKeyCode] = []
        var pastedTexts: [String] = []

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: targetProcessIdentifier,
            validate: {
                currentProcessIdentifier == targetProcessIdentifier
            },
            postKey: { keyCode, _ in
                postedKeys.append(keyCode)
                return true
            },
            wait: { _ in
                // Model an app/focus switch while the guarded rewrite is
                // waiting before its first destructive key event.
                currentProcessIdentifier = 9_999
            },
            paste: { text in
                pastedTexts.append(text)
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertTrue(postedKeys.isEmpty)
        XCTAssertTrue(pastedTexts.isEmpty)
    }

    @MainActor
    func testITermDeletionUsesCapturedProcessAndDoesNotTouchClipboard() async {
        let targetProcessIdentifier: pid_t = 4_242
        let previousText = "terminal draft\n"
        let plan = BackspaceReplacementPlan(
            previousText: previousText,
            replacementText: "",
            preservesTrailingNewline: true
        )
        var postedEvents: [(CGKeyCode, pid_t?)] = []
        var pastedTexts: [String] = []

        XCTAssertTrue(GuardedBackspaceRewritePolicy.prefersDirectEventDelivery(
            bundleIdentifier: "com.googlecode.iterm2"
        ))

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: targetProcessIdentifier,
            validate: { true },
            postKey: { keyCode, processIdentifier in
                postedEvents.append((keyCode, processIdentifier))
                return true
            },
            wait: { _ in },
            paste: { text in
                pastedTexts.append(text)
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(postedEvents.first?.0, CGKeyCode(0x7B))
        XCTAssertEqual(postedEvents.last?.0, CGKeyCode(0x7C))
        XCTAssertEqual(
            postedEvents.filter { $0.0 == CGKeyCode(0x33) }.count,
            "terminal draft".count
        )
        XCTAssertTrue(postedEvents.allSatisfy {
            $0.1 == targetProcessIdentifier
        })
        XCTAssertTrue(pastedTexts.isEmpty)
    }

    @MainActor
    func testTerminalReplacementRollsBackCharactersAfterEventPostingFailure() async {
        let plan = BackspaceReplacementPlan(
            previousText: "abc",
            replacementText: "replacement",
            preservesTrailingNewline: false
        )
        var deleteAttempts = 0
        var rollbackText: String?

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: nil,
            validate: { true },
            postKey: { keyCode, _ in
                guard keyCode == 0x33 else {
                    return true
                }
                deleteAttempts += 1
                return deleteAttempts < 2
            },
            wait: { _ in },
            paste: { _ in true },
            rollback: { text in
                rollbackText = text
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(rollbackText, "c")
    }

    @MainActor
    func testTerminalPureAppendAndDeletionUseOnlyRequiredEvents() async {
        let appendPlan = BackspaceReplacementPlan(
            previousText: "hello",
            replacementText: "hello world",
            preservesTrailingNewline: false
        )
        let deletionPlan = BackspaceReplacementPlan(
            previousText: "hello world",
            replacementText: "hello",
            preservesTrailingNewline: false
        )
        var appendKeys: [CGKeyCode] = []
        var appendPastes: [String] = []
        var deletionKeys: [CGKeyCode] = []
        var deletionPasted = false

        let appended = await ReplacementEventSequence.performTerminalReplacement(
            appendPlan,
            directTargetProcessIdentifier: nil,
            validate: { true },
            postKey: { keyCode, _ in
                appendKeys.append(keyCode)
                return true
            },
            wait: { _ in },
            paste: { text in
                appendPastes.append(text)
                return true
            }
        )
        let deleted = await ReplacementEventSequence.performTerminalReplacement(
            deletionPlan,
            directTargetProcessIdentifier: nil,
            validate: { true },
            postKey: { keyCode, _ in
                deletionKeys.append(keyCode)
                return true
            },
            wait: { _ in },
            paste: { _ in
                deletionPasted = true
                return true
            }
        )

        XCTAssertTrue(appended)
        XCTAssertTrue(appendKeys.isEmpty)
        XCTAssertEqual(appendPastes, [" world"])
        XCTAssertTrue(deleted)
        XCTAssertEqual(deletionKeys, Array(repeating: CGKeyCode(0x33), count: " world".count))
        XCTAssertFalse(deletionPasted)
    }

    @MainActor
    func testPreservedNewlineAppendMovesAroundLineBreakWithoutDeleting() async {
        let plan = BackspaceReplacementPlan(
            previousText: "hello\n",
            replacementText: "hello world\n",
            preservesTrailingNewline: true
        )
        var events: [String] = []

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: 4_242,
            validate: { true },
            postKey: { keyCode, processIdentifier in
                events.append("key:\(keyCode):\(processIdentifier ?? 0)")
                return true
            },
            wait: { _ in },
            paste: { text in
                events.append("paste:\(text)")
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(
            events,
            ["key:123:4242", "paste: world", "key:124:4242"]
        )
    }

    @MainActor
    func testNoOpPlanPostsNoTerminalEvents() async {
        let plan = BackspaceReplacementPlan(
            previousText: "hello\n",
            replacementText: "hello\n",
            preservesTrailingNewline: true
        )
        var eventCount = 0

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: 4_242,
            validate: {
                eventCount += 1
                return true
            },
            postKey: { _, _ in
                eventCount += 1
                return true
            },
            wait: { _ in
                eventCount += 1
            },
            paste: { _ in
                eventCount += 1
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertFalse(plan.hasChanges)
        XCTAssertEqual(eventCount, 0)
    }

    @MainActor
    func testAccessibilityPureDeletionWaitsForPostDeleteVerification() async {
        let plan = BackspaceReplacementPlan(
            previousText: "hello world",
            replacementText: "hello",
            preservesTrailingNewline: false
        )
        var deletedCount = 0
        var waited = false
        var pasted = false

        let result = await ReplacementEventSequence.performAccessibilityReplacement(
            plan,
            validate: { true },
            sendBackspaces: { count in
                deletedCount += count
                return true
            },
            wait: { _ in
                waited = true
            },
            paste: { _ in
                pasted = true
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(deletedCount, " world".count)
        XCTAssertTrue(waited)
        XCTAssertFalse(pasted)
    }

    @MainActor
    func testAccessibilityReplacementStopsWhenPostedDeletionCannotBeVerified() async {
        let plan = BackspaceReplacementPlan(
            previousText: "prefix old",
            replacementText: "prefix new",
            preservesTrailingNewline: false
        )
        var pasted = false
        var rolledBack = false

        let result = await ReplacementEventSequence.performAccessibilityReplacement(
            plan,
            validate: { true },
            sendBackspaces: { _ in true },
            wait: { _ in },
            paste: { _ in
                pasted = true
                return true
            },
            validateDeletion: { false },
            rollback: { _ in
                rolledBack = true
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertFalse(pasted)
        XCTAssertFalse(rolledBack)
    }

    @MainActor
    func testAccessibilityReplacementStopsBeforeNextBackspaceWhenInvalidated() async {
        let plan = BackspaceReplacementPlan(
            previousText: "abcdef",
            replacementText: "x",
            preservesTrailingNewline: false
        )
        var validationCount = 0
        var deletedCount = 0
        var pasted = false

        let result = await ReplacementEventSequence.performAccessibilityReplacement(
            plan,
            validate: {
                validationCount += 1
                return validationCount <= 2
            },
            sendBackspaces: { count in
                deletedCount += count
                return true
            },
            wait: { _ in },
            paste: { _ in
                pasted = true
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(deletedCount, 1)
        XCTAssertFalse(pasted)
    }

    func testFocusedTextSnapshotVerifiesExactUTF16Deletion() {
        let original = FocusedTextSnapshot(
            text: "before old🧪 after",
            selectedRange: NSRange(location: "before old🧪".utf16.count, length: 0)
        )
        let deleted = "old🧪"
        let result = FocusedTextSnapshot(
            text: "before  after",
            selectedRange: NSRange(location: "before ".utf16.count, length: 0)
        )
        let wrongResult = FocusedTextSnapshot(
            text: "before old after",
            selectedRange: NSRange(location: "before old".utf16.count, length: 0)
        )

        XCTAssertTrue(result.reflectsDeletion(of: deleted, from: original))
        XCTAssertFalse(wrongResult.reflectsDeletion(of: deleted, from: original))
    }

    @MainActor
    func testTerminalStopsImmediatelyWhenDeletePostingFails() async {
        let plan = BackspaceReplacementPlan(
            previousText: "abc",
            replacementText: "ax",
            preservesTrailingNewline: false
        )
        var deleteAttempts = 0
        var pasted = false

        let result = await ReplacementEventSequence.performTerminalReplacement(
            plan,
            directTargetProcessIdentifier: nil,
            validate: { true },
            postKey: { keyCode, _ in
                if keyCode == 0x33 {
                    deleteAttempts += 1
                }
                return false
            },
            wait: { _ in },
            paste: { _ in
                pasted = true
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(deleteAttempts, 1)
        XCTAssertFalse(pasted)
    }

}

private struct ProcessScopedFocusedTextSnapshotProvider: FocusedTextSnapshotProviding {
    let processIdentifier: pid_t
    let snapshot: FocusedTextSnapshot

    func focusedTextSnapshot(applicationProcessIdentifier: pid_t?) -> FocusedTextSnapshot? {
        applicationProcessIdentifier == processIdentifier ? snapshot : nil
    }
}

private final class FocusRestorationProbe {
    var restoreCount = 0
    var fallbackAllowances: [Bool] = []
}

private struct FocusRestoringTextSnapshotProvider: FocusedTextSnapshotProviding {
    let target: FocusedTextTarget
    let probe: FocusRestorationProbe

    func focusedTextSnapshot(applicationProcessIdentifier: pid_t?) -> FocusedTextSnapshot? {
        nil
    }

    func focusedTextTarget(applicationProcessIdentifier: pid_t?) -> FocusedTextTarget? {
        applicationProcessIdentifier == target.applicationProcessIdentifier ? target : nil
    }

    func restoreFocus(to target: FocusedTextTarget) -> Bool {
        probe.restoreCount += 1
        return true
    }

    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in target: FocusedTextTarget,
        allowingValueSuffixFallback: Bool
    ) -> Bool {
        probe.fallbackAllowances.append(allowingValueSuffixFallback)
        return allowingValueSuffixFallback
    }
}

final class VoiceCommandAttemptLifecycleTests: XCTestCase {
    func testHandledVoiceCommandIsAnAttemptButNotAProducedTranscript() {
        let item = TranscriptItem(
            text: "",
            rawText: "delete the previous sentence",
            provider: .local,
            model: "local.medium",
            languageHint: .english,
            outcome: .handledVoiceCommand,
            recordingDuration: 1.5,
            transcriptionLatency: 0.4
        )
        let calculator = MetricsCalculator()
        let record = calculator.record(for: item)
        let counters = calculator.counters(from: [record])

        XCTAssertEqual(counters.totalAttempts, 1)
        XCTAssertEqual(counters.transcriptCount, 0)
        XCTAssertEqual(counters.successfulTranscriptions, 0)
        XCTAssertEqual(counters.failedTranscriptions, 0)
    }

    func testStoredCommandAudioCanBeDeletedWithoutCreatingAHistoryItem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let temporaryAudioURL = directory.appendingPathComponent("temporary.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: temporaryAudioURL)
        let store = TranscriptAudioStore(baseDirectory: directory)
        let fileName = try store.storeRecording(at: temporaryAudioURL, for: UUID())

        try store.deleteAudio(forFileName: fileName)
        try store.deleteAudio(forFileName: fileName)

        XCTAssertNil(store.url(forFileName: fileName).flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        })
    }

    func testFailedPhysicalAudioDeletionKeepsRecordingReferencedAndNonOrphaned() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let temporaryAudioURL = directory.appendingPathComponent("temporary.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: temporaryAudioURL)
        let deletionError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError
        )
        let store = TranscriptAudioStore(
            baseDirectory: directory,
            removeItem: { _ in throw deletionError }
        )
        let transcriptID = UUID()
        let fileName = try store.storeRecording(
            at: temporaryAudioURL,
            for: transcriptID
        )
        let item = TranscriptItem(
            id: transcriptID,
            text: "still visible",
            provider: .local,
            model: "local.medium",
            languageHint: .mixed,
            audioFileName: fileName
        )

        XCTAssertThrowsError(try store.deleteAudio(for: item))
        XCTAssertTrue(store.audioExists(for: item))
        XCTAssertTrue(
            try store.unreferencedRecordings(
                referencedFileNames: Set([fileName])
            ).isEmpty
        )
    }

    func testTranscriptAudioStoreFindsOnlyUnreferencedRegularRecordings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recordingsDirectory = directory.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let referenced = "11111111-1111-1111-1111-111111111111.wav"
        let orphan = "22222222-2222-2222-2222-222222222222.wav"
        try Data("referenced".utf8).write(
            to: recordingsDirectory.appendingPathComponent(referenced)
        )
        try Data("orphan".utf8).write(
            to: recordingsDirectory.appendingPathComponent(orphan)
        )
        try FileManager.default.createSymbolicLink(
            at: recordingsDirectory.appendingPathComponent("linked.wav"),
            withDestinationURL: recordingsDirectory.appendingPathComponent(orphan)
        )

        let recordings = try TranscriptAudioStore(baseDirectory: directory)
            .unreferencedRecordings(referencedFileNames: Set([referenced]))

        XCTAssertEqual(recordings.map(\.fileName), [orphan])
    }
}

final class LocalWhisperModelIntegrityTests: XCTestCase {
    func testBackupPolicyRecognizesCurrentAndLegacyManagedModelsOnly() {
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "ggml-base.bin",
                byteCount: 147_951_465
            )
        )
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "ggml-base.en.bin",
                byteCount: 147_964_211
            )
        )
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "ggml-small.en.bin",
                byteCount: 487_614_201
            )
        )
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "ggml-medium.bin",
                byteCount: 1_533_763_059
            )
        )
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "ggml-large-v3-turbo-q8_0.bin",
                byteCount: 874_188_075
            )
        )
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "ggml-small-q5_1.bin",
                byteCount: 190_085_487
            )
        )
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "sensevoice-small-q8.gguf",
                byteCount: 254_208_320
            )
        )
        XCTAssertTrue(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "fsmn-vad.gguf",
                byteCount: 1_720_512
            )
        )
        XCTAssertFalse(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "ggml-small-q5_1.bin",
                byteCount: 190_085_486
            )
        )
        XCTAssertFalse(
            LocalWhisperBackupPolicy.isManagedAsset(
                filename: "custom-model.bin",
                byteCount: 190_085_487
            )
        )
    }

    func testManagedModelCanBeExcludedFromBackupWithoutChangingContents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelURL = directory.appendingPathComponent("managed-model.bin")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalData = Data("model-contents".utf8)
        try originalData.write(to: modelURL)

        try LocalWhisperBackupPolicy.excludeManagedModel(at: modelURL)

        XCTAssertTrue(LocalWhisperBackupPolicy.isExcludedFromBackup(modelURL))
        XCTAssertEqual(try Data(contentsOf: modelURL), originalData)
    }

    func testDownloadDiskRequirementIncludesSafetyReserve() {
        let smallDownload: Int64 = 10 * 1_024 * 1_024
        let largeDownload: Int64 = 1_000 * 1_024 * 1_024

        XCTAssertEqual(
            LocalWhisperDiskSpace.requiredByteCount(forDownloadByteCount: smallDownload),
            smallDownload + LocalWhisperDiskSpace.minimumReserveByteCount
        )
        XCTAssertEqual(
            LocalWhisperDiskSpace.requiredByteCount(forDownloadByteCount: largeDownload),
            largeDownload + largeDownload / 10
        )
    }

    func testDownloadProgressIsClamped() {
        XCTAssertEqual(
            LocalWhisperDownloadProgress(receivedByteCount: 50, totalByteCount: 100).fractionCompleted,
            0.5
        )
        XCTAssertEqual(
            LocalWhisperDownloadProgress(receivedByteCount: 120, totalByteCount: 100).fractionCompleted,
            1
        )
    }

    func testSHA256IsCalculatedFromFileContents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)

        XCTAssertEqual(
            try LocalWhisperModelIntegrity.sha256(of: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testManagedModelWithWrongSizeIsNotReportedAsInstalled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try XCTUnwrap(LocalWhisperModelCatalog.managedModels.first)
        try Data("not a model".utf8).write(to: model.destinationURL(in: directory.path))

        XCTAssertFalse(LocalWhisperModelCatalog.isInstalled(model, in: directory.path))
    }
}

final class MultiUserUpdateCoordinationTests: XCTestCase {
    func testOtherUserDetectorMatchesOnlyTheSharedExecutable() {
        let expectedURL = URL(fileURLWithPath: "/Applications/Shuo.app/Contents/MacOS/Shuo")
        let currentPID: pid_t = 100
        let currentUID: uid_t = 501

        XCTAssertTrue(
            OtherUserShuoProcessDetector.isOtherUserInstance(
                RunningApplicationProcess(
                    processIdentifier: 200,
                    userIdentifier: 502,
                    command: "Shuo",
                    executablePath: expectedURL.path
                ),
                currentProcessIdentifier: currentPID,
                currentUserIdentifier: currentUID,
                expectedExecutableURL: expectedURL
            )
        )
        XCTAssertFalse(
            OtherUserShuoProcessDetector.isOtherUserInstance(
                RunningApplicationProcess(
                    processIdentifier: 200,
                    userIdentifier: currentUID,
                    command: "Shuo",
                    executablePath: expectedURL.path
                ),
                currentProcessIdentifier: currentPID,
                currentUserIdentifier: currentUID,
                expectedExecutableURL: expectedURL
            )
        )
        XCTAssertFalse(
            OtherUserShuoProcessDetector.isOtherUserInstance(
                RunningApplicationProcess(
                    processIdentifier: 200,
                    userIdentifier: 502,
                    command: "Shuo",
                    executablePath: "/Users/other/Applications/Shuo.app/Contents/MacOS/Shuo"
                ),
                currentProcessIdentifier: currentPID,
                currentUserIdentifier: currentUID,
                expectedExecutableURL: expectedURL
            )
        )
    }

    func testOtherUserDetectorFailsConservativelyWhenPathIsUnavailable() {
        let expectedURL = URL(fileURLWithPath: "/Applications/Shuo.app/Contents/MacOS/Shuo")
        XCTAssertTrue(
            OtherUserShuoProcessDetector.isOtherUserInstance(
                RunningApplicationProcess(
                    processIdentifier: 200,
                    userIdentifier: 502,
                    command: "Shuo",
                    executablePath: nil
                ),
                currentProcessIdentifier: 100,
                currentUserIdentifier: 501,
                expectedExecutableURL: expectedURL
            )
        )
    }

    func testSystemProcessSnapshotContainsTheCurrentProcess() throws {
        let snapshot = try OtherUserShuoProcessDetector.processSnapshot()
        XCTAssertTrue(snapshot.contains { $0.processIdentifier == getpid() })
    }

    @MainActor
    func testMachineGateBlocksTheOldBuildAndReleasesForTheNewBuild() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let markerURL = directory.appendingPathComponent("machine-update-gate")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let coordinator = MachineUpdateCoordinator(markerURL: markerURL)
        let now = Date(timeIntervalSince1970: 1_000)
        let token = try XCTUnwrap(coordinator.begin(sourceBuildVersion: "10", now: now))

        XCTAssertTrue(
            coordinator.shouldBlockLaunch(
                currentBuildVersion: "10",
                currentProcessIdentifier: getpid() + 1,
                now: now
            )
        )
        XCTAssertFalse(
            coordinator.shouldBlockLaunch(
                currentBuildVersion: "11",
                currentProcessIdentifier: getpid() + 1,
                now: now
            )
        )

        coordinator.clear(token: token)
    }

    @MainActor
    func testMachineGateExpiresInsteadOfPermanentlyBlockingLaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let markerURL = directory.appendingPathComponent("machine-update-gate")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let coordinator = MachineUpdateCoordinator(markerURL: markerURL)
        let now = Date(timeIntervalSince1970: 1_000)
        _ = try XCTUnwrap(coordinator.begin(sourceBuildVersion: "10", now: now))

        XCTAssertFalse(
            coordinator.shouldBlockLaunch(
                currentBuildVersion: "10",
                currentProcessIdentifier: getpid() + 1,
                now: now.addingTimeInterval(MachineUpdateCoordinator.markerLifetime + 1)
            )
        )
    }
}

final class StatusIconArtworkTests: XCTestCase {
    func testReadyArtworkUsesSevenLogoProportionedBars() {
        let bars = StatusIconArtwork.bars(style: .ready)

        XCTAssertEqual(bars.count, 7)
        XCTAssertEqual(bars[3].frame.height, 15, accuracy: 0.001)
        XCTAssertEqual(bars[0].frame.height, 7.5, accuracy: 0.001)
        XCTAssertEqual(bars[1].frame.height, 10.8, accuracy: 0.001)
        XCTAssertEqual(bars[2].frame.height, 8.7, accuracy: 0.001)
        XCTAssertEqual(bars[0].frame.height, bars[6].frame.height, accuracy: 0.001)
        XCTAssertEqual(bars[1].frame.height, bars[5].frame.height, accuracy: 0.001)
        XCTAssertEqual(bars[2].frame.height, bars[4].frame.height, accuracy: 0.001)
        XCTAssertEqual(bars[3].frame.midX, StatusIconArtwork.canvasSize.width / 2, accuracy: 0.001)
        XCTAssertTrue(bars.allSatisfy { $0.opacity == 1 })
    }

    func testDisabledArtworkKeepsGeometryAndOnlyDimsTheBars() {
        let ready = StatusIconArtwork.bars(style: .ready)
        let disabled = StatusIconArtwork.bars(style: .disabled)

        XCTAssertEqual(ready.map(\.frame), disabled.map(\.frame))
        XCTAssertTrue(disabled.allSatisfy { abs($0.opacity - 0.38) < 0.001 })
    }

    func testRecordingArtworkKeepsCentersAndUsesBolderCapsules() {
        let ready = StatusIconArtwork.bars(style: .ready)
        let recording = StatusIconArtwork.bars(style: .recording)

        XCTAssertEqual(ready.map { $0.frame.midX }, recording.map { $0.frame.midX })
        XCTAssertEqual(ready.map { $0.frame.height }, recording.map { $0.frame.height })
        XCTAssertTrue(zip(ready, recording).allSatisfy { $1.frame.width > $0.frame.width })
        XCTAssertTrue(recording.allSatisfy { $0.opacity == 1 })
    }

    func testRecordingIndicatorIsVisibleOnlyForRecordingArtwork() {
        XCTAssertTrue(StatusIconArtworkStyle.recording.showsRecordingIndicator)
        XCTAssertFalse(StatusIconArtworkStyle.ready.showsRecordingIndicator)
        XCTAssertFalse(StatusIconArtworkStyle.disabled.showsRecordingIndicator)
        XCTAssertFalse(StatusIconArtworkStyle.transcribing.showsRecordingIndicator)
    }

    func testRecordingIndicatorGeometryFitsAtTheLowerRightOfTheStatusItem() {
        for size in [NSSize(width: 24, height: 22), NSSize(width: 24, height: 24)] {
            let bounds = NSRect(origin: .zero, size: size)
            let frame = StatusRecordingIndicatorGeometry.frame(in: bounds)

            XCTAssertEqual(frame.width, 4, accuracy: 0.001)
            XCTAssertEqual(frame.height, 4, accuracy: 0.001)
            XCTAssertTrue(bounds.contains(frame))
            XCTAssertGreaterThan(frame.midX, bounds.midX)
            XCTAssertLessThan(frame.midY, bounds.midY)
        }
    }

    @MainActor
    func testRecordingIndicatorDoesNotInterceptClicksOrAccessibility() {
        let indicator = StatusRecordingIndicatorView(
            frame: NSRect(x: 0, y: 0, width: 24, height: 22)
        )

        XCTAssertNil(indicator.hitTest(NSPoint(x: 18, y: 5)))
        XCTAssertFalse(indicator.isAccessibilityElement())
        XCTAssertFalse(indicator.isOpaque)
    }

    func testTranscribingArtworkVariesEachBarWithinAReadableRange() {
        let firstFrame = StatusIconArtwork.bars(style: .transcribing, frame: 0)
        let laterFrame = StatusIconArtwork.bars(style: .transcribing, frame: 5)
        let firstOpacities = firstFrame.map(\.opacity)
        let laterOpacities = laterFrame.map(\.opacity)

        XCTAssertEqual(
            firstFrame.map(\.frame),
            StatusIconArtwork.bars(style: .ready).map(\.frame)
        )
        XCTAssertGreaterThan(Set(firstOpacities).count, 1)
        XCTAssertNotEqual(firstOpacities, laterOpacities)
        XCTAssertTrue((firstOpacities + laterOpacities).allSatisfy { (0.22 ... 1).contains($0) })
    }

    func testTranscribingArtworkChangesOnlyAStandaloneRandomSubsetPerTick() {
        var largestStep: CGFloat = 0
        for frame in 0..<30 {
            let current = StatusIconArtwork.bars(
                style: .transcribing,
                frame: frame
            ).map(\.opacity)
            let next = StatusIconArtwork.bars(
                style: .transcribing,
                frame: frame + 1
            ).map(\.opacity)
            let changes = zip(current, next).map { abs($1 - $0) }
            largestStep = max(largestStep, changes.max() ?? 0)
            XCTAssertTrue((2 ... 3).contains(changes.filter { $0 > 0.001 }.count))
        }

        let firstFrame = StatusIconArtwork.bars(style: .transcribing, frame: 0).map(\.opacity)
        XCTAssertGreaterThan(Set(firstFrame).count, 4)
        XCTAssertLessThanOrEqual(largestStep, 0.341)
    }

    @MainActor
    func testRenderedArtworkIsAnEighteenPointTemplateImage() {
        let readyImage = StatusIconArtwork.image(style: .ready)
        let recordingImage = StatusIconArtwork.image(style: .recording)

        XCTAssertEqual(readyImage.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(recordingImage.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(readyImage.isTemplate)
        XCTAssertTrue(recordingImage.isTemplate)
    }
}

final class TranscriptionFlickerSequenceTests: XCTestCase {
    func testSeededSequenceIsReplayableWithoutRepeatingEverySession() {
        var first = TranscriptionFlickerSequence(seed: 42)
        var replay = TranscriptionFlickerSequence(seed: 42)
        var different = TranscriptionFlickerSequence(seed: 43)

        XCTAssertEqual(first.opacities, replay.opacities)
        XCTAssertNotEqual(first.opacities, different.opacities)
        for _ in 0..<20 {
            let firstValues = first.advance()
            let replayValues = replay.advance()
            let differentValues = different.advance()
            XCTAssertEqual(firstValues, replayValues)
            XCTAssertNotEqual(firstValues, differentValues)
        }
    }

    func testEachTickChangesTwoOrThreeIndependentBarsWithinBounds() {
        var sequence = TranscriptionFlickerSequence(seed: 7)
        var changedAcrossRun = Set<Int>()
        var previousChangedIndices = Set<Int>()

        for _ in 0..<64 {
            let previous = sequence.opacities
            let current = sequence.advance()
            let changed = Set(zip(previous, current).enumerated().compactMap { index, values in
                abs(values.0 - values.1) > 0.001 ? index : nil
            })

            XCTAssertTrue((2 ... 3).contains(changed.count))
            XCTAssertNotEqual(changed, previousChangedIndices)
            XCTAssertTrue(current.allSatisfy { TranscriptionFlickerSequence.opacityRange.contains($0) })
            XCTAssertLessThanOrEqual(
                zip(previous, current).map { abs($1 - $0) }.max() ?? 0,
                0.341
            )
            changedAcrossRun.formUnion(changed)
            previousChangedIndices = changed
        }

        XCTAssertEqual(changedAcrossRun, Set(0..<TranscriptionFlickerSequence.barCount))
    }
}

final class FloatingWindowGlyphMotionTests: XCTestCase {
    func testReadyPresentationKeepsStableLogoGeometry() {
        let presentation = FloatingWindowGlyphMotion.presentation(
            artworkOpacity: 1
        )

        XCTAssertEqual(presentation.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.widthScale, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.heightScale, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.verticalOffset, 0, accuracy: 0.001)
    }

    func testTranscribingPresentationUsesBrightnessWithoutWaveGeometry() {
        let presentation = FloatingWindowGlyphMotion.presentation(
            artworkOpacity: 0.37
        )

        XCTAssertEqual(presentation.opacity, 0.37, accuracy: 0.001)
        XCTAssertEqual(presentation.widthScale, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.heightScale, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.verticalOffset, 0, accuracy: 0.001)
    }

    func testFloatingFlickerUsesIndependentRandomBarSubsets() {
        let frames = (0..<64).map { frame in
            (0..<7).map { barIndex in
                FloatingTranscriptionBarFlicker.opacity(
                    frame: frame,
                    barIndex: barIndex
                )
            }
        }

        XCTAssertTrue(frames.flatMap { $0 }.allSatisfy { (0.22 ... 1).contains($0) })
        XCTAssertTrue((0..<7).allSatisfy { barIndex in
            Set(frames.map { $0[barIndex] }).count > 10
        })
        XCTAssertTrue(frames.allSatisfy { Set($0).count > 4 })
        for frame in 0..<(frames.count - 1) {
            let changedCount = zip(frames[frame], frames[frame + 1])
                .filter { abs($0 - $1) > 0.001 }
                .count
            XCTAssertTrue((2 ... 3).contains(changedCount))
        }
    }
}

final class RecordingCuePlaybackLevelTests: XCTestCase {
    func testTenCueChoicesRemainAvailable() {
        XCTAssertEqual(RecordingCueSound.allCases.count, 10)
        XCTAssertTrue(RecordingCueSound.allCases.contains(.deepDrop))
        XCTAssertTrue(RecordingCueSound.allCases.contains(.woodKnock))
        XCTAssertTrue(RecordingCueSound.allCases.contains(.softPulse))
        XCTAssertTrue(RecordingCueSound.allCases.contains(.lowOrbit))
        XCTAssertTrue(RecordingCueSound.allCases.contains(.subBeacon))
        XCTAssertTrue(RecordingCueSound.allCases.contains(.darkPulse))
    }

    func testWhisperModeKeepsTheCueMuchQuieter() {
        let normal = RecordingCuePlaybackLevel.scale(whisperModeEnabled: false)
        let whisper = RecordingCuePlaybackLevel.scale(whisperModeEnabled: true)

        XCTAssertEqual(normal, 1, accuracy: 0.001)
        XCTAssertEqual(whisper, 0.18, accuracy: 0.001)
        XCTAssertLessThan(whisper, normal * 0.20)
    }
}

final class StatusMenuPanelLayoutTests: XCTestCase {
    func testPanelAnchorsBelowTheStatusItemWithoutLeavingTheScreen() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let screenFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let statusItemWindowFrame = NSRect(x: 1_382, y: 876, width: 40, height: 24)
        let anchor = NSRect(x: 1_390, y: 878, width: 24, height: 20)
        let frame = StatusMenuPanelLayout.frame(
            anchorRect: anchor,
            statusItemWindowFrame: statusItemWindowFrame,
            contentSize: NSSize(width: 280, height: 360),
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )

        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 8)
        XCTAssertEqual(frame.maxY, statusItemWindowFrame.minY, accuracy: 0.001)
        XCTAssertEqual(frame.size, NSSize(width: 280, height: 360))
    }

    func testMacBookCameraHousingMenuBarHasNoPanelGap() {
        // Realistic values from a camera-housing MacBook: the global status
        // bar still reports 22pt while this display reserves a 39pt top band.
        let screenFrame = NSRect(x: 0, y: 0, width: 2_056, height: 1_329)
        let visibleFrame = NSRect(x: 43, y: 0, width: 2_013, height: 1_290)
        let statusItemWindowFrame = NSRect(x: 1_598, y: 1_290, width: 40, height: 39)
        let anchor = NSRect(x: 1_606, y: 1_295.5, width: 24.5, height: 29)

        let frame = StatusMenuPanelLayout.frame(
            anchorRect: anchor,
            statusItemWindowFrame: statusItemWindowFrame,
            contentSize: NSSize(width: 280, height: 394),
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.maxY, visibleFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(statusItemWindowFrame.minY - frame.maxY, 0, accuracy: 0.001)
        XCTAssertLessThan(frame.maxY, anchor.minY)
    }

    func testMacMiniUsesActualStatusItemWindowToPreventMenuBarOverlap() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let visibleFrame = screenFrame // Simulates a display reporting no reservation.
        let statusItemWindowFrame = NSRect(x: 1_840, y: 1_056, width: 40, height: 24)
        let anchor = NSRect(x: 1_848, y: 1_057, width: 24, height: 22)
        let frame = StatusMenuPanelLayout.frame(
            anchorRect: anchor,
            statusItemWindowFrame: statusItemWindowFrame,
            contentSize: NSSize(width: 280, height: 420),
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.maxY, statusItemWindowFrame.minY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frame.maxY, statusItemWindowFrame.minY)
        XCTAssertLessThan(frame.maxY, screenFrame.maxY - 22)
    }

    func testPanelUsesLowerVisibleFrameBoundaryWhenItIsMoreConservative() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 868)
        let statusItemWindowFrame = NSRect(x: 1_382, y: 876, width: 40, height: 24)
        let anchor = NSRect(x: 1_390, y: 876, width: 24, height: 24)
        let frame = StatusMenuPanelLayout.frame(
            anchorRect: anchor,
            statusItemWindowFrame: statusItemWindowFrame,
            contentSize: NSSize(width: 280, height: 360),
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.maxY, visibleFrame.maxY, accuracy: 0.001)
    }

    func testPanelPlacementSupportsExternalScreenCoordinateOrigins() {
        let screenFrames = [
            NSRect(x: -1_920, y: 240, width: 1_920, height: 1_080),
            NSRect(x: 2_056, y: -1_080, width: 1_920, height: 1_080)
        ]

        for screenFrame in screenFrames {
            let reportedVisibleFrame = screenFrame.insetBy(dx: -40, dy: -40)
            let menuBarBottomY = screenFrame.maxY - 30
            let statusItemWindowFrame = NSRect(
                x: screenFrame.maxX - 88,
                y: menuBarBottomY,
                width: 40,
                height: 30
            )
            let frame = StatusMenuPanelLayout.frame(
                anchorRect: NSRect(
                    x: screenFrame.maxX - 80,
                    y: menuBarBottomY + 4,
                    width: 24,
                    height: 22
                ),
                statusItemWindowFrame: statusItemWindowFrame,
                contentSize: NSSize(width: 280, height: 420),
                visibleFrame: reportedVisibleFrame,
                screenFrame: screenFrame
            )

            XCTAssertEqual(frame.maxY, menuBarBottomY, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(frame.minX, screenFrame.minX + 8)
            XCTAssertLessThanOrEqual(frame.maxX, screenFrame.maxX - 8)
        }
    }

    func testPanelClampsOversizedContentToTheVisibleScreen() {
        let visibleFrame = NSRect(x: 20, y: 40, width: 500, height: 400)
        let screenFrame = NSRect(x: 20, y: 40, width: 500, height: 424)
        let statusItemWindowFrame = NSRect(x: 242, y: 440, width: 40, height: 24)
        let frame = StatusMenuPanelLayout.frame(
            anchorRect: NSRect(x: 250, y: 444, width: 24, height: 20),
            statusItemWindowFrame: statusItemWindowFrame,
            contentSize: NSSize(width: 800, height: 700),
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.minX, visibleFrame.minX + 8, accuracy: 0.001)
        XCTAssertEqual(frame.minY, visibleFrame.minY + 8, accuracy: 0.001)
        XCTAssertEqual(frame.width, visibleFrame.width - 16, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, statusItemWindowFrame.minY, accuracy: 0.001)
        XCTAssertEqual(frame.height, 392, accuracy: 0.001)
    }

    func testLatestTranscriptScrollsOnlyAfterReachingItsMaximumHeight() {
        let short = MenuBarDraftEditorLayout.measurement(for: "一条简短的转写")
        let long = MenuBarDraftEditorLayout.measurement(
            for: String(repeating: "这是一段较长的最新转写内容，需要在弹页里换行。", count: 20)
        )

        XCTAssertFalse(short.showsScrollIndicator)
        XCTAssertLessThan(short.height, 56)
        XCTAssertTrue(long.showsScrollIndicator)
        XCTAssertEqual(long.height, 92, accuracy: 0.001)
    }
}

final class FloatingWindowBehaviorTests: XCTestCase {
    func testSuccessfulCorrectionAdvancesRetainedSessionWithoutLosingIdentity() throws {
        let sessionID = UUID()
        let session = FloatingCorrectionSession(
            id: sessionID,
            originalText: "hello\n",
            hidesTrailingNewline: true
        )

        let advanced = try XCTUnwrap(
            session.advancingAfterSuccessfulReplacement(
                from: "hello\n",
                to: "hello Shuo\n"
            )
        )

        XCTAssertEqual(advanced.id, sessionID)
        XCTAssertEqual(advanced.originalText, "hello Shuo\n")
        XCTAssertEqual(advanced.correctionText, "hello Shuo")
        XCTAssertTrue(advanced.hidesTrailingNewline)
    }

    func testRetainedSessionCannotAdvanceFromStaleInsertion() {
        let session = FloatingCorrectionSession(originalText: "latest text")

        XCTAssertNil(
            session.advancingAfterSuccessfulReplacement(
                from: "stale text",
                to: "edited text"
            )
        )
    }

    func testCorrectionTextHidesOnlyOneConfiguredTrailingLineBreak() {
        let hidden = FloatingCorrectionSession(
            originalText: "hello\n",
            hidesTrailingNewline: true
        )
        let preservedWhenDisabled = FloatingCorrectionSession(
            originalText: "hello\n",
            hidesTrailingNewline: false
        )
        let twoLineBreaks = FloatingCorrectionSession(
            originalText: "hello\n\n",
            hidesTrailingNewline: true
        )
        let windowsLineBreak = FloatingCorrectionSession(
            originalText: "hello\r\n",
            hidesTrailingNewline: true
        )

        XCTAssertEqual(hidden.correctionText, "hello")
        XCTAssertEqual(preservedWhenDisabled.correctionText, "hello\n")
        XCTAssertEqual(twoLineBreaks.correctionText, "hello\n")
        XCTAssertEqual(windowsLineBreak.correctionText, "hello")
    }

    func testCorrectionRestoresConfiguredTrailingLineBreakForReplacement() {
        let hidden = FloatingCorrectionSession(
            originalText: "hello\n",
            hidesTrailingNewline: true
        )
        let preservedWhenDisabled = FloatingCorrectionSession(
            originalText: "hello\n",
            hidesTrailingNewline: false
        )
        let windowsLineBreak = FloatingCorrectionSession(
            originalText: "hello\r\n",
            hidesTrailingNewline: true
        )

        XCTAssertEqual(hidden.replacementText(for: "corrected"), "corrected\n")
        XCTAssertEqual(preservedWhenDisabled.replacementText(for: "corrected"), "corrected")
        XCTAssertEqual(windowsLineBreak.replacementText(for: "corrected"), "corrected\r\n")
    }

    func testCorrectionHidesAndRestoresAutomaticTrailingSpace() {
        var settings = AppSettings()
        let automaticSpaceText = TranscriptInsertionBoundaryPolicy.apply(
            to: "hello",
            mode: settings.transcriptInsertionBoundaryMode
        )
        let session = FloatingCorrectionSession(originalText: automaticSpaceText)

        XCTAssertEqual(session.correctionText, "hello")
        XCTAssertEqual(session.replacementText(for: "corrected"), "corrected ")
        XCTAssertEqual(session.replacementText(for: "corrected "), "corrected ")

        settings.appendSpaceAfterTranscription = false
        let unseparatedText = TranscriptInsertionBoundaryPolicy.apply(
            to: "hello",
            mode: settings.transcriptInsertionBoundaryMode
        )
        let unseparatedSession = FloatingCorrectionSession(originalText: unseparatedText)
        XCTAssertEqual(unseparatedSession.correctionText, "hello")
        XCTAssertEqual(unseparatedSession.replacementText(for: "corrected"), "corrected")
    }

    func testDisplayDurationGrowsWithReadingAmountAndStaysBounded() {
        let short = FloatingWindowBehavior.displayDuration(for: "好的")
        let medium = FloatingWindowBehavior.displayDuration(
            for: "这是一段需要稍微多一点时间阅读的转写内容。"
        )
        let long = FloatingWindowBehavior.displayDuration(
            for: String(repeating: "这是较长的转写内容。", count: 40)
        )

        XCTAssertEqual(short, 5, accuracy: 0.001)
        XCTAssertGreaterThan(medium, short)
        XCTAssertGreaterThan(long, medium)
        XCTAssertLessThanOrEqual(long, 16)
    }

    func testAutomaticDismissalIgnoresSyntheticAndQueuedPrePresentationEvents() {
        XCTAssertTrue(
            FloatingWindowAutomaticDismissalPolicy.shouldIgnore(
                eventTimestamp: 102.25,
                presentationTimestamp: 103,
                isSynthetic: false
            )
        )
        XCTAssertTrue(
            FloatingWindowAutomaticDismissalPolicy.shouldIgnore(
                eventTimestamp: 103,
                presentationTimestamp: 103,
                isSynthetic: false
            )
        )
        XCTAssertTrue(
            FloatingWindowAutomaticDismissalPolicy.shouldIgnore(
                eventTimestamp: 104,
                presentationTimestamp: 103,
                isSynthetic: true
            )
        )
    }

    func testAutomaticDismissalStillRespondsToNewUserEvents() {
        XCTAssertFalse(
            FloatingWindowAutomaticDismissalPolicy.shouldIgnore(
                eventTimestamp: 103.01,
                presentationTimestamp: 103,
                isSynthetic: false
            )
        )
        XCTAssertFalse(
            FloatingWindowAutomaticDismissalPolicy.shouldIgnore(
                eventTimestamp: .nan,
                presentationTimestamp: 103,
                isSynthetic: false
            )
        )
    }

    func testWindowWidthAdaptsForOneLineAndHeightGrowsForMultipleLines() {
        let shortLine = FloatingWindowBehavior.windowSize(for: "好的")
        let longerLine = FloatingWindowBehavior.windowSize(
            for: "This is a longer single-line transcript."
        )
        let multipleLines = FloatingWindowBehavior.windowSize(
            for: (1 ... 8).map { "第\($0)行转写内容" }.joined(separator: "\n")
        )

        XCTAssertGreaterThan(longerLine.width, shortLine.width)
        XCTAssertEqual(shortLine.height, 60, accuracy: 0.001)
        XCTAssertGreaterThan(multipleLines.height, shortLine.height)
        XCTAssertLessThanOrEqual(longerLine.width, 532)
    }

    func testEditingWidthStaysStableWhileHeightTracksTheDraft() {
        let initial = FloatingWindowBehavior.editingWindowSize(for: "短句")
        let longer = FloatingWindowBehavior.editingWindowSize(
            for: String(repeating: "这是修改后的更长内容。", count: 12),
            fixedWindowWidth: initial.width
        )

        XCTAssertGreaterThanOrEqual(initial.width, 248)
        XCTAssertEqual(longer.width, initial.width, accuracy: 0.001)
        XCTAssertGreaterThan(longer.height, initial.height)
    }

    func testVeryLongFloatingContentHasABoundedHeight() {
        let size = FloatingWindowBehavior.windowSize(
            for: (1...80).map { "第\($0)行内容" }.joined(separator: "\n")
        )

        XCTAssertLessThanOrEqual(size.height, 280)
        XCTAssertGreaterThan(size.height, 60)
    }
}

final class SettingsSearchIndexTests: XCTestCase {
    func testEmptyOrWhitespaceOnlyQueryReturnsNoResults() {
        let items = makeItems(configuration: .mvp)

        XCTAssertTrue(SettingsSearchIndex.search("", in: items).isEmpty)
        XCTAssertTrue(SettingsSearchIndex.search("  \n\t", in: items).isEmpty)
    }

    func testSimplifiedChineseShortcutQueryFindsShortcutSetting() {
        let items = makeItems(
            language: .simplifiedChinese,
            configuration: .mvp
        )

        let results = SettingsSearchIndex.search("快捷键", in: items)

        XCTAssertEqual(results.first?.target, .inputShortcut)
        XCTAssertEqual(results.first?.section, .transcription)
    }

    func testCorrectionDataSearchRoutesToHumanCorrectionStage() {
        let items = makeItems(
            language: .simplifiedChinese,
            configuration: .mvp
        )

        let result = SettingsSearchIndex.search("学习记录", in: items).first

        XCTAssertEqual(result?.target, .correctionData)
        XCTAssertEqual(result?.section, .architecture)
    }

    func testBasicApplicationSettingsRouteToSettingsPage() throws {
        let items = makeItems(configuration: .mvp)
        let language = try XCTUnwrap(items.first { $0.target == .appLanguage })
        let launchAtLogin = try XCTUnwrap(items.first { $0.target == .launchAtLogin })

        XCTAssertEqual(language.section, .transcription)
        XCTAssertEqual(launchAtLogin.section, .transcription)
        XCTAssertEqual(language.pageTitle, "Settings")
    }

    func testArchitectureSearchRoutesToSignalChainPage() {
        let items = makeItems(
            language: .simplifiedChinese,
            configuration: .mvp
        )

        let result = SettingsSearchIndex.search("架构", in: items).first

        XCTAssertEqual(result?.title, "高级")
        XCTAssertEqual(result?.pageTitle, "高级")
        XCTAssertEqual(result?.target, .architectureOverview)
        XCTAssertEqual(result?.section, .architecture)
    }

    func testEnglishAliasMatchingIsCaseInsensitive() {
        let items = makeItems(configuration: .mvp)

        let results = SettingsSearchIndex.search("HoTkEy", in: items)

        XCTAssertEqual(results.first?.target, .inputShortcut)
    }

    func testMultiTokenSearchRequiresEveryTokenToMatch() {
        let items = makeItems(configuration: .mvp)

        let results = SettingsSearchIndex.search("microphone permission", in: items)

        XCTAssertEqual(results.first?.target, .microphonePermission)
        XCTAssertEqual(results.first?.section, .about)
        XCTAssertFalse(results.contains(where: { $0.target == .audioInputDevice }))
    }

    func testDisabledOptionalFeatureRoutesToItsOwningPage() throws {
        let items = makeItems(configuration: .mvp)

        let correctionRules = try XCTUnwrap(
            items.first(where: { $0.target == .featureCorrectionRules })
        )

        XCTAssertEqual(correctionRules.section, .architecture)
    }

    func testEnabledOptionalFeatureStillRoutesToItsEnableSwitch() throws {
        let items = makeItems(configuration: .fullDevelopment)

        let correctionRules = try XCTUnwrap(
            items.first(where: { $0.target == .featureCorrectionRules })
        )

        XCTAssertEqual(correctionRules.section, .architecture)
    }

    func testLanguageSpecificOutputSettingsOnlyAppearForSelectedLanguages() {
        let englishOnly = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .openAI,
                pluginConfiguration: .fullDevelopment,
                selectedTranscriptionLanguages: [.english]
            )
        )
        let chineseAndEnglish = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .openAI,
                pluginConfiguration: .fullDevelopment,
                selectedTranscriptionLanguages: [.chinese, .english]
            )
        )

        XCTAssertFalse(englishOnly.contains { $0.target == .featureChineseConversion })
        XCTAssertFalse(englishOnly.contains { $0.target == .insertChineseEnglishSpace })
        XCTAssertTrue(englishOnly.contains { $0.target == .lowercaseEnglish })

        XCTAssertTrue(chineseAndEnglish.contains { $0.target == .featureChineseConversion })
        XCTAssertTrue(chineseAndEnglish.contains { $0.target == .insertChineseEnglishSpace })
    }

    func testSentenceEndingControlsUseStableNonConditionalSearchTargets() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .fullDevelopment
            )
        )

        XCTAssertEqual(items.filter { $0.target == .punctuationHandling }.count, 1)
        XCTAssertEqual(items.filter { $0.target == .transcriptBoundary }.count, 1)
    }

    func testOpenAIConnectionSearchFallsBackToProviderWhenRuntimeFeaturesAreOff() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .fullDevelopment
            )
        )

        XCTAssertEqual(
            SettingsSearchIndex.search("OpenAI API key", in: items).first?.target,
            .transcriptionProvider
        )
        XCTAssertTrue(items.contains { $0.target == .openAITextModel })
        XCTAssertFalse(items.contains { $0.target == .voiceEditMode })
        XCTAssertFalse(items.contains { $0.target == .voiceEditCommands })
    }

    func testEnabledRuntimeRetouchIndexesVisibleOpenAIControls() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .openAI,
                pluginConfiguration: .fullDevelopment,
                transcriptRetouchEnabled: true
            )
        )

        XCTAssertEqual(
            SettingsSearchIndex.search("OpenAI API key", in: items).first?.target,
            .openAIAPIKey
        )
        XCTAssertTrue(items.contains { $0.target == .openAITextModel })
    }

    func testLocalProviderMasksPersistedCloudTextFeaturesFromSearch() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .fullDevelopment,
                transcriptRetouchEnabled: true,
                emojiPostProcessingEnabled: true,
                aiEmojiResolverEnabled: true,
                voiceEditCommandsEnabled: true,
                voiceEditCommandMode: .llmOnly,
                openAITextModelSelectionMode: .fixed
            )
        )

        XCTAssertTrue(items.contains { $0.target == .openAITextModel })
        XCTAssertFalse(items.contains { $0.target == .transcriptRetouch })
        XCTAssertFalse(items.contains { $0.target == .voiceEditCommands })
        XCTAssertEqual(
            SettingsSearchIndex.search("OpenAI API key", in: items).first?.target,
            .transcriptionProvider
        )
    }

    func testLocalOnlyVoiceEditingDoesNotExposeHiddenOpenAIControls() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .fullDevelopment,
                voiceEditCommandsEnabled: true,
                voiceEditCommandMode: .localOnly,
                openAITextModelSelectionMode: .fixed
            )
        )

        XCTAssertTrue(items.contains { $0.target == .voiceEditMode })
        XCTAssertFalse(items.contains { $0.target == .voiceEditCommands })
        XCTAssertTrue(items.contains { $0.target == .openAITextModel })
        XCTAssertEqual(
            SettingsSearchIndex.search("OpenAI API key", in: items).first?.target,
            .transcriptionProvider
        )
    }

    func testVoiceEditModelSearchOnlyIndexesTheFixedModelField() {
        let automaticItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .openAI,
                pluginConfiguration: .fullDevelopment,
                voiceEditCommandsEnabled: true,
                voiceEditCommandMode: .llmOnly
            )
        )
        let fixedItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .openAI,
                pluginConfiguration: .fullDevelopment,
                voiceEditCommandsEnabled: true,
                voiceEditCommandMode: .llmOnly,
                openAITextModelSelectionMode: .fixed
            )
        )

        XCTAssertFalse(automaticItems.contains { $0.target == .voiceEditCommands })
        XCTAssertFalse(fixedItems.contains { $0.target == .voiceEditCommands })
        XCTAssertTrue(automaticItems.contains { $0.target == .openAITextModel })
        XCTAssertTrue(fixedItems.contains { $0.target == .openAITextModel })
    }

    func testDisabledTextModelsMaskCloudFeatureSearchButKeepTheModeSelector() {
        let context = SettingsSearchContext(
            provider: .elevenLabs,
            pluginConfiguration: .fullDevelopment,
            transcriptRetouchEnabled: true,
            emojiPostProcessingEnabled: true,
            aiEmojiResolverEnabled: true,
            voiceEditCommandsEnabled: true,
            voiceEditCommandMode: .llmOnly,
            openAITextModelSelectionMode: .disabled
        )
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: context
        )

        XCTAssertFalse(context.featureVisibility.usesOpenAITextFeatures)
        XCTAssertTrue(items.contains { $0.target == .openAITextModel })
        XCTAssertFalse(items.contains { $0.target == .transcriptRetouch })
        XCTAssertTrue(items.contains { $0.target == .aiEmojiResolver })
        XCTAssertFalse(items.contains { $0.target == .voiceEditCommands })
    }

    func testEmojiChildSearchResultsFollowRuntimeVisibility() {
        let disabledItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .fullDevelopment,
                emojiPostProcessingEnabled: false
            )
        )
        let enabledItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .fullDevelopment,
                emojiPostProcessingEnabled: true
            )
        )

        XCTAssertTrue(disabledItems.contains { $0.target == .featureEmojiOutput })
        XCTAssertFalse(disabledItems.contains { $0.target == .smartEmojiMatching })
        XCTAssertEqual(
            SettingsSearchIndex.search("AI emoji", in: disabledItems).first?.target,
            .featureEmojiOutput
        )
        XCTAssertTrue(enabledItems.contains { $0.target == .smartEmojiMatching })
        XCTAssertEqual(
            SettingsSearchIndex.search("AI emoji", in: enabledItems).first?.target,
            .aiEmojiResolver
        )
    }

    func testAdvancedAudioSearchRoutesToArchitecturePage() throws {
        let items = makeItems(configuration: .mvp)
        let advancedAudio = try XCTUnwrap(
            items.first(where: { $0.target == .advancedAudio })
        )

        XCTAssertEqual(advancedAudio.section, .architecture)
    }

    func testItemIDsAreUniqueInMVPAndFullDevelopmentConfigurations() {
        for configuration in [PluginConfiguration.mvp, .fullDevelopment] {
            let items = makeItems(configuration: configuration)
            let ids = items.map(\.id)

            XCTAssertFalse(ids.isEmpty)
            XCTAssertEqual(
                Set(ids).count,
                ids.count,
                "Duplicate settings-search ID in \(configuration.profile)"
            )
        }
    }

    func testLinkProjectSearchFallsBackToTheEnableSwitchUntilAvailable() {
        let disabledItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .mvp,
                projectVocabularyEnabled: false
            )
        )
        let enabledItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .mvp,
                projectVocabularyEnabled: true
            )
        )

        XCTAssertEqual(
            SettingsSearchIndex.search("add project", in: disabledItems).first?.target,
            .projectVocabulary
        )
        XCTAssertEqual(
            SettingsSearchIndex.search("add project", in: enabledItems).first?.target,
            .linkProject
        )
    }

    func testVocabularyModulesAndPresetNamesFindPreferredTerms() {
        let englishItems = makeItems(configuration: .fullDevelopment)
        let chineseItems = makeItems(
            language: .simplifiedChinese,
            configuration: .fullDevelopment
        )

        for query in ["Coding", "Machine Learning", "PM", "preset package"] {
            XCTAssertTrue(
                SettingsSearchIndex.search(query, in: englishItems).contains {
                    $0.target == .manualTerms
                },
                "Expected \(query) to find the vocabulary module"
            )
        }
        for query in ["词库", "内置术语包", "机器学习"] {
            XCTAssertTrue(
                SettingsSearchIndex.search(query, in: chineseItems).contains {
                    $0.target == .manualTerms
                },
                "Expected \(query) to find the vocabulary module"
            )
        }
    }

    func testStoreBuildDoesNotIndexUnavailableDirectUpdateControls() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .openAI,
                pluginConfiguration: .mvp,
                supportsDirectUpdates: false
            )
        )

        XCTAssertFalse(items.contains { $0.title == "Automatic updates" })
        XCTAssertTrue(items.contains { $0.target == .updates && $0.section == .transcription })
        XCTAssertTrue(items.contains { $0.target == .exportSettings && $0.section == .about })
    }

    func testCommunityBuildDoesNotIndexAnUpdateRowThatItDoesNotRender() {
        let items = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .publicRelease,
                supportsDirectUpdates: false,
                showsUpdateSettings: false
            )
        )

        XCTAssertFalse(items.contains { $0.target == .updates })
    }

    func testCueStyleSearchFollowsCueStyleRowVisibility() {
        let disabledItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .publicRelease,
                recordingStartSoundEnabled: false
            )
        )
        let enabledItems = SettingsSearchIndex.items(
            localizer: AppLocalizer(language: .english),
            context: SettingsSearchContext(
                provider: .local,
                pluginConfiguration: .publicRelease,
                recordingStartSoundEnabled: true
            )
        )

        XCTAssertFalse(disabledItems.contains { $0.target == .inputRecordingCueStyle })
        XCTAssertTrue(enabledItems.contains { $0.target == .inputRecordingCueStyle })
        XCTAssertEqual(
            SettingsSearchIndex.search("tone", in: disabledItems).first?.target,
            .inputRecordingCue
        )
    }

    func testMaintenanceSearchUsesLocalizedDestinations() throws {
        for language in AppLanguage.allCases {
            let localizer = AppLocalizer(language: language)
            let items = SettingsSearchIndex.items(
                localizer: localizer,
                context: SettingsSearchContext(
                    provider: .local,
                    pluginConfiguration: .mvp
                )
            )

            let updates = try XCTUnwrap(items.first { $0.target == .updates })
            let export = try XCTUnwrap(items.first { $0.target == .exportSettings })
            let settingsPageTitle = AppPanelSection.transcription.sidebarTitle(localizer: localizer)
            let aboutPageTitle = AppPanelSection.about.sidebarTitle(localizer: localizer)

            XCTAssertEqual(updates.section, .transcription)
            XCTAssertEqual(export.section, .about)
            XCTAssertEqual(updates.pageTitle, settingsPageTitle)
            XCTAssertEqual(export.pageTitle, aboutPageTitle)
        }
    }

    func testNaturalChinesePhraseCanContainASettingsKeyword() {
        let items = makeItems(
            language: .simplifiedChinese,
            configuration: .mvp
        )

        let results = SettingsSearchIndex.search("我想修改快捷键", in: items)

        XCTAssertEqual(results.first?.target, .inputShortcut)
    }

    func testAutomaticSpaceSearchRoutesToOutputBoundaryControls() {
        let items = makeItems(
            language: .simplifiedChinese,
            configuration: .mvp
        )

        let results = SettingsSearchIndex.search("自动空格", in: items)

        XCTAssertEqual(results.first?.target, .transcriptBoundary)
        XCTAssertEqual(results.first?.section, .architecture)
        XCTAssertEqual(
            SettingsSearchTarget.transcriptBoundary.pipelinePlacement,
            SettingsPipelinePlacement(stage: .postProcessing, appearsInBasicSettings: false)
        )
    }

    func testSentenceEndingLabelsAreLocalizedInEverySupportedLanguage() {
        let expectations: [(AppLanguage, String, String, String)] = [
            (.english, "Punctuation & formatting", "Automatic (Recommended)", "Smart space (Recommended)"),
            (.simplifiedChinese, "标点与格式", "自动补全（推荐）", "智能空格（推荐）"),
            (.traditionalChinese, "標點與格式", "自動補全（建議）", "智慧空格（建議）"),
            (.japanese, "句読点と書式", "自動補完（推奨）", "スマートスペース（推奨）")
        ]

        for (language, section, punctuation, boundary) in expectations {
            let localizer = AppLocalizer(language: language)
            XCTAssertEqual(localizer.text(.sentenceEndings), section)
            XCTAssertEqual(localizer.text(.automaticPunctuationRecommended), punctuation)
            XCTAssertEqual(localizer.text(.smartSpaceRecommended), boundary)
            XCTAssertFalse(localizer.text(.sentenceEndingsHint).isEmpty)
        }
    }

    private func makeItems(
        language: AppLanguage = .english,
        configuration: PluginConfiguration
    ) -> [SettingsSearchItem] {
        SettingsSearchIndex.items(
            localizer: AppLocalizer(language: language),
            context: SettingsSearchContext(
                provider: .openAI,
                pluginConfiguration: configuration
            )
        )
    }
}

final class CancellableProcessRunnerTests: XCTestCase {
    func testProcessKeepsStandardOutputSeparateFromDiagnostics() async throws {
        let result = try await CancellableProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'recognized text'; printf 'runtime diagnostics' >&2"],
            timeout: 5
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput, "recognized text")
        XCTAssertEqual(result.standardError, "runtime diagnostics")
        XCTAssertEqual(result.output, "recognized text\nruntime diagnostics")
    }

    func testProcessTimeoutTerminatesAStuckProcess() async {
        let startedAt = Date()

        do {
            _ = try await CancellableProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.1
            )
            XCTFail("Expected the process to time out")
        } catch CancellableProcessRunnerError.timedOut(let timeout) {
            XCTAssertEqual(timeout, 0.1, accuracy: 0.001)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func testTaskCancellationTerminatesTheChildProcess() async {
        let task = Task {
            try await CancellableProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 10
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class FloatingWindowPlacementTests: XCTestCase {
    func testStoredCenterSurvivesCompactAndExpandedSizes() throws {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let center = NSPoint(x: 980, y: 410)

        let compact = try XCTUnwrap(
            FloatingWindowPlacement.frame(
                size: NSSize(width: 54, height: 18),
                centeredAt: center,
                visibleFrames: [visibleFrame]
            )
        )
        let expanded = try XCTUnwrap(
            FloatingWindowPlacement.frame(
                size: NSSize(width: 480, height: 180),
                centeredAt: center,
                visibleFrames: [visibleFrame]
            )
        )

        XCTAssertEqual(compact.midX, center.x, accuracy: 0.001)
        XCTAssertEqual(compact.midY, center.y, accuracy: 0.001)
        XCTAssertEqual(expanded.midX, center.x, accuracy: 0.001)
        XCTAssertEqual(expanded.midY, center.y, accuracy: 0.001)
    }

    func testUnavailableSavedScreenPositionIsClampedOntoNearestScreen() throws {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = try XCTUnwrap(
            FloatingWindowPlacement.frame(
                size: NSSize(width: 480, height: 180),
                centeredAt: NSPoint(x: 3_000, y: 1_800),
                visibleFrames: [visibleFrame]
            )
        )

        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 8)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 8)
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + 8)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY + 8)
    }

    func testDragFollowsCursorAcrossDisplaysAndRemainsVisible() {
        let primary = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let external = NSRect(x: 1_440, y: 120, width: 1_920, height: 1_080)
        let dragged = FloatingWindowPlacement.frame(
            byDragging: NSRect(x: 1_500, y: 900, width: 480, height: 180),
            cursor: NSPoint(x: 1_700, y: 950),
            visibleFrames: [primary, external]
        )

        XCTAssertGreaterThanOrEqual(dragged.minX, external.minX + 8)
        XCTAssertLessThanOrEqual(dragged.maxX, external.maxX - 8)
        XCTAssertGreaterThanOrEqual(dragged.minY, external.minY + 8)
        XCTAssertLessThanOrEqual(dragged.maxY, external.maxY - 8)
    }

    func testPositionStoreRoundTripsFiniteCoordinates() throws {
        let suiteName = "FloatingWindowPlacementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = NSPoint(x: -812.25, y: 744.5)

        FloatingWindowPositionStore.save(center, to: defaults)
        let restored = try XCTUnwrap(FloatingWindowPositionStore.load(from: defaults))

        XCTAssertEqual(restored.x, center.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, center.y, accuracy: 0.001)
    }
}

final class FloatingWindowContextMenuCopyTests: XCTestCase {
    func testContextMenuHasExactlyThreeLocalizedRowsInActionOrder() {
        let appName = AppBuildIdentity.displayName
        let expectations: [(AppLanguage, [String])] = [
            (.english, ["Hide Floating Bar", "Open \(appName)", "Quit \(appName)"]),
            (.simplifiedChinese, ["隐藏悬浮栏", "打开 \(appName)", "退出 \(appName)"]),
            (.traditionalChinese, ["隱藏懸浮列", "開啟 \(appName)", "結束 \(appName)"]),
            (.japanese, ["フローティングバーを非表示", "\(appName)を開く", "\(appName)を終了"])
        ]

        for (language, expectedTitles) in expectations {
            XCTAssertEqual(
                FloatingWindowContextMenuCopy.titles(
                    localizer: AppLocalizer(language: language)
                ),
                expectedTitles
            )
        }
    }
}
