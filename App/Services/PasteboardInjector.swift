import AppKit
import ApplicationServices
import OSLog

enum ShuoSyntheticEventMarker {
    private static let marker: Int64 = 0x5348_554F // "SHUO"

    static func mark(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    static func isMarked(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == marker
    }
}

enum PasteboardInjectionResult: Equatable {
    case pasteEventPosted
    case copiedOnly
    case clipboardSnapshotUnavailable
    case cancelled
}

enum PreviousInsertionReplacementResult: Equatable {
    case replaced
    case copiedForSafety
    case notVerified
    case eventAccessDenied
    case clipboardSnapshotUnavailable
    case partialModification
}

struct GuardedBackspaceRewritePolicy {
    static let maximumDirectPasteCharacterCount = 1_000
    private static let blockingReplacementModifiers: CGEventFlags = [
        .maskCommand,
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskSecondaryFn
    ]
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2"
    ]

    static func hasBlockingReplacementModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(blockingReplacementModifiers).isEmpty
    }

    static func prefersDirectEventDelivery(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.googlecode.iterm2"
    }

    static func preservesConfiguredTrailingNewlineInPlace(
        bundleIdentifier: String?
    ) -> Bool {
        guard let bundleIdentifier else {
            return false
        }
        return terminalBundleIdentifiers.contains(bundleIdentifier)
    }

    static func targetOmitsConfiguredTrailingNewline(
        bundleIdentifier: String?,
        accessibilityRole: String?
    ) -> Bool {
        !preservesConfiguredTrailingNewlineInPlace(bundleIdentifier: bundleIdentifier)
            && accessibilityRole == kAXTextFieldRole as String
    }

    static func allowsRewrite(
        bundleIdentifier: String?,
        currentBundleIdentifier: String?,
        targetProcessIdentifier: pid_t?,
        currentProcessIdentifier: pid_t?,
        observedExternalInteraction: Bool,
        previousText: String
    ) -> Bool {
        guard let bundleIdentifier,
              let currentBundleIdentifier,
              bundleIdentifier == currentBundleIdentifier,
              let targetProcessIdentifier,
              currentProcessIdentifier == targetProcessIdentifier else {
            return false
        }

        return !observedExternalInteraction
            && !previousText.isEmpty
            && previousText.unicodeScalars.count <= maximumDirectPasteCharacterCount
    }
}

struct BackspaceReplacementPlan: Equatable {
    let backspaceCount: Int
    let pastedText: String
    let preservesTrailingNewline: Bool
    let commonPrefixCount: Int
    let verificationText: String
    let previousSuffixText: String

    var hasChanges: Bool {
        backspaceCount > 0 || !pastedText.isEmpty
    }

    init(
        previousText: String,
        replacementText: String,
        preservesTrailingNewline: Bool,
        omitsTrailingNewline: Bool = false
    ) {
        let previousEditableText: String
        let replacementEditableText: String
        let excludesTrailingNewline = preservesTrailingNewline || omitsTrailingNewline
        if excludesTrailingNewline,
           let previousTrailingNewline = previousText.shuoTrailingLineBreak {
            previousEditableText = String(
                previousText.dropLast(previousTrailingNewline.count)
            )
            if let replacementTrailingNewline = replacementText.shuoTrailingLineBreak {
                replacementEditableText = String(
                    replacementText.dropLast(replacementTrailingNewline.count)
                )
            } else {
                replacementEditableText = replacementText
            }
            self.preservesTrailingNewline = preservesTrailingNewline
            verificationText = omitsTrailingNewline ? previousEditableText : previousText
        } else {
            previousEditableText = previousText
            replacementEditableText = replacementText
            self.preservesTrailingNewline = false
            verificationText = previousText
        }

        let previousCharacters = Array(previousEditableText)
        let replacementCharacters = Array(replacementEditableText)
        commonPrefixCount = zip(previousCharacters, replacementCharacters)
            .prefix { previous, replacement in
                previous == replacement
            }
            .count
        backspaceCount = previousCharacters.count - commonPrefixCount
        previousSuffixText = String(previousCharacters.dropFirst(commonPrefixCount))
        pastedText = String(replacementCharacters.dropFirst(commonPrefixCount))
    }

    func suffixRestoringLastDeletedCharacters(_ count: Int) -> String {
        guard count > 0 else {
            return ""
        }
        return String(Array(previousSuffixText).suffix(min(count, backspaceCount)))
    }
}

@MainActor
enum ReplacementEventSequence {
    static func performAccessibilityReplacement(
        _ plan: BackspaceReplacementPlan,
        validate: () -> Bool,
        sendBackspaces: (Int) -> Bool,
        wait: (TimeInterval) async -> Void,
        paste: (String) -> Bool,
        validateDeletion: () -> Bool = { true },
        mutationOccurred: () -> Void = {},
        rollback: (String) -> Bool = { _ in false }
    ) async -> Bool {
        guard plan.hasChanges else {
            return true
        }
        guard validate() else {
            return false
        }
        let interval: TimeInterval
        switch plan.backspaceCount {
        case ...64:
            interval = 0.004
        case ...256:
            interval = 0.002
        default:
            interval = 0.001
        }
        var deletedCount = 0
        for _ in 0..<plan.backspaceCount {
            await wait(interval)
            guard validate() else {
                return false
            }
            guard sendBackspaces(1) else {
                if validate(), deletedCount > 0 {
                    _ = rollback(plan.suffixRestoringLastDeletedCharacters(deletedCount))
                }
                return false
            }
            deletedCount += 1
            mutationOccurred()
        }
        if deletedCount > 0 {
            await wait(0.05)
            guard validate(), validateDeletion() else {
                return false
            }
        }
        guard !plan.pastedText.isEmpty else {
            return true
        }
        guard paste(plan.pastedText) else {
            if validate(), deletedCount > 0 {
                _ = rollback(plan.previousSuffixText)
            }
            return false
        }
        return true
    }

