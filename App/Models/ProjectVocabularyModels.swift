import Foundation

enum ProjectVocabularyTermSource: String, Codable, CaseIterable, Hashable {
    case projectName
    case manifest
    case path
    case symbol
    case documentation
}

struct ProjectVocabularyTerm: Codable, Equatable, Identifiable {
    let value: String
    let score: Int
    let occurrenceCount: Int
    let sources: [ProjectVocabularyTermSource]

    var id: String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}

enum ProjectVocabularyLimits {
    static let maximumIndexedTermCount = 60

    static func limitedIndexedTerms(
        _ terms: [ProjectVocabularyTerm]
    ) -> [ProjectVocabularyTerm] {
        Array(
            terms
                .sorted {
                    if $0.score == $1.score {
                        return $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
                    }
                    return $0.score > $1.score
                }
                .prefix(maximumIndexedTermCount)
        )
    }
}

struct LinkedProjectVocabulary: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var lastKnownPath: String
    var bookmarkData: Data?
    var isEnabled: Bool
    var terms: [ProjectVocabularyTerm]
    var disabledTermIDs: Set<String>
    var lastIndexedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        lastKnownPath: String,
        bookmarkData: Data? = nil,
        isEnabled: Bool = true,
        terms: [ProjectVocabularyTerm] = [],
        disabledTermIDs: Set<String> = [],
        lastIndexedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.lastKnownPath = lastKnownPath
        self.bookmarkData = bookmarkData
        self.isEnabled = isEnabled
        self.terms = terms
        self.disabledTermIDs = disabledTermIDs
        self.lastIndexedAt = lastIndexedAt
    }

    var enabledTerms: [ProjectVocabularyTerm] {
        guard isEnabled else {
            return []
        }
        return terms.filter { !disabledTermIDs.contains($0.id) }
    }
}

struct ProjectVocabularyState: Codable, Equatable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var isProjectVocabularyEnabled: Bool
    var projects: [LinkedProjectVocabulary]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        isProjectVocabularyEnabled: Bool = false,
        projects: [LinkedProjectVocabulary] = []
    ) {
        self.schemaVersion = schemaVersion
        self.isProjectVocabularyEnabled = isProjectVocabularyEnabled
        self.projects = projects
    }

    mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        for index in projects.indices {
            let limitedTerms = ProjectVocabularyLimits.limitedIndexedTerms(
                projects[index].terms
            )
            projects[index].terms = limitedTerms
            projects[index].disabledTermIDs.formIntersection(
                Set(limitedTerms.map(\.id))
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isProjectVocabularyEnabled
        case projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isProjectVocabularyEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isProjectVocabularyEnabled
        ) ?? false
        projects = try container.decodeIfPresent(
            [LinkedProjectVocabulary].self,
            forKey: .projects
        ) ?? []
        normalize()
    }
}

struct TerminologyPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let terms: [String]
}

/// A user-owned, reusable vocabulary source.
///
/// Curated starter vocabularies use `presetID` as a stable migration identity,
/// but otherwise behave exactly like vocabularies the user creates: their
/// names and terms are editable, and the entire source can be removed.
struct NamedVocabularyItem: Codable, Equatable, Identifiable {
    static let importedLegacyGlossaryID = UUID(
        uuidString: "8A9F51D3-735A-41D8-A993-47D18C01D010"
    )!
    static let importedLegacyGlossaryName = "Existing preferred terms"

    var id: UUID
    var name: String
    var terms: String
    var isEnabled: Bool
    var presetID: String?

    init(
        id: UUID = UUID(),
        name: String,
        terms: String = "",
        isEnabled: Bool = true,
        presetID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.terms = terms
        self.isEnabled = isEnabled
        self.presetID = presetID
    }

