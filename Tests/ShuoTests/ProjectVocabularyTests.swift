import Foundation
import XCTest
@testable import Shuo

final class ProjectVocabularyTests: XCTestCase {
    func testLegacyRoutingFieldsAreIgnoredWithoutLosingProjectState() throws {
        let data = Data(
            #"{"schemaVersion":2,"isProjectVocabularyEnabled":true,"automaticProjectDetectionEnabled":true,"fallbackProjectID":"40CB68CF-2D21-4B07-BDEC-09D025825284","projects":[{"id":"40CB68CF-2D21-4B07-BDEC-09D025825284","displayName":"Demo","lastKnownPath":"/tmp/Demo","isEnabled":true,"terms":[],"disabledTermIDs":[]}] }"#.utf8
        )

        let state = try JSONDecoder().decode(ProjectVocabularyState.self, from: data)

        XCTAssertTrue(state.isProjectVocabularyEnabled)
        XCTAssertEqual(state.projects.map(\.displayName), ["Demo"])
        XCTAssertEqual(state.schemaVersion, ProjectVocabularyState.currentSchemaVersion)
    }

    @MainActor
    func testDisabledProjectVocabularyKeepsManualTerms() {
        let project = LinkedProjectVocabulary(
            displayName: "Demo",
            lastKnownPath: "/tmp/Demo",
            terms: [term("ProjectOnly", score: 900)],
            lastIndexedAt: Date()
        )
        let controller = ProjectVocabularyController(
            store: nil,
            initialState: ProjectVocabularyState(
                isProjectVocabularyEnabled: false,
                projects: [project]
            )
        )

        let disabledSnapshot = controller.captureTranscriptionVocabulary(
            manualGlossary: "ManualOnly",
            isEnabled: true
        )

        XCTAssertEqual(disabledSnapshot.terms, ["Shuo", "ManualOnly"])

        let builtInOnlySnapshot = controller.captureTranscriptionVocabulary(
            manualGlossary: "Ignored",
            isEnabled: false
        )
        XCTAssertEqual(builtInOnlySnapshot.terms, ["Shuo"])

        controller.setProjectVocabularyEnabled(true)
        let enabledSnapshot = controller.captureTranscriptionVocabulary(
            manualGlossary: "ManualOnly",
            isEnabled: true
        )

        XCTAssertTrue(enabledSnapshot.terms.contains("ProjectOnly"))
    }

