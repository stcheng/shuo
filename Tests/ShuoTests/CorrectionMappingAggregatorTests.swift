import XCTest
@testable import Shuo

final class CorrectionMappingAggregatorTests: XCTestCase {
    private let aggregator = CorrectionMappingAggregator()

    func testMixedChineseAndEnglishCorrectionsProduceLocalTokenMappings() throws {
        let summaries = aggregator.aggregate([
            event("我在用 Shou 写代码。", "我在用 Shuo 写代码。"),
            event("请让 Shou 优化这个项目。", "请让 Shuo 优化这个项目。"),
            event("这个优惠不错。", "这个优化不错。")
        ])

        let name = try XCTUnwrap(
            summaries.first { $0.beforeText == "Shou" && $0.afterText == "Shuo" }
        )
        XCTAssertEqual(name.count, 2)
        XCTAssertEqual(name.kind, .replacement)

        let chinese = try XCTUnwrap(
            summaries.first { $0.beforeText == "优惠" && $0.afterText == "优化" }
        )
        XCTAssertEqual(chinese.count, 1)
        XCTAssertFalse(summaries.contains { $0.beforeText.contains("我在用") })
    }

    func testPunctuationAndWhitespaceOnlyChangesAreIgnored() {
        let summaries = aggregator.aggregate([
            event("Hello world", "Hello,   world!"),
            event("你好世界", "你好，世界。"),
            event("keep spacing", "  keep   spacing  ")
        ])

        XCTAssertTrue(summaries.isEmpty)
    }

    func testJapaneseRunsProduceWordLevelMappings() throws {
        let summaries = aggregator.aggregate([
            event("これはウィスパーです。", "これはWhisperです。")
        ])

        let mapping = try XCTUnwrap(
            summaries.first {
                $0.beforeText == "ウィスパー" && $0.afterText == "Whisper"
            }
        )
        XCTAssertEqual(mapping.count, 1)
    }

    func testLargeWholeSentenceRewriteIsFilteredInsteadOfCreatingWordMappings() {
        let summaries = aggregator.aggregate([
            event(
                "alpha bravo charlie delta echo foxtrot golf",
                "hotel india juliet kilo lima mike november"
            )
        ])

        XCTAssertTrue(summaries.isEmpty)
    }

    func testShortReplacementInsertionAndDeletionAreRetained() throws {
        let summaries = aggregator.aggregate([
            event("please use Shou now", "please use Shuo now"),
            event("please use Shuo now", "please use new Shuo now"),
            event("please remove old token now", "please remove token now")
        ])

        XCTAssertEqual(
            try XCTUnwrap(summaries.first { $0.beforeText == "Shou" }).afterText,
            "Shuo"
        )
        XCTAssertEqual(
            try XCTUnwrap(summaries.first { $0.beforeText.isEmpty && $0.afterText == "new" }).kind,
            .insertion
        )
        XCTAssertEqual(
            try XCTUnwrap(summaries.first { $0.beforeText == "old" && $0.afterText.isEmpty }).kind,
            .deletion
        )
    }

    func testMappingsAggregateNormalizedOccurrencesAndSortByFrequencyThenText() {
        let events = [
            event("say zed now", "say Z now"),
            event("use beta now", "use Beta now"),
            event("try one now", "try 1 now"),
            event("say “beta” now", "say “Beta” now"),
            event("say zed again", "say Z again")
        ]

        let summaries = aggregator.aggregate(events)

        XCTAssertEqual(summaries.map(\.beforeText), ["beta", "zed", "one"])
        XCTAssertEqual(summaries.map(\.afterText), ["Beta", "Z", "1"])
        XCTAssertEqual(summaries.map(\.count), [2, 2, 1])
        XCTAssertEqual(aggregator.aggregate(Array(events.reversed())), summaries)
        XCTAssertEqual(
            aggregator.aggregate(events, minimumCount: 2).map(\.count),
            [2, 2]
        )
    }

    private func event(_ beforeText: String, _ afterText: String) -> CorrectionCaptureEvent {
        CorrectionCaptureEvent(
            source: .floatingCorrection,
            beforeText: beforeText,
            afterText: afterText,
            provider: .local,
            model: "local.small",
            languageHint: .mixed
        )
    }
}

