import Foundation

enum TranscriptInsertionBoundaryPolicy {
    private enum EndingScript {
        case hanOrKana
        case latin
        case otherLetter
        case number
        case symbol
    }

    private static let trailingBracketCharacters = Set(
        "」』】）》〕〉〗〙〛)]}".map { $0 }
    )
    private static let cjkTerminalPunctuation = Set(
        "。！？；：，、…—～".map { $0 }
    )
    private static let numericDecorationCharacters = Set(
        "+-−.,，٫٬:/：%％()（）".map { $0 }
    )
    private static let continuationPunctuation = Set(
        ",，、:：;；".map { $0 }
    )
    private static let fullStopCharacters = Set(".。".map { $0 })
    private static let technicalDelimiterCharacters = Set("[]{}".map { $0 })
    private static let developerCommandSubcommands: [String: Set<String>] = [
        "git": [
            "add", "bisect", "branch", "checkout", "cherry-pick", "clean",
            "clone", "commit", "diff", "fetch", "grep", "init", "log",
            "merge", "pull", "push", "rebase", "remote", "reset", "restore",
            "revert", "show", "stash", "status", "switch", "tag", "worktree"
        ],
        "gh": ["auth", "issue", "pr", "release", "repo", "run", "workflow"],
        "npm": ["ci", "install", "publish", "run", "start", "test", "uninstall"],
        "pnpm": ["add", "build", "exec", "install", "remove", "run", "test"],
        "yarn": ["add", "build", "install", "remove", "run", "test"],
        "bun": ["add", "build", "install", "remove", "run", "test"],
        "cargo": ["add", "build", "check", "clean", "clippy", "install", "run", "test"],
        "swift": ["build", "package", "run", "test"],
        "docker": ["build", "compose", "exec", "images", "logs", "ps", "pull", "push", "run"],
        "kubectl": ["apply", "config", "delete", "describe", "exec", "get", "logs"],
        "brew": ["cleanup", "doctor", "install", "list", "services", "uninstall", "update", "upgrade"]
    ]
    private static let syntaxDrivenCommandTokens = Set([
        "awk", "cat", "chmod", "chown", "cmake", "cp", "curl", "find", "grep",
        "head", "less", "ls", "make", "mkdir", "mv", "open", "rg", "rm", "rsync",
        "scp", "sed", "ssh", "tail", "xcodebuild"
    ])

    /// Applies the sentence ending first, then one authoritative insertion
    /// boundary. Running this after local and optional AI finalization keeps
    /// model output and manually corrected output on the same path.
    static func apply(
        to text: String,
        punctuationMode: PunctuationPostProcessingMode = .keep,
        mode: TranscriptInsertionBoundaryMode
    ) -> String {
        let textWithoutBoundary = removingTrailingWhitespace(from: text)
        guard !textWithoutBoundary.isEmpty else {
            return ""
        }

        let punctuatedText: String
        switch punctuationMode {
        case .automatic:
            punctuatedText = addingAutomaticTerminalPunctuation(to: textWithoutBoundary)
        case .keep:
            punctuatedText = textWithoutBoundary
        case .replaceWithSpaces:
            punctuatedText = replacingChineseSentencePunctuationWithSpaces(
                in: textWithoutBoundary
            )
        }
        let normalizedPunctuatedText = removingTrailingWhitespace(from: punctuatedText)
        guard !normalizedPunctuatedText.isEmpty else {
            return ""
        }

        switch mode {
        case .newline:
            return normalizedPunctuatedText + "\n"
        case .smartSpace:
            return shouldAppendSmartSpace(to: normalizedPunctuatedText)
                ? normalizedPunctuatedText + " "
                : normalizedPunctuatedText
        case .none:
            return normalizedPunctuatedText
        }
    }

