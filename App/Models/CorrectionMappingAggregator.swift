import Foundation
import NaturalLanguage

struct CorrectionMappingSummary: Identifiable, Equatable {
    struct ID: Hashable {
        let beforeText: String
        let afterText: String
    }

    enum Kind: Equatable {
        case replacement
        case insertion
        case deletion
    }

    let beforeText: String
    let afterText: String
    let count: Int

    var id: ID {
        ID(beforeText: beforeText, afterText: afterText)
    }

    var kind: Kind {
        if beforeText.isEmpty {
            return .insertion
        }
        if afterText.isEmpty {
            return .deletion
        }
        return .replacement
    }
}

/// Derives compact, display-only correction mappings from captured edits.
///
/// Latin words and numbers are kept as units. Contiguous Han, kana, and Hangul
/// runs use the system word tokenizer when it can prove complete coverage, with
/// grapheme fallback for unknown text. Unchanged punctuation and whitespace
/// never split a change hunk, which prevents an unrelated sentence rewrite from
/// being presented as several plausible-looking word corrections.
struct CorrectionMappingAggregator {
    struct Configuration: Equatable {
        var maximumEventTokenCount = 512
        var maximumChangedTokensPerSide = 6
        var maximumChangedCharactersPerSide = 48
        var maximumWholeEventTokensPerSide = 3

        init(
            maximumEventTokenCount: Int = 512,
            maximumChangedTokensPerSide: Int = 6,
            maximumChangedCharactersPerSide: Int = 48,
            maximumWholeEventTokensPerSide: Int = 3
        ) {
            self.maximumEventTokenCount = max(1, maximumEventTokenCount)
            self.maximumChangedTokensPerSide = max(1, maximumChangedTokensPerSide)
            self.maximumChangedCharactersPerSide = max(1, maximumChangedCharactersPerSide)
            self.maximumWholeEventTokensPerSide = max(1, maximumWholeEventTokensPerSide)
        }
    }

    private struct MappingKey: Hashable {
        let beforeText: String
        let afterText: String
    }

    private struct Token: Hashable {
        enum Kind: Hashable {
            case latinWord
            case number
            case cjkGrapheme
            case otherContent
            case whitespace
            case punctuation
        }

        let text: String
        let kind: Kind

        var isContent: Bool {
            switch kind {
            case .latinWord, .number, .cjkGrapheme, .otherContent:
                return true
            case .whitespace, .punctuation:
                return false
            }
        }
    }

    private enum Edit {
        case equal(Token)
        case remove(Token)
        case insert(Token)
    }

    private struct Hunk {
        var beforeTokens: [Token] = []
        var afterTokens: [Token] = []

