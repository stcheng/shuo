import Foundation

struct PromptContextItem: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var prompt: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isEnabled = isEnabled
    }
}

struct FixedReplacementRule: Equatable {
    var source: String
    var replacement: String
}

struct FixedReplacementRuleDraft: Equatable, Identifiable {
    let id: UUID
    var source: String
    var replacement: String

    fileprivate let originalRaw: String?
    fileprivate let originalSource: String?
    fileprivate let originalReplacement: String?
    fileprivate var lineTerminator: String

    fileprivate init(
        id: UUID = UUID(),
        source: String,
        replacement: String,
        originalRaw: String?,
        originalSource: String?,
        originalReplacement: String?,
        lineTerminator: String
    ) {
        self.id = id
        self.source = source
        self.replacement = replacement
        self.originalRaw = originalRaw
        self.originalSource = originalSource
        self.originalReplacement = originalReplacement
        self.lineTerminator = lineTerminator
    }

    fileprivate var serializedContent: String? {
        if let originalRaw,
           source == originalSource,
           replacement == originalReplacement {
            return originalRaw
        }

        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        // A new row is only persisted once its match text exists. This keeps
        // an in-progress replacement-first draft from turning into a legacy
        // invalid line after relaunch; preserved pre-existing raw lines still
        // round-trip through the originalRaw branch above.
        if originalRaw == nil, normalizedSource.isEmpty {
            return nil
        }

        return "\(normalizedSource) => \(normalizedReplacement)"
    }
}

struct FixedReplacementPreservedLine: Equatable, Identifiable {
    enum Kind: Equatable {
        case blank
        case comment
        case invalid
    }

    let id: UUID
    let raw: String
    let kind: Kind
    fileprivate var lineTerminator: String
}

/// A line-preserving editor model for the legacy string-backed replacement rules.
///
/// `AppSettings.customCorrections` intentionally remains the only persisted source of
/// truth. Untouched rules, comments, invalid lines, and line endings round-trip exactly.
struct FixedReplacementDocument: Equatable {
    private enum Line: Equatable {
        case rule(FixedReplacementRuleDraft)
        case preserved(FixedReplacementPreservedLine)

        var lineTerminator: String {
            switch self {
            case let .rule(rule):
                return rule.lineTerminator
            case let .preserved(line):
                return line.lineTerminator
            }
        }

        var serializedContent: String? {
            switch self {
            case let .rule(rule):
                return rule.serializedContent
            case let .preserved(line):
                return line.raw
            }
        }
    }

    private var lines: [Line]