    private static func addingAutomaticTerminalPunctuation(to text: String) -> String {
        let (body, closingCharacters) = separatingTrailingClosingCharacters(in: text)
        guard let finalCharacter = body.last else {
            return text
        }
        let technicalCandidate = continuationPunctuation.contains(finalCharacter)
            || fullStopCharacters.contains(finalCharacter)
            ? String(body.dropLast())
            : body
        guard !isObviousTechnicalText(technicalCandidate), !isPureNumber(body) else {
            return text
        }

        if isPreservedTerminalPunctuation(in: body) {
            return text
        }

        let contentForScript = continuationPunctuation.contains(finalCharacter)
            || fullStopCharacters.contains(finalCharacter)
            ? String(body.dropLast())
            : body
        guard let punctuation = automaticFullStop(for: contentForScript) else {
            return text
        }

        if continuationPunctuation.contains(finalCharacter)
            || fullStopCharacters.contains(finalCharacter) {
            return String(body.dropLast()) + String(punctuation) + closingCharacters
        }

        guard !isPunctuation(finalCharacter) else {
            return text
        }
        return body + String(punctuation) + closingCharacters
    }

    private static func automaticFullStop(for text: String) -> Character? {
        guard let finalCharacter = text.last else {
            return nil
        }

        switch endingScript(of: finalCharacter) {
        case .hanOrKana:
            return "。"
        case .latin, .otherLetter:
            return "."
        case .number:
            guard let precedingScript = lastLetterScript(in: text) else {
                return nil
            }
            return precedingScript == .hanOrKana ? "。" : "."
        case .symbol:
            return nil
        }
    }

    private static func isPreservedTerminalPunctuation(in text: String) -> Bool {
        text.hasSuffix("...")
            || text.hasSuffix("…")
            || text.hasSuffix("……")
            || text.hasSuffix("?")
            || text.hasSuffix("!")
            || text.hasSuffix("？")
            || text.hasSuffix("！")
    }

    private static func shouldAppendSmartSpace(to text: String) -> Bool {
        let (body, closingCharacters) = separatingTrailingClosingCharacters(in: text)
        guard let finalCharacter = body.last else {
            return false
        }

        if cjkTerminalPunctuation.contains(finalCharacter) {
            return false
        }

        guard let script = lastMeaningfulScript(in: body) else {
            return false
        }

        switch script {
        case .hanOrKana:
            // Preserve the historical safety boundary only when a model emits
            // bare CJK text. CJK punctuation or a closing CJK quote already
            // provides the visual boundary on its own.
            return closingCharacters.isEmpty && !isPunctuation(finalCharacter)
        case .latin, .otherLetter, .number:
            return true
        case .symbol:
            return false
        }
    }

    private static func separatingTrailingClosingCharacters(
        in text: String
    ) -> (body: String, closingCharacters: String) {
        var insertionIndex = text.endIndex
        while insertionIndex > text.startIndex {
            let previousIndex = text.index(before: insertionIndex)
            guard isTrailingClosingCharacter(
                text[previousIndex],
                before: previousIndex,
                in: text
            ) else {
                break
            }
            insertionIndex = previousIndex
        }

        return (
            String(text[..<insertionIndex]),
            String(text[insertionIndex...])
        )
    }

    private static func isTrailingClosingCharacter(
        _ character: Character,
        before index: String.Index,
        in text: String
    ) -> Bool {
        if trailingBracketCharacters.contains(character) {
            return true
        }

        let prefix = text[..<index]
        switch character {
        case "'":
            return prefix.filter { $0 == "'" }.count.isMultiple(of: 2) == false
        case "\"":
            return prefix.filter { $0 == "\"" }.count.isMultiple(of: 2) == false
        case "’":
            return prefix.filter { $0 == "‘" }.count > prefix.filter { $0 == "’" }.count
        case "”":
            return prefix.filter { $0 == "“" }.count > prefix.filter { $0 == "”" }.count
        default:
            return false
        }
    }