        var isEmpty: Bool {
            beforeTokens.isEmpty && afterTokens.isEmpty
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func aggregate(
        _ events: [CorrectionCaptureEvent],
        minimumCount: Int = 1
    ) -> [CorrectionMappingSummary] {
        var counts: [MappingKey: Int] = [:]

        for event in events {
            guard !Task.isCancelled else {
                break
            }
            for mapping in mappings(from: event) {
                counts[mapping, default: 0] += 1
            }
        }

        let threshold = max(1, minimumCount)
        return counts
            .compactMap { key, count in
                guard count >= threshold else {
                    return nil
                }
                return CorrectionMappingSummary(
                    beforeText: key.beforeText,
                    afterText: key.afterText,
                    count: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                if lhs.beforeText != rhs.beforeText {
                    return lhs.beforeText < rhs.beforeText
                }
                return lhs.afterText < rhs.afterText
            }
    }

    private func mappings(from event: CorrectionCaptureEvent) -> [MappingKey] {
        let beforeTokens = Self.tokenize(event.beforeText)
        let afterTokens = Self.tokenize(event.afterText)
        guard beforeTokens.count <= configuration.maximumEventTokenCount,
              afterTokens.count <= configuration.maximumEventTokenCount else {
            return []
        }

        let totalBeforeContentCount = beforeTokens.lazy.filter(\.isContent).count
        let totalAfterContentCount = afterTokens.lazy.filter(\.isContent).count

        return Self.hunks(from: Self.diff(beforeTokens, afterTokens)).compactMap { hunk in
            mapping(
                from: hunk,
                totalBeforeContentCount: totalBeforeContentCount,
                totalAfterContentCount: totalAfterContentCount
            )
        }
    }

    private func mapping(
        from hunk: Hunk,
        totalBeforeContentCount: Int,
        totalAfterContentCount: Int
    ) -> MappingKey? {
        let normalizedHunk = Self.removingSharedBoundarySeparators(from: hunk)
        let beforeContentCount = normalizedHunk.beforeTokens.lazy.filter(\.isContent).count
        let afterContentCount = normalizedHunk.afterTokens.lazy.filter(\.isContent).count
        guard beforeContentCount > 0 || afterContentCount > 0,
              beforeContentCount <= configuration.maximumChangedTokensPerSide,
              afterContentCount <= configuration.maximumChangedTokensPerSide else {
            return nil
        }

        let coversWholeEvent = beforeContentCount == totalBeforeContentCount
            && afterContentCount == totalAfterContentCount
        if coversWholeEvent,
           max(totalBeforeContentCount, totalAfterContentCount)
            > configuration.maximumWholeEventTokensPerSide {
            return nil
        }

        let beforeText = Self.normalizedMappingText(normalizedHunk.beforeTokens.map(\.text).joined())
        let afterText = Self.normalizedMappingText(normalizedHunk.afterTokens.map(\.text).joined())
        guard beforeText != afterText,
              !beforeText.isEmpty || !afterText.isEmpty,
              beforeText.count <= configuration.maximumChangedCharactersPerSide,
              afterText.count <= configuration.maximumChangedCharactersPerSide,
              Self.containsContent(beforeText) || Self.containsContent(afterText) else {
            return nil
        }

        return MappingKey(beforeText: beforeText, afterText: afterText)
    }

    /// Punctuation and spacing which are identical on both sides are context,
    /// not part of the correction. Different punctuation remains available to
    /// the caller when it accompanies a substantive text change.
    private static func removingSharedBoundarySeparators(from hunk: Hunk) -> Hunk {
        var beforeTokens = hunk.beforeTokens
        var afterTokens = hunk.afterTokens

        while let before = beforeTokens.first,
              let after = afterTokens.first,
              !before.isContent,
              before == after {
            beforeTokens.removeFirst()
            afterTokens.removeFirst()
        }

        while let before = beforeTokens.last,
              let after = afterTokens.last,
              !before.isContent,
              before == after {
            beforeTokens.removeLast()
            afterTokens.removeLast()
        }

        return Hunk(beforeTokens: beforeTokens, afterTokens: afterTokens)
    }

    /// LCS alignment is deterministic: ties prefer removing from the old text.
    /// The event-size guard above bounds the quadratic table.
    private static func diff(_ before: [Token], _ after: [Token]) -> [Edit] {
        let rowWidth = after.count + 1
        var lengths = [Int](repeating: 0, count: (before.count + 1) * rowWidth)

        if !before.isEmpty, !after.isEmpty {
            for beforeIndex in stride(from: before.count - 1, through: 0, by: -1) {
                for afterIndex in stride(from: after.count - 1, through: 0, by: -1) {
                    let index = beforeIndex * rowWidth + afterIndex
                    if before[beforeIndex] == after[afterIndex] {
                        lengths[index] = 1 + lengths[(beforeIndex + 1) * rowWidth + afterIndex + 1]
                    } else {
                        lengths[index] = max(
                            lengths[(beforeIndex + 1) * rowWidth + afterIndex],
                            lengths[beforeIndex * rowWidth + afterIndex + 1]
                        )
                    }
                }
            }
        }

        var edits: [Edit] = []
        var beforeIndex = 0
        var afterIndex = 0
        while beforeIndex < before.count, afterIndex < after.count {
            if before[beforeIndex] == after[afterIndex] {
                edits.append(.equal(before[beforeIndex]))
                beforeIndex += 1
                afterIndex += 1
                continue
            }

            let removingLength = lengths[(beforeIndex + 1) * rowWidth + afterIndex]
            let insertingLength = lengths[beforeIndex * rowWidth + afterIndex + 1]
            if removingLength >= insertingLength {
                edits.append(.remove(before[beforeIndex]))
                beforeIndex += 1
            } else {
                edits.append(.insert(after[afterIndex]))
                afterIndex += 1
            }
        }

        while beforeIndex < before.count {
            edits.append(.remove(before[beforeIndex]))
            beforeIndex += 1
        }
        while afterIndex < after.count {
            edits.append(.insert(after[afterIndex]))
            afterIndex += 1
        }
        return edits
    }

    private static func hunks(from edits: [Edit]) -> [Hunk] {
        var result: [Hunk] = []
        var current = Hunk()

        func flush() {
            guard !current.isEmpty else {
                return
            }
            result.append(current)
            current = Hunk()
        }

        for edit in edits {
            switch edit {
            case .equal(let token):
                if token.isContent {
                    flush()
                } else if !current.isEmpty {
                    current.beforeTokens.append(token)
                    current.afterTokens.append(token)
                }
            case .remove(let token):
                current.beforeTokens.append(token)
            case .insert(let token):
                current.afterTokens.append(token)
            }
        }
        flush()
        return result
    }

    private static func tokenize(_ text: String) -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isCJKGrapheme(character) {
                var run = String(character)
                index += 1
                while index < characters.count, isCJKGrapheme(characters[index]) {
                    run.append(characters[index])
                    index += 1
                }
                tokens.append(contentsOf: tokenizeCJKRun(run))
                continue
            }

            if isLatinLetter(character) {
                var word = String(character)
                index += 1
                while index < characters.count {
                    let candidate = characters[index]
                    if isLatinLetter(candidate) {
                        word.append(candidate)
                        index += 1
                        continue
                    }
                    if isWordApostrophe(candidate),
                       index + 1 < characters.count,
                       isLatinLetter(characters[index + 1]) {
                        word.append(candidate)
                        index += 1
                        continue
                    }
                    break
                }
                tokens.append(Token(text: word, kind: .latinWord))
                continue
            }

            if character.isNumber {
                var number = String(character)
                index += 1
                while index < characters.count, characters[index].isNumber {
                    number.append(characters[index])
                    index += 1
                }
                tokens.append(Token(text: number, kind: .number))
                continue
            }

            if character.isWhitespace {
                var whitespace = String(character)
                index += 1
                while index < characters.count, characters[index].isWhitespace {
                    whitespace.append(characters[index])
                    index += 1
                }
                tokens.append(Token(text: whitespace, kind: .whitespace))
                continue
            }

            let kind: Token.Kind = isPunctuation(character) ? .punctuation : .otherContent
            tokens.append(Token(text: String(character), kind: kind))
            index += 1
        }

        return tokens
    }