    var normalizedTerms: [String] {
        terms
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func combinedGlossary(
        legacyGlossary: String,
        items: [NamedVocabularyItem]
    ) -> String {
        let sources = [normalizedTerms(in: legacyGlossary)]
            + items.filter(\.isEnabled).map { $0.normalizedTerms }
        var sourceOffsets = Array(repeating: 0, count: sources.count)
        var combined: [String] = []
        var seen = Set<String>()

        // Preserve source boundaries long enough to give every enabled source a
        // fair turn. The transcription composer has a strict term budget, so
        // concatenating one large legacy glossary ahead of newer vocabularies
        // can otherwise make the newer sources silently ineffective.
        while true {
            var visitedTerm = false

            for sourceIndex in sources.indices {
                let terms = sources[sourceIndex]
                while sourceOffsets[sourceIndex] < terms.count {
                    let term = terms[sourceOffsets[sourceIndex]]
                    sourceOffsets[sourceIndex] += 1
                    visitedTerm = true

                    if seen.insert(normalizedKey(for: term)).inserted {
                        combined.append(term)
                        break
                    }
                }
            }

            guard visitedTerm else {
                break
            }
        }

        return combined.joined(separator: "\n")
    }

    private static func normalizedTerms(in text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedKey(for term: String) -> String {
        term
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}

enum TerminologyPresetCatalog {
    static let codingID = "coding"
    static let machineLearningID = "machine-learning"
    static let productManagementID = "product-management"

    /// Starter vocabularies are deliberately short. They contain terms whose
    /// spelling is often ambiguous from audio, rather than a broad glossary of
    /// already-common product names.
    static let seedItems: [NamedVocabularyItem] = [
        NamedVocabularyItem(
            id: UUID(uuidString: "8A9F51D3-735A-41D8-A993-47D18C01D001")!,
            name: "Coding",
            terms: [
                "SwiftUI",
                "Xcode",
                "TypeScript",
                "Node.js",
                "Kubernetes",
                "PostgreSQL",
                "GraphQL",
                "WebSocket",
                "CocoaPods",
                "TestFlight",
                "Homebrew",
                "Ghostty"
            ].joined(separator: "\n"),
            isEnabled: false,
            presetID: codingID
        ),
        NamedVocabularyItem(
            id: UUID(uuidString: "8A9F51D3-735A-41D8-A993-47D18C01D002")!,
            name: "Machine Learning",
            terms: [
                "Codex",
                "RAG",
                "fine-tuning",
                "PyTorch",
                "Hugging Face",
                "LoRA",
                "MLX",
                "Core ML",
                "llama.cpp",
                "safetensors",
                "ONNX"
            ].joined(separator: "\n"),
            isEnabled: false,
            presetID: machineLearningID
        ),
        NamedVocabularyItem(
            id: UUID(uuidString: "8A9F51D3-735A-41D8-A993-47D18C01D003")!,
            name: "Product Management",
            terms: [
                "PRD",
                "product-market fit",
                "A/B test",
                "north-star metric",
                "go-to-market",
                "feature flag",
                "dogfooding",
                "RICE",
                "MoSCoW",
                "Jobs to Be Done"
            ].joined(separator: "\n"),
            isEnabled: false,
            presetID: productManagementID
        )
    ]

    /// Compatibility projection for the legacy preset pipeline. New code
    /// should consume the editable `NamedVocabularyItem` sources directly.
    static let all: [TerminologyPreset] = seedItems.compactMap { item in
        guard let presetID = item.presetID else {
            return nil
        }
        return TerminologyPreset(id: presetID, title: item.name, terms: item.normalizedTerms)
    }

    /// Adds starter vocabularies exactly once while preserving every user edit.
    /// A deleted starter is not recreated when its preset ID is present in the
    /// supplied tombstone set.
    static func mergedItems(
        existing: [NamedVocabularyItem],
        deletedPresetIDs: Set<String> = [],
        legacyEnabledPresetIDs: Set<String> = []
    ) -> [NamedVocabularyItem] {
        var result: [NamedVocabularyItem] = []
        var seenItemIDs = Set<UUID>()
        var seenPresetIDs = Set<String>()

        for var item in existing {
            if item.presetID == nil,
               let seed = seedItems.first(where: { $0.id == item.id }) {
                item.presetID = seed.presetID
            }
            guard seenItemIDs.insert(item.id).inserted else {
                continue
            }
            if let presetID = item.presetID {
                guard !deletedPresetIDs.contains(presetID),
                      seenPresetIDs.insert(presetID).inserted else {
                    continue
                }
            }
            result.append(item)
        }

        for var seed in seedItems {
            guard let presetID = seed.presetID,
                  !deletedPresetIDs.contains(presetID),
                  !seenPresetIDs.contains(presetID) else {
                continue
            }
            seed.isEnabled = legacyEnabledPresetIDs.contains(presetID)
            result.append(seed)
        }

        return result
    }

    static func deletionTombstones(
        afterRemoving item: NamedVocabularyItem,
        existing: Set<String>
    ) -> Set<String> {
        guard let presetID = item.presetID else {
            return existing
        }
        return existing.union([presetID])
    }

    static func enabledPresets(for ids: Set<String>) -> [TerminologyPreset] {
        all.filter { ids.contains($0.id) }
    }
}

enum TranscriptionVocabularySource: String, Equatable {
    case builtIn
    case manual
    case learnedCorrection
    case project
    case preset
}

struct TranscriptionVocabularyTerm: Equatable {
    let value: String
    let source: TranscriptionVocabularySource
    let priority: Int
}

struct TranscriptionVocabularySnapshot: Equatable {
    static let empty = TranscriptionVocabularySnapshot(terms: [])

    let terms: [String]

    var prompt: String {
        terms.joined(separator: ", ")
    }
}