final class CorrectionLearningServiceTests: XCTestCase {
    private let service = AdaptiveRecognitionService()

    func testHistoryPrefersInitialOutputAndUsesRawOnlyWithoutInitialOutput() throws {
        let initialOutputHistory = transcript(
            raw: "unrelated raw wording",
            initial: "please use Shou now",
            final: "please use Shuo now"
        )
        let rawFallbackHistory = transcript(
            raw: "please use Code X now",
            initial: nil,
            final: "please use Codex now"
        )

        let snapshot = service.learningSnapshot(
            history: [initialOutputHistory, rawFallbackHistory],
            state: AdaptiveRecognitionState(correctionEvents: [
                event(
                    "please use Code X now",
                    "please use Codex now",
                    historyID: rawFallbackHistory.id
                )
            ])
        )

        XCTAssertNotNil(pattern("Shou", "Shuo", in: snapshot))
        XCTAssertNotNil(pattern("Code X", "Codex", in: snapshot))
        XCTAssertFalse(snapshot.patterns.contains { $0.observedText.contains("unrelated") })
    }

    func testRetainedHistoryIsAuthoritativeAndDoesNotDoubleCountItsEvents() throws {
        let historyID = UUID()
        let history = [transcript(
            id: historyID,
            raw: "please use Shou now",
            initial: "please use Shou now",
            final: "please use Shuo now"
        )]
        let linkedDuplicate = event(
            "please use Shou now",
            "please use Shuo now",
            historyID: historyID
        )
        let linkedIntermediate = event(
            "please use Shou now",
            "please use Show now",
            historyID: historyID
        )
        let independent = event("say Shou again", "say Shuo again")

        let snapshot = service.learningSnapshot(
            history: history,
            state: AdaptiveRecognitionState(correctionEvents: [
                linkedIntermediate,
                linkedDuplicate,
                independent
            ])
        )
        let mapping = try XCTUnwrap(pattern("Shou", "Shuo", in: snapshot))

        XCTAssertEqual(mapping.observationCount, 2)
        XCTAssertEqual(mapping.historyObservationCount, 1)
        XCTAssertEqual(mapping.explicitObservationCount, 1)
        XCTAssertEqual(mapping.trustedSessionCount, 2)
        XCTAssertEqual(snapshot.evidenceEventCount, 2)
    }

    func testLinkedQuickCopyIsPreservedWhenHistoryDoesNotContainItsAfterText() throws {
        let historyID = UUID()
        let history = transcript(
            id: historyID,
            raw: "please use Shou now",
            initial: nil,
            final: "please use Shou now"
        )
        let copiedCorrection = event(
            "please use Shou now",
            "please use Shuo now",
            source: .quickCopy,
            historyID: historyID
        )

        let snapshot = service.learningSnapshot(
            history: [history],
            state: AdaptiveRecognitionState(correctionEvents: [copiedCorrection])
        )
        let mapping = try XCTUnwrap(pattern("Shou", "Shuo", in: snapshot))

        XCTAssertEqual(mapping.historyObservationCount, 0)
        XCTAssertEqual(mapping.explicitObservationCount, 1)
        XCTAssertEqual(mapping.trustedSessionCount, 1)
        XCTAssertEqual(snapshot.evidenceEventCount, 1)
    }

    func testFrequencyConfidenceAndAmbiguityAreExposedConservatively() throws {
        let events = [
            event("say Shou now", "say Shuo now"),
            event("use Shou here", "use Shuo here"),
            event("type Shou please", "type Shuo please"),
            event("keep Shou here", "keep Show here")
        ]
        let snapshot = snapshotWithAllEligiblePatternsEnabled(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: events)
        )
        let preferred = try XCTUnwrap(pattern("Shou", "Shuo", in: snapshot))