    private static func tokenizeCJKRun(_ run: String) -> [Token] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = run
        var values: [String] = []
        tokenizer.enumerateTokens(in: run.startIndex..<run.endIndex) { range, _ in
            let value = String(run[range])
            if !value.isEmpty {
                values.append(value)
            }
            return true
        }

        // NLTokenizer may decline unfamiliar or malformed text. Only trust it
        // when its ranges cover the entire run without dropping characters.
        if !values.isEmpty, values.joined() == run {
            return values.map { Token(text: $0, kind: .cjkGrapheme) }
        }
        return run.map { Token(text: String($0), kind: .cjkGrapheme) }
    }

    private static func normalizedMappingText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        var result = ""
        var hasPendingWhitespace = false
        for character in trimmed {
            if character.isWhitespace {
                hasPendingWhitespace = true
                continue
            }
            if hasPendingWhitespace, !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
            hasPendingWhitespace = false
        }
        return result.precomposedStringWithCanonicalMapping
    }

    private static func containsContent(_ text: String) -> Bool {
        tokenize(text).contains(where: \.isContent)
    }

    private static func isWordApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "’"
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        !character.unicodeScalars.isEmpty
            && character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0)
            }
    }

    private static func isLatinLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
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

    private static func isCJKGrapheme(_ character: Character) -> Bool {
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
}
