import AppKit
import SwiftUI

struct TranscriptTextDiff: Equatable {
    enum SegmentKind: Equatable {
        case unchanged
        case removed
        case added
    }

    struct Segment: Equatable {
        let text: String
        let kind: SegmentKind
    }

    enum ChangeContentKind: Equatable {
        case text
        case punctuation
    }

    struct HighlightRun: Equatable {
        let text: String
        let contentKind: ChangeContentKind
    }

    let originalSegments: [Segment]
    let finalSegments: [Segment]

    var hasChanges: Bool {
        originalSegments.contains(where: { $0.kind == .removed })
            || finalSegments.contains(where: { $0.kind == .added })
    }

    /// Splits a changed segment into display-only semantic runs. Unicode punctuation
    /// categories cover both Latin and CJK punctuation; emoji and whitespace remain text.
    static func highlightRuns(in text: String) -> [HighlightRun] {
        var runs: [HighlightRun] = []

        for character in text {
            let contentKind: ChangeContentKind = isPunctuation(character)
                ? .punctuation
                : .text
            let characterText = String(character)

            if let last = runs.last, last.contentKind == contentKind {
                runs[runs.count - 1] = HighlightRun(
                    text: last.text + characterText,
                    contentKind: contentKind
                )
            } else {
                runs.append(HighlightRun(text: characterText, contentKind: contentKind))
            }
        }

        return runs
    }

