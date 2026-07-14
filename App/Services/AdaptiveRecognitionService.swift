import Foundation
import NaturalLanguage

struct AdaptiveRecognitionLearningConfiguration: Equatable {
    var vocabularyMinimumObservationCount: Int
    var vocabularyMinimumConfidence: Double
    var vocabularyMinimumLead: Int
    var maximumVocabularyHintCount: Int
    var replacementMinimumTrustedSessionCount: Int
    var replacementMinimumConfidence: Double
    var maximumAutomaticSourceCharacterCount: Int

    init(
        vocabularyMinimumObservationCount: Int = 2,
        vocabularyMinimumConfidence: Double = 0.75,
        vocabularyMinimumLead: Int = 2,
        maximumVocabularyHintCount: Int = 24,
        replacementMinimumTrustedSessionCount: Int = 3,
        replacementMinimumConfidence: Double = 1,
        maximumAutomaticSourceCharacterCount: Int = 32
    ) {
        self.vocabularyMinimumObservationCount = max(1, vocabularyMinimumObservationCount)
        self.vocabularyMinimumConfidence = min(max(vocabularyMinimumConfidence, 0), 1)
        self.vocabularyMinimumLead = max(1, vocabularyMinimumLead)
        self.maximumVocabularyHintCount = max(1, maximumVocabularyHintCount)
        self.replacementMinimumTrustedSessionCount = max(
            1,
            replacementMinimumTrustedSessionCount
        )
        self.replacementMinimumConfidence = min(max(replacementMinimumConfidence, 0), 1)
        self.maximumAutomaticSourceCharacterCount = max(2, maximumAutomaticSourceCharacterCount)
    }
}

struct AdaptiveRecognitionService {
    private struct HistoryEvidence {
        let event: CorrectionCaptureEvent
        let isTrustedForReplacement: Bool
    }

    private struct MappingKey: Hashable {
        let observedKey: String
        let preferredKey: String
    }

    private enum EvidenceSessionKey: Hashable {
        case history(UUID)
        case event(UUID)
    }

    private struct RepresentativeMapping {
        var observedText: String
        var preferredText: String
        var strongestExactCount: Int
    }

    private let configuration: AdaptiveRecognitionLearningConfiguration
    private let aggregator: CorrectionMappingAggregator
    private let snapshotCache: CorrectionLearningSnapshotCache

    init(
        configuration: AdaptiveRecognitionLearningConfiguration = .init(),
        aggregator: CorrectionMappingAggregator = .init()
    ) {
        self.configuration = configuration
        self.aggregator = aggregator
        snapshotCache = CorrectionLearningSnapshotCache()
    }

    func recordFeedback(
        before beforeText: String,
        after afterText: String,
        source: AdaptiveRecognitionFeedbackSource,
        context: AdaptiveRecognitionFeedbackContext,
        state: AdaptiveRecognitionState,
        now: Date = Date()
    ) -> AdaptiveRecognitionState {
        let normalizedBefore = beforeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAfter = afterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBefore.isEmpty,
              !normalizedAfter.isEmpty,
              normalizedBefore != normalizedAfter else {
            return state
        }

        let event = CorrectionCaptureEvent(
            createdAt: now,
            source: source,
            beforeText: beforeText,
            afterText: afterText,
            provider: context.provider,
            model: context.model,
            languageHint: context.languageHint,
            historyID: context.historyID,
            audioFileName: context.audioFileName
        )

        var updated = state
        updated.correctionEvents.insert(event, at: 0)
        return updated
    }

    /// Derives learning data from the authoritative final state of retained
    /// History plus explicit edits which are not represented by retained
    /// History. This avoids counting a single correction twice.
    func learningSnapshot(
        history: [TranscriptItem],
        state: AdaptiveRecognitionState
    ) -> CorrectionLearningSnapshot {
        let potentialSnapshot = snapshotCache.value(
            history: history,
            events: state.correctionEvents,
            learningResetAt: state.learningResetAt
        ) {
            let eligibleHistory: [TranscriptItem]
            let eligibleEvents: [CorrectionCaptureEvent]
            if let cutoff = state.learningResetAt {
                eligibleHistory = history.filter { $0.createdAt > cutoff }
                eligibleEvents = state.correctionEvents.filter { $0.createdAt > cutoff }
            } else {
                eligibleHistory = history
                eligibleEvents = state.correctionEvents
            }
            return deriveLearningSnapshot(
                history: eligibleHistory,
                explicitEvents: eligibleEvents
            )
        }
        return applyingEnabledPatterns(
            to: potentialSnapshot,
            enabledPatternIDs: state.enabledCorrectionPatternIDs
        )
    }