    static func performTerminalReplacement(
        _ plan: BackspaceReplacementPlan,
        directTargetProcessIdentifier: pid_t?,
        validate: () -> Bool,
        postKey: (CGKeyCode, pid_t?) -> Bool,
        wait: (TimeInterval) async -> Void,
        paste: (String) -> Bool,
        mutationOccurred: () -> Void = {},
        rollback: (String) -> Bool = { _ in false }
    ) async -> Bool {
        let leftArrowKeyCode: CGKeyCode = 0x7B
        let rightArrowKeyCode: CGKeyCode = 0x7C
        let deleteKeyCode: CGKeyCode = 0x33
        let interval: TimeInterval
        if directTargetProcessIdentifier != nil {
            interval = 0.012
        } else {
            switch plan.backspaceCount {
            case ...64:
                interval = 0.004
            case ...256:
                interval = 0.002
            default:
                interval = 0.001
            }
        }

        guard plan.hasChanges else {
            return true
        }
        guard validate() else {
            return false
        }
        if plan.preservesTrailingNewline {
            guard postKey(leftArrowKeyCode, directTargetProcessIdentifier) else {
                return false
            }
        }

        var deletedCount = 0
        for _ in 0..<plan.backspaceCount {
            await wait(interval)
            guard validate() else {
                return false
            }
            guard postKey(deleteKeyCode, directTargetProcessIdentifier) else {
                if validate(), deletedCount > 0 {
                    let restored = rollback(
                        plan.suffixRestoringLastDeletedCharacters(deletedCount)
                    )
                    if restored, plan.preservesTrailingNewline {
                        _ = postKey(rightArrowKeyCode, directTargetProcessIdentifier)
                    }
                }
                return false
            }
            deletedCount += 1
            mutationOccurred()
        }

        await wait(0.05)
        guard validate() else {
            return false
        }
        var pastePosted = true
        if !plan.pastedText.isEmpty {
            pastePosted = paste(plan.pastedText)
        }
        if !pastePosted {
            if validate(), deletedCount > 0 {
                let restored = rollback(plan.previousSuffixText)
                if restored, plan.preservesTrailingNewline {
                    _ = postKey(rightArrowKeyCode, directTargetProcessIdentifier)
                }
            }
            return false
        }

        if plan.preservesTrailingNewline {
            await wait(0.12)
            guard validate() else {
                return false
            }
            guard postKey(rightArrowKeyCode, directTargetProcessIdentifier) else {
                return false
            }
        }

        return true
    }
}

private extension String {
    var shuoTrailingLineBreak: String? {
        if hasSuffix("\r\n") {
            return "\r\n"
        }
        guard let last, last.isNewline else {
            return nil
        }
        return String(last)
    }
}

struct FocusedTextSnapshot: Equatable {
    let text: String
    let selectedRange: NSRange

    func hasCollapsedCursorImmediatelyAfter(_ previousText: String) -> Bool {
        guard selectedRange.length == 0 else {
            return false
        }

        let textCodeUnits = Array(text.utf16)
        let previousLength = previousText.utf16.count
        guard selectedRange.location <= textCodeUnits.count,
              previousLength <= selectedRange.location else {
            return false
        }

        let prefix = String(
            decoding: textCodeUnits[..<selectedRange.location],
            as: UTF16.self
        )
        return Self.normalizedForAccessibilityComparison(prefix).hasSuffix(
            Self.normalizedForAccessibilityComparison(previousText)
        )
    }

    static func normalizedForAccessibilityComparison(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .precomposedStringWithCanonicalMapping
    }

    func reflectsDeletion(
        of deletedText: String,
        from original: FocusedTextSnapshot
    ) -> Bool {
        guard selectedRange.length == 0,
              original.selectedRange.length == 0 else {
            return false
        }

        let deletedUTF16Count = deletedText.utf16.count
        guard deletedUTF16Count > 0,
              deletedUTF16Count <= original.selectedRange.location else {
            return false
        }
        let deletionStart = original.selectedRange.location - deletedUTF16Count
        let originalCodeUnits = Array(original.text.utf16)
        guard original.selectedRange.location <= originalCodeUnits.count else {
            return false
        }

        let deletedRange = deletionStart..<original.selectedRange.location
        let actualDeletedText = String(
            decoding: originalCodeUnits[deletedRange],
            as: UTF16.self
        )
        guard Self.normalizedForAccessibilityComparison(actualDeletedText)
                == Self.normalizedForAccessibilityComparison(deletedText) else {
            return false
        }

        var expectedCodeUnits = originalCodeUnits
        expectedCodeUnits.removeSubrange(deletedRange)
        let expectedText = String(decoding: expectedCodeUnits, as: UTF16.self)
        return selectedRange.location == deletionStart
            && Self.normalizedForAccessibilityComparison(text)
                == Self.normalizedForAccessibilityComparison(expectedText)
    }
}