    init(serialized: String = "") {
        lines = Self.rawLinesPreservingTerminators(in: serialized).map { rawLine in
            let trimmed = rawLine.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .preserved(
                    FixedReplacementPreservedLine(
                        id: UUID(),
                        raw: rawLine.content,
                        kind: .blank,
                        lineTerminator: rawLine.terminator
                    )
                )
            }

            if trimmed.hasPrefix("#") {
                return .preserved(
                    FixedReplacementPreservedLine(
                        id: UUID(),
                        raw: rawLine.content,
                        kind: .comment,
                        lineTerminator: rawLine.terminator
                    )
                )
            }

            if let parsedRule = Self.parseRule(rawLine.content) {
                return .rule(
                    FixedReplacementRuleDraft(
                        source: parsedRule.source,
                        replacement: parsedRule.replacement,
                        originalRaw: rawLine.content,
                        originalSource: parsedRule.source,
                        originalReplacement: parsedRule.replacement,
                        lineTerminator: rawLine.terminator
                    )
                )
            }

            return .preserved(
                FixedReplacementPreservedLine(
                    id: UUID(),
                    raw: rawLine.content,
                    kind: .invalid,
                    lineTerminator: rawLine.terminator
                )
            )
        }
    }

    var rules: [FixedReplacementRuleDraft] {
        lines.compactMap { line in
            guard case let .rule(rule) = line else {
                return nil
            }
            return rule
        }
    }

    var invalidLines: [FixedReplacementPreservedLine] {
        lines.compactMap { line in
            guard case let .preserved(preserved) = line,
                  preserved.kind == .invalid else {
                return nil
            }
            return preserved
        }
    }

    var serialized: String {
        var output = ""
        var previousEmittedLineHadNoTerminator = false
        let fallbackTerminator = preferredLineTerminator

        for line in lines {
            guard let content = line.serializedContent else {
                continue
            }

            if !output.isEmpty, previousEmittedLineHadNoTerminator {
                output.append(fallbackTerminator)
            }
            output.append(content)
            output.append(line.lineTerminator)
            previousEmittedLineHadNoTerminator = line.lineTerminator.isEmpty
        }

        return output
    }

    mutating func addRule() -> UUID {
        let rule = FixedReplacementRuleDraft(
            source: "",
            replacement: "",
            originalRaw: nil,
            originalSource: nil,
            originalReplacement: nil,
            lineTerminator: ""
        )
        lines.append(.rule(rule))
        return rule.id
    }

    mutating func updateRule(id: UUID, source: String? = nil, replacement: String? = nil) {
        guard let index = lines.firstIndex(where: { line in
            guard case let .rule(rule) = line else {
                return false
            }
            return rule.id == id
        }), case var .rule(rule) = lines[index] else {
            return
        }

        if let source {
            rule.source = Self.singleLine(source)
        }
        if let replacement {
            rule.replacement = Self.singleLine(replacement)
        }
        lines[index] = .rule(rule)
    }

    mutating func removeRule(id: UUID) {
        lines.removeAll { line in
            guard case let .rule(rule) = line else {
                return false
            }
            return rule.id == id
        }
    }

    mutating func removePreservedLine(id: UUID) {
        lines.removeAll { line in
            guard case let .preserved(preserved) = line else {
                return false
            }
            return preserved.id == id
        }
    }

    static func executableRules(from serialized: String) -> [FixedReplacementRule] {
        serialized
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("#") }
            .compactMap(parseRule)
    }

    private var preferredLineTerminator: String {
        lines.lazy.map(\.lineTerminator).first(where: { !$0.isEmpty }) ?? "\n"
    }

    private static func parseRule(_ line: String) -> FixedReplacementRule? {
        let separatorRange = line.range(of: "=>") ?? line.range(of: "->")
        guard let separatorRange else {
            return nil
        }

        let source = line[..<separatorRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = line[separatorRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return nil
        }

        return FixedReplacementRule(source: source, replacement: replacement)
    }

    private static func rawLinesPreservingTerminators(
        in serialized: String
    ) -> [(content: String, terminator: String)] {
        guard !serialized.isEmpty else {
            return []
        }

        var result: [(content: String, terminator: String)] = []
        var lineStart = serialized.startIndex
        var index = serialized.startIndex

        while index < serialized.endIndex {
            let character = serialized[index]
            let nextIndex = serialized.index(after: index)
            if character.isNewline {
                result.append(
                    (
                        content: String(serialized[lineStart..<index]),
                        terminator: String(serialized[index..<nextIndex])
                    )
                )
                lineStart = nextIndex
            }
            index = nextIndex
        }

        if lineStart < serialized.endIndex {
            result.append(
                (
                    content: String(serialized[lineStart..<serialized.endIndex]),
                    terminator: ""
                )
            )
        }

        return result
    }

    private static func singleLine(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
    }
}

extension PromptContextItem {
    static let defaultGeneralPrompt = "Prefer verbatim transcription. Do not translate. Preserve mixed Chinese, English, and Japanese."
    private static let legacyNoPunctuationPrompt = "Return plain words only. Do not output punctuation marks; use spaces where punctuation would otherwise appear."

    static var defaultItems: [PromptContextItem] {
        [
            PromptContextItem(
                title: "General",
                prompt: defaultGeneralPrompt
            ),
            PromptContextItem(
                title: "Developer vocabulary",
                prompt: "Preserve code identifiers, library names, product names, and developer terminology exactly when recognizable."
            ),
            PromptContextItem(
                title: "Lowercase English",
                prompt: "Use lowercase for normal English words, unless they are proper nouns, acronyms, product names, or code identifiers.",
                isEnabled: false
            )
        ]
    }