    /// Produces a local, token-aware diff. Han characters and other East Asian scripts are
    /// compared one grapheme at a time, while Latin text is compared by word. Quadratic work
    /// is capped; unusually large changes fall back to their shared prefix and suffix.
    static func compare(original: String, final: String) -> TranscriptTextDiff {
        let originalTokens = tokenize(original)
        let finalTokens = tokenize(final)

        var prefixCount = 0
        while prefixCount < originalTokens.count,
              prefixCount < finalTokens.count,
              originalTokens[prefixCount] == finalTokens[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < originalTokens.count - prefixCount,
              suffixCount < finalTokens.count - prefixCount,
              originalTokens[originalTokens.count - suffixCount - 1]
                == finalTokens[finalTokens.count - suffixCount - 1] {
            suffixCount += 1
        }

        let originalPrefix = Array(originalTokens.prefix(prefixCount))
        let finalPrefix = Array(finalTokens.prefix(prefixCount))
        let originalMiddle = Array(
            originalTokens.dropFirst(prefixCount).dropLast(suffixCount)
        )
        let finalMiddle = Array(
            finalTokens.dropFirst(prefixCount).dropLast(suffixCount)
        )
        let originalSuffix = suffixCount == 0
            ? []
            : Array(originalTokens.suffix(suffixCount))
        let finalSuffix = suffixCount == 0
            ? []
            : Array(finalTokens.suffix(suffixCount))

        var originalSegments: [Segment] = []
        var finalSegments: [Segment] = []
        append(originalPrefix, kind: .unchanged, to: &originalSegments)
        append(finalPrefix, kind: .unchanged, to: &finalSegments)

        appendMiddleDiff(
            originalMiddle,
            finalMiddle,
            originalSegments: &originalSegments,
            finalSegments: &finalSegments
        )

        append(originalSuffix, kind: .unchanged, to: &originalSegments)
        append(finalSuffix, kind: .unchanged, to: &finalSegments)

        return TranscriptTextDiff(
            originalSegments: originalSegments,
            finalSegments: finalSegments
        )
    }

    private static let maximumMatrixCells = 180_000

    private static func appendMiddleDiff(
        _ original: [String],
        _ final: [String],
        originalSegments: inout [Segment],
        finalSegments: inout [Segment]
    ) {
        guard !original.isEmpty || !final.isEmpty else {
            return
        }

        guard !original.isEmpty else {
            append(final, kind: .added, to: &finalSegments)
            return
        }

        guard !final.isEmpty else {
            append(original, kind: .removed, to: &originalSegments)
            return
        }

        let cellCount = original.count.multipliedReportingOverflow(by: final.count)
        guard !cellCount.overflow, cellCount.partialValue <= maximumMatrixCells else {
            append(original, kind: .removed, to: &originalSegments)
            append(final, kind: .added, to: &finalSegments)
            return
        }

        let columnCount = final.count + 1
        var lengths = [UInt16](repeating: 0, count: (original.count + 1) * columnCount)

        for originalIndex in stride(from: original.count - 1, through: 0, by: -1) {
            for finalIndex in stride(from: final.count - 1, through: 0, by: -1) {
                let index = originalIndex * columnCount + finalIndex
                if original[originalIndex] == final[finalIndex] {
                    lengths[index] = lengths[(originalIndex + 1) * columnCount + finalIndex + 1] + 1
                } else {
                    lengths[index] = max(
                        lengths[(originalIndex + 1) * columnCount + finalIndex],
                        lengths[originalIndex * columnCount + finalIndex + 1]
                    )
                }
            }
        }

        var originalIndex = 0
        var finalIndex = 0
        while originalIndex < original.count, finalIndex < final.count {
            if original[originalIndex] == final[finalIndex] {
                append([original[originalIndex]], kind: .unchanged, to: &originalSegments)
                append([final[finalIndex]], kind: .unchanged, to: &finalSegments)
                originalIndex += 1
                finalIndex += 1
            } else if lengths[(originalIndex + 1) * columnCount + finalIndex]
                        >= lengths[originalIndex * columnCount + finalIndex + 1] {
                append([original[originalIndex]], kind: .removed, to: &originalSegments)
                originalIndex += 1
            } else {
                append([final[finalIndex]], kind: .added, to: &finalSegments)
                finalIndex += 1
            }
        }

        if originalIndex < original.count {
            append(Array(original[originalIndex...]), kind: .removed, to: &originalSegments)
        }
        if finalIndex < final.count {
            append(Array(final[finalIndex...]), kind: .added, to: &finalSegments)
        }
    }

    private static func append(
        _ tokens: [String],
        kind: SegmentKind,
        to segments: inout [Segment]
    ) {
        guard !tokens.isEmpty else {
            return
        }

        let text = tokens.joined()
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1] = Segment(text: last.text + text, kind: kind)
        } else {
            segments.append(Segment(text: text, kind: kind))
        }
    }

    private enum TokenClass: Equatable {
        case whitespace
        case word
        case atom
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var bufferedText = ""
        var bufferedClass: TokenClass?

        func flushBuffer() {
            guard !bufferedText.isEmpty else {
                return
            }
            tokens.append(bufferedText)
            bufferedText = ""
            bufferedClass = nil
        }

        for character in text {
            let tokenClass = tokenClass(for: character)
            if tokenClass == .atom {
                flushBuffer()
                tokens.append(String(character))
            } else if bufferedClass == tokenClass {
                bufferedText.append(character)
            } else {
                flushBuffer()
                bufferedClass = tokenClass
                bufferedText.append(character)
            }
        }
        flushBuffer()
        return tokens
    }

    private static func tokenClass(for character: Character) -> TokenClass {
        if character.isWhitespace {
            return .whitespace
        }
        if isEastAsianGrapheme(character) {
            return .atom
        }
        if character.isLetter || character.isNumber || character == "_"
            || character == "'" || character == "’" {
            return .word
        }
        return .atom
    }

    private static func isEastAsianGrapheme(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FDF, // CJK radicals
                 0x3040...0x30FF, // Hiragana and Katakana
                 0x3100...0x312F, // Bopomofo
                 0x31A0...0x31BF,
                 0x3400...0x4DBF, // CJK extension A
                 0x4E00...0x9FFF, // Unified ideographs
                 0xAC00...0xD7AF, // Hangul syllables
                 0xF900...0xFAFF,
                 0x20000...0x3134F: // CJK extensions B-G
                return true
            default:
                return false
            }
        }
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .connectorPunctuation,
                 .dashPunctuation,
                 .openPunctuation,
                 .closePunctuation,
                 .initialPunctuation,
                 .finalPunctuation,
                 .otherPunctuation:
                return true
            default:
                return false
            }
        }
    }
}

enum HistoryTrailingLineBreakMarkerPolicy {
    static func trailingLineBreakUTF16Range(in text: String) -> NSRange? {
        let text = text as NSString
        guard text.length > 0 else {
            return nil
        }

        if text.hasSuffix("\r\n") {
            return NSRange(location: text.length - 2, length: 2)
        }
        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            return NSRange(location: text.length - 1, length: 1)
        }
        return nil
    }
}

struct HistoryComparisonBaseline: Equatable {
    enum Kind: Equatable {
        case rawTranscript
        case initialOutput
    }

    let text: String
    let kind: Kind