struct FocusedTextTarget {
    let applicationProcessIdentifier: pid_t
    let element: AXUIElement
    let accessibilityRole: String?

    init(
        applicationProcessIdentifier: pid_t,
        element: AXUIElement,
        accessibilityRole: String? = nil
    ) {
        self.applicationProcessIdentifier = applicationProcessIdentifier
        self.element = element
        self.accessibilityRole = accessibilityRole
    }
}

protocol FocusedTextSnapshotProviding {
    func focusedTextSnapshot(applicationProcessIdentifier: pid_t?) -> FocusedTextSnapshot?
    func focusedTextTarget(applicationProcessIdentifier: pid_t?) -> FocusedTextTarget?
    func restoreFocus(to target: FocusedTextTarget) -> Bool
    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in target: FocusedTextTarget
    ) -> Bool
    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in target: FocusedTextTarget,
        allowingValueSuffixFallback: Bool
    ) -> Bool
    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        applicationProcessIdentifier: pid_t?
    ) -> Bool
}

extension FocusedTextSnapshotProviding {
    func focusedTextTarget(applicationProcessIdentifier: pid_t?) -> FocusedTextTarget? {
        nil
    }

    func restoreFocus(to target: FocusedTextTarget) -> Bool {
        false
    }

    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in target: FocusedTextTarget
    ) -> Bool {
        hasCollapsedCursorImmediatelyAfter(
            previousText,
            applicationProcessIdentifier: target.applicationProcessIdentifier
        )
    }

    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in target: FocusedTextTarget,
        allowingValueSuffixFallback: Bool
    ) -> Bool {
        hasCollapsedCursorImmediatelyAfter(previousText, in: target)
    }

    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        applicationProcessIdentifier: pid_t?
    ) -> Bool {
        focusedTextSnapshot(applicationProcessIdentifier: applicationProcessIdentifier)?
            .hasCollapsedCursorImmediatelyAfter(previousText) == true
    }
}

