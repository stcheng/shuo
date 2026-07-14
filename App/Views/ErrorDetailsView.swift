import AppKit
import SwiftUI

struct ErrorDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let message: String
    let localizer: AppLocalizer
    let copy: (String) -> Void
    var close: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)

                Text(localizer.text(.errorDetails))
                    .font(.headline)

                Spacer()
            }

            SelectableTextView(text: message)
                .frame(minWidth: 560, minHeight: 280)

            HStack(spacing: 8) {
                Spacer()

                Button {
                    copy(message)
                } label: {
                    Label(localizer.text(.copy), systemImage: "doc.on.doc")
                }

                Button(localizer.text(.close)) {
                    if let close {
                        close()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 620, height: 390)
    }
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        updateTextLayout(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        updateTextLayout(in: scrollView)
    }

    private func updateTextLayout(in scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        let contentSize = scrollView.contentSize
        let width = max(contentSize.width, 1)
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.frame.size.width = width

        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            textView.frame.size.height = max(contentSize.height, usedHeight + textView.textContainerInset.height * 2)
        } else {
            textView.frame.size.height = max(contentSize.height, textView.frame.height)
        }
    }
}

#Preview {
    ErrorDetailsView(
        message: "OpenAI transcription failed (400): Example error body with request details.",
        localizer: AppLocalizer(language: .english),
        copy: { _ in }
    )
}
