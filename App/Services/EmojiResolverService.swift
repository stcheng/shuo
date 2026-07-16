import Foundation

struct EmojiPhraseMatch {
    let range: Range<String.Index>
    let phrase: String
}

struct EmojiResolverService {
    static let shared = EmojiResolverService()

    private static let triggerWords = ["emoji", "表情", "絵文字"]
    private let annotationAliasIndex: EmojiAliasIndex

    private init() {
        annotationAliasIndex = EmojiAliasIndex(aliases: Self.loadAnnotationAliases())
    }

    func resolveLocal(in text: String) -> String {
        guard !annotationAliasIndex.aliases.isEmpty else {
            return text
        }

        let replacements = Self.triggerRanges(in: text).compactMap {
            Self.replacement(for: $0, in: text, aliasIndex: annotationAliasIndex)
        }

        guard !replacements.isEmpty else {
            return text
        }

        return Self.applying(replacements, to: text)
    }

    func unresolvedPhraseMatches(in text: String, limit: Int = 3) -> [EmojiPhraseMatch] {
        var matches: [EmojiPhraseMatch] = []

        for triggerRange in Self.triggerRanges(in: text) {
            guard let match = Self.phraseMatch(for: triggerRange, in: text) else {
                continue
            }
            matches.append(match)
            if matches.count >= limit {
                break
            }
        }

        return matches
    }

    func applying(_ replacements: [(EmojiPhraseMatch, String)], to text: String) -> String {
        let textReplacements = replacements
            .filter { Self.isValidEmojiReplacement($0.1) }
            .map { TextReplacement(range: $0.0.range, replacement: $0.1) }
        return Self.applying(textReplacements, to: text)
    }