struct AccessibilityFocusedTextSnapshotProvider: FocusedTextSnapshotProviding {
    private static let logger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "SafeReplacement"
    )

    func focusedTextSnapshot(applicationProcessIdentifier: pid_t?) -> FocusedTextSnapshot? {
        guard let focusedElement = focusedElement(
            applicationProcessIdentifier: applicationProcessIdentifier
        ),
              let selectedRange = selectedRange(in: focusedElement),
              let text = text(in: focusedElement) else {
            return nil
        }

        return FocusedTextSnapshot(text: text, selectedRange: selectedRange)
    }

    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        applicationProcessIdentifier: pid_t?
    ) -> Bool {
        guard let focusedElement = focusedElement(
            applicationProcessIdentifier: applicationProcessIdentifier
        ) else {
            Self.logger.notice(
                "Verification failed: focused element unavailable; pid=\(String(applicationProcessIdentifier ?? 0), privacy: .public)"
            )
            return false
        }

        return hasCollapsedCursorImmediatelyAfter(previousText, in: focusedElement)
    }

    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in target: FocusedTextTarget
    ) -> Bool {
        hasCollapsedCursorImmediatelyAfter(
            previousText,
            in: target,
            allowingValueSuffixFallback: false
        )
    }

    func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in target: FocusedTextTarget,
        allowingValueSuffixFallback: Bool
    ) -> Bool {
        var currentProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(target.element, &currentProcessIdentifier) == .success,
              currentProcessIdentifier == target.applicationProcessIdentifier else {
            Self.logger.notice(
                "Verification failed: saved target is no longer valid; expectedPid=\(String(target.applicationProcessIdentifier), privacy: .public) actualPid=\(String(currentProcessIdentifier), privacy: .public)"
            )
            return false
        }

        return hasCollapsedCursorImmediatelyAfter(
            previousText,
            in: target.element,
            allowingValueSuffixFallback: allowingValueSuffixFallback
        )
    }

    private func hasCollapsedCursorImmediatelyAfter(
        _ previousText: String,
        in focusedElement: AXUIElement,
        allowingValueSuffixFallback: Bool = false
    ) -> Bool {
        let role = accessibilityStringAttribute(kAXRoleAttribute, in: focusedElement) ?? "unknown"
        guard let selectedRange = selectedRange(in: focusedElement) else {
            Self.logger.notice(
                "Verification failed: selected text range unavailable; role=\(role, privacy: .public)"
            )
            return false
        }
        guard selectedRange.length == 0 else {
            Self.logger.notice(
                "Verification failed: selection is not collapsed; role=\(role, privacy: .public) selectionLength=\(selectedRange.length, privacy: .public)"
            )
            return false
        }

        let accessibleText = text(in: focusedElement)
        if let text = accessibleText {
            let snapshot = FocusedTextSnapshot(text: text, selectedRange: selectedRange)
            if snapshot.hasCollapsedCursorImmediatelyAfter(previousText) {
                Self.logger.info(
                    "Verification succeeded using AXValue; role=\(role, privacy: .public) cursor=\(selectedRange.location, privacy: .public) valueLength=\(text.utf16.count, privacy: .public) previousLength=\(previousText.utf16.count, privacy: .public)"
                )
                return true
            }
        }

        let previousLength = previousText.utf16.count
        if allowingValueSuffixFallback,
           selectedRange.location == 0,
           previousLength > 0,
           let accessibleText,
           FocusedTextSnapshot.normalizedForAccessibilityComparison(accessibleText).hasSuffix(
            FocusedTextSnapshot.normalizedForAccessibilityComparison(previousText)
           ) {
            Self.logger.info(
                "Verification succeeded using unchanged AXValue suffix for unreliable zero cursor; role=\(role, privacy: .public) valueLength=\(accessibleText.utf16.count, privacy: .public) previousLength=\(previousLength, privacy: .public)"
            )
            return true
        }

        guard previousLength <= selectedRange.location else {
            Self.logger.notice(
                "Verification failed: cursor precedes expected text; role=\(role, privacy: .public) cursor=\(selectedRange.location, privacy: .public) valueLength=\(accessibleText?.utf16.count ?? -1, privacy: .public) previousLength=\(previousLength, privacy: .public) suffixFallbackAllowed=\(allowingValueSuffixFallback, privacy: .public)"
            )
            return false
        }

        let flexibleLength = min(
            selectedRange.location,
            previousLength + min(16, previousText.filter(\.isNewline).count + 8)
        )
        var suffixRange = CFRange(
            location: selectedRange.location - flexibleLength,
            length: flexibleLength
        )
        guard let rangeValue = AXValueCreate(.cfRange, &suffixRange) else {
            Self.logger.notice(
                "Verification failed: could not create AX range; role=\(role, privacy: .public)"
            )
            return false
        }

        var suffixValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &suffixValue
        )
        guard result == .success,
              let suffix = suffixValue as? String else {
            Self.logger.notice(
                "Verification failed: AX string-for-range unavailable; role=\(role, privacy: .public) axError=\(result.rawValue, privacy: .public)"
            )
            return false
        }

        let matches = FocusedTextSnapshot.normalizedForAccessibilityComparison(suffix).hasSuffix(
            FocusedTextSnapshot.normalizedForAccessibilityComparison(previousText)
        )
        if matches {
            Self.logger.info(
                "Verification succeeded using AX string-for-range; role=\(role, privacy: .public) cursor=\(selectedRange.location, privacy: .public) returnedLength=\(suffix.utf16.count, privacy: .public) previousLength=\(previousLength, privacy: .public)"
            )
        } else {
            Self.logger.notice(
                "Verification failed: text before cursor does not match; role=\(role, privacy: .public) cursor=\(selectedRange.location, privacy: .public) returnedLength=\(suffix.utf16.count, privacy: .public) previousLength=\(previousLength, privacy: .public) previousNewlines=\(previousText.filter(\.isNewline).count, privacy: .public)"
            )
        }
        return matches
    }

    func focusedTextTarget(applicationProcessIdentifier: pid_t?) -> FocusedTextTarget? {
        guard let element = focusedElement(
            applicationProcessIdentifier: applicationProcessIdentifier
        ) else {
            return nil
        }

        var elementProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &elementProcessIdentifier) == .success,
              applicationProcessIdentifier == nil
                || applicationProcessIdentifier == elementProcessIdentifier else {
            return nil
        }

        return FocusedTextTarget(
            applicationProcessIdentifier: elementProcessIdentifier,
            element: element,
            accessibilityRole: accessibilityStringAttribute(kAXRoleAttribute, in: element)
        )
    }

    func restoreFocus(to target: FocusedTextTarget) -> Bool {
        var currentProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(target.element, &currentProcessIdentifier) == .success,
              currentProcessIdentifier == target.applicationProcessIdentifier else {
            return false
        }

        let applicationElement = AXUIElementCreateApplication(
            target.applicationProcessIdentifier
        )
        let applicationResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            target.element
        )
        let elementResult = AXUIElementSetAttributeValue(
            target.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        if applicationResult != .success, elementResult != .success {
            Self.logger.notice(
                "Focus restoration failed; pid=\(String(target.applicationProcessIdentifier), privacy: .public) appError=\(applicationResult.rawValue, privacy: .public) elementError=\(elementResult.rawValue, privacy: .public)"
            )
        }
        return applicationResult == .success || elementResult == .success
    }

    private func focusedElement(applicationProcessIdentifier: pid_t?) -> AXUIElement? {
        let rootElement = applicationProcessIdentifier.map(AXUIElementCreateApplication)
            ?? AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            rootElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedValue as! AXUIElement)
    }

    private func text(in focusedElement: AXUIElement) -> String? {
        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
        let text = textValue as? String else {
            return nil
        }
        return text
    }

    private func accessibilityStringAttribute(
        _ attribute: String,
        in element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedRange(in focusedElement: AXUIElement) -> NSRange? {
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
        let selectedRangeValue,
        CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
            return nil
        }

        let axRange = selectedRangeValue as! AXValue
        guard AXValueGetType(axRange) == .cfRange else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &range),
              range.location >= 0,
              range.length >= 0 else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }
}