    private static func removingTrailingWhitespace(from text: String) -> String {
        var endIndex = text.endIndex
        while endIndex > text.startIndex {
            let previousIndex = text.index(before: endIndex)
            guard text[previousIndex].isWhitespace else {
                break
            }
            endIndex = previousIndex
        }
        return String(text[..<endIndex])
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            CharacterSet.punctuationCharacters.contains($0)
        }
    }

    private static func replacingChineseSentencePunctuationWithSpaces(
        in text: String
    ) -> String {
        let punctuationToReplace = Set("，。".unicodeScalars)
        var scalars = String.UnicodeScalarView()

        for scalar in text.unicodeScalars {
            scalars.append(
                punctuationToReplace.contains(scalar) ? UnicodeScalar(32)! : scalar
            )
        }
        return String(scalars)
    }

    private static func isPureNumber(_ text: String) -> Bool {
        var containsNumber = false
        for character in text {
            if character.isNumber {
                containsNumber = true
            } else if character.isWhitespace || numericDecorationCharacters.contains(character) {
                continue
            } else {
                return false
            }
        }
        return containsNumber
    }

    private static func isObviousTechnicalText(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Be conservative around code-shaped fragments. Closing brackets are
        // separated before punctuation is inserted, so inspecting only pairs
        // such as `[]` would otherwise turn `[foo]` into `[foo.]`.
        if trimmedText.contains(where: technicalDelimiterCharacters.contains)
            || trimmedText.hasPrefix("$")
            || trimmedText.hasPrefix("-") {
            return true
        }

        return isObviousSingleTokenTechnicalText(trimmedText)
            || isObviousDeveloperOrShellCommand(text)
    }

    private static func isObviousSingleTokenTechnicalText(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isWhitespace }) else {
            return false
        }

        let lowercased = text.lowercased()
        if lowercased.hasPrefix("http://")
            || lowercased.hasPrefix("https://")
            || lowercased.hasPrefix("www.")
            || lowercased.hasPrefix("file://") {
            return true
        }

        if text.contains("@"),
           text.split(separator: "@", omittingEmptySubsequences: false).count == 2 {
            return true
        }

        if text.contains("/") || text.contains("\\") || text.contains(".") {
            return true
        }

        let codeMarkers = ["_", "`", "::", "->", "=>", "=", "()", "[]", "{}"]
        return codeMarkers.contains { text.contains($0) }
    }

    private static func isObviousDeveloperOrShellCommand(_ text: String) -> Bool {
        var tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count > 1 else {
            return false
        }

        if let prompt = tokens.first, ["$", "%", ">"].contains(prompt) {
            tokens.removeFirst()
        }
        guard tokens.count > 1 else {
            return false
        }

        let command = URL(fileURLWithPath: tokens[0]).lastPathComponent.lowercased()
        let nextToken = normalizedCommandToken(tokens[1])
        if developerCommandSubcommands[command]?.contains(nextToken) == true {
            return tokens.count == 2
                || tokens.dropFirst(2).contains(where: containsShellSyntaxMarker)
        }

        guard syntaxDrivenCommandTokens.contains(command) else {
            return false
        }
        return tokens.dropFirst().contains(where: containsShellSyntaxMarker)
    }

    private static func normalizedCommandToken(_ token: String) -> String {
        token.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ",，、:：;；.!?！？")
        )
    }

    private static func containsShellSyntaxMarker(_ token: String) -> Bool {
        let exactMarkers = Set(["|", "||", "&&", ";", "<", ">", ">>"])
        return exactMarkers.contains(token)
            || token.hasPrefix("-")
            || token.contains("/")
            || token.contains("\\")
            || token.contains("=")
            || token.contains("$")
    }

    private static func lastMeaningfulScript(in text: String) -> EndingScript? {
        for character in text.reversed() {
            if character.isWhitespace || isPunctuation(character) {
                continue
            }
            return endingScript(of: character)
        }
        return nil
    }

    private static func lastLetterScript(in text: String) -> EndingScript? {
        for character in text.reversed() where character.isLetter {
            return endingScript(of: character)
        }
        return nil
    }

    private static func endingScript(of character: Character) -> EndingScript {
        if character.isNumber {
            return .number
        }

        for scalar in character.unicodeScalars {
            let value = scalar.value
            if isHanOrKana(value) {
                return .hanOrKana
            }
            if isLatin(value) {
                return .latin
            }
        }

        return character.isLetter ? .otherLetter : .symbol
    }

    private static func isHanOrKana(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value)
            || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0x20000...0x2FA1F).contains(value)
            || (0x3040...0x30FF).contains(value)
            || (0x31F0...0x31FF).contains(value)
            || (0xFF66...0xFF9F).contains(value)
    }

    private static func isLatin(_ value: UInt32) -> Bool {
        (0x0041...0x005A).contains(value)
            || (0x0061...0x007A).contains(value)
            || (0x00C0...0x024F).contains(value)
            || (0x1E00...0x1EFF).contains(value)
            || (0x2C60...0x2C7F).contains(value)
            || (0xA720...0xA7FF).contains(value)
            || (0xAB30...0xAB6F).contains(value)
            || (0xFF21...0xFF5A).contains(value)
    }
}

