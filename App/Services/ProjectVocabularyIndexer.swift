import Foundation

struct ProjectVocabularyIndexResult: Equatable {
    let terms: [ProjectVocabularyTerm]
    let scannedFileCount: Int
    let scannedByteCount: Int
}

struct ProjectVocabularyIndexer {
    static let maximumFileCount = 2_500
    static let maximumVisitedEntryCount = 20_000
    static let maximumTotalBytes = 8 * 1_024 * 1_024
    static let maximumFileBytes = 256 * 1_024

    private static let excludedDirectoryNames: Set<String> = [
        ".git", ".hg", ".svn", ".build", ".next", ".nuxt", ".cache",
        "node_modules", "deriveddata", "build", "dist", "coverage", "vendor",
        "pods", "carthage", "target", "venv", ".venv", "__pycache__"
    ]

    private static let sensitiveFileNames: Set<String> = [
        ".env", ".env.local", ".env.development", ".env.production",
        "credentials", "credentials.json", "secrets", "secrets.json"
    ]

    private static let sensitiveExtensions: Set<String> = [
        "key", "pem", "p12", "pfx", "cer", "crt", "mobileprovision"
    ]

    private static let sourceExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "cs", "java", "kt",
        "kts", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "php",
        "scala", "sql", "graphql", "proto", "sh", "zsh", "fish"
    ]

    private static let manifestNames: Set<String> = [
        "package.json", "package.swift", "pyproject.toml", "cargo.toml", "go.mod",
        "podfile", "gemfile", "composer.json", "build.gradle", "build.gradle.kts"
    ]

    private static let documentationExtensions: Set<String> = ["md", "mdx", "rst"]

    private static let commonIdentifiers: Set<String> = [
        "array", "bool", "boolean", "data", "date", "dictionary", "double",
        "error", "false", "file", "float", "foundation", "function", "int",
        "integer", "nil", "none", "null", "object", "result", "self", "string",
        "true", "url", "uuid", "value", "values", "view", "void"
    ]

    private struct Accumulator {
        var value: String
        var score: Int
        var occurrenceCount: Int
        var sources: Set<ProjectVocabularyTermSource>
    }

    func indexProject(at rootURL: URL) throws -> ProjectVocabularyIndexResult {
        let rootURL = rootURL.standardizedFileURL
        var accumulators: [String: Accumulator] = [:]
        record(
            rootURL.lastPathComponent,
            source: .projectName,
            weight: 1_000,
            into: &accumulators
        )

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return ProjectVocabularyIndexResult(
                terms: makeTerms(from: accumulators),
                scannedFileCount: 0,
                scannedByteCount: 0
            )
        }

        var scannedFileCount = 0
        var scannedByteCount = 0
        var visitedEntryCount = 0

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                throw CancellationError()
            }
            guard visitedEntryCount < Self.maximumVisitedEntryCount else {
                break
            }
            visitedEntryCount += 1

            let relativeComponents = fileURL.pathComponents.dropFirst(rootURL.pathComponents.count)
            if shouldExclude(relativeComponents: relativeComponents) {
                if isDirectory(fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard scannedFileCount < Self.maximumFileCount,
                  scannedByteCount < Self.maximumTotalBytes else {
                break
            }

            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true else {
                continue
            }

            let fileSize = values?.fileSize ?? 0
            guard fileSize > 0,
                  fileSize <= Self.maximumFileBytes,
                  scannedByteCount + fileSize <= Self.maximumTotalBytes,
                  shouldRead(fileURL) else {
                continue
            }

            scannedFileCount += 1
            scannedByteCount += fileSize
            extractPathTerms(from: fileURL, into: &accumulators)

            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            let lowercasedName = fileURL.lastPathComponent.lowercased()
            if lowercasedName == "package.json" {
                extractPackageJSONTerms(text, into: &accumulators)
            } else if Self.manifestNames.contains(lowercasedName) {
                extractManifestTerms(text, into: &accumulators)
            }

            if Self.documentationExtensions.contains(fileURL.pathExtension.lowercased()) {
                extractDocumentationTerms(text, into: &accumulators)
            } else if Self.sourceExtensions.contains(fileURL.pathExtension.lowercased()) {
                extractSourceTerms(text, into: &accumulators)
            }
        }

        return ProjectVocabularyIndexResult(
            terms: makeTerms(from: accumulators),
            scannedFileCount: scannedFileCount,
            scannedByteCount: scannedByteCount
        )
    }

    private func shouldExclude(relativeComponents: ArraySlice<String>) -> Bool {
        for component in relativeComponents {
            let lowercased = component.lowercased()
            let stem = URL(fileURLWithPath: lowercased).deletingPathExtension().lastPathComponent
            if Self.excludedDirectoryNames.contains(lowercased)
                || Self.sensitiveFileNames.contains(lowercased)
                || ["credential", "credentials", "secret", "secrets"].contains(stem)
                || Self.sensitiveExtensions.contains(URL(fileURLWithPath: component).pathExtension.lowercased()) {
                return true
            }
        }
        return false
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func shouldRead(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return Self.manifestNames.contains(name)
            || Self.sourceExtensions.contains(url.pathExtension.lowercased())
            || Self.documentationExtensions.contains(url.pathExtension.lowercased())
    }

    private func extractPathTerms(
        from fileURL: URL,
        into accumulators: inout [String: Accumulator]
    ) {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        for candidate in lexicalCandidates(in: baseName) where isDistinctive(candidate) {
            record(candidate, source: .path, weight: 350, into: &accumulators)
        }
    }

    private func extractPackageJSONTerms(
        _ text: String,
        into accumulators: inout [String: Accumulator]
    ) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            extractManifestTerms(text, into: &accumulators)
            return
        }

        if let name = object["name"] as? String {
            record(name, source: .manifest, weight: 850, into: &accumulators)
        }

        for key in ["dependencies", "devDependencies", "peerDependencies"] {
            guard let dependencies = object[key] as? [String: Any] else {
                continue
            }
            for dependency in dependencies.keys {
                record(dependency, source: .manifest, weight: 750, into: &accumulators)
            }
        }
    }

    private func extractManifestTerms(
        _ text: String,
        into accumulators: inout [String: Accumulator]
    ) {
        for candidate in matches(
            pattern: #"[A-Za-z@][A-Za-z0-9@._/-]{2,}"#,
            in: text,
            captureGroup: 0
        ) where isDistinctive(candidate) {
            record(candidate, source: .manifest, weight: 650, into: &accumulators)
        }
    }

    private func extractSourceTerms(
        _ text: String,
        into accumulators: inout [String: Accumulator]
    ) {
        let declarationPattern = #"\b(?:actor|class|def|enum|func|function|interface|protocol|record|struct|trait|type)\s+([\p{L}_][\p{L}\p{N}_]*)"#
        for candidate in matches(pattern: declarationPattern, in: text, captureGroup: 1) {
            record(candidate, source: .symbol, weight: 700, into: &accumulators)
        }

        let distinctivePatterns = [
            #"\b[A-Z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*\b"#,
            #"\b[A-Z][a-z]+[A-Za-z0-9]{2,}\b"#,
            #"\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b"#,
            #"\b[A-Z]{2,10}\b"#
        ]
        for pattern in distinctivePatterns {
            for candidate in matches(pattern: pattern, in: text, captureGroup: 0)
                where isDistinctive(candidate) {
                record(candidate, source: .symbol, weight: 500, into: &accumulators)
            }
        }
    }

    private func extractDocumentationTerms(
        _ text: String,
        into accumulators: inout [String: Accumulator]
    ) {
        for inlineCode in matches(pattern: #"`([^`\n]{2,80})`"#, in: text, captureGroup: 1) {
            for candidate in lexicalCandidates(in: inlineCode) where isDistinctive(candidate) {
                record(candidate, source: .documentation, weight: 500, into: &accumulators)
            }
        }

        for heading in matches(pattern: #"(?m)^#{1,4}\s+(.{2,120})$"#, in: text, captureGroup: 1) {
            for candidate in lexicalCandidates(in: heading) where isDistinctive(candidate) {
                record(candidate, source: .documentation, weight: 350, into: &accumulators)
            }
        }
    }

    private func lexicalCandidates(in text: String) -> [String] {
        let latinAndTechnical = matches(
            pattern: #"[A-Za-z@][A-Za-z0-9@._/-]{1,79}"#,
            in: text,
            captureGroup: 0
        )
        let cjk = matches(
            pattern: #"[\p{script=Han}\p{script=Hiragana}\p{script=Katakana}\p{script=Hangul}]{2,24}"#,
            in: text,
            captureGroup: 0
        )
        return latinAndTechnical + cjk
    }

    private func matches(pattern: String, in text: String, captureGroup: Int) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard captureGroup < match.numberOfRanges,
                  let swiftRange = Range(match.range(at: captureGroup), in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }

    private func isDistinctive(_ candidate: String) -> Bool {
        let value = cleaned(candidate)
        guard value.count >= 2,
              value.count <= 80,
              value.rangeOfCharacter(from: .letters) != nil else {
            return false
        }

        let lowercased = value.lowercased()
        guard !Self.commonIdentifiers.contains(lowercased),
              value.range(of: #"^[0-9a-fA-F]{16,}$"#, options: .regularExpression) == nil,
              !value.contains("://") else {
            return false
        }

        let hasSeparator = value.contains("_") || value.contains("-") || value.contains(".") || value.contains("/")
        let hasDigit = value.rangeOfCharacter(from: .decimalDigits) != nil
        let hasCJKScript = value.unicodeScalars.contains(where: isCJKScalar)
        let uppercaseCount = value.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        let lowercaseCount = value.unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) }.count
        return hasSeparator
            || hasDigit
            || hasCJKScript
            || uppercaseCount >= 2
            || (value.first?.isUppercase == true && lowercaseCount >= 2)
    }

    private func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x20000...0x2FA1F, 0x3040...0x30FF, 0xAC00...0xD7AF,
             0xFF66...0xFF9D:
            return true
        default:
            return false
        }
    }

    private func cleaned(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'(),[]{}<>"))
    }

    private func record(
        _ rawValue: String,
        source: ProjectVocabularyTermSource,
        weight: Int,
        into accumulators: inout [String: Accumulator]
    ) {
        let value = cleaned(rawValue)
        guard isDistinctive(value) || source == .projectName || source == .manifest else {
            return
        }
        let key = normalizedKey(value)
        guard !key.isEmpty else {
            return
        }

        if var accumulator = accumulators[key] {
            if weight > accumulator.score {
                accumulator.value = value
            }
            accumulator.occurrenceCount += 1
            accumulator.score = max(accumulator.score, weight) + 1
            accumulator.sources.insert(source)
            accumulators[key] = accumulator
        } else {
            accumulators[key] = Accumulator(
                value: value,
                score: weight,
                occurrenceCount: 1,
                sources: [source]
            )
        }
    }

    private func normalizedKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeTerms(from accumulators: [String: Accumulator]) -> [ProjectVocabularyTerm] {
        let terms = accumulators.values
            .map { accumulator in
                ProjectVocabularyTerm(
                    value: accumulator.value,
                    score: accumulator.score + min(accumulator.occurrenceCount, 25),
                    occurrenceCount: accumulator.occurrenceCount,
                    sources: accumulator.sources.sorted { $0.rawValue < $1.rawValue }
                )
            }
        return ProjectVocabularyLimits.limitedIndexedTerms(terms)
    }
}