        XCTAssertEqual(preferred.observationCount, 3)
        XCTAssertEqual(preferred.totalObservedSourceCount, 4)
        XCTAssertEqual(preferred.alternativeCount, 1)
        XCTAssertEqual(preferred.runnerUpObservationCount, 1)
        XCTAssertEqual(preferred.confidence, 0.75, accuracy: 0.000_1)
        XCTAssertTrue(preferred.isVocabularyHintEligible)
        XCTAssertFalse(preferred.isHighConfidenceReplacementEligible)
        XCTAssertEqual(snapshot.vocabularyHints, ["Shuo"])
        XCTAssertTrue(snapshot.highConfidenceReplacements.isEmpty)
    }

    func testAutomaticReplacementRequiresThreeDistinctTrustedSessions() throws {
        let repeatedInOneSession = event(
            "Shou alpha Shou beta Shou",
            "Shuo alpha Shuo beta Shuo",
            historyID: UUID()
        )
        let oneSessionSnapshot = service.learningSnapshot(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [repeatedInOneSession])
        )
        let oneSessionPattern = try XCTUnwrap(pattern("Shou", "Shuo", in: oneSessionSnapshot))

        XCTAssertEqual(oneSessionPattern.observationCount, 3)
        XCTAssertEqual(oneSessionPattern.trustedSessionCount, 1)
        XCTAssertFalse(oneSessionPattern.isHighConfidenceReplacementEligible)

        let sharedHistoryID = UUID()
        let repeatedEditsSnapshot = service.learningSnapshot(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                event("say Shou", "say Shuo", historyID: sharedHistoryID),
                event("use Shou", "use Shuo", historyID: sharedHistoryID),
                event("type Shou", "type Shuo", historyID: sharedHistoryID)
            ])
        )
        XCTAssertEqual(
            pattern("Shou", "Shuo", in: repeatedEditsSnapshot)?.trustedSessionCount,
            1
        )

        let threeSessionSnapshot = service.learningSnapshot(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                repeatedInOneSession,
                event("say Shou", "say Shuo", historyID: UUID()),
                event("use Shou", "use Shuo", historyID: UUID())
            ])
        )
        let threeSessionPattern = try XCTUnwrap(pattern("Shou", "Shuo", in: threeSessionSnapshot))

        XCTAssertEqual(threeSessionPattern.trustedSessionCount, 3)
        XCTAssertTrue(threeSessionPattern.isHighConfidenceReplacementEligible)
    }

    func testRawHistoryWithoutExplicitCorrectionIsNotLearningEvidence() {
        let history = (0..<3).map { index in
            transcript(
                raw: "please use Shou \(index)",
                initial: nil,
                final: "please use Shuo \(index)"
            )
        }
        let snapshot = service.learningSnapshot(
            history: history,
            state: AdaptiveRecognitionState()
        )

        XCTAssertEqual(snapshot.evidenceEventCount, 0)
        XCTAssertTrue(snapshot.patterns.isEmpty)
        XCTAssertTrue(snapshot.vocabularyHints.isEmpty)
    }

    func testRawPostprocessingWithoutInitialOrExplicitCorrectionProducesNoLearningEvidence() {
        let snapshot = service.learningSnapshot(
            history: [
                transcript(
                    raw: "今天測試",
                    initial: nil,
                    final: "今天测试。"
                )
            ],
            state: AdaptiveRecognitionState()
        )

        XCTAssertEqual(snapshot.evidenceEventCount, 0)
        XCTAssertTrue(snapshot.patterns.isEmpty)
        XCTAssertTrue(snapshot.vocabularyHints.isEmpty)
        XCTAssertTrue(snapshot.highConfidenceReplacements.isEmpty)
    }

    func testRawHistoryWithMatchingExplicitCorrectionsCanBecomeLearningEvidence() throws {
        let history = (0..<3).map { index in
            transcript(
                raw: "please use Shou \(index)",
                initial: nil,
                final: "please use Shuo \(index)"
            )
        }
        let events = history.map { item in
            event(
                item.rawText,
                item.text,
                historyID: item.id
            )
        }
        let snapshot = service.learningSnapshot(
            history: history,
            state: AdaptiveRecognitionState(correctionEvents: events)
        )
        let mapping = try XCTUnwrap(pattern("Shou", "Shuo", in: snapshot))

        XCTAssertEqual(mapping.observationCount, 3)
        XCTAssertEqual(mapping.historyObservationCount, 3)
        XCTAssertEqual(mapping.explicitObservationCount, 0)
        XCTAssertEqual(mapping.trustedSessionCount, 3)
        XCTAssertTrue(mapping.isHighConfidenceReplacementEligible)
    }

    func testVoiceRewriteEventsAreIgnoredAndCJKWordReplacementUsesWordBoundaries() throws {
        let voiceEvents = (0..<3).map { _ in
            event(
                "make this short",
                "ship it",
                source: .voiceEditCommand
            )
        }
        let chineseHistory = (0..<3).map { _ in
            transcript(
                raw: "这个优惠不错",
                initial: "这个优惠不错",
                final: "这个优化不错"
            )
        }
        let snapshot = snapshotWithAllEligiblePatternsEnabled(
            history: chineseHistory,
            state: AdaptiveRecognitionState(correctionEvents: voiceEvents)
        )
        let chinese = try XCTUnwrap(pattern("优惠", "优化", in: snapshot))

        XCTAssertEqual(snapshot.evidenceEventCount, 3)
        XCTAssertFalse(snapshot.patterns.contains { $0.observedText == "make this short" })
        XCTAssertTrue(chinese.isVocabularyHintEligible)
        XCTAssertTrue(chinese.isHighConfidenceReplacementEligible)
        XCTAssertEqual(snapshot.vocabularyHints, ["优化"])
        XCTAssertEqual(
            service.applyHighConfidenceReplacements(
                to: "这个优惠不错，优惠券也不错",
                snapshot: snapshot
            ),
            "这个优化不错，优惠券也不错"
        )
    }

    func testSingleCJKGraphemeCorrectionRemainsStatisticsOnly() throws {
        let snapshot = service.learningSnapshot(
            history: (0..<3).map { _ in
                transcript(
                    raw: "请用 惠 字",
                    initial: "请用 惠 字",
                    final: "请用 慧 字"
                )
            },
            state: AdaptiveRecognitionState()
        )
        let mapping = try XCTUnwrap(pattern("惠", "慧", in: snapshot))

        XCTAssertEqual(mapping.observationCount, 3)
        XCTAssertFalse(mapping.isVocabularyHintEligible)
        XCTAssertFalse(mapping.isHighConfidenceReplacementEligible)
        XCTAssertEqual(
            service.applyHighConfidenceReplacements(to: "惠 惠顾", snapshot: snapshot),
            "惠 惠顾"
        )
    }

    func testHighConfidenceReplacementUsesBoundariesAndDoesNotCascade() {
        let events = [
            event("say Shou", "say Shuo"),
            event("use Shou", "use Shuo"),
            event("type Shou", "type Shuo"),
            event("say Shuo", "say Nova"),
            event("use Shuo", "use Nova"),
            event("type Shuo", "type Nova")
        ]
        let snapshot = snapshotWithAllEligiblePatternsEnabled(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: events)
        )

        XCTAssertEqual(
            service.applyHighConfidenceReplacements(
                to: "Shou Shout Shuo",
                snapshot: snapshot
            ),
            "Shuo Shout Nova"
        )
    }

    func testReverseMappingsDisableHintsAndAutomaticReplacement() throws {
        let snapshot = service.learningSnapshot(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                event("say Shou", "say Shuo"),
                event("use Shou", "use Shuo"),
                event("type Shou", "type Shuo"),
                event("say Shuo", "say Shou"),
                event("use Shuo", "use Shou"),
                event("type Shuo", "type Shou")
            ])
        )
        let forward = try XCTUnwrap(pattern("Shou", "Shuo", in: snapshot))
        let reverse = try XCTUnwrap(pattern("Shuo", "Shou", in: snapshot))

        XCTAssertTrue(forward.hasReverseMapping)
        XCTAssertTrue(reverse.hasReverseMapping)
        XCTAssertFalse(forward.isVocabularyHintEligible)
        XCTAssertFalse(reverse.isVocabularyHintEligible)
        XCTAssertTrue(snapshot.vocabularyHints.isEmpty)
        XCTAssertTrue(snapshot.highConfidenceReplacements.isEmpty)
    }

    func testNumericAndShortLowercaseSourcesRemainStatisticsOnly() throws {
        let snapshot = service.learningSnapshot(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                event("use 12 now", "use 13 now"),
                event("say 12 now", "say 13 now"),
                event("type 12 now", "type 13 now"),
                event("put it in here", "put it on here"),
                event("keep it in place", "keep it on place"),
                event("leave it in view", "leave it on view")
            ])
        )
        let numeric = try XCTUnwrap(pattern("12", "13", in: snapshot))
        let shortWord = try XCTUnwrap(pattern("in", "on", in: snapshot))

        XCTAssertFalse(numeric.isHighConfidenceReplacementEligible)
        XCTAssertFalse(shortWord.isHighConfidenceReplacementEligible)
        XCTAssertFalse(numeric.isVocabularyHintEligible)
        XCTAssertFalse(shortWord.isVocabularyHintEligible)
        XCTAssertTrue(snapshot.vocabularyHints.isEmpty)
        XCTAssertTrue(snapshot.highConfidenceReplacements.isEmpty)
        XCTAssertEqual(
            service.applyHighConfidenceReplacements(to: "12 in input", snapshot: snapshot),
            "12 in input"
        )
    }

    func testLearningResetCutoffHidesOlderHistoryAndEventsWithoutDeletingHistory() {
        let cutoff = Date(timeIntervalSince1970: 2_000)
        let oldHistory = transcript(
            raw: "say Shou",
            initial: "say Shou",
            final: "say Shuo",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let oldEvent = event(
            "use Shou",
            "use Shuo",
            createdAt: Date(timeIntervalSince1970: 1_500)
        )
        let newEvent = event(
            "say Code X",
            "say Codex",
            createdAt: Date(timeIntervalSince1970: 2_500)
        )

        let snapshot = service.learningSnapshot(
            history: [oldHistory],
            state: AdaptiveRecognitionState(
                correctionEvents: [oldEvent, newEvent],
                learningResetAt: cutoff
            )
        )

        XCTAssertNil(pattern("Shou", "Shuo", in: snapshot))
        XCTAssertNotNil(pattern("Code X", "Codex", in: snapshot))
        XCTAssertEqual(snapshot.evidenceEventCount, 1)
    }

    func testLearningResetCutoffRoundTripsAndMissingCutoffDecodesAsNil() throws {
        let cutoff = Date(timeIntervalSince1970: 2_000)
        let enabledPatternID = CorrectionLearningPattern.ID(
            observedKey: "shou",
            preferredKey: "Shuo"
        )
        let state = AdaptiveRecognitionState(
            enabledCorrectionPatternIDs: [enabledPatternID],
            learningResetAt: cutoff
        )
        let decoded = try JSONDecoder().decode(
            AdaptiveRecognitionState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded.learningResetAt, cutoff)
        XCTAssertEqual(decoded.enabledCorrectionPatternIDs, [enabledPatternID])
        XCTAssertNil(
            try JSONDecoder().decode(
                AdaptiveRecognitionState.self,
                from: Data("{}".utf8)
            ).learningResetAt
        )
        XCTAssertTrue(
            try JSONDecoder().decode(
                AdaptiveRecognitionState.self,
                from: Data("{}".utf8)
            ).enabledCorrectionPatternIDs.isEmpty
        )
    }

    func testPostProcessorAppliesSnapshotOnlyInOptedInReplacementMode() {
        let snapshot = snapshotWithAllEligiblePatternsEnabled(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                event("say Shou", "say Shuo"),
                event("use Shou", "use Shuo"),
                event("type Shou", "type Shuo")
            ])
        )
        var settings = AppSettings()
        settings.useCustomCorrections = false

        XCTAssertEqual(
            TranscriptPostProcessor().process(
                "Shou",
                settings: settings,
                correctionLearningSnapshot: snapshot
            ),
            "Shou"
        )

        settings.adaptiveRecognitionEnabled = true
        settings.adaptiveRecognitionMode = .vocabularyHints
        XCTAssertEqual(
            TranscriptPostProcessor().process(
                "Shou",
                settings: settings,
                correctionLearningSnapshot: snapshot
            ),
            "Shou"
        )

        settings.adaptiveRecognitionMode = .highConfidenceReplacement
        XCTAssertEqual(
            TranscriptPostProcessor().process(
                "Shou",
                settings: settings,
                correctionLearningSnapshot: snapshot
            ),
            "Shuo"
        )
    }

    func testExplicitCustomRuleWinsAfterLearnedReplacement() {
        let snapshot = snapshotWithAllEligiblePatternsEnabled(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                event("say Shou", "say Shuo"),
                event("use Shou", "use Shuo"),
                event("type Shou", "type Shuo")
            ])
        )
        var settings = AppSettings()
        settings.adaptiveRecognitionEnabled = true
        settings.adaptiveRecognitionMode = .highConfidenceReplacement
        settings.useCustomCorrections = true
        settings.customCorrections = "Shuo => SHUO-CUSTOM"

        XCTAssertEqual(
            TranscriptPostProcessor().process(
                "Shou",
                settings: settings,
                correctionLearningSnapshot: snapshot
            ),
            "SHUO-CUSTOM"
        )
    }

    func testExplicitCustomRuleWinsWhenItConflictsWithLearnedSource() {
        let snapshot = snapshotWithAllEligiblePatternsEnabled(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                event("say Shou", "say Shuo"),
                event("use Shou", "use Shuo"),
                event("type Shou", "type Shuo")
            ])
        )
        var settings = AppSettings()
        settings.adaptiveRecognitionEnabled = true
        settings.adaptiveRecognitionMode = .highConfidenceReplacement
        settings.useCustomCorrections = true
        settings.customCorrections = "shou => MANUAL-CUSTOM"

        XCTAssertEqual(
            TranscriptPostProcessor().process(
                "Shou",
                settings: settings,
                correctionLearningSnapshot: snapshot
            ),
            "MANUAL-CUSTOM"
        )
    }

    func testOnlyIndividuallyEnabledPatternsProduceHintsAndReplacements() throws {
        let events = [
            event("say Shou", "say Shuo", historyID: UUID()),
            event("use Shou", "use Shuo", historyID: UUID()),
            event("type Shou", "type Shuo", historyID: UUID()),
            event("say Code X", "say Codex", historyID: UUID()),
            event("use Code X", "use Codex", historyID: UUID()),
            event("type Code X", "type Codex", historyID: UUID())
        ]
        var state = AdaptiveRecognitionState(correctionEvents: events)
        let disabledSnapshot = service.learningSnapshot(history: [], state: state)
        let shuoPattern = try XCTUnwrap(pattern("Shou", "Shuo", in: disabledSnapshot))

        XCTAssertTrue(disabledSnapshot.vocabularyHints.isEmpty)
        XCTAssertTrue(disabledSnapshot.highConfidenceReplacements.isEmpty)

        state.enabledCorrectionPatternIDs = [shuoPattern.id]
        let enabledSnapshot = service.learningSnapshot(history: [], state: state)

        XCTAssertEqual(enabledSnapshot.vocabularyHints, ["Shuo"])
        XCTAssertEqual(enabledSnapshot.highConfidenceReplacements.map(\.preferredText), ["Shuo"])
        XCTAssertEqual(
            service.applyHighConfidenceReplacements(
                to: "Shou and Code X",
                snapshot: enabledSnapshot
            ),
            "Shuo and Code X"
        )
    }

    func testPatternsRemainSortedByDescendingFrequency() {
        let snapshot = service.learningSnapshot(
            history: [],
            state: AdaptiveRecognitionState(correctionEvents: [
                event("Alpha", "Aster"),
                event("Alpha", "Aster"),
                event("Alpha", "Aster"),
                event("Beta", "Bravo"),
                event("Beta", "Bravo"),
                event("Gamma", "Delta")
            ])
        )

        XCTAssertEqual(snapshot.patterns.map(\.observationCount), [3, 2, 1])
        XCTAssertEqual(snapshot.patterns.map(\.observedText), ["Alpha", "Beta", "Gamma"])

        XCTAssertEqual(
            CorrectionLearningPatternDisplayPolicy.visiblePatterns(
                from: snapshot.patterns,
                frequentLimit: 2,
                enabledPatternIDs: []
            ).map(\.observedText),
            ["Alpha", "Beta"]
        )
        XCTAssertEqual(
            CorrectionLearningPatternDisplayPolicy.visiblePatterns(
                from: snapshot.patterns,
                frequentLimit: 2,
                enabledPatternIDs: [snapshot.patterns[2].id]
            ).map(\.observedText),
            ["Alpha", "Beta", "Gamma"]
        )
    }

    func testPluginGateKeepsPublicReleaseOptIn() {
        var settings = AppSettings()
        settings.adaptiveRecognitionEnabled = true
        settings.adaptiveRecognitionMode = .highConfidenceReplacement

        XCTAssertFalse(
            PluginCapabilityPolicy(configuration: .publicRelease)
                .applying(to: settings)
                .adaptiveRecognitionEnabled
        )

        var optedIn = PluginConfiguration.publicRelease
        optedIn.setEnabled(true, for: .smartAdaptiveRecognition)
        XCTAssertTrue(
            PluginCapabilityPolicy(configuration: optedIn)
                .applying(to: settings)
                .adaptiveRecognitionEnabled
        )
        XCTAssertTrue(
            PluginCatalog.descriptor(for: .smartAdaptiveRecognition)?.isPublic == true
        )
    }

    func testAdaptiveRecognitionModeRoundTripsAndMissingValueUsesSafeDefault() throws {
        XCTAssertEqual(
            AdaptiveRecognitionMode.allCases,
            [.highConfidenceReplacement, .vocabularyHints]
        )
        XCTAssertTrue(AdaptiveRecognitionMode.highConfidenceReplacement.usesLocalReplacement)
        XCTAssertFalse(AdaptiveRecognitionMode.highConfidenceReplacement.usesVocabularyHints)
        XCTAssertTrue(AdaptiveRecognitionMode.vocabularyHints.usesVocabularyHints)
        XCTAssertFalse(AdaptiveRecognitionMode.vocabularyHints.usesLocalReplacement)

        var settings = AppSettings()
        settings.adaptiveRecognitionEnabled = true
        settings.adaptiveRecognitionMode = .highConfidenceReplacement

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )
        XCTAssertTrue(decoded.adaptiveRecognitionEnabled)
        XCTAssertEqual(decoded.adaptiveRecognitionMode, .highConfidenceReplacement)

        let defaults = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(defaults.adaptiveRecognitionEnabled)
        XCTAssertEqual(defaults.adaptiveRecognitionMode, .vocabularyHints)
    }

    private func pattern(
        _ before: String,
        _ after: String,
        in snapshot: CorrectionLearningSnapshot
    ) -> CorrectionLearningPattern? {
        snapshot.patterns.first {
            $0.observedText == before && $0.preferredText == after
        }
    }

    private func snapshotWithAllEligiblePatternsEnabled(
        history: [TranscriptItem],
        state: AdaptiveRecognitionState
    ) -> CorrectionLearningSnapshot {
        let potentialSnapshot = service.learningSnapshot(history: history, state: state)
        var enabledState = state
        enabledState.enabledCorrectionPatternIDs = Set(
            potentialSnapshot.patterns
                .filter(\.isVocabularyHintEligible)
                .map(\.id)
        )
        return service.learningSnapshot(history: history, state: enabledState)
    }

    private func event(
        _ beforeText: String,
        _ afterText: String,
        source: AdaptiveRecognitionFeedbackSource = .floatingCorrection,
        historyID: UUID? = nil,
        createdAt: Date = Date()
    ) -> CorrectionCaptureEvent {
        CorrectionCaptureEvent(
            createdAt: createdAt,
            source: source,
            beforeText: beforeText,
            afterText: afterText,
            provider: .local,
            model: "local.small",
            languageHint: .mixed,
            historyID: historyID
        )
    }

    private func transcript(
        id: UUID = UUID(),
        raw: String,
        initial: String?,
        final: String,
        createdAt: Date = Date()
    ) -> TranscriptItem {
        TranscriptItem(
            id: id,
            text: final,
            rawText: raw,
            locallyProcessedText: initial ?? raw,
            initialText: initial,
            createdAt: createdAt,
            provider: .local,
            model: "local.small",
            languageHint: .mixed
        )
    }
}