    /// Keeps all derived patterns visible while exposing only explicitly
    /// enabled patterns to provider hints and local replacement. This is a
    /// cheap projection over the cached corpus, so flipping one row never
    /// reruns token diffs across all retained History.
    func applyingEnabledPatterns(
        to snapshot: CorrectionLearningSnapshot,
        enabledPatternIDs: Set<CorrectionLearningPattern.ID>
    ) -> CorrectionLearningSnapshot {
        let enabledPatterns = snapshot.patterns.filter {
            enabledPatternIDs.contains($0.id)
        }
        let vocabularyHints = uniqueVocabularyHints(from: enabledPatterns)
        let replacements = enabledPatterns
            .filter { $0.isHighConfidenceReplacementEligible }
            .sorted {
                if $0.observedText.count != $1.observedText.count {
                    return $0.observedText.count > $1.observedText.count
                }
                return Self.patternOrdering($0, $1)
            }

        return CorrectionLearningSnapshot(
            evidenceEventCount: snapshot.evidenceEventCount,
            historyEvidenceEventCount: snapshot.historyEvidenceEventCount,
            explicitEvidenceEventCount: snapshot.explicitEvidenceEventCount,
            patterns: snapshot.patterns,
            vocabularyHints: vocabularyHints,
            highConfidenceReplacements: replacements
        )
    }

    func applyHighConfidenceReplacements(
        to text: String,
        snapshot: CorrectionLearningSnapshot
    ) -> String {
        AdaptiveRecognitionReplacementEngine.apply(
            snapshot.highConfidenceReplacements,
            to: text
        )
    }