    static func singleEmoji(from text: String) -> String? {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.hasPrefix("```") {
            output = output.replacingOccurrences(of: #"^```[A-Za-z]*\s*"#, with: "", options: .regularExpression)
            output = output.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if output.count >= 2,
           let first = output.first,
           let last = output.last,
           (first == "\"" && last == "\"") || (first == "“" && last == "”") {
            output.removeFirst()
            output.removeLast()
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if output.uppercased() == "NONE" {
            return nil
        }

        guard isValidEmojiReplacement(output) else {
            return nil
        }
        return output
    }

    private static func loadAnnotationAliases() -> [EmojiAlias] {
        let curatedAliases = [
            // CLDR covers literal emoji names well, but not every colloquial
            // phrase. Put product-specific phrases first so they win if a
            // future annotation introduces a conflicting alias.
            EmojiAlias(name: "撒花", replacement: "🎉"),
            EmojiAlias(name: "点赞", replacement: "👍"),
            EmojiAlias(name: "赞", replacement: "👍")
        ]

        guard let url = Bundle.main.url(forResource: "EmojiAnnotations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(EmojiAnnotationData.self, from: data) else {
            return deduplicatedAliases(curatedAliases + unicodeNameAliases())
        }

        let aliases = decoded.entries.flatMap { entry -> [EmojiAlias] in
            guard isValidEmojiReplacement(entry.emoji) else {
                return []
            }

            return entry.aliases.compactMap { alias in
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }
                return EmojiAlias(name: trimmed, replacement: entry.emoji)
            }
        }

        return deduplicatedAliases(curatedAliases + aliases + unicodeNameAliases())
    }

    private static func unicodeNameAliases() -> [EmojiAlias] {
        var aliases: [EmojiAlias] = []

        for value in 0 ... 0x1FAFF {
            guard let scalar = UnicodeScalar(value),
                  scalar.properties.isEmojiPresentation,
                  let name = scalar.properties.name else {
                continue
            }

            let emoji = String(scalar)
            guard isValidEmojiReplacement(emoji) else {
                continue
            }

            aliases.append(EmojiAlias(name: name.replacingOccurrences(of: "-", with: " "), replacement: emoji))
        }

        return aliases
    }

    fileprivate static func deduplicatedAliases(_ aliases: [EmojiAlias]) -> [EmojiAlias] {
        var output: [EmojiAlias] = []
        var seen = Set<String>()

        for alias in aliases {
            let key = alias.exactKey
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            output.append(alias)
        }

        return output.sorted {
            if $0.name.count == $1.name.count {
                return $0.name < $1.name
            }
            return $0.name.count > $1.name.count
        }
    }

    private static func triggerRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []

        for trigger in triggerWords {
            var searchRange = text.startIndex ..< text.endIndex
            while let range = text.range(
                of: trigger,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            ) {
                if isTriggerRange(range, in: text) {
                    ranges.append(range)
                }

                searchRange = range.upperBound ..< text.endIndex
            }
        }

        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    private static func isTriggerRange(_ range: Range<String.Index>, in text: String) -> Bool {
        let trigger = String(text[range]).lowercased()
        guard trigger == "emoji" else {
            return true
        }

        guard range.upperBound < text.endIndex else {
            return true
        }

        return !isASCIILetterOrDigit(text[range.upperBound])
    }

    private static func replacement(
        for triggerRange: Range<String.Index>,
        in text: String,
        aliasIndex: EmojiAliasIndex
    ) -> TextReplacement? {
        let descriptorEnd = indexSkippingWhitespaceBackward(from: triggerRange.lowerBound, in: text)
        guard descriptorEnd > text.startIndex else {
            return nil
        }

        let exactLowerBound = text.index(descriptorEnd, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        if let (aliasRange, alias) = exactSuffixMatch(
            before: descriptorEnd,
            lowerBound: exactLowerBound,
            in: text,
            aliasIndex: aliasIndex
        ) {
            return TextReplacement(
                range: aliasRange.lowerBound ..< triggerRange.upperBound,
                replacement: alias.replacement
            )
        }

        return fuzzyReplacement(
            before: triggerRange,
            descriptorEnd: descriptorEnd,
            in: text,
            aliases: aliasIndex.asciiAliases
        )
    }

    private static func exactSuffixMatch(
        before end: String.Index,
        lowerBound: String.Index,
        in text: String,
        aliasIndex: EmojiAliasIndex
    ) -> (range: Range<String.Index>, alias: EmojiAlias)? {
        var candidateStart = lowerBound

        while candidateStart < end {
            let actualStart = indexSkippingWhitespaceForward(from: candidateStart, to: end, in: text)
            if actualStart < end {
                let candidate = String(text[actualStart..<end])
                if let alias = aliasIndex.exactAliases[normalizedEmojiAliasName(candidate)] {
                    if !alias.isASCIIName || hasASCIIWordBoundary(before: actualStart, in: text) {
                        return (actualStart..<end, alias)
                    }
                }
            }

            candidateStart = text.index(after: candidateStart)
        }

        return nil
    }

    private static func fuzzyReplacement(
        before triggerRange: Range<String.Index>,
        descriptorEnd: String.Index,
        in text: String,
        aliases: [EmojiAlias]
    ) -> TextReplacement? {
        guard !aliases.isEmpty else {
            return nil
        }

        let candidates = asciiPhraseSuffixCandidates(before: descriptorEnd, in: text)
        var best: (candidate: PhraseCandidate, alias: EmojiAlias, distance: Int, maxLength: Int)?

        for candidate in candidates {
            let normalizedCandidate = normalizedASCIIEmojiPhrase(candidate.text)
            guard normalizedCandidate.count >= 4 else {
                continue
            }

            for alias in aliases {
                let distance = levenshteinDistance(normalizedCandidate, alias.normalizedName)
                let maxLength = max(normalizedCandidate.count, alias.normalizedName.count)
                guard isAcceptableFuzzyMatch(distance: distance, maxLength: maxLength) else {
                    continue
                }

                if let current = best {
                    let currentRatio = Double(current.distance) / Double(current.maxLength)
                    let newRatio = Double(distance) / Double(maxLength)
                    if newRatio > currentRatio {
                        continue
                    }
                    if newRatio == currentRatio,
                       alias.normalizedName.count <= current.alias.normalizedName.count {
                        continue
                    }
                }

                best = (candidate, alias, distance, maxLength)
            }
        }

        guard let best else {
            return nil
        }

        return TextReplacement(
            range: best.candidate.range.lowerBound ..< triggerRange.upperBound,
            replacement: best.alias.replacement
        )
    }

    private static func phraseMatch(
        for triggerRange: Range<String.Index>,
        in text: String
    ) -> EmojiPhraseMatch? {
        let descriptorEnd = indexSkippingWhitespaceBackward(from: triggerRange.lowerBound, in: text)
        guard descriptorEnd > text.startIndex else {
            return nil
        }

        let phraseRange = phraseRange(before: descriptorEnd, in: text)
        guard phraseRange.lowerBound < phraseRange.upperBound else {
            return nil
        }

        let phrase = String(text[phraseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else {
            return nil
        }

        return EmojiPhraseMatch(
            range: phraseRange.lowerBound ..< triggerRange.upperBound,
            phrase: phrase
        )
    }

    private static func phraseRange(before end: String.Index, in text: String) -> Range<String.Index> {
        let suffixStart = text.index(end, offsetBy: -16, limitedBy: text.startIndex) ?? text.startIndex
        var start = end
        var hanCount = 0

        while start > suffixStart {
            let previousIndex = text.index(before: start)
            let character = text[previousIndex]

            if character.isWhitespace {
                guard start == end else {
                    break
                }
                start = previousIndex
                continue
            }

            if isPhraseBoundary(character) {
                break
            }

            start = previousIndex

            if isHanCharacter(character) {
                hanCount += 1
                if hanCount >= 8 {
                    break
                }
            }
        }

        return start ..< end
    }

    private static func asciiPhraseSuffixCandidates(before end: String.Index, in text: String) -> [PhraseCandidate] {
        var wordRanges: [Range<String.Index>] = []
        var cursor = end

        while wordRanges.count < 3 {
            cursor = indexSkippingWhitespaceBackward(from: cursor, in: text)
            let wordEnd = cursor
            var wordStart = wordEnd

            while wordStart > text.startIndex {
                let previousIndex = text.index(before: wordStart)
                let character = text[previousIndex]
                guard isASCIIEmojiNameCharacter(character) else {
                    break
                }
                wordStart = previousIndex
            }

            guard wordStart < wordEnd else {
                break
            }

            wordRanges.insert(wordStart ..< wordEnd, at: 0)
            cursor = wordStart
        }

        guard let lastWordEnd = wordRanges.last?.upperBound else {
            return []
        }

        return wordRanges.indices.map { index in
            let range = wordRanges[index].lowerBound ..< lastWordEnd
            return PhraseCandidate(range: range, text: String(text[range]))
        }
    }

    private static func applying(_ replacements: [TextReplacement], to text: String) -> String {
        var output = text
        for replacement in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            output.replaceSubrange(replacement.range, with: replacement.replacement)
        }
        return output
    }

    private static func indexSkippingWhitespaceBackward(from index: String.Index, in text: String) -> String.Index {
        var current = index
        while current > text.startIndex {
            let previous = text.index(before: current)
            guard text[previous].isWhitespace else {
                break
            }
            current = previous
        }
        return current
    }

    private static func indexSkippingWhitespaceForward(
        from index: String.Index,
        to end: String.Index,
        in text: String
    ) -> String.Index {
        var current = index
        while current < end, text[current].isWhitespace {
            current = text.index(after: current)
        }
        return current
    }

    private static func hasASCIIWordBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return true
        }

        return !isASCIILetterOrDigit(text[text.index(before: index)])
    }

    fileprivate static func normalizedASCIIEmojiPhrase(_ phrase: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in phrase.lowercased().unicodeScalars {
            let value = scalar.value
            if (97 ... 122).contains(value) || (48 ... 57).contains(value) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    fileprivate static func normalizedEmojiAliasName(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }

    private static func isAcceptableFuzzyMatch(distance: Int, maxLength: Int) -> Bool {
        guard maxLength >= 4 else {
            return false
        }

        if maxLength <= 5 {
            return distance <= 1
        }

        if maxLength <= 10 {
            return distance <= 2 && Double(distance) / Double(maxLength) <= 0.25
        }

        return distance <= 3 && Double(distance) / Double(maxLength) <= 0.2
    }

    private static func levenshteinDistance(_ left: String, _ right: String) -> Int {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        guard !leftCharacters.isEmpty else {
            return rightCharacters.count
        }
        guard !rightCharacters.isEmpty else {
            return leftCharacters.count
        }

        var previousRow = Array(0 ... rightCharacters.count)
        for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
            var currentRow = [leftIndex + 1]
            for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                currentRow.append(
                    min(
                        previousRow[rightIndex + 1] + 1,
                        currentRow[rightIndex] + 1,
                        previousRow[rightIndex] + substitutionCost
                    )
                )
            }
            previousRow = currentRow
        }

        return previousRow[rightCharacters.count]
    }

    private static func isValidEmojiReplacement(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1,
              let character = trimmed.first else {
            return false
        }

        let scalars = Array(character.unicodeScalars)
        let hasEmojiScalar = scalars.contains { $0.properties.isEmoji }
        guard hasEmojiScalar else {
            return false
        }

        return scalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || scalar.value == 0xFE0F
                || scalar.value == 0x200D
                || (0x1F000 ... 0x1FAFF).contains(scalar.value)
                || (0x2600 ... 0x27BF).contains(scalar.value)
        }
    }

    private static func isASCIIEmojiNameCharacter(_ character: Character) -> Bool {
        isASCIILetterOrDigit(character) || character == "-"
    }

    fileprivate static func isASCIIName(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value < 128 }
    }