struct TranscriptPostProcessor {
    private static let correctionRuleCache = CorrectionRuleCache()

    func process(
        _ text: String,
        settings: AppSettings,
        correctionLearningSnapshot: CorrectionLearningSnapshot = .empty
    ) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let customRules = settings.useCustomCorrections
            ? parseCorrectionRules(settings.customCorrections)
            : []

        if settings.adaptiveRecognitionEnabled,
           settings.adaptiveRecognitionMode.usesLocalReplacement {
            let explicitSourceKeys = Set(customRules.map {
                Self.normalizedReplacementSourceKey($0.source)
            })
            let eligibleLearnedPatterns = correctionLearningSnapshot
                .highConfidenceReplacements
                .filter {
                    !explicitSourceKeys.contains(
                        Self.normalizedReplacementSourceKey($0.observedText)
                    )
                }
            output = AdaptiveRecognitionReplacementEngine.apply(
                eligibleLearnedPatterns,
                to: output
            )
        }

        if settings.useCustomCorrections {
            output = applyCorrectionRules(customRules, to: output)
        }

        output = applyPostProcessing(to: output, settings: settings)

        output = output.trimmingCharacters(in: .whitespacesAndNewlines)

        return output
    }

    private static func normalizedReplacementSourceKey(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }

    private func parseCorrectionRules(_ rulesText: String) -> [FixedReplacementRule] {
        Self.correctionRuleCache.rules(for: rulesText)
    }

    fileprivate static func parseCorrectionRulesUncached(_ rulesText: String) -> [FixedReplacementRule] {
        FixedReplacementDocument.executableRules(from: rulesText)
    }

    private func applyCorrectionRules(_ rules: [FixedReplacementRule], to text: String) -> String {
        guard !rules.isEmpty else {
            return text
        }

        var output = text
        for rule in rules {
            output = replacingBoundaryAwareOccurrences(
                of: rule.source,
                with: rule.replacement,
                in: output
            )
        }
        return output
    }

    private func replacingBoundaryAwareOccurrences(
        of source: String,
        with replacement: String,
        in text: String
    ) -> String {
        guard !source.isEmpty else {
            return text
        }

        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(
            of: source,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            if hasRequiredTextBoundaries(for: range, source: source, in: text) {
                ranges.append(range)
            }
            searchRange = range.upperBound..<text.endIndex
        }

        guard !ranges.isEmpty else {
            return text
        }

        var output = text
        for range in ranges.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }

    private func hasRequiredTextBoundaries(
        for range: Range<String.Index>,
        source: String,
        in text: String
    ) -> Bool {
        if let first = source.first,
           isASCIILetterOrDigit(first),
           !hasASCIIWordBoundary(before: range.lowerBound, in: text) {
            return false
        }

        if let last = source.last,
           isASCIILetterOrDigit(last),
           range.upperBound < text.endIndex,
           isASCIILetterOrDigit(text[range.upperBound]) {
            return false
        }

        return true
    }

    private func applyPostProcessing(to text: String, settings: AppSettings) -> String {
        var output = text

        output = convertChineseText(
            output,
            mode: settings.chineseTextConversionMode,
            preservesJapaneseClauses: settings.selectedTranscriptionLanguages.contains(.japanese)
        )

        if settings.emojiPostProcessingEnabled {
            if settings.smartEmojiMatchingAfterTranscription {
                output = EmojiResolverService.shared.resolveLocal(in: output)
            }
        }

        switch settings.punctuationPostProcessingMode {
        case .automatic, .keep:
            break
        case .replaceWithSpaces:
            output = replaceChineseSentencePunctuationWithSpaces(in: output)
        }

        if settings.lowercaseEnglishAfterTranscription {
            output = lowercaseASCIILetters(in: output)
        }

        if settings.insertSpaceBetweenChineseAndEnglish {
            output = insertSpacesBetweenChineseAndEnglish(in: output)
        }

        output = collapseWhitespace(in: output)

        return output
    }

    private func hasASCIIWordBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return true
        }

        return !isASCIILetterOrDigit(text[text.index(before: index)])
    }

    private func convertChineseText(
        _ text: String,
        mode: ChineseTextConversionMode,
        preservesJapaneseClauses: Bool
    ) -> String {
        let transform: String

        switch mode {
        case .keep:
            return text
        case .simplified:
            transform = "Hant-Hans"
        case .traditional:
            transform = "Hans-Hant"
        }

        guard preservesJapaneseClauses else {
            return applyingChineseTransform(transform, to: text)
        }

        var output = ""
        var clause = ""
        for character in text {
            clause.append(character)
            if isSentenceBoundary(character) {
                output += transformedChineseClause(
                    clause,
                    transform: transform
                )
                clause.removeAll(keepingCapacity: true)
            }
        }
        output += transformedChineseClause(clause, transform: transform)
        return output
    }

    private func transformedChineseClause(
        _ clause: String,
        transform: String
    ) -> String {
        guard !containsJapaneseKana(clause) else {
            return clause
        }
        return applyingChineseTransform(transform, to: clause)
    }

    private func applyingChineseTransform(
        _ transform: String,
        to text: String
    ) -> String {
        let mutableText = NSMutableString(string: text)
        guard CFStringTransform(mutableText, nil, transform as CFString, false) else {
            return text
        }
        return mutableText as String
    }

    private func containsJapaneseKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040 ... 0x30FF).contains(scalar.value)
                || (0x31F0 ... 0x31FF).contains(scalar.value)
                || (0xFF66 ... 0xFF9D).contains(scalar.value)
        }
    }

    private func isSentenceBoundary(_ character: Character) -> Bool {
        character.isNewline || "。！？!?；;".contains(character)
    }

    private func replaceChineseSentencePunctuationWithSpaces(in text: String) -> String {
        let punctuationToReplace = Set("，。".unicodeScalars)
        var scalars = String.UnicodeScalarView()

        for scalar in text.unicodeScalars {
            if punctuationToReplace.contains(scalar) {
                scalars.append(UnicodeScalar(32)!)
                continue
            }

            scalars.append(scalar)
        }

        return String(scalars)
    }

    private func collapseWhitespace(in text: String) -> String {
        text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
    }

    private func lowercaseASCIILetters(in text: String) -> String {
        var scalars = String.UnicodeScalarView()

        for scalar in text.unicodeScalars {
            if (65 ... 90).contains(scalar.value),
               let lowercaseScalar = UnicodeScalar(scalar.value + 32) {
                scalars.append(lowercaseScalar)
                continue
            }

            scalars.append(scalar)
        }

        return String(scalars)
    }

    private func insertSpacesBetweenChineseAndEnglish(in text: String) -> String {
        var output = ""
        var previousCharacter: Character?

        for character in text {
            if let previousCharacter,
               shouldInsertSpaceBetween(previousCharacter, and: character) {
                output.append(" ")
            }

            output.append(character)
            previousCharacter = character
        }

        return output
    }

    private func shouldInsertSpaceBetween(_ left: Character, and right: Character) -> Bool {
        (isHanCharacter(left) && isASCIILetterOrDigit(right))
            || (isASCIILetterOrDigit(left) && isHanCharacter(right))
    }

    private func isHanCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400 ... 0x4DBF,
                 0x4E00 ... 0x9FFF,
                 0xF900 ... 0xFAFF,
                 0x20000 ... 0x2A6DF,
                 0x2A700 ... 0x2B73F,
                 0x2B740 ... 0x2B81F,
                 0x2B820 ... 0x2CEAF,
                 0x2CEB0 ... 0x2EBEF,
                 0x30000 ... 0x3134F:
                return true
            default:
                return false
            }
        }
    }

    private func isASCIILetterOrDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (65 ... 90).contains(value)
                || (97 ... 122).contains(value)
                || (48 ... 57).contains(value)
        }
    }
}

private final class CorrectionRuleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var rulesByText: [String: [FixedReplacementRule]] = [:]

    func rules(for rulesText: String) -> [FixedReplacementRule] {
        lock.lock()
        if let cachedRules = rulesByText[rulesText] {
            lock.unlock()
            return cachedRules
        }
        lock.unlock()

        let rules = TranscriptPostProcessor.parseCorrectionRulesUncached(rulesText)

        lock.lock()
        rulesByText[rulesText] = rules
        lock.unlock()

        return rules
    }
}