    static func migratedItems(from legacyContextPrompt: String) -> [PromptContextItem] {
        let trimmed = legacyContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultItems
        }

        if trimmed == defaultGeneralPrompt {
            return defaultItems
        }

        var items = defaultItems
        items.insert(
            PromptContextItem(
                title: "Imported context",
                prompt: trimmed
            ),
            at: 0
        )
        return items
    }

    static func removingLegacyPostProcessingItems(from items: [PromptContextItem]) -> [PromptContextItem] {
        items.filter { !$0.isLegacyNoPunctuationPostProcessingItem }
    }

    var isLegacyNoPunctuationPostProcessingItem: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) == "No punctuation"
            && prompt.trimmingCharacters(in: .whitespacesAndNewlines) == Self.legacyNoPunctuationPrompt
    }

    var requestsNoPunctuation: Bool {
        let normalized = prompt
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        let compact = normalized.filter { !$0.isWhitespace }
        let mentionsEnglishPunctuation = compact.contains("punctuation")
        let asksToAvoidEnglishPunctuation = mentionsEnglishPunctuation
            && (
                compact.contains("nopunctuation")
                    || compact.contains("withoutpunctuation")
                    || compact.contains("dontusepunctuation")
                    || compact.contains("donotusepunctuation")
                    || compact.contains("dontaddpunctuation")
                    || compact.contains("donotaddpunctuation")
                    || compact.contains("dontoutputpunctuation")
                    || compact.contains("donotoutputpunctuation")
                    || compact.contains("removepunctuation")
                    || compact.contains("replacepunctuationwithspace")
                    || compact.contains("replacepunctuationwithspaces")
                    || compact.contains("没有punctuation")
                    || compact.contains("不要punctuation")
                    || compact.contains("不用punctuation")
                    || compact.contains("去掉punctuation")
                    || compact.contains("去除punctuation")
                    || compact.contains("無punctuation")
                    || compact.contains("沒有punctuation")
                    || compact.contains("不要punctuation")
                    || compact.contains("不用punctuation")
                    || compact.contains("去掉punctuation")
                    || compact.contains("去除punctuation")
            )
        let mentionsChinesePunctuation = compact.contains("标点") || compact.contains("標點")
        let mentionsSpaces = compact.contains("空格")
        let asksToReplaceChinesePunctuationWithSpaces = (
            mentionsChinesePunctuation
                && mentionsSpaces
                && (
                    compact.contains("换")
                        || compact.contains("替换")
                        || compact.contains("变")
                        || compact.contains("換")
                        || compact.contains("替換")
                        || compact.contains("變")
                )
        )
            || compact.contains("标点换成空格")
            || compact.contains("标点符号换成空格")
            || compact.contains("标点替换成空格")
            || compact.contains("标点符号替换成空格")
            || compact.contains("标点变成空格")
            || compact.contains("标点符号变成空格")
            || compact.contains("標點換成空格")
            || compact.contains("標點符號換成空格")
            || compact.contains("標點替換成空格")
            || compact.contains("標點符號替換成空格")
            || compact.contains("標點變成空格")
            || compact.contains("標點符號變成空格")

        return asksToAvoidEnglishPunctuation
            || asksToReplaceChinesePunctuationWithSpaces
            || normalized.contains("no punctuation")
            || normalized.contains("without punctuation")
            || normalized.contains("do not use punctuation")
            || normalized.contains("do not add punctuation")
            || normalized.contains("do not output punctuation")
            || normalized.contains("remove punctuation")
            || compact.contains("不要标点")
            || compact.contains("不要任何标点")
            || compact.contains("不要任何的标点")
            || compact.contains("不加标点")
            || compact.contains("去掉标点")
            || compact.contains("去除标点")
            || compact.contains("不要標點")
            || compact.contains("不要任何標點")
            || compact.contains("不要任何的標點")
            || compact.contains("不加標點")
            || compact.contains("去掉標點")
            || compact.contains("去除標點")
            || normalized.contains("句読点なし")
            || normalized.contains("句読点を使わない")
            || normalized.contains("句読点を付けない")
    }
}