    private func deriveLearningSnapshot(
        history: [TranscriptItem],
        explicitEvents: [CorrectionCaptureEvent]
    ) -> CorrectionLearningSnapshot {
        let learningExplicitEvents = explicitEvents.filter {
            $0.source != .voiceEditCommand
        }
        var linkedEventsByHistoryID: [UUID: [CorrectionCaptureEvent]] = [:]
        for event in learningExplicitEvents {
            if let historyID = event.historyID {
                linkedEventsByHistoryID[historyID, default: []].append(event)
            }
        }
        let finalMatchedHistoryIDs = Set(history.compactMap { item -> UUID? in
            let finalText = Self.comparisonText(item.text)
            guard !finalText.isEmpty,
                  linkedEventsByHistoryID[item.id]?.contains(where: {
                      Self.comparisonText($0.afterText) == finalText
                  }) == true else {
                return nil
            }
            return item.id
        })
        let historyEvidenceItems: [HistoryEvidence] = history.compactMap { item in
            self.historyEvidence(
                from: item,
                rawFallbackWasExplicitlyCorrected: finalMatchedHistoryIDs.contains(item.id)
            )
        }
        let authoritativeHistoryIDs = Set(
            historyEvidenceItems.compactMap(\.event.historyID)
        ).intersection(finalMatchedHistoryIDs)

        // History supersedes its linked action log only when at least one
        // explicit event's after-text is actually reflected by the retained
        // final text. Quick Copy and failed replacement attempts intentionally
        // retain their explicit evidence instead of being dropped by ID alone.
        let independentExplicitEvents = learningExplicitEvents.filter { event in
            guard let historyID = event.historyID else {
                return true
            }
            return !authoritativeHistoryIDs.contains(historyID)
        }

        let historyEvents = historyEvidenceItems.map { $0.event }
        let trustedEvents = historyEvidenceItems
            .filter { $0.isTrustedForReplacement }
            .map { $0.event } + independentExplicitEvents
        let allEvents = historyEvents + independentExplicitEvents
        guard !allEvents.isEmpty else {
            return .empty
        }

        let allSummaries = aggregator.aggregate(allEvents)
            .filter { $0.kind == .replacement }
        guard !allSummaries.isEmpty else {
            return CorrectionLearningSnapshot(
                evidenceEventCount: allEvents.count,
                historyEvidenceEventCount: historyEvents.count,
                explicitEvidenceEventCount: independentExplicitEvents.count,
                patterns: [],
                vocabularyHints: [],
                highConfidenceReplacements: []
            )
        }

        let allCounts = groupedCounts(allSummaries)
        let trustedCounts = groupedCounts(
            aggregator.aggregate(trustedEvents).filter { $0.kind == .replacement }
        )
        let trustedSessionCounts = distinctSessionCounts(trustedEvents)
        let historyCounts = groupedCounts(
            aggregator.aggregate(historyEvents).filter { $0.kind == .replacement }
        )
        let explicitCounts = groupedCounts(
            aggregator.aggregate(independentExplicitEvents).filter { $0.kind == .replacement }
        )
        let representatives = representativeMappings(allSummaries)

        var totalsByObservedKey: [String: Int] = [:]
        var alternativesByObservedKey: [String: Set<String>] = [:]
        for (key, count) in allCounts {
            totalsByObservedKey[key.observedKey, default: 0] += count
            alternativesByObservedKey[key.observedKey, default: []].insert(key.preferredKey)
        }

        let patterns = allCounts.compactMap { key, observationCount -> CorrectionLearningPattern? in
            guard let representative = representatives[key] else {
                return nil
            }
            let totalObservedSourceCount = totalsByObservedKey[key.observedKey] ?? observationCount
            let competingCounts = allCounts.compactMap { candidateKey, count -> Int? in
                candidateKey.observedKey == key.observedKey && candidateKey != key ? count : nil
            }
            let runnerUpCount = competingCounts.max() ?? 0
            let alternativeCount = max(
                0,
                (alternativesByObservedKey[key.observedKey]?.count ?? 1) - 1
            )
            let confidence = totalObservedSourceCount > 0
                ? Double(observationCount) / Double(totalObservedSourceCount)
                : 0
            let trustedObservationCount = trustedCounts[key, default: 0]
            let trustedSessionCount = trustedSessionCounts[key, default: 0]
            let hasReverseMapping = Self.hasReverseMapping(
                for: key,
                representative: representative,
                in: allCounts.keys
            )
            let isVocabularyHintEligible = vocabularyHintIsEligible(
                observedText: representative.observedText,
                preferredText: representative.preferredText,
                observationCount: observationCount,
                confidence: confidence,
                runnerUpCount: runnerUpCount,
                hasReverseMapping: hasReverseMapping
            )
            let isHighConfidenceReplacementEligible = automaticReplacementIsEligible(
                observedText: representative.observedText,
                preferredText: representative.preferredText,
                trustedSessionCount: trustedSessionCount,
                confidence: confidence,
                alternativeCount: alternativeCount,
                hasReverseMapping: hasReverseMapping
            )

            return CorrectionLearningPattern(
                id: CorrectionLearningPattern.ID(
                    observedKey: key.observedKey,
                    preferredKey: key.preferredKey
                ),
                observedText: representative.observedText,
                preferredText: representative.preferredText,
                observationCount: observationCount,
                trustedObservationCount: trustedObservationCount,
                trustedSessionCount: trustedSessionCount,
                historyObservationCount: historyCounts[key, default: 0],
                explicitObservationCount: explicitCounts[key, default: 0],
                totalObservedSourceCount: totalObservedSourceCount,
                alternativeCount: alternativeCount,
                hasReverseMapping: hasReverseMapping,
                runnerUpObservationCount: runnerUpCount,
                confidence: confidence,
                isVocabularyHintEligible: isVocabularyHintEligible,
                isHighConfidenceReplacementEligible: isHighConfidenceReplacementEligible
            )
        }
        .sorted(by: Self.patternOrdering)

        return CorrectionLearningSnapshot(
            evidenceEventCount: allEvents.count,
            historyEvidenceEventCount: historyEvents.count,
            explicitEvidenceEventCount: independentExplicitEvents.count,
            patterns: patterns,
            vocabularyHints: [],
            highConfidenceReplacements: []
        )
    }