    private static func isASCIILetterOrDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (65 ... 90).contains(value)
                || (97 ... 122).contains(value)
                || (48 ... 57).contains(value)
        }
    }

    private static func isPhraseBoundary(_ character: Character) -> Bool {
        if character.isNewline {
            return true
        }

        return character.unicodeScalars.contains { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || Set("，。！？、；：「」『』（）《》〈〉【】〔〕…—～·".unicodeScalars).contains(scalar)
        }
    }

    private static func isHanCharacter(_ character: Character) -> Bool {
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
}

struct EmojiAIResolverService {
    func resolve(phrase: String, settings: AppSettings, apiKey: String?) async throws -> String? {
        guard CloudTextAICapabilityPolicy.isCloudTextAIAvailable(for: settings) else {
            throw settings.provider == .local
                ? VoiceEditLLMError.unavailableInLocalMode
                : VoiceEditLLMError.disabledInSettings
        }
        guard let apiKey = OpenAICompatibleRequestBuilder.normalizedAPIKey(apiKey) else {
            return nil
        }

        if settings.provider == .gemini {
            do {
                let content = try await GeminiTextCompletionService().complete(
                    systemInstruction: """
                    You resolve short spoken emoji requests.
                    Return exactly one Unicode emoji if the phrase clearly names an emoji concept.
                    Return NONE if the phrase is ambiguous, unsafe, not an emoji concept, or no suitable emoji exists.
                    Do not return words, explanations, Markdown, quotes, punctuation, or multiple emoji.
                    """,
                    userContent: "Phrase: \(phrase)",
                    settings: settings,
                    apiKey: apiKey
                )
                return EmojiResolverService.singleEmoji(from: content)
            } catch VoiceEditLLMError.requestFailed {
                // Match the existing OpenAI-compatible behavior: an optional
                // emoji enhancement never prevents the transcript from being
                // inserted when the provider rejects the request.
                return nil
            }
        }

        guard let endpoint = OpenAICompatibleRequestBuilder.endpoint(
            baseURLString: settings.openAIBaseURL,
            path: "chat/completions"
        ) else {
            throw VoiceEditLLMError.invalidBaseURL(settings.openAIBaseURL)
        }
        var urlRequest = OpenAICompatibleRequestBuilder.authenticatedPOSTRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            settings: settings,
            contentType: "application/json"
        )

