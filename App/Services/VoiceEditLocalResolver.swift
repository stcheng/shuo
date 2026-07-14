import Foundation

struct VoiceEditLocalResolver {
    func replacing(_ source: String, with replacement: String, in text: String) -> String {
        if let range = replacementRange(of: source, in: text, options: []) {
            var correctedText = text
            correctedText.replaceSubrange(range, with: replacement)
            return correctedText
        }

        if let range = replacementRange(
            of: source,
            in: text,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            var correctedText = text
            correctedText.replaceSubrange(range, with: replacement)
            return correctedText
        }

        return text
    }

    func shouldUseLocalResolution(mode: VoiceEditCommandMode) -> Bool {
        switch mode {
        case .localOnly:
            return true
        case .llmOnly:
            return false
        }
    }

    func commandText(rawText: String, fallbackText: String, parser: VoiceEditCommandParser) -> String {
        let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)

        if parser.looksLikeEditCommand(raw) {
            return raw
        }

        if parser.looksLikeEditCommand(fallback) {
            return fallback
        }

        return raw.isEmpty ? fallback : raw
    }

    private func replacementRange(
        of source: String,
        in text: String,
        options: String.CompareOptions
    ) -> Range<String.Index>? {
        guard requiresWordBoundary(source) else {
            return text.range(of: source, options: options)
        }

        let escapedSource = NSRegularExpression.escapedPattern(for: source)
        let pattern = "(?<![A-Za-z0-9_])\(escapedSource)(?![A-Za-z0-9_])"
        let regexOptions: NSRegularExpression.Options = options.contains(.caseInsensitive) ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else {
            return nil
        }

        return Range(match.range, in: text)
    }

    private func requiresWordBoundary(_ source: String) -> Bool {
        guard !source.isEmpty else {
            return false
        }

        return source.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (65 ... 90).contains(value)
                || (97 ... 122).contains(value)
                || (48 ... 57).contains(value)
                || value == 95
        }
    }

}