    static func resolve(
        rawText: String,
        initialText: String?,
        itemText: String
    ) -> HistoryComparisonBaseline {
        if let initialText {
            return HistoryComparisonBaseline(text: initialText, kind: .initialOutput)
        }
        return HistoryComparisonBaseline(
            text: rawText.isEmpty ? itemText : rawText,
            kind: .rawTranscript
        )
    }
}

enum HistorySelectionResolver {
    static func nextSelectionAfterDeleting(
        id deletedID: TranscriptItem.ID,
        from history: [TranscriptItem]
    ) -> TranscriptItem.ID? {
        nextSelectionAfterDeleting(
            ids: Set([deletedID]),
            currentSelection: deletedID,
            from: history
        )
    }

    static func nextSelectionAfterDeleting(
        ids deletedIDs: Set<TranscriptItem.ID>,
        currentSelection: TranscriptItem.ID?,
        from history: [TranscriptItem]
    ) -> TranscriptItem.ID? {
        guard !deletedIDs.isEmpty else {
            return currentSelection.flatMap { selectedID in
                history.contains(where: { $0.id == selectedID }) ? selectedID : nil
            }
        }

        if let currentSelection,
           !deletedIDs.contains(currentSelection),
           history.contains(where: { $0.id == currentSelection }) {
            return currentSelection
        }

        let anchorIndex = currentSelection.flatMap { selectedID in
            history.firstIndex(where: { $0.id == selectedID })
        } ?? history.firstIndex(where: { deletedIDs.contains($0.id) })

        guard let anchorIndex else {
            return nil
        }

        if anchorIndex < history.count {
            for index in anchorIndex ..< history.count
            where !deletedIDs.contains(history[index].id) {
                return history[index].id
            }
        }

        guard anchorIndex > 0 else {
            return nil
        }
        for index in stride(from: anchorIndex - 1, through: 0, by: -1)
        where !deletedIDs.contains(history[index].id) {
            return history[index].id
        }
        return nil
    }
}

private struct HistoryDeletionRequest: Equatable {
    let itemIDs: Set<TranscriptItem.ID>
    let nextSelectionID: TranscriptItem.ID?
}