    private func historyEvidence(
        from item: TranscriptItem,
        rawFallbackWasExplicitlyCorrected: Bool
    ) -> HistoryEvidence? {
        guard item.outcome.isSuccessful else {
            return nil
        }

        let beforeText: String
        let isTrustedForReplacement: Bool
        if let initialText = item.initialText {
            beforeText = initialText
            isTrustedForReplacement = true
        } else {
            guard rawFallbackWasExplicitlyCorrected else {
                // Raw and final often differ because of ordinary configured
                // post-processing. Without a matching explicit correction,
                // that difference is not learning evidence.
                return nil
            }
            beforeText = item.rawText
            isTrustedForReplacement = true
        }

        let normalizedBefore = beforeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAfter = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBefore.isEmpty,
              !normalizedAfter.isEmpty,
              normalizedBefore != normalizedAfter else {
            return nil
        }

        return HistoryEvidence(
            event: CorrectionCaptureEvent(
                id: item.id,
                createdAt: item.createdAt,
                source: .historyEdit,
                beforeText: beforeText,
                afterText: item.text,
                provider: item.provider,
                model: item.model,
                languageHint: item.languageHint,
                historyID: item.id,
                audioFileName: item.audioFileName
            ),
            isTrustedForReplacement: isTrustedForReplacement
        )
    }

    private func groupedCounts(
        _ summaries: [CorrectionMappingSummary]
    ) -> [MappingKey: Int] {
        var result: [MappingKey: Int] = [:]
        for summary in summaries {
            let key = mappingKey(before: summary.beforeText, after: summary.afterText)
            result[key, default: 0] += summary.count
        }
        return result
    }

    /// Runtime confidence is session-based, not raw occurrence-based. Saying
    /// the same mistaken token three times in one transcript must not unlock a
    /// global replacement.
    private func distinctSessionCounts(
        _ events: [CorrectionCaptureEvent]
    ) -> [MappingKey: Int] {
        var keysBySession: [EvidenceSessionKey: Set<MappingKey>] = [:]
        for event in events {
            let sessionKey = event.historyID.map(EvidenceSessionKey.history)
                ?? .event(event.id)
            let eventKeys = Set(
                aggregator.aggregate([event])
                    .filter { $0.kind == .replacement }
                    .map { mappingKey(before: $0.beforeText, after: $0.afterText) }
            )
            keysBySession[sessionKey, default: []].formUnion(eventKeys)
        }

        var result: [MappingKey: Int] = [:]
        for keys in keysBySession.values {
            for key in keys {
                result[key, default: 0] += 1
            }
        }
        return result
    }

    private func representativeMappings(
        _ summaries: [CorrectionMappingSummary]
    ) -> [MappingKey: RepresentativeMapping] {
        var result: [MappingKey: RepresentativeMapping] = [:]
        for summary in summaries {
            let key = mappingKey(before: summary.beforeText, after: summary.afterText)
            let candidate = RepresentativeMapping(
                observedText: summary.beforeText,
                preferredText: summary.afterText,
                strongestExactCount: summary.count
            )
            guard let existing = result[key] else {
                result[key] = candidate
                continue
            }
            if candidate.strongestExactCount > existing.strongestExactCount
                || (candidate.strongestExactCount == existing.strongestExactCount
                    && Self.representativeOrdering(candidate, existing)) {
                result[key] = candidate
            }
        }
        return result
    }

    private func mappingKey(before: String, after: String) -> MappingKey {
        MappingKey(
            observedKey: Self.foldedKey(before),
            // Preferred spelling and case are meaningful. Only canonical
            // Unicode representation is normalized on this side.
            preferredKey: after.precomposedStringWithCanonicalMapping
        )
    }

    private func vocabularyHintIsEligible(
        observedText: String,
        preferredText: String,
        observationCount: Int,
        confidence: Double,
        runnerUpCount: Int,
        hasReverseMapping: Bool
    ) -> Bool {
        guard observationCount >= configuration.vocabularyMinimumObservationCount,
              confidence >= configuration.vocabularyMinimumConfidence,
              observationCount - runnerUpCount >= configuration.vocabularyMinimumLead,
              !hasReverseMapping,
              !Self.isLowercaseShortLatinWord(observedText),
              preferredText.count >= 2,
              preferredText.count <= 100,
              preferredText.contains(where: { $0.isLetter }) else {
            return false
        }
        return true
    }

