@preconcurrency import ApplicationServices
import Foundation

final class RightOptionPushToTalkMonitor {
    private let shortcut: PushToTalkShortcut
    private let customShortcut: CustomPushToTalkShortcut?
    private let onPress: @Sendable () -> Void
    private let onRelease: @Sendable () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isShortcutDown = false
    private var shortcutKeyPressIsSuppressed = false

    init(
        shortcut: PushToTalkShortcut,
        customShortcut: CustomPushToTalkShortcut? = nil,
        onPress: @escaping @Sendable () -> Void,
        onRelease: @escaping @Sendable () -> Void
    ) {
        self.shortcut = shortcut
        self.customShortcut = customShortcut
        self.onPress = onPress
        self.onRelease = onRelease
    }

    var isRunning: Bool {
        eventTap != nil
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        guard !hasAccessibilityPermission else {
            return true
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        guard !AppRuntime.isRunningUnderXCTest else {
            return false
        }

        guard eventTap == nil else {
            return true
        }

        guard resolvedShortcut != nil else {
            return false
        }

        // Permission prompts are deliberately kept out of monitor startup.
        // This event tap listens to and may suppress the selected modifier, so
        // Accessibility is the single permission required for this path.
        guard Self.hasAccessibilityPermission else {
            return false
        }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        )
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<RightOptionPushToTalkMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    monitor.releaseShortcutIfNeededAfterTapInterruption()
                    monitor.enableEventTap()
                    return Unmanaged.passUnretained(event)
                }

                if monitor.handle(type: type, event: event) {
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        eventTap = tap
        runLoopSource = source
        enableEventTap()
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isShortcutDown = false
        shortcutKeyPressIsSuppressed = false
    }

    deinit {
        stop()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard let shortcut = resolvedShortcut else {
            return false
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event, shortcut: shortcut)
        case .keyDown:
            return handleKeyDown(event, shortcut: shortcut)
        case .keyUp:
            return handleKeyUp(event, shortcut: shortcut)
        default:
            return false
        }
    }

    private var resolvedShortcut: ResolvedPushToTalkShortcut? {
        switch shortcut {
        case .rightOption:
            return ResolvedPushToTalkShortcut(keyCode: 0x3D)
        case .rightCommand:
            return ResolvedPushToTalkShortcut(keyCode: 0x36)
        case .custom:
            guard let customShortcut,
                  customShortcut.isValidHoldShortcut else {
                return nil
            }
            return ResolvedPushToTalkShortcut(
                keyCode: customShortcut.keyCode,
                modifiers: customShortcut.modifiers
            )
        }
    }

    private func handleFlagsChanged(
        _ event: CGEvent,
        shortcut: ResolvedPushToTalkShortcut
    ) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if shortcut.usesModifierKey, keyCode == shortcut.keyCode {
            transitionShortcut(
                down: shortcut.downState(
                    keyStateDown: CGEventSource.keyState(
                        .combinedSessionState,
                        key: CGKeyCode(shortcut.keyCode)
                    ),
                    eventFlags: event.flags,
                    previousDown: isShortcutDown
                )
            )
            return true
        }

        if isShortcutDown, !shortcut.isCurrentlyDown(eventFlags: event.flags) {
            transitionShortcut(down: false)
        }

        return false
    }

    private func handleKeyDown(
        _ event: CGEvent,
        shortcut: ResolvedPushToTalkShortcut
    ) -> Bool {
        guard !shortcut.usesModifierKey else {
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == shortcut.keyCode else {
            return false
        }

        guard shortcut.modifiersAreDown(in: event.flags) else {
            return false
        }

        shortcutKeyPressIsSuppressed = true
        transitionShortcut(down: true)
        return true
    }

    private func handleKeyUp(
        _ event: CGEvent,
        shortcut: ResolvedPushToTalkShortcut
    ) -> Bool {
        guard !shortcut.usesModifierKey else {
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == shortcut.keyCode else {
            return false
        }

        let shouldSuppress = shortcutKeyPressIsSuppressed || isShortcutDown
        shortcutKeyPressIsSuppressed = false
        transitionShortcut(down: false)
        return shouldSuppress
    }

    private func transitionShortcut(down shortcutIsDown: Bool) {
        guard shortcutIsDown != isShortcutDown else {
            return
        }

        isShortcutDown = shortcutIsDown
        if shortcutIsDown {
            DispatchQueue.main.async { [onPress] in
                onPress()
            }
        } else {
            DispatchQueue.main.async { [onRelease] in
                onRelease()
            }
        }
    }

    private func releaseShortcutIfNeededAfterTapInterruption() {
        guard let shortcut = resolvedShortcut,
              isShortcutDown,
              !shortcut.isCurrentlyDown(eventFlags: CGEventSource.flagsState(.combinedSessionState)) else {
            return
        }

        shortcutKeyPressIsSuppressed = false
        transitionShortcut(down: false)
    }

    private func enableEventTap() {
        guard let eventTap else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

}

struct ResolvedPushToTalkShortcut {
    var keyCode: UInt16
    var modifiers: Set<PushToTalkShortcutModifier> = []

    var usesModifierKey: Bool {
        CustomPushToTalkShortcut.modifierKeyCodes.contains(keyCode)
    }

    func modifiersAreDown(in flags: CGEventFlags) -> Bool {
        modifiers.allSatisfy { flags.contains($0.cgEventFlag) }
    }

    func downState(
        keyStateDown: Bool,
        eventFlags: CGEventFlags,
        previousDown: Bool
    ) -> Bool {
        let keyStateWithRequiredModifiers = keyStateDown && modifiersAreDown(in: eventFlags)
        if keyStateWithRequiredModifiers != previousDown {
            return keyStateWithRequiredModifiers
        }

        let eventFlagsDown = eventFlagsIndicateShortcutKeyDown(eventFlags)
            && modifiersAreDown(in: eventFlags)
        if eventFlagsDown != previousDown {
            return eventFlagsDown
        }

        return keyStateWithRequiredModifiers
    }

    func isCurrentlyDown(eventFlags: CGEventFlags) -> Bool {
        downState(
            keyStateDown: CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode)),
            eventFlags: eventFlags,
            previousDown: false
        )
    }

    private func eventFlagsIndicateShortcutKeyDown(_ flags: CGEventFlags) -> Bool {
        guard let keyModifier = PushToTalkShortcutModifier.modifier(forKeyCode: keyCode) else {
            return false
        }
        return flags.contains(keyModifier.cgEventFlag)
    }
}

private extension PushToTalkShortcutModifier {
    var cgEventFlag: CGEventFlags {
        switch self {
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .shift:
            return .maskShift
        case .command:
            return .maskCommand
        case .function:
            return .maskSecondaryFn
        }
    }
}