        urlRequest.httpBody = try JSONEncoder().encode(makePayload(phrase: phrase, settings: settings))

        let (data, response) = try await SensitiveRequestURLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(EmojiChatCompletionResponse.self, from: data)
        let content = decoded.choices.first?.message.content ?? ""
        return EmojiResolverService.singleEmoji(from: content)
    }

    private func makePayload(phrase: String, settings: AppSettings) -> EmojiChatCompletionRequest {
        return EmojiChatCompletionRequest(
            model: settings.effectiveEmojiResolverLLMModel,
            messages: [
                EmojiChatMessage(
                    role: "system",
                    content: """
                    You resolve short spoken emoji requests.
                    Return exactly one Unicode emoji if the phrase clearly names an emoji concept.
                    Return NONE if the phrase is ambiguous, unsafe, not an emoji concept, or no suitable emoji exists.
                    Do not return words, explanations, Markdown, quotes, punctuation, or multiple emoji.
                    """
                ),
                EmojiChatMessage(
                    role: "user",
                    content: "Phrase: \(phrase)"
                )
            ]
        )
    }
}

private struct EmojiAnnotationData: Decodable {
    let entries: [EmojiAnnotationEntry]
}

private struct EmojiAnnotationEntry: Decodable {
    let emoji: String
    let aliases: [String]
}

private struct EmojiAlias {
    let name: String
    let replacement: String
    let exactKey: String
    let normalizedName: String
    let isASCIIName: Bool

    init(name: String, replacement: String) {
        self.name = name
        self.replacement = replacement
        self.exactKey = EmojiResolverService.normalizedEmojiAliasName(name)
        self.normalizedName = EmojiResolverService.normalizedASCIIEmojiPhrase(name)
        self.isASCIIName = EmojiResolverService.isASCIIName(name)
    }
}

private struct EmojiAliasIndex {
    let aliases: [EmojiAlias]
    let exactAliases: [String: EmojiAlias]
    let asciiAliases: [EmojiAlias]

    init(aliases: [EmojiAlias]) {
        let deduplicatedAliases = EmojiResolverService.deduplicatedAliases(aliases)
        self.aliases = deduplicatedAliases
        self.exactAliases = Dictionary(
            deduplicatedAliases.map { ($0.exactKey, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        self.asciiAliases = deduplicatedAliases.filter {
            $0.isASCIIName && $0.normalizedName.count >= 4
        }
    }
}

private struct TextReplacement {
    let range: Range<String.Index>
    let replacement: String
}

private struct PhraseCandidate {
    let range: Range<String.Index>
    let text: String
}

private struct EmojiChatCompletionRequest: Encodable {
    let model: String
    let messages: [EmojiChatMessage]
}

private struct EmojiChatMessage: Codable {
    let role: String
    let content: String
}

private struct EmojiChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: EmojiChatMessage
    }
}