@MainActor
final class PasteboardInjector {
    private static let logger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "SafeReplacement"
    )

    private let pasteboard: NSPasteboard
    private let focusedTextSnapshotProvider: FocusedTextSnapshotProviding
    private let snapshotCaptureCoordinator: PasteboardSnapshotCaptureCoordinator

    init(
        pasteboard: NSPasteboard = .general,
        focusedTextSnapshotProvider: FocusedTextSnapshotProviding = AccessibilityFocusedTextSnapshotProvider(),
        snapshotCaptureCoordinator: PasteboardSnapshotCaptureCoordinator = .shared
    ) {
        self.pasteboard = pasteboard
        self.focusedTextSnapshotProvider = focusedTextSnapshotProvider
        self.snapshotCaptureCoordinator = snapshotCaptureCoordinator
    }

    func copy(_ text: String) {
        _ = write(text)
    }

    @discardableResult
    private func write(_ text: String) -> Int? {
        // A timed-out pasteboard owner can still be resolving on the snapshot
        // queue. Never mutate the shared pasteboard while that read is alive:
        // it avoids racing AppKit/pasteboard-server access and preserves the
        // user's clipboard until the owner finishes responding.
        guard !snapshotCaptureCoordinator.isCaptureInFlight else {
            Self.logger.notice("Pasteboard write deferred because a snapshot is still in flight")
            return nil
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    func paste(_ text: String, restoreClipboard: Bool) async -> PasteboardInjectionResult {
        guard !Task.isCancelled else {
            return .cancelled
        }
        let pasteboardName = pasteboard.name
        let snapshot = restoreClipboard
            ? await PasteboardContentsSnapshot.captureWithoutBlockingMain(
                named: pasteboardName,
                coordinator: snapshotCaptureCoordinator
            )
            : nil
        guard !Task.isCancelled else {
            return .cancelled
        }
        if restoreClipboard, snapshot == nil {
            Self.logger.notice(
                "Paste refused because the existing clipboard could not be captured safely"
            )
            return .clipboardSnapshotUnavailable
        }
        return paste(text, restoring: snapshot)
    }

    private func paste(
        _ text: String,
        restoring snapshot: PasteboardContentsSnapshot?
    ) -> PasteboardInjectionResult {
        guard let injectedChangeCount = write(text) else {
            return .clipboardSnapshotUnavailable
        }
        guard sendCommandKey(0x09) else {
            // Keep the transcript on the clipboard when the paste event cannot be posted.
            return .copiedOnly
        }

        guard let snapshot else {
            return .pasteEventPosted
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else {
                return
            }
            _ = self.restore(snapshot, ifUnchangedSince: injectedChangeCount)
        }
        return .pasteEventPosted
    }

    @discardableResult
    private func restore(
        _ snapshot: PasteboardContentsSnapshot,
        ifUnchangedSince changeCount: Int
    ) -> Bool {
        guard !snapshotCaptureCoordinator.isCaptureInFlight else {
            Self.logger.notice("Clipboard restoration skipped because a snapshot is still in flight")
            return false
        }
        return snapshot.restore(to: pasteboard, ifUnchangedSince: changeCount)
    }

    @discardableResult
    func replacePreviousInsertion(
        previousText: String,
        with text: String,
        restoreClipboard: Bool,
        targetProcessIdentifier: pid_t? = nil,
        focusedTextTarget: FocusedTextTarget? = nil,
        allowsValueSuffixFallback: Bool = false,
        allowsGuardedBackspaceFallback: Bool = false,
        preservesTrailingNewline: Bool = false,
        terminalApplicationBundleIdentifier: String? = nil,
        validateBeforeDestructiveAction: @MainActor () -> Bool = { true }
    ) async -> PreviousInsertionReplacementResult {
        guard hasEventPostAccess else {
            return .eventAccessDenied
        }

        let preservesTrailingNewlineInPlace = preservesTrailingNewline
            && GuardedBackspaceRewritePolicy.preservesConfiguredTrailingNewlineInPlace(
                bundleIdentifier: terminalApplicationBundleIdentifier
            )
        let omitsTrailingNewline = preservesTrailingNewline
            && GuardedBackspaceRewritePolicy.targetOmitsConfiguredTrailingNewline(
                bundleIdentifier: terminalApplicationBundleIdentifier,
                accessibilityRole: focusedTextTarget?.accessibilityRole
            )
        let plan = BackspaceReplacementPlan(
            previousText: previousText,
            replacementText: text,
            preservesTrailingNewline: preservesTrailingNewlineInPlace,
            omitsTrailingNewline: omitsTrailingNewline
        )
        let requiresClipboardSnapshot = restoreClipboard && plan.hasChanges
        let pasteboardName = pasteboard.name
        let snapshot = requiresClipboardSnapshot
            ? await PasteboardContentsSnapshot.captureWithoutBlockingMain(
                named: pasteboardName,
                coordinator: snapshotCaptureCoordinator
            )
            : nil
        if requiresClipboardSnapshot, snapshot == nil {
            Self.logger.notice(
                "Replacement refused because the existing clipboard could not be captured safely"
            )
            return .clipboardSnapshotUnavailable
        }
        guard !Task.isCancelled, validateBeforeDestructiveAction() else {
            return .notVerified
        }

        if allowsGuardedBackspaceFallback {
            Self.logger.notice(
                "Using guarded suffix replacement; pid=\(String(targetProcessIdentifier ?? 0), privacy: .public) originalGraphemes=\(previousText.count, privacy: .public) commonPrefixGraphemes=\(plan.commonPrefixCount, privacy: .public) backspaceCount=\(plan.backspaceCount, privacy: .public) pasteGraphemes=\(plan.pastedText.count, privacy: .public) preservesTrailingNewline=\(plan.preservesTrailingNewline, privacy: .public) omitsTrailingNewline=\(omitsTrailingNewline, privacy: .public)"
            )
            guard await waitForReplacementModifiersToRelease() else {
                if !Task.isCancelled, validateBeforeDestructiveAction(), !text.isEmpty {
                    copy(text)
                }
                Self.logger.notice(
                    "Guarded replacement aborted before deletion: keyboard modifiers remained pressed or the transaction was cancelled"
                )
                return Task.isCancelled || !validateBeforeDestructiveAction()
                    ? .notVerified
                    : (text.isEmpty ? .notVerified : .copiedForSafety)
            }
            guard !Task.isCancelled,
                  validateBeforeDestructiveAction(),
                  let targetProcessIdentifier,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetProcessIdentifier else {
                if !Task.isCancelled, validateBeforeDestructiveAction(), !text.isEmpty {
                    copy(text)
                }
                Self.logger.notice(
                    "Guarded replacement aborted before deletion: target app or transaction changed; pid=\(String(targetProcessIdentifier ?? 0), privacy: .public)"
                )
                return .notVerified
            }
            if let focusedTextTarget,
               focusedTextTarget.applicationProcessIdentifier == targetProcessIdentifier {
                _ = restoreFocus(to: focusedTextTarget)
            }
            guard !Task.isCancelled,
                  validateBeforeDestructiveAction(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetProcessIdentifier else {
                if !Task.isCancelled, validateBeforeDestructiveAction(), !text.isEmpty {
                    copy(text)
                }
                Self.logger.notice(
                    "Guarded replacement aborted after focus restoration: target app or transaction changed; pid=\(String(targetProcessIdentifier), privacy: .public)"
                )
                return .notVerified
            }

            let directTargetProcessIdentifier = GuardedBackspaceRewritePolicy
                .prefersDirectEventDelivery(
                    bundleIdentifier: terminalApplicationBundleIdentifier
                ) ? targetProcessIdentifier : nil
            var didModifyTargetText = false
            let eventsPosted = await ReplacementEventSequence.performTerminalReplacement(
                plan,
                directTargetProcessIdentifier: directTargetProcessIdentifier,
                validate: {
                    !Task.isCancelled
                        && validateBeforeDestructiveAction()
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier
                            == targetProcessIdentifier
                },
                postKey: { [weak self] keyCode, processIdentifier in
                    self?.postKeyPress(
                        keyCode,
                        processIdentifier: processIdentifier
                    ) == true
                },
                wait: { [weak self] interval in
                    await self?.waitForEventInterval(interval)
                },
                paste: { [weak self] plannedText in
                    guard let self else {
                        return false
                    }
                    return self.paste(plannedText, restoring: snapshot) == .pasteEventPosted
                },
                mutationOccurred: {
                    didModifyTargetText = true
                },
                rollback: { [weak self] originalSuffix in
                    guard let self, !originalSuffix.isEmpty else {
                        return false
                    }
                    let restored = self.paste(
                        originalSuffix,
                        restoring: snapshot
                    ) == .pasteEventPosted
                    if restored {
                        didModifyTargetText = false
                    }
                    return restored
                }
            )
            Self.logger.notice(
                "Terminal replacement event sequence completed; backspaceCount=\(plan.backspaceCount, privacy: .public) eventsPosted=\(eventsPosted, privacy: .public) preservesTrailingNewline=\(plan.preservesTrailingNewline, privacy: .public) directToProcess=\(directTargetProcessIdentifier != nil, privacy: .public)"
            )
            if eventsPosted {
                return .replaced
            }
            if didModifyTargetText {
                return .partialModification
            }
            if !text.isEmpty {
                copy(text)
                return .copiedForSafety
            }
            return .notVerified
        }

        let accessibilityVerified = canSafelyReplacePreviousInsertion(
            plan.verificationText,
            targetProcessIdentifier: targetProcessIdentifier,
            focusedTextTarget: focusedTextTarget,
            allowsValueSuffixFallback: allowsValueSuffixFallback
        )
        guard accessibilityVerified else {
            Self.logger.notice(
                "Replacement refused: Accessibility verification was unavailable; pid=\(String(targetProcessIdentifier ?? 0), privacy: .public) originalGraphemes=\(previousText.count, privacy: .public)"
            )
            if !text.isEmpty {
                copy(text)
                return .copiedForSafety
            }
            return .notVerified
        }

        guard !Task.isCancelled, validateBeforeDestructiveAction() else {
            return .notVerified
        }

        Self.logger.notice(
            "Using Accessibility-verified suffix replacement; pid=\(String(targetProcessIdentifier ?? 0), privacy: .public) originalGraphemes=\(previousText.count, privacy: .public) commonPrefixGraphemes=\(plan.commonPrefixCount, privacy: .public) backspaceCount=\(plan.backspaceCount, privacy: .public) pasteGraphemes=\(plan.pastedText.count, privacy: .public) omitsTrailingNewline=\(omitsTrailingNewline, privacy: .public)"
        )
        let deletionBaseline: FocusedTextSnapshot?
        if plan.backspaceCount > 0 {
            deletionBaseline = focusedTextSnapshotProvider.focusedTextSnapshot(
                applicationProcessIdentifier: targetProcessIdentifier
            )
            guard deletionBaseline != nil else {
                Self.logger.notice(
                    "Replacement refused: a post-delete Accessibility snapshot would not be verifiable"
                )
                if !text.isEmpty {
                    copy(text)
                    return .copiedForSafety
                }
                return .notVerified
            }
        } else {
            deletionBaseline = nil
        }
        var didModifyTargetText = false
        let eventsPosted = await ReplacementEventSequence.performAccessibilityReplacement(
            plan,
            validate: {
                !Task.isCancelled
                    && validateBeforeDestructiveAction()
                    && (targetProcessIdentifier == nil
                        || NSWorkspace.shared.frontmostApplication?.processIdentifier
                            == targetProcessIdentifier)
            },
            sendBackspaces: { [weak self] count in
                self?.sendBackspaceKeyPresses(count: count) == true
            },
            wait: { [weak self] interval in
                await self?.waitForEventInterval(interval)
            },
            paste: { [weak self] plannedText in
                guard let self else {
                    return false
                }
                guard targetProcessIdentifier == nil
                    || NSWorkspace.shared.frontmostApplication?.processIdentifier
                        == targetProcessIdentifier else {
                    self.copy(text)
                    return false
                }
                return self.paste(plannedText, restoring: snapshot) == .pasteEventPosted
            },
            validateDeletion: { [weak self] in
                guard let self,
                      let deletionBaseline,
                      let snapshot = self.focusedTextSnapshotProvider.focusedTextSnapshot(
                        applicationProcessIdentifier: targetProcessIdentifier
                      ) else {
                    return plan.backspaceCount == 0
                }
                return snapshot.reflectsDeletion(
                    of: plan.previousSuffixText,
                    from: deletionBaseline
                )
            },
            mutationOccurred: {
                didModifyTargetText = true
            },
            rollback: { [weak self] originalSuffix in
                guard let self, !originalSuffix.isEmpty else {
                    return false
                }
                let restored = self.paste(
                    originalSuffix,
                    restoring: snapshot
                ) == .pasteEventPosted
                if restored {
                    didModifyTargetText = false
                }
                return restored
            }
        )
        if eventsPosted {
            return .replaced
        }
        if didModifyTargetText {
            return .partialModification
        }
        if !text.isEmpty {
            copy(text)
            return .copiedForSafety
        }
        return .notVerified
    }

    func canSafelyReplacePreviousInsertion(
        _ previousText: String,
        targetProcessIdentifier: pid_t? = nil,
        focusedTextTarget: FocusedTextTarget? = nil,
        allowsValueSuffixFallback: Bool = false
    ) -> Bool {
        if let focusedTextTarget,
           targetProcessIdentifier == nil
            || focusedTextTarget.applicationProcessIdentifier == targetProcessIdentifier {
            return focusedTextSnapshotProvider.hasCollapsedCursorImmediatelyAfter(
                previousText,
                in: focusedTextTarget,
                allowingValueSuffixFallback: allowsValueSuffixFallback
            )
        }

        return focusedTextSnapshotProvider.hasCollapsedCursorImmediatelyAfter(
            previousText,
            applicationProcessIdentifier: targetProcessIdentifier
        )
    }

    func focusedTextTarget(applicationProcessIdentifier: pid_t?) -> FocusedTextTarget? {
        focusedTextSnapshotProvider.focusedTextTarget(
            applicationProcessIdentifier: applicationProcessIdentifier
        )
    }

    @discardableResult
    func restoreFocus(to target: FocusedTextTarget) -> Bool {
        focusedTextSnapshotProvider.restoreFocus(to: target)
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

    private var hasEventPostAccess: Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }

    @discardableResult
    private func sendCommandKey(_ keyCode: CGKeyCode) -> Bool {
        guard hasEventPostAccess else {
            return false
        }

        let source = CGEventSource(stateID: .privateState)

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            return false
        }
        keyDown.flags = .maskCommand
        ShuoSyntheticEventMarker.mark(keyDown)
        keyDown.post(tap: .cghidEventTap)

        keyUp.flags = .maskCommand
        ShuoSyntheticEventMarker.mark(keyUp)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func sendBackspaceKeyPresses(count: Int) -> Bool {
        guard count > 0 else {
            return true
        }

        let source = CGEventSource(stateID: .privateState)
        let deleteKeyCode: CGKeyCode = 0x33
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: deleteKeyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: deleteKeyCode,
            keyDown: false
        ) else {
            return false
        }
        keyDown.flags = []
        keyUp.flags = []
        ShuoSyntheticEventMarker.mark(keyDown)
        ShuoSyntheticEventMarker.mark(keyUp)
        keyDown.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        keyUp.setIntegerValueField(.keyboardEventAutorepeat, value: 0)

        for _ in 0 ..< count {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    private func waitForReplacementModifiersToRelease() async -> Bool {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(1.5)
        var modifiersClearSince: Date?

        while Date() < deadline {
            guard !Task.isCancelled else {
                return false
            }
            let flags = CGEventSource.flagsState(.hidSystemState)
            if GuardedBackspaceRewritePolicy.hasBlockingReplacementModifiers(flags) {
                modifiersClearSince = nil
            } else {
                let now = Date()
                if let modifiersClearSince,
                   now.timeIntervalSince(modifiersClearSince) >= 0.04 {
                    Self.logger.notice(
                        "Keyboard modifiers released before replacement; waitMilliseconds=\(Int(now.timeIntervalSince(startedAt) * 1_000), privacy: .public)"
                    )
                    return true
                }
                if modifiersClearSince == nil {
                    modifiersClearSince = now
                }
            }
            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                return false
            }
        }

        return false
    }

    private func waitForEventInterval(_ interval: TimeInterval) async {
        guard interval > 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                continuation.resume()
            }
        }
    }

    @discardableResult
    private func postKeyPress(
        _ keyCode: CGKeyCode,
        source: CGEventSource? = CGEventSource(stateID: .privateState),
        processIdentifier: pid_t? = nil
    ) -> Bool {
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            return false
        }
        keyDown.flags = []
        ShuoSyntheticEventMarker.mark(keyDown)
        keyDown.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        if let processIdentifier {
            keyDown.postToPid(processIdentifier)
        } else {
            keyDown.post(tap: .cghidEventTap)
        }

        keyUp.flags = []
        ShuoSyntheticEventMarker.mark(keyUp)
        keyUp.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        if let processIdentifier {
            keyUp.postToPid(processIdentifier)
        } else {
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }
}