    func testIndexerFindsProjectTermsAndSkipsExcludedOrSensitiveFiles() throws {
        let temporaryRoot = try makeTemporaryDirectory(named: "Indexer")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let root = temporaryRoot.appendingPathComponent("ShuoKit", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try write(
            #"{"name":"shuo-kit","dependencies":{"OpenAIKit":"1.0.0"}}"#,
            to: root.appendingPathComponent("package.json")
        )
        try write(
            "struct MetricsStore {}\nfunc captureProjectVocabulary() {}",
            to: root.appendingPathComponent("VocabularyEngine.swift")
        )

        let excluded = root.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try write("struct ShouldNeverAppear {}", to: excluded.appendingPathComponent("Noise.swift"))
        try write("struct PrivateCredentialName {}", to: root.appendingPathComponent("Secrets.swift"))

        let result = try ProjectVocabularyIndexer().indexProject(at: root)
        let values = Set(result.terms.map(\.value))

        XCTAssertTrue(values.contains("ShuoKit"))
        XCTAssertTrue(values.contains("shuo-kit"))
        XCTAssertTrue(values.contains("OpenAIKit"))
        XCTAssertTrue(values.contains("MetricsStore"))
        XCTAssertTrue(values.contains("captureProjectVocabulary"))
        XCTAssertFalse(values.contains("ShouldNeverAppear"))
        XCTAssertFalse(values.contains("PrivateCredentialName"))
    }

    func testIndexerFindsCJKProjectNamesSymbolsAndDocumentationTerms() throws {
        let temporaryRoot = try makeTemporaryDirectory(named: "CJKIndexer")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let root = temporaryRoot.appendingPathComponent("语音工具", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try write(
            "struct 项目词汇管理器 {}",
            to: root.appendingPathComponent("词汇索引.swift")
        )
        try write(
            "## 项目术语索引\n\n使用 `悬浮窗口` 完成修改。",
            to: root.appendingPathComponent("README.md")
        )

        let values = Set(try ProjectVocabularyIndexer().indexProject(at: root).terms.map(\.value))

        XCTAssertTrue(values.contains("语音工具"))
        XCTAssertTrue(values.contains("项目词汇管理器"))
        XCTAssertTrue(values.contains("词汇索引"))
        XCTAssertTrue(values.contains("项目术语索引"))
        XCTAssertTrue(values.contains("悬浮窗口"))
    }

    func testIndexerRetainsOnlyTheTopSixtyProjectTerms() throws {
        let temporaryRoot = try makeTemporaryDirectory(named: "IndexerLimit")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let root = temporaryRoot.appendingPathComponent("LimitProject", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let declarations = (1...100)
            .map { "struct ProjectSpecificType\($0) {}" }
            .joined(separator: "\n")
        try write(declarations, to: root.appendingPathComponent("Terms.swift"))

        let result = try ProjectVocabularyIndexer().indexProject(at: root)

        XCTAssertEqual(result.terms.count, ProjectVocabularyLimits.maximumIndexedTermCount)
        XCTAssertTrue(result.terms.contains { $0.value == "LimitProject" })
    }

    func testProjectStateNormalizesExistingIndexesAndDisabledTermsToSixty() throws {
        let terms = (1...100).map { number in
            term("LegacyProjectTerm\(number)", score: number)
        }
        let project = LinkedProjectVocabulary(
            displayName: "Legacy",
            lastKnownPath: "/tmp/Legacy",
            terms: terms,
            disabledTermIDs: Set(terms.map(\.id))
        )
        let encoded = try JSONEncoder().encode(
            ProjectVocabularyState(
                isProjectVocabularyEnabled: true,
                projects: [project]
            )
        )

        let decoded = try JSONDecoder().decode(ProjectVocabularyState.self, from: encoded)
        let normalized = try XCTUnwrap(decoded.projects.first)

        XCTAssertEqual(normalized.terms.count, ProjectVocabularyLimits.maximumIndexedTermCount)
        XCTAssertEqual(normalized.disabledTermIDs.count, ProjectVocabularyLimits.maximumIndexedTermCount)
        XCTAssertEqual(normalized.terms.first?.value, "LegacyProjectTerm100")
        XCTAssertFalse(normalized.terms.contains { $0.value == "LegacyProjectTerm1" })
    }

    func testComposerPrioritizesManualThenProjectAndDeduplicates() {
        let projectTerms = [
            term("Duplicate", score: 900),
            term("ProjectOnly", score: 800),
            term("LowerPriority", score: 700)
        ]

        let snapshot = TranscriptionVocabularyComposer().compose(
            manualGlossary: "ManualOnly\nDuplicate",
            projectTerms: projectTerms,
            budget: TranscriptionVocabularyBudget(
                maximumTermCount: 5,
                maximumCharacterCount: 200
            )
        )

        XCTAssertEqual(snapshot.terms, ["Shuo", "ManualOnly", "Duplicate", "ProjectOnly", "LowerPriority"])
        XCTAssertEqual(snapshot.prompt, "Shuo, ManualOnly, Duplicate, ProjectOnly, LowerPriority")
    }

    func testBuiltInShuoTermIsHighestPriorityAndDeduplicated() {
        let snapshot = TranscriptionVocabularyComposer().compose(
            manualGlossary: "shuo\nGhostty"
        )

        XCTAssertEqual(snapshot.terms.first, "Shuo")
        XCTAssertEqual(snapshot.terms.filter { $0.lowercased() == "shuo" }.count, 1)
        XCTAssertTrue(snapshot.terms.contains("Ghostty"))
    }

    func testLearnedCorrectionsBecomeHintsBelowManualAndAboveProjectTerms() {
        let snapshot = TranscriptionVocabularyComposer().compose(
            manualGlossary: "ManualOnly",
            learnedCorrectionTerms: ["LearnedName", "manualonly"],
            projectTerms: [term("ProjectOnly", score: 900)],
            budget: TranscriptionVocabularyBudget(
                maximumTermCount: 5,
                maximumCharacterCount: 200
            )
        )

        XCTAssertEqual(
            snapshot.terms,
            ["Shuo", "ManualOnly", "LearnedName", "ProjectOnly"]
        )
    }

    func testTerminologyPresetCatalogUsesStableEditableSeedsAndFocusedTerms() {
        XCTAssertEqual(
            TerminologyPresetCatalog.seedItems.compactMap(\.presetID),
            ["coding", "machine-learning", "product-management"]
        )
        XCTAssertEqual(
            TerminologyPresetCatalog.seedItems.map(\.id),
            [
                UUID(uuidString: "8A9F51D3-735A-41D8-A993-47D18C01D001")!,
                UUID(uuidString: "8A9F51D3-735A-41D8-A993-47D18C01D002")!,
                UUID(uuidString: "8A9F51D3-735A-41D8-A993-47D18C01D003")!
            ]
        )
        XCTAssertTrue(
            TerminologyPresetCatalog.seedItems
                .first { $0.presetID == TerminologyPresetCatalog.codingID }?
                .normalizedTerms.contains("SwiftUI") == true
        )
        XCTAssertTrue(
            TerminologyPresetCatalog.seedItems
                .first { $0.presetID == TerminologyPresetCatalog.machineLearningID }?
                .normalizedTerms.contains("Hugging Face") == true
        )
        XCTAssertTrue(
            TerminologyPresetCatalog.seedItems
                .first { $0.presetID == TerminologyPresetCatalog.productManagementID }?
                .normalizedTerms.contains("product-market fit") == true
        )
        let allTerms = TerminologyPresetCatalog.seedItems.flatMap(\.normalizedTerms)
        XCTAssertFalse(allTerms.contains("API"))
        XCTAssertFalse(allTerms.contains("OpenAI"))
        XCTAssertFalse(allTerms.contains("ChatGPT"))
        XCTAssertFalse(allTerms.contains("GitHub"))
    }

    func testSeedMergePreservesEditsAndMigratesLegacyEnabledState() {
        var editedCoding = TerminologyPresetCatalog.seedItems[0]
        editedCoding.name = "iOS vocabulary"
        editedCoding.terms = "SwiftUI\nMyFramework"
        editedCoding.isEnabled = false

        let merged = TerminologyPresetCatalog.mergedItems(
            existing: [editedCoding],
            legacyEnabledPresetIDs: [TerminologyPresetCatalog.machineLearningID]
        )

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0], editedCoding)
        XCTAssertEqual(
            merged.first { $0.presetID == TerminologyPresetCatalog.machineLearningID }?.isEnabled,
            true
        )
        XCTAssertEqual(
            merged.first { $0.presetID == TerminologyPresetCatalog.productManagementID }?.isEnabled,
            false
        )
    }

    func testDeletedSeedStaysDeletedAcrossSubsequentMerges() throws {
        let firstMerge = TerminologyPresetCatalog.mergedItems(existing: [])
        let removed = try XCTUnwrap(
            firstMerge.first { $0.presetID == TerminologyPresetCatalog.codingID }
        )
        let tombstones = TerminologyPresetCatalog.deletionTombstones(
            afterRemoving: removed,
            existing: []
        )
        let remaining = firstMerge.filter { $0.id != removed.id }

        let relaunched = TerminologyPresetCatalog.mergedItems(
            existing: remaining,
            deletedPresetIDs: tombstones
        )

        XCTAssertFalse(relaunched.contains { $0.presetID == TerminologyPresetCatalog.codingID })
        XCTAssertEqual(relaunched.count, 2)
    }

    func testPresetIdentityRoundTripsAndOlderVocabularyDecodesWithoutIt() throws {
        let seed = TerminologyPresetCatalog.seedItems[1]
        let decodedSeed = try JSONDecoder().decode(
            NamedVocabularyItem.self,
            from: JSONEncoder().encode(seed)
        )
        XCTAssertEqual(decodedSeed, seed)

        let legacyData = Data(
            #"{"id":"D27ADE27-AE94-4B48-BBD7-E834F5118472","name":"Legacy","terms":"Ghostty","isEnabled":true}"#.utf8
        )
        let legacy = try JSONDecoder().decode(NamedVocabularyItem.self, from: legacyData)
        XCTAssertNil(legacy.presetID)
    }

    func testNamedVocabulariesComposeWithLegacyTermsAndSkipDisabledSources() {
        let enabled = NamedVocabularyItem(
            name: "Team names",
            terms: "Aaditya\n Shuotian \n",
            isEnabled: true
        )
        let disabled = NamedVocabularyItem(
            name: "Old project",
            terms: "DoNotInclude",
            isEnabled: false
        )

        let glossary = NamedVocabularyItem.combinedGlossary(
            legacyGlossary: "Ghostty\nCodex",
            items: [enabled, disabled]
        )

        XCTAssertEqual(glossary, "Ghostty\nAaditya\nCodex\nShuotian")
        XCTAssertEqual(enabled.normalizedTerms, ["Aaditya", "Shuotian"])
        XCTAssertFalse(glossary.contains("DoNotInclude"))
    }

    func testNamedVocabulariesRoundRobinAndDeduplicateAcrossSources() {
        let first = NamedVocabularyItem(
            name: "Team",
            terms: "Codex\nAaditya\nShuo"
        )
        let second = NamedVocabularyItem(
            name: "Product",
            terms: "Ghostty\nLaunch\nShuó"
        )

        let glossary = NamedVocabularyItem.combinedGlossary(
            legacyGlossary: "Legacy One\nLegacy Two\nlegacy three",
            items: [first, second]
        )

        XCTAssertEqual(
            glossary.components(separatedBy: .newlines),
            [
                "Legacy One", "Codex", "Ghostty",
                "Legacy Two", "Aaditya", "Launch",
                "legacy three", "Shuo"
            ]
        )
    }

    func testLargeLegacyGlossaryDoesNotStarveNamedVocabularyWithinBudget() {
        let legacyTerms = (1...80).map { "Legacy-\($0)" }.joined(separator: "\n")
        let named = NamedVocabularyItem(
            name: "Current project",
            terms: "ImportantAlpha\nImportantBeta"
        )
        let manualGlossary = NamedVocabularyItem.combinedGlossary(
            legacyGlossary: legacyTerms,
            items: [named]
        )

        let snapshot = TranscriptionVocabularyComposer().compose(
            manualGlossary: manualGlossary
        )

        XCTAssertTrue(snapshot.terms.contains("ImportantAlpha"))
        XCTAssertTrue(snapshot.terms.contains("ImportantBeta"))
        XCTAssertLessThanOrEqual(snapshot.terms.count, 60)
    }

    func testNamedVocabulariesRoundTripMigratesLegacyGlossaryIntoEditableSource() throws {
        var settings = AppSettings()
        settings.developerGlossary = "LegacyTerm"
        let customVocabulary = NamedVocabularyItem(
            name: "ML team",
            terms: "Hugging Face\nPyTorch",
            isEnabled: false
        )
        settings.namedVocabularies.append(customVocabulary)

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertTrue(decoded.developerGlossary.isEmpty)
        XCTAssertEqual(
            decoded.namedVocabularies.compactMap(\.presetID),
            ["coding", "machine-learning", "product-management"]
        )
        XCTAssertTrue(decoded.namedVocabularies.contains(customVocabulary))
        XCTAssertTrue(decoded.namedVocabularies.contains { item in
            item.name == "Existing preferred terms" && item.normalizedTerms == ["LegacyTerm"]
        })
        XCTAssertEqual(decoded.effectiveVocabularyTerms, ["LegacyTerm"])
    }

    func testSettingsWithoutNamedVocabularyKeyKeepExistingTermsUntouched() throws {
        let data = Data(
            #"{"appLanguage":"english","developerGlossary":"Existing\nTerms"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.developerGlossary.isEmpty)
        XCTAssertEqual(decoded.namedVocabularies.count, TerminologyPresetCatalog.seedItems.count + 1)
        XCTAssertTrue(decoded.namedVocabularies.contains { item in
            item.name == "Existing preferred terms"
                && item.normalizedTerms == ["Existing", "Terms"]
        })
        XCTAssertEqual(decoded.effectiveVocabularyTerms, ["Existing", "Terms"])
    }

    func testProjectStateRoundTripPreservesMultipleLinkedProjectsAndBookmarks() throws {
        let first = LinkedProjectVocabulary(
            displayName: "Client",
            lastKnownPath: "/tmp/Client",
            bookmarkData: Data([0x01, 0x02])
        )
        let second = LinkedProjectVocabulary(
            displayName: "Server",
            lastKnownPath: "/tmp/Server",
            bookmarkData: Data([0x03, 0x04]),
            isEnabled: false
        )
        let state = ProjectVocabularyState(
            isProjectVocabularyEnabled: true,
            projects: [first, second]
        )

        let decoded = try JSONDecoder().decode(
            ProjectVocabularyState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded.projects, [first, second])
    }

    func testComposerPlacesPresetsAfterProjectAndDeduplicatesAcrossPackages() {
        let snapshot = TranscriptionVocabularyComposer().compose(
            manualGlossary: "ManualOnly",
            projectTerms: [term("ProjectOnly", score: -100)],
            presetTerms: TerminologyPresetCatalog.seedItems.prefix(2).flatMap(\.normalizedTerms),
            budget: TranscriptionVocabularyBudget(
                maximumTermCount: 8,
                maximumCharacterCount: 200
            )
        )

        XCTAssertEqual(
            snapshot.terms,
            [
                "Shuo", "ManualOnly", "ProjectOnly", "SwiftUI",
                "Xcode", "TypeScript", "Node.js", "Kubernetes"
            ]
        )
        XCTAssertEqual(snapshot.terms.filter { $0 == "SwiftUI" }.count, 1)
    }

    func testPresetCompositionRespectsWhisperBudget() {
        let snapshot = TranscriptionVocabularyComposer().compose(
            manualGlossary: "",
            presetTerms: TerminologyPresetCatalog.seedItems.flatMap(\.normalizedTerms)
        )

        XCTAssertLessThanOrEqual(snapshot.terms.count, 60)
        XCTAssertLessThanOrEqual(snapshot.prompt.count, 900)
        XCTAssertTrue(snapshot.terms.contains("SwiftUI"))
        XCTAssertTrue(snapshot.terms.contains("Codex"))
        XCTAssertTrue(snapshot.terms.contains("PRD"))
    }

    @MainActor
    func testControllerIncludesPresetsOnlyWhenPreferredTermsAreEnabled() {
        let controller = ProjectVocabularyController(
            store: nil,
            initialState: ProjectVocabularyState(isProjectVocabularyEnabled: false)
        )

        let enabled = controller.captureTranscriptionVocabulary(
            manualGlossary: "",
            presetTerms: TerminologyPresetCatalog.seedItems[0].normalizedTerms,
            isEnabled: true
        )
        let disabled = controller.captureTranscriptionVocabulary(
            manualGlossary: "Ignored",
            presetTerms: TerminologyPresetCatalog.seedItems[0].normalizedTerms,
            isEnabled: false
        )

        XCTAssertTrue(enabled.terms.contains("SwiftUI"))
        XCTAssertEqual(disabled.terms, ["Shuo"])
    }

    @MainActor
    func testEveryEnabledProjectContributesAndDisabledSourcesStayExcluded() {
        let disabledTerm = term("TermDisabled", score: 950)
        let first = LinkedProjectVocabulary(
            displayName: "Client",
            lastKnownPath: "/tmp/Client",
            terms: [term("ClientSpecific", score: 900), disabledTerm],
            disabledTermIDs: [disabledTerm.id],
            lastIndexedAt: Date()
        )
        let second = LinkedProjectVocabulary(
            displayName: "Server",
            lastKnownPath: "/tmp/Server",
            terms: [term("ServerSpecific", score: 850)],
            lastIndexedAt: Date()
        )
        let disabled = LinkedProjectVocabulary(
            displayName: "Archive",
            lastKnownPath: "/tmp/Archive",
            isEnabled: false,
            terms: [term("ArchivedSpecific", score: 999)],
            lastIndexedAt: Date()
        )
        let controller = ProjectVocabularyController(
            store: nil,
            initialState: ProjectVocabularyState(
                isProjectVocabularyEnabled: true,
                projects: [first, second, disabled]
            )
        )

        var snapshot = controller.captureTranscriptionVocabulary(
            manualGlossary: "",
            presetTerms: [],
            isEnabled: true
        )

        XCTAssertTrue(snapshot.terms.contains("ClientSpecific"))
        XCTAssertTrue(snapshot.terms.contains("ServerSpecific"))
        XCTAssertFalse(snapshot.terms.contains("TermDisabled"))
        XCTAssertFalse(snapshot.terms.contains("ArchivedSpecific"))

        controller.setProjectEnabled(false, id: first.id)
        snapshot = controller.captureTranscriptionVocabulary(
            manualGlossary: "",
            presetTerms: [],
            isEnabled: true
        )
        XCTAssertFalse(snapshot.terms.contains("ClientSpecific"))
        XCTAssertTrue(snapshot.terms.contains("ServerSpecific"))
    }

    func testStoreRecoversBackupAndPreservesCorruptPrimary() throws {
        let root = try makeTemporaryDirectory(named: "Store")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectVocabularyStore(baseDirectory: root)
        let first = ProjectVocabularyState(projects: [
            LinkedProjectVocabulary(displayName: "First", lastKnownPath: "/tmp/First")
        ])
        let second = ProjectVocabularyState(projects: [
            LinkedProjectVocabulary(displayName: "Second", lastKnownPath: "/tmp/Second")
        ])

        try store.save(first)
        try store.save(second)
        try Data("not json".utf8).write(to: store.stateFileURL, options: .atomic)

        let result = store.load()
        XCTAssertEqual(result.state.projects.first?.displayName, "First")
        guard case .recoveredFromBackup(let preservedPath) = result.issue else {
            return XCTFail("Expected recovery from backup")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedPath))
    }

    func testStorePersistsTheSixtyTermMigrationAndBacksUpThePreviousIndex() throws {
        let root = try makeTemporaryDirectory(named: "StoreLimitMigration")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectVocabularyStore(baseDirectory: root)
        try FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )

        let terms = (1...100).map { number in
            term("StoredProjectTerm\(number)", score: number)
        }
        let oversizedState = ProjectVocabularyState(projects: [
            LinkedProjectVocabulary(
                displayName: "Stored",
                lastKnownPath: "/tmp/Stored",
                terms: terms
            )
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(oversizedState).write(to: store.stateFileURL, options: .atomic)

        let result = store.load()

        XCTAssertEqual(
            result.state.projects.first?.terms.count,
            ProjectVocabularyLimits.maximumIndexedTermCount
        )
        XCTAssertEqual(try rawStoredTermCount(at: store.stateFileURL), 60)
        XCTAssertEqual(try rawStoredTermCount(at: store.backupFileURL), 100)
    }

    func testStoreRefusesToRotateUnreadablePrimaryOverReadableBackup() throws {
        let root = try makeTemporaryDirectory(named: "StoreCorruption")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectVocabularyStore(baseDirectory: root)
        let first = ProjectVocabularyState(projects: [
            LinkedProjectVocabulary(displayName: "First", lastKnownPath: "/tmp/First")
        ])
        let second = ProjectVocabularyState(projects: [
            LinkedProjectVocabulary(displayName: "Second", lastKnownPath: "/tmp/Second")
        ])
        try store.save(first)
        try store.save(second)
        let intactBackup = try Data(contentsOf: store.backupFileURL)
        let damagedPrimary = Data("not json".utf8)
        try damagedPrimary.write(to: store.stateFileURL, options: .atomic)

        XCTAssertThrowsError(try store.save(ProjectVocabularyState())) { error in
            guard case ProjectVocabularyStoreSaveError.unreadablePrimary = error else {
                return XCTFail("Expected unreadable-primary protection, got: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: store.stateFileURL), damagedPrimary)
        XCTAssertEqual(try Data(contentsOf: store.backupFileURL), intactBackup)
    }

    func testOpenAIPromptUsesOnePromptContextControlAndComposedVocabulary() {
        var settings = AppSettings()
        settings.sendContextPrompt = false
        let vocabulary = TranscriptionVocabularySnapshot(terms: ["Shuo", "ProjectVocabulary"])

        let prompt = OpenAITranscriptionService().buildPrompt(
            settings: settings,
            context: "explicit context",
            vocabulary: vocabulary
        )

        XCTAssertTrue(prompt.contains("Shuo, ProjectVocabulary"))
        XCTAssertTrue(prompt.contains("explicit context"))
    }

    private func term(_ value: String, score: Int) -> ProjectVocabularyTerm {
        ProjectVocabularyTerm(
            value: value,
            score: score,
            occurrenceCount: 1,
            sources: [.symbol]
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShuoTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ string: String, to url: URL) throws {
        try string.write(to: url, atomically: true, encoding: .utf8)
    }

    private func rawStoredTermCount(at url: URL) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let root = try XCTUnwrap(object as? [String: Any])
        let projects = try XCTUnwrap(root["projects"] as? [[String: Any]])
        let first = try XCTUnwrap(projects.first)
        return try XCTUnwrap(first["terms"] as? [[String: Any]]).count
    }
}