    private func automaticReplacementIsEligible(
        observedText: String,
        preferredText: String,
        trustedSessionCount: Int,
        confidence: Double,
        alternativeCount: Int,
        hasReverseMapping: Bool
    ) -> Bool {
        guard trustedSessionCount >= configuration.replacementMinimumTrustedSessionCount,
              confidence >= configuration.replacementMinimumConfidence,
              alternativeCount == 0,
              !hasReverseMapping,
              observedText.count >= 2,
              observedText.count <= configuration.maximumAutomaticSourceCharacterCount,
              observedText.contains(where: { $0.isLetter }),
              preferredText.contains(where: { $0.isLetter }),
              !Self.isLowercaseShortLatinWord(observedText) else {
            return false
        }

        // Pure casing/diacritic changes are often contextual (for example a
        // sentence-initial word) and should influence hints rather than every
        // matching token. Single-grapheme substitutions are likewise too
        // broad for automatic CJK replacement.
        return Self.foldedKey(observedText) != Self.foldedKey(preferredText)
    }

    private func uniqueVocabularyHints(
        from patterns: [CorrectionLearningPattern]
    ) -> [String] {
        var hints: [String] = []
        var keys = Set<String>()
        for pattern in patterns where pattern.isVocabularyHintEligible {
            let key = Self.foldedKey(pattern.preferredText)
            guard keys.insert(key).inserted else {
                continue
            }
            hints.append(pattern.preferredText)
            if hints.count == configuration.maximumVocabularyHintCount {
                break
            }
        }
        return hints
    }

    private static func patternOrdering(
        _ lhs: CorrectionLearningPattern,
        _ rhs: CorrectionLearningPattern
    ) -> Bool {
        if lhs.observationCount != rhs.observationCount {
            return lhs.observationCount > rhs.observationCount
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        if lhs.observedText != rhs.observedText {
            return lhs.observedText.localizedStandardCompare(rhs.observedText) == .orderedAscending
        }
        return lhs.preferredText.localizedStandardCompare(rhs.preferredText) == .orderedAscending
    }

    private static func representativeOrdering(
        _ lhs: RepresentativeMapping,
        _ rhs: RepresentativeMapping
    ) -> Bool {
        if lhs.observedText != rhs.observedText {
            return lhs.observedText.localizedStandardCompare(rhs.observedText) == .orderedAscending
        }
        return lhs.preferredText.localizedStandardCompare(rhs.preferredText) == .orderedAscending
    }

    private static func hasReverseMapping(
        for key: MappingKey,
        representative: RepresentativeMapping,
        in keys: Dictionary<MappingKey, Int>.Keys
    ) -> Bool {
        let preferredAsSource = foldedKey(representative.preferredText)
        let observedAsTarget = foldedKey(representative.observedText)
        guard preferredAsSource != observedAsTarget else {
            return false
        }
        return keys.contains { candidate in
            candidate != key
                && candidate.observedKey == preferredAsSource
                && foldedKey(candidate.preferredKey) == observedAsTarget
        }
    }

    private static func isLowercaseShortLatinWord(_ text: String) -> Bool {
        guard text.count <= 3,
              text == text.lowercased(),
              !text.isEmpty else {
            return false
        }
        return text.allSatisfy { character in
            character.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 0x0061 ... 0x007A, 0x00DF ... 0x024F,
                     0x1E01 ... 0x1EFF, 0x2C61 ... 0x2C7F,
                     0xA721 ... 0xA7FF, 0xAB30 ... 0xAB6F,
                     0xFF41 ... 0xFF5A:
                    return true
                default:
                    return false
                }
            }
        }
    }

    private static func foldedKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }

    private static func comparisonText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }
}

private final class CorrectionLearningSnapshotCache: @unchecked Sendable {
    private let lock = NSLock()
    private var history: [TranscriptItem] = []
    private var events: [CorrectionCaptureEvent] = []
    private var learningResetAt: Date?
    private var snapshot = CorrectionLearningSnapshot.empty

    func value(
        history nextHistory: [TranscriptItem],
        events nextEvents: [CorrectionCaptureEvent],
        learningResetAt nextLearningResetAt: Date?,
        build: () -> CorrectionLearningSnapshot
    ) -> CorrectionLearningSnapshot {
        lock.lock()
        if history == nextHistory,
           events == nextEvents,
           learningResetAt == nextLearningResetAt {
            let cached = snapshot
            lock.unlock()
            return cached
        }
        lock.unlock()

        let derived = build()
        lock.lock()
        history = nextHistory
        events = nextEvents
        learningResetAt = nextLearningResetAt
        snapshot = derived
        lock.unlock()
        return derived
    }
}

