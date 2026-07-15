import Foundation

struct TranscriptionVocabularyBudget: Equatable {
    var maximumTermCount: Int
    var maximumCharacterCount: Int

    static let whisperCompatible = TranscriptionVocabularyBudget(
        maximumTermCount: 60,
        maximumCharacterCount: 900
    )
}

struct TranscriptionVocabularyComposer {
    private static let builtInTerms = ["Shuo"]

    func compose(
        manualGlossary: String,
        learnedCorrectionTerms: [String] = [],
        projectTerms: [ProjectVocabularyTerm] = [],
        presetTerms: [String] = [],
        budget: TranscriptionVocabularyBudget = .whisperCompatible
    ) -> TranscriptionVocabularySnapshot {
        var candidates: [TranscriptionVocabularyTerm] = []

        candidates.append(contentsOf: Self.builtInTerms.enumerated().map { index, value in
            TranscriptionVocabularyTerm(
                value: value,
                source: .builtIn,
                priority: 4_000 - index
            )
        })

        let manualTerms = manualGlossary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        candidates.append(contentsOf: manualTerms.enumerated().map { index, value in
            TranscriptionVocabularyTerm(
                value: value,
                source: .manual,
                priority: 3_000 - min(index, 500)
            )
        })

        candidates.append(contentsOf: learnedCorrectionTerms.enumerated().map { index, value in
            TranscriptionVocabularyTerm(
                value: value,
                source: .learnedCorrection,
                priority: 2_500 - min(index, 400)
            )
        })

        candidates.append(contentsOf: projectTerms.map { term in
            TranscriptionVocabularyTerm(
                value: term.value,
                source: .project,
                priority: 1_000 + min(max(term.score, 0), 899)
            )
        })

        candidates.append(contentsOf: presetTerms.enumerated().map { index, value in
            TranscriptionVocabularyTerm(
                value: value,
                source: .preset,
                priority: 500 - min(index, 499)
            )
        })

        let selectedTerms = selectTerms(candidates, budget: budget)
        return TranscriptionVocabularySnapshot(terms: selectedTerms)
    }

    private func selectTerms(
        _ candidates: [TranscriptionVocabularyTerm],
        budget: TranscriptionVocabularyBudget
    ) -> [String] {
        let sortedCandidates = candidates.sorted {
            if $0.priority == $1.priority {
                return $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
            }
            return $0.priority > $1.priority
        }

        var selected: [String] = []
        var selectedKeys = Set<String>()
        var characterCount = 0

        for candidate in sortedCandidates {
            guard selected.count < budget.maximumTermCount else {
                break
            }

            let value = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedKey(value)
            guard !value.isEmpty,
                  value.count <= 100,
                  !selectedKeys.contains(key) else {
                continue
            }

            let separatorCount = selected.isEmpty ? 0 : 2
            guard characterCount + separatorCount + value.count <= budget.maximumCharacterCount else {
                continue
            }

            selected.append(value)
            selectedKeys.insert(key)
            characterCount += separatorCount + value.count
        }

        return selected
    }

    private func normalizedKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