struct PasteboardContentsSnapshot {
    struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardContentsSnapshot? {
        let capturedItems = pasteboard.pasteboardItems ?? []
        var items: [Item] = []
        items.reserveCapacity(capturedItems.count)

        for pasteboardItem in capturedItems {
            var values: [(type: NSPasteboard.PasteboardType, data: Data)] = []
            values.reserveCapacity(pasteboardItem.types.count)
            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else {
                    return nil
                }
                values.append((type: type, data: data))
            }
            items.append(Item(values: values))
        }

        return PasteboardContentsSnapshot(items: items)
    }

    @MainActor
    static func captureWithoutBlockingMain(
        from pasteboard: NSPasteboard,
        timeout: TimeInterval = 0.12,
        coordinator: PasteboardSnapshotCaptureCoordinator = .shared
    ) async -> PasteboardContentsSnapshot? {
        await captureWithoutBlockingMain(
            named: pasteboard.name,
            timeout: timeout,
            coordinator: coordinator
        )
    }

    static func captureWithoutBlockingMain(
        named pasteboardName: NSPasteboard.Name,
        timeout: TimeInterval = 0.12,
        coordinator: PasteboardSnapshotCaptureCoordinator = .shared
    ) async -> PasteboardContentsSnapshot? {
        await coordinator.capture(named: pasteboardName, timeout: timeout)
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard, ifUnchangedSince changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else {
            return false
        }

        let restoredItems = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for value in item.values {
                pasteboardItem.setData(value.data, forType: value.type)
            }
            return pasteboardItem
        }

        pasteboard.clearContents()
        guard !restoredItems.isEmpty else {
            return true
        }
        return pasteboard.writeObjects(restoredItems)
    }
}

