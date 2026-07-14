@preconcurrency import ApplicationServices
import Foundation

final class RightOptionPushToTalkMonitor {
    private let shortcut: PushToTalkShortcut
    private let onPress: @Sendable () -> Void
    private let onRelease: @Sendable () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isShortcutDown = false

    init(
        shortcut: PushToTalkShortcut,
        onPress: @escaping @Sendable () -> Void,
        onRelease: @escaping @Sendable () -> Void
    ) {
        self.shortcut = shortcut
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

        // Permission prompts are deliberately kept out of monitor startup.
        // This event tap listens to and may suppress the selected modifier, so
        // Accessibility is the single permission required for this path.
        guard Self.hasAccessibilityPermission else {
            return false
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
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
    }

    deinit {
        stop()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .flagsChanged else {
            return false
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == shortcut.keyCode else {
            return false
        }

        let shortcutIsDown = shortcutDownState(from: event)
        guard shortcutIsDown != isShortcutDown else {
            return true
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

        return true
    }

    private func shortcutDownState(from event: CGEvent) -> Bool {
        let keyStateDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode))
        if keyStateDown != isShortcutDown {
            return keyStateDown
        }

        let eventFlagsDown = eventIndicatesShortcutDown(event)
        if eventFlagsDown != isShortcutDown {
            return eventFlagsDown
        }

        return keyStateDown
    }

    private func eventIndicatesShortcutDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        switch shortcut {
        case .rightOption:
            return flags.contains(.maskAlternate)
        case .rightCommand:
            return flags.contains(.maskCommand)
        }
    }

    private func releaseShortcutIfNeededAfterTapInterruption() {
        guard isShortcutDown,
              !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode)) else {
            return
        }

        isShortcutDown = false
        DispatchQueue.main.async { [onRelease] in
            onRelease()
        }
    }

    private func enableEventTap() {
        guard let eventTap else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

}