/// One-pass replacement avoids cascading A -> B -> C rules. Latin words use
/// Unicode-aware boundaries; CJK mappings must exactly match a word range
/// confirmed by the system tokenizer.
enum AdaptiveRecognitionReplacementEngine {
    private struct Match {
        let range: Range<String.Index>
        let replacement: String
        let sourceLength: Int
    }

    static func apply(
        _ patterns: [CorrectionLearningPattern],
        to text: String
    ) -> String {
        guard !patterns.isEmpty, !text.isEmpty else {
            return text
        }

        let requiresCJKBoundaries = patterns.contains { pattern in
            pattern.isHighConfidenceReplacementEligible
                && pattern.observedText.contains(where: containsCJKGrapheme)
        }
        let cjkWordRanges = requiresCJKBoundaries ? wordTokenRanges(in: text) : []
        var candidates: [Match] = []
        for pattern in patterns where pattern.isHighConfidenceReplacementEligible {
            candidates.append(contentsOf: matches(
                source: pattern.observedText,
                replacement: pattern.preferredText,
                in: text,
                cjkWordRanges: cjkWordRanges
            ))
        }
        guard !candidates.isEmpty else {
            return text
        }

        candidates.sort { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            if lhs.sourceLength != rhs.sourceLength {
                return lhs.sourceLength > rhs.sourceLength
            }
            return lhs.replacement < rhs.replacement
        }

        var accepted: [Match] = []
        var acceptedUpperBound = text.startIndex
        for candidate in candidates {
            guard candidate.range.lowerBound >= acceptedUpperBound else {
                continue
            }
            accepted.append(candidate)
            acceptedUpperBound = candidate.range.upperBound
        }

        var output = text
        for match in accepted.reversed() {
            output.replaceSubrange(match.range, with: match.replacement)
        }
        return output
    }

    private static func matches(
        source: String,
        replacement: String,
        in text: String,
        cjkWordRanges: [Range<String.Index>]
    ) -> [Match] {
        guard !source.isEmpty else {
            return []
        }

        var result: [Match] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(
            of: source,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            if hasRequiredBoundaries(
                for: range,
                source: source,
                in: text,
                cjkWordRanges: cjkWordRanges
            ) {
                result.append(Match(
                    range: range,
                    replacement: replacement,
                    sourceLength: source.count
                ))
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return result
    }

    private static func hasRequiredBoundaries(
        for range: Range<String.Index>,
        source: String,
        in text: String,
        cjkWordRanges: [Range<String.Index>]
    ) -> Bool {
        if source.contains(where: containsCJKGrapheme) {
            return cjkWordRanges.contains(range)
        }

        if let first = source.first,
           isLatinLetterOrNumber(first),
           range.lowerBound > text.startIndex,
           isLatinLetterOrNumber(text[text.index(before: range.lowerBound)]) {
            return false
        }

        if let last = source.last,
           isLatinLetterOrNumber(last),
           range.upperBound < text.endIndex,
           isLatinLetterOrNumber(text[range.upperBound]) {
            return false
        }
        return true
    }

    private static func wordTokenRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        return ranges
    }

    private static func containsCJKGrapheme(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100 ... 0x11FF, 0x2E80 ... 0x2FFF,
                 0x3040 ... 0x30FF, 0x3100 ... 0x318F,
                 0x31A0 ... 0x31BF, 0x31F0 ... 0x31FF,
                 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF,
                 0xA960 ... 0xA97F, 0xAC00 ... 0xD7AF,
                 0xD7B0 ... 0xD7FF, 0xF900 ... 0xFAFF,
                 0xFF66 ... 0xFF9D, 0x20000 ... 0x2FA1F:
                return true
            default:
                return false
            }
        }
    }

    private static func isLatinLetterOrNumber(_ character: Character) -> Bool {
        if character.isNumber {
            return true
        }
        return character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0041 ... 0x005A, 0x0061 ... 0x007A,
                 0x00C0 ... 0x024F, 0x1E00 ... 0x1EFF,
                 0x2C60 ... 0x2C7F, 0xA720 ... 0xA7FF,
                 0xAB30 ... 0xAB6F, 0xFF21 ... 0xFF3A,
                 0xFF41 ... 0xFF5A:
                return true
            default:
                return false
            }
        }
    }
}