final class PasteboardSnapshotCaptureCoordinator: @unchecked Sendable {
    static let shared = PasteboardSnapshotCaptureCoordinator()

    private let queue = DispatchQueue(
        label: "\(AppBuildIdentity.bundleIdentifier).pasteboard-snapshot"
    )
    private let lock = NSLock()
    private var captureIsInFlight = false

    var isCaptureInFlight: Bool {
        lock.lock()
        defer { lock.unlock() }
        return captureIsInFlight
    }

    func capture(
        named pasteboardName: NSPasteboard.Name,
        timeout: TimeInterval
    ) async -> PasteboardContentsSnapshot? {
        guard beginCapture() else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let gate = PasteboardSnapshotContinuationGate(continuation: continuation)
            queue.async { [self] in
                // Use a background-owned pasteboard instance. Passing the
                // main-actor instance across queues was both unsafe under
                // strict concurrency and could race a later write after the
                // capture timeout had returned to the caller.
                let pasteboard = NSPasteboard(name: pasteboardName)
                let snapshot = PasteboardContentsSnapshot.capture(
                    from: pasteboard
                )
                finishCapture()
                gate.resume(returning: snapshot)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + max(0, timeout)
            ) {
                gate.resume(returning: nil)
            }
        }
    }

    private func beginCapture() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !captureIsInFlight else {
            return false
        }
        captureIsInFlight = true
        return true
    }

    private func finishCapture() {
        lock.lock()
        captureIsInFlight = false
        lock.unlock()
    }
}

private final class PasteboardSnapshotContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PasteboardContentsSnapshot?, Never>?

    init(continuation: CheckedContinuation<PasteboardContentsSnapshot?, Never>) {
        self.continuation = continuation
    }

    func resume(returning snapshot: PasteboardContentsSnapshot?) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: snapshot)
    }
}
