import Foundation

struct VoiceEditCommand {
    let source: String
    let replacement: String
}

struct VoiceEditCommandParser {
    func parse(_ text: String) -> VoiceEditCommand? {
        let trimmed = trimCommandEdges(text)
        guard !trimmed.isEmpty,
              let prefix = matchingPrefix(in: trimmed) else {
            return nil
        }

        var body = String(trimmed.dropFirst(prefix.count))
        body = trimCommandEdges(body)

        for marker in leadingMarkers where body.range(
            of: marker,
            options: [.anchored, .caseInsensitive, .diacriticInsensitive]
        ) != nil {
            body = String(body.dropFirst(marker.count))
            body = trimCommandEdges(body)
            break
        }

        guard let separatorRange = firstSeparatorRange(in: body) else {
            return nil
        }

        let source = trimCommandEdges(String(body[..<separatorRange.lowerBound]))
        let replacement = trimCommandEdges(String(body[separatorRange.upperBound...]))

        guard !source.isEmpty, !replacement.isEmpty else {
            return nil
        }

        return VoiceEditCommand(source: source, replacement: replacement)
    }

    func isDeletePreviousInsertionCommand(_ text: String) -> Bool {
        let trimmed = trimCommandEdges(text)
        guard !trimmed.isEmpty else {
            return false
        }

        for prefix in deleteCommandPrefixes {
            guard let range = trimmed.range(
                of: prefix,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) else {
                continue
            }

            let remainingText = trimCommandEdges(String(trimmed[range.upperBound...]))
            if remainingText.isEmpty {
                return true
            }
        }

        return false
    }

    func looksLikeEditCommand(_ text: String) -> Bool {
        let trimmed = trimCommandEdges(text)
        return matchingPrefix(in: trimmed) != nil || isDeletePreviousInsertionCommand(trimmed)
    }

    private var commandPrefixes: [String] {
        [
            "修改上一句",
            "修改 上一句",
            "修改上句",
            "修改 上句",
            "修改上一段",
            "修改 上一段",
            "修改上一次",
            "修改 上一次",
            "更正上一句",
            "更正 上一句",
            "修正上一句",
            "修正 上一句",
            "edit last sentence",
            "edit previous sentence",
            "edit last line",
            "edit previous line",
            "edit last text",
            "edit previous text",
            "edit last entry",
            "edit previous entry",
            "fix last sentence",
            "fix previous sentence",
            "correct last sentence",
            "correct previous sentence",
            "change last sentence",
            "change previous sentence",
            "replace last sentence",
            "replace previous sentence",
            "modify last sentence",
            "modify previous sentence",
            "前の文を修正",
            "前の文章を修正",
            "直前の文を修正",
            "直前の文章を修正",
            "最後の文を修正",
            "最後の文章を修正"
        ]
    }

    private var deleteCommandPrefixes: [String] {
        [
            "删除上一句",
            "删除 上一句",
            "删除上句",
            "删除 上句",
            "删除上一段",
            "删除 上一段",
            "删除上一次",
            "删除 上一次",
            "删掉上一句",
            "删掉 上一句",
            "删掉上句",
            "删掉 上句",
            "删掉上一段",
            "删掉 上一段",
            "删掉上一次",
            "删掉 上一次",
            "刪除上一句",
            "刪除 上一句",
            "刪除上句",
            "刪除 上句",
            "刪除上一段",
            "刪除 上一段",
            "刪除上一次",
            "刪除 上一次",
            "刪掉上一句",
            "刪掉 上一句",
            "刪掉上句",
            "刪掉 上句",
            "刪掉上一段",
            "刪掉 上一段",
            "刪掉上一次",
            "刪掉 上一次",
            "delete last sentence",
            "delete previous sentence",
            "delete last line",
            "delete previous line",
            "delete last text",
            "delete previous text",
            "delete last entry",
            "delete previous entry",
            "remove last sentence",
            "remove previous sentence",
            "remove last line",
            "remove previous line",
            "remove last text",
            "remove previous text",
            "remove last entry",
            "remove previous entry",
            "前の文を削除",
            "前の文章を削除",
            "直前の文を削除",
            "直前の文章を削除",
            "最後の文を削除",
            "最後の文章を削除"
        ]
    }

    private var leadingMarkers: [String] {
        [
            "把上一句里面的",
            "把上一句裡面的",
            "把上一句里的",
            "把上一句裏的",
            "把上一句的",
            "把上句的",
            "把上一段里面的",
            "把上一段裡面的",
            "把上一段里的",
            "把上一段裏的",
            "把上一段的",
            "把刚才的",
            "把剛才的",
            "把 上一句 的",
            "把 上一段 的",
            "把",
            "将",
            "將",
            "change",
            "replace",
            "correct",
            "fix",
            "the word",
            "word"
        ]
    }

    private var separators: [String] {
        [
            "替换成",
            "替換成",
            "替换为",
            "替換為",
            "改成",
            "改为",
            "改為",
            "换成",
            "換成",
            "变成",
            "變成",
            " to ",
            " with ",
            " into "
        ]
    }

    private func matchingPrefix(in text: String) -> String? {
        commandPrefixes.first {
            text.range(
                of: $0,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    private func firstSeparatorRange(in text: String) -> Range<String.Index>? {
        var earliestRange: Range<String.Index>?

        for separator in separators {
            guard let range = text.range(
                of: separator,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) else {
                continue
            }

            if let current = earliestRange {
                if range.lowerBound < current.lowerBound {
                    earliestRange = range
                }
            } else {
                earliestRange = range
            }
        }

        return earliestRange
    }

    private func trimCommandEdges(_ text: String) -> String {
        let edgeCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ":：,，.。;；\"'“”‘’"))
        return text.trimmingCharacters(in: edgeCharacters)
    }
}