enum HistoryPendingEditPolicy {
    static func shouldSave(item: TranscriptItem, editedText: String) -> Bool {
        item.outcome.isSuccessful
            && editedText != item.text
            && !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct HistoryTextEditorDocumentState: Equatable {
    struct Transition: Equatable {
        let resetCursorUTF16Offset: Int?

        var shouldResetEditingContext: Bool {
            resetCursorUTF16Offset != nil
        }
    }

    private(set) var documentID: TranscriptItem.ID?

    mutating func transition(
        to documentID: TranscriptItem.ID,
        documentText: String
    ) -> Transition {
        guard self.documentID != documentID else {
            return Transition(resetCursorUTF16Offset: nil)
        }

        self.documentID = documentID
        return Transition(resetCursorUTF16Offset: documentText.utf16.count)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedID: TranscriptItem.ID?
    @State private var editedText = ""
    @State private var pendingDeletion: HistoryDeletionRequest?

    private var localizer: AppLocalizer {
        AppLocalizer(language: appState.settings.appLanguage)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(appState.history) { item in
                    HStack(alignment: .center, spacing: 10) {
                        Text(historyTitle(for: item))
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .foregroundStyle(.secondary)
                            if item.outcome == .failed {
                                Text(localizer.transcriptionAttemptOutcomeName(item.outcome))
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption2)
                    }
                    .padding(.vertical, 2)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowSeparator(.hidden)
                    .tag(item.id)
                }
                .onDelete(perform: requestDeletion)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 270, idealWidth: 300, maxWidth: 340)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedID == nil {
                selectedID = appState.history.first?.id
                syncSelection()
            }
        }
        .onChange(of: selectedID) { previousID, _ in
            savePendingEdit(for: previousID)
            syncSelection()
        }
        .onDisappear {
            savePendingEdit(for: selectedID)
        }
        .confirmationDialog(
            localizer.historyDeletionConfirmationTitle(
                count: pendingDeletion?.itemIDs.count ?? 1
            ),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(localizer.text(.delete), role: .destructive) {
                confirmPendingDeletion()
            }
            Button(localizer.cancelLabel(), role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(localizer.historyDeletionConfirmationDetail())
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedID, let item = appState.history.first(where: { $0.id == selectedID }) {
            let comparisonBaseline = HistoryComparisonBaseline.resolve(
                rawText: item.rawText,
                initialText: item.initialText,
                itemText: item.text
            )
            let textDiff = TranscriptTextDiff.compare(
                original: comparisonBaseline.text,
                final: editedText
            )

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(item.createdAt, format: .dateTime.year().month(.wide).day().hour().minute())
                            .font(.title3.weight(.semibold))

                        Spacer(minLength: 12)

                        Text(localizer.transcriptionAttemptOutcomeName(item.outcome))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.outcome == .failed ? .red : .secondary)
                            .lineLimit(1)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        metadataRow(
                            localizer.text(.provider),
                            value: localizer.providerName(item.provider)
                        )
                        metadataRow(localizer.text(.model), value: item.model)
                        metadataRow(
                            localizer.text(.transcriptionLanguage),
                            value: localizer.languageHintName(item.languageHint)
                        )
                    }
                    .font(.caption)

                    HStack(spacing: 8) {
                        Button {
                            appState.toggleAudioPlayback(for: item)
                        } label: {
                            let isPlaying = appState.playingAudioHistoryID == item.id
                            Label(
                                localizer.text(isPlaying ? .stopAudio : .playAudio),
                                systemImage: isPlaying ? "stop.fill" : "play.fill"
                            )
                            .labelStyle(.iconOnly)
                        }
                        .disabled(!appState.canPlayAudio(for: item))
                        .accessibilityLabel(
                            localizer.text(
                                appState.playingAudioHistoryID == item.id ? .stopAudio : .playAudio
                            )
                        )
                        .help(
                            localizer.text(
                                appState.playingAudioHistoryID == item.id ? .stopAudio : .playAudio
                            )
                        )

                        Button {
                            saveEditIfNeeded(item)
                            appState.copy(editedText)
                        } label: {
                            Label(localizer.text(.copy), systemImage: "doc.on.doc")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(editedText.isEmpty)
                        .accessibilityLabel(localizer.text(.copy))
                        .help(localizer.text(.copy))

                        Button {
                            saveEditIfNeeded(item)
                            appState.paste(editedText)
                        } label: {
                            Label(localizer.text(.paste), systemImage: "arrow.turn.down.left")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(editedText.isEmpty)
                        .accessibilityLabel(localizer.text(.paste))
                        .help(localizer.text(.paste))

                        Spacer(minLength: 12)

                        Button(role: .destructive) {
                            requestDeletion(of: Set([item.id]))
                        } label: {
                            Label(localizer.text(.delete), systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel(localizer.text(.delete))
                        .help(localizer.text(.delete))

                        Button {
                            appState.updateHistoryItem(id: selectedID, text: editedText)
                        } label: {
                            Label(localizer.text(.save), systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave(item))
                        .keyboardShortcut("s", modifiers: .command)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let errorSummary = item.errorSummary, !errorSummary.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(item.outcome == .failed ? .red : .secondary)
                                Text(errorSummary)
                                    .foregroundStyle(item.outcome == .failed ? .red : .secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if comparisonBaseline.text != editedText {
                            HistoryReadOnlyTextSection(
                                title: comparisonBaseline.kind == .initialOutput
                                    ? localizer.initialOutputLabel()
                                    : localizer.rawTranscriptLabel(),
                                segments: textDiff.originalSegments,
                                localizer: localizer
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                item.initialText == nil
                                    ? localizer.finalTranscriptLabel()
                                    : localizer.correctedOutputLabel()
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            HistoryDiffTextEditor(
                                documentID: item.id,
                                documentText: item.text,
                                text: $editedText,
                                diff: textDiff,
                                isEditable: item.outcome.isSuccessful,
                                accessibilityLabel: finalOutputAccessibilityLabel(
                                    item: item,
                                    diff: textDiff
                                )
                            )
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
                                }
                                .frame(minHeight: 180)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            ContentUnavailableView(localizer.text(.noTranscriptSelected), systemImage: "text.quote")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncSelection() {
        guard let selectedID,
              let item = appState.history.first(where: { $0.id == selectedID }) else {
            editedText = ""
            return
        }
        editedText = item.text
    }

    @ViewBuilder
    private func metadataRow(_ label: String, value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)

            Text(value)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func canSave(_ item: TranscriptItem) -> Bool {
        HistoryPendingEditPolicy.shouldSave(item: item, editedText: editedText)
    }

    private func saveEditIfNeeded(_ item: TranscriptItem) {
        guard canSave(item) else {
            return
        }
        appState.updateHistoryItem(id: item.id, text: editedText)
    }

    private func savePendingEdit(for itemID: TranscriptItem.ID?) {
        guard let itemID,
              let item = appState.history.first(where: { $0.id == itemID }) else {
            return
        }
        saveEditIfNeeded(item)
    }

    private func finalOutputAccessibilityLabel(
        item: TranscriptItem,
        diff: TranscriptTextDiff
    ) -> String {
        let title = item.initialText == nil
            ? localizer.finalTranscriptLabel()
            : localizer.correctedOutputLabel()
        let addedSummary = HistoryDiffAccessibility.addedSummary(
            from: diff.finalSegments,
            localizer: localizer
        )
        guard !addedSummary.isEmpty else {
            return title
        }
        return "\(title). \(addedSummary)"
    }

    private func historyTitle(for item: TranscriptItem) -> String {
        if !item.text.isEmpty {
            return item.text
        }
        if let errorSummary = item.errorSummary, !errorSummary.isEmpty {
            return errorSummary
        }
        return localizer.transcriptionAttemptOutcomeName(item.outcome)
    }

    private func requestDeletion(at offsets: IndexSet) {
        let itemIDs = Set(offsets.compactMap { index in
            appState.history.indices.contains(index) ? appState.history[index].id : nil
        })
        requestDeletion(of: itemIDs)
    }

    private func requestDeletion(of itemIDs: Set<TranscriptItem.ID>) {
        guard !itemIDs.isEmpty else {
            return
        }
        pendingDeletion = HistoryDeletionRequest(
            itemIDs: itemIDs,
            nextSelectionID: HistorySelectionResolver.nextSelectionAfterDeleting(
                ids: itemIDs,
                currentSelection: selectedID,
                from: appState.history
            )
        )
    }

    private func confirmPendingDeletion() {
        guard let request = pendingDeletion else {
            return
        }
        let offsets = IndexSet(
            appState.history.indices.filter { index in
                request.itemIDs.contains(appState.history[index].id)
            }
        )
        pendingDeletion = nil
        guard !offsets.isEmpty else {
            return
        }

        guard appState.deleteHistoryItems(at: offsets) else {
            return
        }
        selectedID = request.nextSelectionID
        syncSelection()
    }

}

private enum HistoryDiffPalette {
    static func nsColor(for contentKind: TranscriptTextDiff.ChangeContentKind) -> NSColor {
        switch contentKind {
        case .text:
            return .systemBlue
        case .punctuation:
            return .systemOrange
        }
    }

    static func color(for contentKind: TranscriptTextDiff.ChangeContentKind) -> Color {
        Color(nsColor: nsColor(for: contentKind))
    }
}

private enum HistoryDiffAccessibility {
    static func removedSummary(
        from segments: [TranscriptTextDiff.Segment],
        localizer: AppLocalizer
    ) -> String {
        summary(from: segments, kind: .removed, localizer: localizer)
    }

    static func addedSummary(
        from segments: [TranscriptTextDiff.Segment],
        localizer: AppLocalizer
    ) -> String {
        summary(from: segments, kind: .added, localizer: localizer)
    }

    private static func summary(
        from segments: [TranscriptTextDiff.Segment],
        kind: TranscriptTextDiff.SegmentKind,
        localizer: AppLocalizer
    ) -> String {
        let runs = segments
            .filter { $0.kind == kind }
            .flatMap { TranscriptTextDiff.highlightRuns(in: $0.text) }
        let text = runs
            .filter { $0.contentKind == .text }
            .map(\.text)
            .joined()
        let punctuation = runs
            .filter { $0.contentKind == .punctuation }
            .map(\.text)
            .joined()

        var summaries: [String] = []
        if !text.isEmpty {
            summaries.append(
                kind == .removed
                    ? localizer.historyRemovedTextAccessibility(text)
                    : localizer.historyAddedTextAccessibility(text)
            )
        }
        if !punctuation.isEmpty {
            summaries.append(
                kind == .removed
                    ? localizer.historyRemovedPunctuationAccessibility(punctuation)
                    : localizer.historyAddedPunctuationAccessibility(punctuation)
            )
        }
        return summaries.joined(separator: ". ")
    }
}

private struct HistoryReadOnlyTextSection: View {
    let title: String
    let segments: [TranscriptTextDiff.Segment]
    let localizer: AppLocalizer

    private var accessibilitySummary: String {
        HistoryDiffAccessibility.removedSummary(from: segments, localizer: localizer)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for segment in segments {
            if segment.kind == .removed {
                for run in TranscriptTextDiff.highlightRuns(in: segment.text) {
                    var part = AttributedString(run.text)
                    let color = HistoryDiffPalette.color(for: run.contentKind)
                    part.foregroundColor = color
                    part.backgroundColor = color.opacity(0.09)
                    part.strikethroughStyle = Text.LineStyle(
                        pattern: .solid,
                        color: color.opacity(0.38)
                    )
                    result += part
                }
            } else {
                result += AttributedString(segment.text)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(attributedText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilitySummary)
        }
    }
}

private final class HistoryDiffTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTrailingLineBreakMarker()
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func drawTrailingLineBreakMarker() {
        guard let markerRange = HistoryTrailingLineBreakMarkerPolicy
            .trailingLineBreakUTF16Range(in: string),
              let layoutManager,
              let textContainer,
              markerRange.location < string.utf16.count else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: markerRange.location)
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return
        }

        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        let usedRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        let marker = NSAttributedString(
            string: "↵",
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        let markerSize = marker.size()
        let desiredX = usedRect.maxX + 2
        let markerX = min(desiredX, max(lineRect.minX, lineRect.maxX - markerSize.width))
        let markerY = lineRect.minY + max(0, (lineRect.height - markerSize.height) / 2)
        marker.draw(
            at: NSPoint(
                x: textContainerOrigin.x + markerX,
                y: textContainerOrigin.y + markerY
            )
        )
    }
}

private struct HistoryDiffTextEditor: NSViewRepresentable {
    let documentID: TranscriptItem.ID
    let documentText: String
    @Binding var text: String
    let diff: TranscriptTextDiff
    let isEditable: Bool
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = HistoryDiffTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        let transition = context.coordinator.documentState.transition(
            to: documentID,
            documentText: documentText
        )

        if let cursorOffset = transition.resetCursorUTF16Offset {
            if textView.string != documentText {
                textView.string = documentText
            }
            textView.breakUndoCoalescing()
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(
                NSRange(
                    location: min(cursorOffset, textView.string.utf16.count),
                    length: 0
                )
            )
        } else if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            let textLength = textView.string.utf16.count
            let validRanges = selectedRanges.filter {
                NSMaxRange($0.rangeValue) <= textLength
            }
            if !validRanges.isEmpty {
                textView.selectedRanges = validRanges
            } else {
                textView.setSelectedRange(NSRange(location: textLength, length: 0))
            }
        }

        textView.isEditable = isEditable
        textView.setAccessibilityLabel(accessibilityLabel)
        if transition.shouldResetEditingContext, text != documentText {
            clearHighlights(in: textView)
        } else {
            applyHighlights(to: textView)
        }
        updateTextLayout(in: scrollView)
        textView.needsDisplay = true
    }

    private func applyHighlights(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else {
            return
        }

        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        clearHighlights(in: textView)

        var offset = 0
        for segment in diff.finalSegments {
            let length = segment.text.utf16.count
            if segment.kind == .added, length > 0, offset + length <= fullRange.length {
                var runOffset = offset
                for run in TranscriptTextDiff.highlightRuns(in: segment.text) {
                    let runLength = run.text.utf16.count
                    let range = NSRange(location: runOffset, length: runLength)
                    let color = HistoryDiffPalette.nsColor(for: run.contentKind)
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: color.withAlphaComponent(0.13),
                        forCharacterRange: range
                    )
                    layoutManager.addTemporaryAttribute(
                        .foregroundColor,
                        value: color,
                        forCharacterRange: range
                    )
                    runOffset += runLength
                }
            }
            offset += length
        }
    }

    private func clearHighlights(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else {
            return
        }

        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
    }

    private func updateTextLayout(in scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        let contentSize = scrollView.contentSize
        let width = max(contentSize.width, 1)
        textView.textContainer?.containerSize = NSSize(
            width: width,
            height: .greatestFiniteMagnitude
        )
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.frame.size.width = width
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            textView.frame.size.height = max(
                contentSize.height,
                usedHeight + textView.textContainerInset.height * 2
            )
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HistoryDiffTextEditor
        var documentState = HistoryTextEditorDocumentState()
        var isUpdating = false

        init(parent: HistoryDiffTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else {
                return
            }
            parent.text = textView.string
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppState())
}
