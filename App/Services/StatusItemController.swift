import AppKit
import Combine
import OSLog
import QuartzCore
import SwiftUI

enum StatusIconArtworkStyle: Equatable {
    case ready
    case disabled
    case recording
    case transcribing

    var showsRecordingIndicator: Bool {
        self == .recording
    }
}

enum StatusRecordingIndicatorGeometry {
    static let diameter: CGFloat = 4

    private static let horizontalCenterOffset: CGFloat = 6
    private static let verticalCenterOffset: CGFloat = -6

    static func frame(in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.midX + horizontalCenterOffset - diameter / 2,
            y: bounds.midY + verticalCenterOffset - diameter / 2,
            width: diameter,
            height: diameter
        )
    }
}

final class StatusRecordingIndicatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.setFill()
        NSBezierPath(
            ovalIn: StatusRecordingIndicatorGeometry.frame(in: bounds)
        ).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

struct StatusIconBar: Equatable {
    let frame: NSRect
    let opacity: CGFloat
}

struct FloatingGlyphBarPresentation: Equatable {
    let opacity: CGFloat
    let widthScale: CGFloat
    let heightScale: CGFloat
    let verticalOffset: CGFloat
}

enum FloatingWindowGlyphMotion {
    static func presentation(artworkOpacity: CGFloat) -> FloatingGlyphBarPresentation {
        // Transcription is expressed only through the shared per-bar opacity.
        // Keeping geometry fixed avoids reading the sequence as a traveling wave.
        return FloatingGlyphBarPresentation(
            opacity: artworkOpacity,
            widthScale: 1,
            heightScale: 1,
            verticalOffset: 0
        )
    }
}

struct TranscriptionFlickerSequence: Equatable {
    static let barCount = 7
    static let opacityRange: ClosedRange<CGFloat> = 0.22 ... 1

    private(set) var opacities: [CGFloat]
    private(set) var lastChangedIndices = Set<Int>()
    private var randomState: UInt64

    init(seed: UInt64) {
        randomState = seed
        opacities = Array(repeating: 1, count: Self.barCount)
        for index in opacities.indices {
            opacities[index] = Self.opacityRange.lowerBound
                + nextUnitValue() * (Self.opacityRange.upperBound - Self.opacityRange.lowerBound)
        }
    }

    @discardableResult
    mutating func advance() -> [CGFloat] {
        let changeCount = 2 + Int(nextRandom() & 1)
        var candidates = Array(0..<Self.barCount)
        for index in candidates.indices.dropLast() {
            let remainingCount = candidates.count - index
            let offset = Int(nextRandom() % UInt64(remainingCount))
            candidates.swapAt(index, index + offset)
        }

        var changedIndices = Set(candidates.prefix(changeCount))
        if changedIndices == lastChangedIndices,
           let replacement = candidates.dropFirst(changeCount).first,
           let removed = changedIndices.min() {
            changedIndices.remove(removed)
            changedIndices.insert(replacement)
        }

        // Set iteration is intentionally randomized by Swift. Sorting keeps a
        // seeded sequence replayable while the selected positions stay random.
        for index in changedIndices.sorted() {
            let magnitude = 0.14 + nextUnitValue() * 0.20
            let preferredDirection: CGFloat = (nextRandom() & 1) == 0 ? -1 : 1
            var candidate = opacities[index] + preferredDirection * magnitude
            if !Self.opacityRange.contains(candidate) {
                candidate = opacities[index] - preferredDirection * magnitude
            }
            opacities[index] = min(
                Self.opacityRange.upperBound,
                max(Self.opacityRange.lowerBound, candidate)
            )
        }

        lastChangedIndices = changedIndices
        return opacities
    }

    private mutating func nextUnitValue() -> CGFloat {
        CGFloat(nextRandom() & 0xFFFF) / CGFloat(0xFFFF)
    }

    private mutating func nextRandom() -> UInt64 {
        randomState &+= 0x9E37_79B9_7F4A_7C15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

enum TranscriptionBarFlicker {
    static func opacities(frame: Int, seed: UInt64 = 0x5348_554F) -> [CGFloat] {
        var sequence = TranscriptionFlickerSequence(seed: seed)
        for _ in 0..<max(0, frame) {
            sequence.advance()
        }
        return sequence.opacities
    }

    static func opacity(frame: Int, barIndex: Int) -> CGFloat {
        let values = opacities(frame: frame)
        return values[max(0, barIndex) % values.count]
    }
}

enum FloatingTranscriptionBarFlicker {
    static func opacity(frame: Int, barIndex: Int) -> CGFloat {
        let values = TranscriptionBarFlicker.opacities(
            frame: frame,
            seed: 0x464C_4F41_5449_4E47
        )
        return values[max(0, barIndex) % values.count]
    }
}

enum StatusIconArtwork {
    static let canvasSize = NSSize(width: 18, height: 18)
    static let heightRatios: [CGFloat] = [0.50, 0.72, 0.58, 1.00, 0.58, 0.72, 0.50]

    private static let maximumBarHeight: CGFloat = 15
    private static let horizontalInset: CGFloat = 1
    private static let regularBarWidth: CGFloat = 1.55
    private static let recordingBarWidth: CGFloat = 2.03

    static func bars(
        style: StatusIconArtworkStyle,
        frame: Int = 0,
        transcribingOpacities: [CGFloat]? = nil
    ) -> [StatusIconBar] {
        let barWidth = style == .recording ? recordingBarWidth : regularBarWidth
        let usableWidth = canvasSize.width - horizontalInset * 2
        let regularGap = (
            usableWidth - regularBarWidth * CGFloat(heightRatios.count)
        ) / CGFloat(heightRatios.count - 1)
        let firstCenterX = horizontalInset + regularBarWidth / 2
        let opacities = barOpacities(
            style: style,
            frame: frame,
            transcribingOpacities: transcribingOpacities
        )

        return heightRatios.enumerated().map { index, ratio in
            let height = maximumBarHeight * ratio
            let centerX = firstCenterX + CGFloat(index) * (regularBarWidth + regularGap)
            return StatusIconBar(
                frame: NSRect(
                    x: centerX - barWidth / 2,
                    y: (canvasSize.height - height) / 2,
                    width: barWidth,
                    height: height
                ),
                opacity: opacities[index]
            )
        }
    }

    static func image(
        style: StatusIconArtworkStyle,
        frame: Int = 0,
        transcribingOpacities: [CGFloat]? = nil
    ) -> NSImage {
        let image = NSImage(size: canvasSize, flipped: false) { _ in
            for bar in bars(
                style: style,
                frame: frame,
                transcribingOpacities: transcribingOpacities
            ) {
                NSColor.black.withAlphaComponent(bar.opacity).setFill()
                NSBezierPath(
                    roundedRect: bar.frame,
                    xRadius: bar.frame.width / 2,
                    yRadius: bar.frame.width / 2
                )
                .fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppBuildIdentity.displayName
        return image
    }

    private static func barOpacities(
        style: StatusIconArtworkStyle,
        frame: Int,
        transcribingOpacities: [CGFloat]?
    ) -> [CGFloat] {
        switch style {
        case .ready, .recording:
            return Array(repeating: 1, count: heightRatios.count)
        case .disabled:
            return Array(repeating: 0.38, count: heightRatios.count)
        case .transcribing:
            if let transcribingOpacities,
               transcribingOpacities.count == heightRatios.count {
                return transcribingOpacities
            }
            return defaultTranscribingOpacities(frame: frame)
        }
    }

    private static func defaultTranscribingOpacities(frame: Int) -> [CGFloat] {
        TranscriptionBarFlicker.opacities(frame: frame)
    }
}

enum FloatingWindowBehavior {
    private static var font: NSFont {
        NSFont.systemFont(ofSize: 13.5, weight: .regular)
    }
    private static let minimumTextWidth: CGFloat = 96
    private static let minimumEditingTextWidth: CGFloat = 196
    private static let maximumTextWidth: CGFloat = 480
    private static let horizontalChrome: CGFloat = 52
    private static let minimumWindowHeight: CGFloat = 60
    private static let verticalPadding: CGFloat = 14
    private static let widthMeasurementSlack: CGFloat = 3
    static let maximumVisibleLineCount = 14

    private static var maximumWindowHeight: CGFloat {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return ceil(lineHeight * CGFloat(maximumVisibleLineCount) + verticalPadding)
    }

    static func displayDuration(for text: String) -> TimeInterval {
        let characterReadingTime = Double(text.count) * 0.055
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        let wordReadingTime = Double(wordCount) * 0.28
        let estimatedReadingTime = max(characterReadingTime, wordReadingTime)
        return min(16, max(5, 4 + estimatedReadingTime))
    }

    static func windowSize(for text: String) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let lines = text.components(separatedBy: .newlines)
        let naturalWidth = lines
            .map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
            .max() ?? 0
        let textWidth = min(
            max(naturalWidth + widthMeasurementSlack, minimumTextWidth),
            maximumTextWidth
        )
        return measuredWindowSize(for: text, textWidth: textWidth)
    }

    static func editingWindowSize(
        for text: String,
        fixedWindowWidth: CGFloat? = nil
    ) -> NSSize {
        let adaptiveWidth = windowSize(for: text).width
        let initialWidth = max(
            adaptiveWidth,
            minimumEditingTextWidth + horizontalChrome
        )
        let windowWidth = min(
            max(fixedWindowWidth ?? initialWidth, minimumEditingTextWidth + horizontalChrome),
            maximumTextWidth + horizontalChrome
        )
        return measuredWindowSize(
            for: text,
            textWidth: windowWidth - horizontalChrome
        )
    }

    private static func measuredWindowSize(
        for text: String,
        textWidth: CGFloat
    ) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textBounds = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let contentHeight = max(ceil(textBounds.height), font.ascender - font.descender)

        return NSSize(
            width: ceil(textWidth + horizontalChrome),
            height: ceil(
                min(
                    maximumWindowHeight,
                    max(minimumWindowHeight, contentHeight + verticalPadding)
                )
            )
        )
    }
}

/// A synthetic paste is posted before the transcript session is published, but
/// AppKit can deliver that event to a newly installed monitor afterwards. An
/// event that occurred before the transcript was presented must not immediately
/// collapse the just-created floating window.
enum FloatingWindowAutomaticDismissalPolicy {
    static func shouldIgnore(
        eventTimestamp: TimeInterval,
        presentationTimestamp: TimeInterval,
        isSynthetic: Bool
    ) -> Bool {
        guard !isSynthetic,
              eventTimestamp.isFinite,
              eventTimestamp > 0,
              presentationTimestamp.isFinite,
              presentationTimestamp > 0 else {
            return isSynthetic
        }

        return eventTimestamp <= presentationTimestamp
    }
}

struct FloatingWindowStoredPosition: Codable, Equatable {
    let centerX: Double
    let centerY: Double

    var center: NSPoint {
        NSPoint(x: centerX, y: centerY)
    }

    init(center: NSPoint) {
        centerX = Double(center.x)
        centerY = Double(center.y)
    }
}

enum FloatingWindowPositionStore {
    static let userDefaultsKey = "floatingWindowPosition.v1"

    static func load(from defaults: UserDefaults = .standard) -> NSPoint? {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let storedPosition = try? JSONDecoder().decode(
                  FloatingWindowStoredPosition.self,
                  from: data
              ),
              storedPosition.centerX.isFinite,
              storedPosition.centerY.isFinite else {
            return nil
        }
        return storedPosition.center
    }

    static func save(_ center: NSPoint, to defaults: UserDefaults = .standard) {
        guard center.x.isFinite,
              center.y.isFinite,
              let data = try? JSONEncoder().encode(
                  FloatingWindowStoredPosition(center: center)
              ) else {
            return
        }
        defaults.set(data, forKey: userDefaultsKey)
    }
}

enum FloatingWindowPlacement {
    static let screenInset: CGFloat = 8

    static func defaultFrame(size: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + min(96, visibleFrame.height * 0.12),
            width: size.width,
            height: size.height
        )
    }

    static func frame(
        size: NSSize,
        centeredAt center: NSPoint,
        visibleFrames: [NSRect]
    ) -> NSRect? {
        guard let visibleFrame = preferredVisibleFrame(
            for: center,
            proposedFrame: NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            visibleFrames: visibleFrames
        ) else {
            return nil
        }
        return clamped(
            NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            to: visibleFrame
        )
    }

    static func frame(
        byDragging proposedFrame: NSRect,
        cursor: NSPoint,
        visibleFrames: [NSRect]
    ) -> NSRect {
        guard let visibleFrame = preferredVisibleFrame(
            for: cursor,
            proposedFrame: proposedFrame,
            visibleFrames: visibleFrames
        ) else {
            return proposedFrame
        }
        return clamped(proposedFrame, to: visibleFrame)
    }

    private static func preferredVisibleFrame(
        for point: NSPoint,
        proposedFrame: NSRect,
        visibleFrames: [NSRect]
    ) -> NSRect? {
        if let containingFrame = visibleFrames.first(where: { $0.contains(point) }) {
            return containingFrame
        }

        let intersectingFrame = visibleFrames.max { lhs, rhs in
            intersectionArea(lhs.intersection(proposedFrame))
                < intersectionArea(rhs.intersection(proposedFrame))
        }
        if let intersectingFrame,
           intersectionArea(intersectingFrame.intersection(proposedFrame)) > 0 {
            return intersectingFrame
        }

        return visibleFrames.min { lhs, rhs in
            squaredDistance(from: point, to: lhs)
                < squaredDistance(from: point, to: rhs)
        }
    }

    private static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        let availableFrame = visibleFrame.insetBy(dx: screenInset, dy: screenInset)
        let x: CGFloat
        if frame.width >= availableFrame.width {
            x = availableFrame.minX
        } else {
            x = min(max(frame.minX, availableFrame.minX), availableFrame.maxX - frame.width)
        }
        let y: CGFloat
        if frame.height >= availableFrame.height {
            y = availableFrame.minY
        } else {
            y = min(max(frame.minY, availableFrame.minY), availableFrame.maxY - frame.height)
        }
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private static func intersectionArea(_ frame: NSRect) -> CGFloat {
        guard !frame.isNull, !frame.isEmpty else {
            return 0
        }
        return frame.width * frame.height
    }

    private static func squaredDistance(from point: NSPoint, to frame: NSRect) -> CGFloat {
        let nearestX = min(max(point.x, frame.minX), frame.maxX)
        let nearestY = min(max(point.y, frame.minY), frame.maxY)
        let dx = point.x - nearestX
        let dy = point.y - nearestY
        return dx * dx + dy * dy
    }
}

enum FloatingWindowContextMenuCopy {
    static func titles(localizer: AppLocalizer) -> [String] {
        [
            localizer.hideFloatingWindowLabel(),
            localizer.openShuoLabel(),
            localizer.quitShuoLabel()
        ]
    }
}

private struct StatusIconState {
    let artworkStyle: StatusIconArtworkStyle
    let toolTip: String
    let isAnimated: Bool
}

enum StatusMenuPanelLayout {
    static let contentWidth: CGFloat = 280
    private static let screenInset: CGFloat = 8

    static func menuBarBottomY(
        statusItemWindowFrame: NSRect,
        visibleFrame: NSRect,
        screenFrame: NSRect
    ) -> CGFloat {
        let usableFrame = usableFrame(
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let statusItemBottom = min(
            max(statusItemWindowFrame.minY, screenFrame.minY),
            screenFrame.maxY
        )

        // The status item's window occupies the display's real menu-bar band.
        // Its lower edge therefore follows a tall camera-housing menu bar and
        // each external display, unlike NSStatusBar.system.thickness. Keep the
        // visible-frame boundary as the conservative limit when macOS reports
        // a still larger reserved area.
        return min(statusItemBottom, usableFrame.maxY)
    }

    static func maximumContentHeight(
        statusItemWindowFrame: NSRect,
        visibleFrame: NSRect,
        screenFrame: NSRect
    ) -> CGFloat {
        let usableFrame = usableFrame(
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let topBoundary = panelTopBoundary(
            statusItemWindowFrame: statusItemWindowFrame,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let bottomBoundary = usableFrame.minY + screenInset
        return max(1, topBoundary - bottomBoundary)
    }

    static func frame(
        anchorRect: NSRect,
        statusItemWindowFrame: NSRect,
        contentSize: NSSize,
        visibleFrame: NSRect,
        screenFrame: NSRect
    ) -> NSRect {
        let usableFrame = usableFrame(
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let maximumWidth = max(1, usableFrame.width - screenInset * 2)
        let maximumHeight = maximumContentHeight(
            statusItemWindowFrame: statusItemWindowFrame,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let width = min(max(1, contentSize.width), maximumWidth)
        let height = min(max(1, contentSize.height), maximumHeight)
        let desiredX = anchorRect.midX - width / 2
        let x = min(
            max(desiredX, usableFrame.minX + screenInset),
            usableFrame.maxX - screenInset - width
        )
        let topBoundary = panelTopBoundary(
            statusItemWindowFrame: statusItemWindowFrame,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let desiredY = topBoundary - height
        let y = max(usableFrame.minY + screenInset, desiredY)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func panelTopBoundary(
        statusItemWindowFrame: NSRect,
        visibleFrame: NSRect,
        screenFrame: NSRect
    ) -> CGFloat {
        menuBarBottomY(
            statusItemWindowFrame: statusItemWindowFrame,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
    }

    private static func usableFrame(
        visibleFrame: NSRect,
        screenFrame: NSRect
    ) -> NSRect {
        let intersection = visibleFrame.intersection(screenFrame)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else {
            return screenFrame
        }
        return intersection
    }
}

@MainActor
private final class FloatingWindowActivityModel: ObservableObject {
    @Published var style = StatusIconArtworkStyle.ready
    @Published var frame = 0
    @Published var barOpacities = Array(repeating: CGFloat(1), count: TranscriptionFlickerSequence.barCount)
}

@MainActor
final class StatusItemController: NSObject {
    private static let floatingWindowLogger = Logger(
        subsystem: AppBuildIdentity.bundleIdentifier,
        category: "FloatingWindow"
    )
    private static let statusItemLength: CGFloat = 24
    private static let activityInterval: TimeInterval = 0.16
    private static let floatingTransitionDuration: TimeInterval = 0.28
    private static let floatingResizeDuration: TimeInterval = 0.16
    private static let floatingFadeInDuration: TimeInterval = 0.18
    private static let floatingFadeOutDuration: TimeInterval = 0.16

    private let appState: AppState
    private let statusItem: NSStatusItem
    private let recordingIndicatorView = StatusRecordingIndicatorView(frame: .zero)
    private let floatingWindowActivity = FloatingWindowActivityModel()
    private var appStateCancellable: AnyCancellable?
    private var floatingWindowCancellable: AnyCancellable?
    private var replacementSafetyCancellable: AnyCancellable?
    private var statusMenuPanel: StatusMenuPanel?
    private var statusMenuHostingController: NSHostingController<AnyView>?
    private var statusMenuGlobalEventMonitor: Any?
    private var statusMenuLocalEventMonitor: Any?
    private var statusMenuAppResignObserver: NSObjectProtocol?
    private var activityTimer: Timer?
    private var activityFrame = 0
    private var transcriptionFlickerSeed = DispatchTime.now().uptimeNanoseconds
    private var transcriptionFlickerSequence = TranscriptionFlickerSequence(seed: 0x5348_554F)
    private var transcriptionBarOpacities = Array(
        repeating: CGFloat(1),
        count: TranscriptionFlickerSequence.barCount
    )
    private var mainWindow: NSWindow?
    private var errorDetailsWindow: NSWindow?
    private var floatingWindowPanel: FloatingWindowPanel?
    private var floatingWindowMode = FloatingWindowMode.hidden
    private var floatingWindowVisibilityRevision: UInt = 0
    private var isFloatingWindowFadingOut = false
    private var floatingWindowAutoCollapseTask: Task<Void, Never>?
    private var floatingWindowGlobalEventMonitor: Any?
    private var floatingWindowLocalEventMonitor: Any?
    private var replacementSafetyEventMonitor: Any?
    private var replacementSafetySessionID: UUID?
    private var floatingWindowCenter = FloatingWindowPositionStore.load()
    private var shouldSuppressNextActivationPanel = false

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: Self.statusItemLength)

        super.init()

        configureStatusItem()
        configureStatusMenuPanel()
        updateStatusItem()

        appStateCancellable = appState.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
                self?.scheduleStatusMenuPanelResize()
            }
        }

        floatingWindowCancellable = Publishers.CombineLatest3(
            appState.$floatingCorrectionSession.removeDuplicates(),
            appState.$pluginConfiguration
                .map { $0.isEnabled(.smartCorrectionWindow) }
                .removeDuplicates(),
            appState.$settings
                .map(\.appLanguage)
                .removeDuplicates()
        )
            .sink { [weak self] session, isEnabled, language in
                Task { @MainActor in
                    self?.updateFloatingWindow(
                        session: session,
                        isEnabled: isEnabled,
                        language: language
                    )
                }
            }

        replacementSafetyCancellable = appState.$replacementSafetySessionID
            .removeDuplicates()
            .sink { [weak self] sessionID in
                Task { @MainActor in
                    self?.configureReplacementTargetSafetyMonitoring(sessionID: sessionID)
                }
            }
    }

    deinit {
        activityTimer?.invalidate()
        floatingWindowAutoCollapseTask?.cancel()
        if let floatingWindowGlobalEventMonitor {
            NSEvent.removeMonitor(floatingWindowGlobalEventMonitor)
        }
        if let floatingWindowLocalEventMonitor {
            NSEvent.removeMonitor(floatingWindowLocalEventMonitor)
        }
        if let replacementSafetyEventMonitor {
            NSEvent.removeMonitor(replacementSafetyEventMonitor)
        }
        if let statusMenuGlobalEventMonitor {
            NSEvent.removeMonitor(statusMenuGlobalEventMonitor)
        }
        if let statusMenuLocalEventMonitor {
            NSEvent.removeMonitor(statusMenuLocalEventMonitor)
        }
        if let statusMenuAppResignObserver {
            NotificationCenter.default.removeObserver(statusMenuAppResignObserver)
        }
    }

    func showMainPanelFromExternalActivation(selectedSection: AppPanelSection? = nil) {
        if let selectedSection {
            appState.selectedPanelSection = selectedSection
        }

        showMainPanel()
    }

    func handleApplicationDidBecomeActive() {
        if shouldSuppressNextActivationPanel {
            shouldSuppressNextActivationPanel = false
            return
        }

        guard mainWindow?.isVisible != true,
              statusMenuPanel?.isVisible != true else {
            return
        }

        showMainPanel()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown

        recordingIndicatorView.frame = button.bounds
        recordingIndicatorView.autoresizingMask = [.width, .height]
        recordingIndicatorView.isHidden = true
        button.addSubview(recordingIndicatorView)
    }

    private func configureStatusMenuPanel() {
        let rootView = AnyView(
            MenuBarView(
                openSection: { [weak self] section in
                    self?.showMainWindow(selectedSection: section)
                },
                showErrorDetails: { [weak self] message in
                    self?.showErrorDetails(message)
                }
            )
            .environmentObject(appState)
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]

        let panel = StatusMenuPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: StatusMenuPanelLayout.contentWidth, height: 300)
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = hostingController

        statusMenuHostingController = hostingController
        statusMenuPanel = panel
        statusMenuAppResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeStatusMenuPanel()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        suppressNextActivationPanel()
        toggleStatusMenuPanel(relativeTo: sender)
    }

    private func suppressNextActivationPanel() {
        shouldSuppressNextActivationPanel = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.shouldSuppressNextActivationPanel = false
        }
    }

    private func toggleStatusMenuPanel(relativeTo button: NSStatusBarButton) {
        guard let panel = statusMenuPanel else {
            return
        }

        if panel.isVisible {
            closeStatusMenuPanel()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        updateStatusMenuPanelFrame(relativeTo: button, animated: false)
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        startStatusMenuDismissalMonitoring()

        guard panel.alphaValue < 1 else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func closeStatusMenuPanel() {
        stopStatusMenuDismissalMonitoring()
        statusMenuPanel?.alphaValue = 1
        statusMenuPanel?.orderOut(nil)
    }

    private func scheduleStatusMenuPanelResize() {
        guard statusMenuPanel?.isVisible == true else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.statusMenuPanel?.isVisible == true,
                  let button = self.statusItem.button else {
                return
            }
            self.updateStatusMenuPanelFrame(
                relativeTo: button,
                animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        }
    }

    private func updateStatusMenuPanelFrame(
        relativeTo button: NSStatusBarButton,
        animated: Bool
    ) {
        guard let panel = statusMenuPanel,
              let hostingController = statusMenuHostingController,
              let buttonWindow = button.window else {
            return
        }

        let anchorRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let screen = buttonWindow.screen ?? NSScreen.main
        guard let screen else {
            return
        }
        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame
        let maximumContentHeight = StatusMenuPanelLayout.maximumContentHeight(
            statusItemWindowFrame: buttonWindow.frame,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(
                width: StatusMenuPanelLayout.contentWidth,
                height: maximumContentHeight
            )
        )
        let contentSize = NSSize(
            width: StatusMenuPanelLayout.contentWidth,
            height: min(maximumContentHeight, max(1, ceil(fittingSize.height)))
        )
        let targetFrame = StatusMenuPanelLayout.frame(
            anchorRect: anchorRect,
            statusItemWindowFrame: buttonWindow.frame,
            contentSize: contentSize,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame
        )

        guard animated, panel.isVisible else {
            panel.setFrame(targetFrame, display: true)
            return
        }
        guard abs(panel.frame.width - targetFrame.width) > 0.5
                || abs(panel.frame.height - targetFrame.height) > 0.5
                || abs(panel.frame.origin.x - targetFrame.origin.x) > 0.5
                || abs(panel.frame.origin.y - targetFrame.origin.y) > 0.5 else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func startStatusMenuDismissalMonitoring() {
        stopStatusMenuDismissalMonitoring()

        let mouseEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        statusMenuGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mouseEvents
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeStatusMenuPanel()
            }
        }
        statusMenuLocalEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mouseEvents.union(.keyDown)
        ) { [weak self] event in
            guard let self, let panel = self.statusMenuPanel else {
                return event
            }

            if event.type == .keyDown, event.keyCode == 53 {
                self.closeStatusMenuPanel()
                return nil
            }

            guard event.type == .leftMouseDown
                    || event.type == .rightMouseDown
                    || event.type == .otherMouseDown else {
                return event
            }
            let allowedWindowNumbers = [
                panel.windowNumber,
                panel.attachedSheet?.windowNumber,
                self.statusItem.button?.window?.windowNumber
            ].compactMap { $0 }
            if !allowedWindowNumbers.contains(event.windowNumber) {
                self.closeStatusMenuPanel()
            }
            return event
        }
    }

    private func stopStatusMenuDismissalMonitoring() {
        if let statusMenuGlobalEventMonitor {
            NSEvent.removeMonitor(statusMenuGlobalEventMonitor)
            self.statusMenuGlobalEventMonitor = nil
        }
        if let statusMenuLocalEventMonitor {
            NSEvent.removeMonitor(statusMenuLocalEventMonitor)
            self.statusMenuLocalEventMonitor = nil
        }
    }

    private func showErrorDetails(_ message: String) {
        closeStatusMenuPanel()
        NSApp.activate(ignoringOtherApps: true)

        let localizer = AppLocalizer(language: appState.settings.appLanguage)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 390),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = localizer.text(.errorDetails)
        window.isReleasedWhenClosed = false
        window.center()

        window.contentViewController = NSHostingController(
            rootView: ErrorDetailsView(
                message: message,
                localizer: localizer,
                copy: { [weak self] text in
                    self?.appState.copy(text)
                },
                close: { [weak window] in
                    window?.close()
                }
            )
        )

        errorDetailsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func updateFloatingWindow(
        session: FloatingCorrectionSession?,
        isEnabled: Bool,
        language: AppLanguage
    ) {
        guard isEnabled else {
            if case .editing(let editingSession) = floatingWindowMode {
                appState.restoreFloatingCorrectionTarget(sessionID: editingSession.id)
            }
            floatingWindowMode = .hidden
            stopFloatingWindowAutomaticDismissal()
            hideFloatingWindowPanel()
            return
        }

        if let session {
            if floatingWindowMode.sessionID != session.id {
                floatingWindowMode = .transcript(session)
                Self.floatingWindowLogger.notice(
                    "Showing floating transcript; graphemes=\(session.correctionText.count, privacy: .public)"
                )
            } else {
                floatingWindowMode = floatingWindowMode.updatingSession(session)
            }
        } else {
            floatingWindowMode = .idle
        }

        renderFloatingWindow(language: language, animated: true)
    }

    private func renderFloatingWindow(language: AppLanguage, animated: Bool) {
        guard floatingWindowMode != .hidden else {
            stopFloatingWindowAutomaticDismissal()
            hideFloatingWindowPanel()
            return
        }

        let panel = makeFloatingWindowPanelIfNeeded()
        let localizer = AppLocalizer(language: language)
        let panelNeedsAppearanceFade = !panel.isVisible
            || isFloatingWindowFadingOut
            || panel.alphaValue < 0.99
        let shouldAnimateAppearance = animated
            && panel.isVisible
            && !panelNeedsAppearanceFade
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let hostingView = makeFloatingWindowContentView(
            mode: floatingWindowMode,
            localizer: localizer,
            panel: panel
        )

        panel.contentViewController = nil
        hostingView.alphaValue = shouldAnimateAppearance ? 0 : 1
        panel.contentView = hostingView
        panel.ignoresMouseEvents = false
        configureFloatingPanelActivation(panel, isEditing: floatingWindowMode.isEditing)
        positionFloatingWindowPanel(
            panel,
            size: floatingWindowMode.size,
            animated: animated
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                && panel.isVisible
                && !panelNeedsAppearanceFade
        )

        showFloatingWindowPanel(panel, isEditing: floatingWindowMode.isEditing)

        if shouldAnimateAppearance {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = Self.floatingTransitionTimingFunction
                hostingView.animator().alphaValue = 1
            }
        }

        configureFloatingWindowAutomaticDismissal()
    }

    private func showFloatingWindowPanel(_ panel: NSPanel, isEditing: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasVisible = panel.isVisible
        let wasFadingOut = isFloatingWindowFadingOut

        floatingWindowVisibilityRevision &+= 1
        let revision = floatingWindowVisibilityRevision
        isFloatingWindowFadingOut = false
        panel.ignoresMouseEvents = false

        if !wasVisible && !reduceMotion {
            panel.alphaValue = 0
        }

        if isEditing {
            suppressNextActivationPanel()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        guard !reduceMotion,
              !wasVisible || wasFadingOut || panel.alphaValue < 0.99 else {
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.floatingFadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self,
                      let panel,
                      self.floatingWindowVisibilityRevision == revision,
                      self.floatingWindowMode != .hidden else {
                    return
                }
                panel.alphaValue = 1
                panel.ignoresMouseEvents = false
            }
        }
    }

    private func hideFloatingWindowPanel() {
        guard let panel = floatingWindowPanel else {
            return
        }
        guard panel.isVisible else {
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            isFloatingWindowFadingOut = false
            return
        }
        guard !isFloatingWindowFadingOut else {
            return
        }

        floatingWindowVisibilityRevision &+= 1
        let revision = floatingWindowVisibilityRevision
        isFloatingWindowFadingOut = true
        panel.ignoresMouseEvents = true

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            isFloatingWindowFadingOut = false
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.floatingFadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self,
                      let panel,
                      self.floatingWindowVisibilityRevision == revision,
                      self.floatingWindowMode == .hidden else {
                    return
                }
                panel.orderOut(nil)
                panel.alphaValue = 1
                panel.ignoresMouseEvents = false
                self.isFloatingWindowFadingOut = false
            }
        }
    }

    private func makeFloatingWindowContentView(
        mode: FloatingWindowMode,
        localizer: AppLocalizer,
        panel: FloatingWindowPanel
    ) -> NSView {
        let content = FloatingWindowView(
            mode: mode,
            localizer: localizer,
            activity: floatingWindowActivity,
            expand: { [weak self, weak panel] session in
                guard let self,
                      let panel,
                      !panel.isSuppressingContentAction,
                      case .collapsed(let collapsedSession) = self.floatingWindowMode,
                      collapsedSession.id == session.id else {
                    return
                }
                self.transitionFloatingWindow(
                    to: .transcript(session),
                    language: self.appState.settings.appLanguage
                )
            },
            beginCorrection: { [weak self, weak panel] session in
                guard let self,
                      let panel,
                      !panel.isSuppressingContentAction,
                      self.floatingWindowMode.sessionID == session.id else {
                    return
                }
                self.transitionFloatingWindow(
                    to: .editing(session),
                    language: self.appState.settings.appLanguage
                )
            },
            collapse: { [weak self, weak panel] session in
                guard let self,
                      let panel,
                      !panel.isSuppressingContentAction else {
                    return
                }
                if self.floatingWindowMode.isEditing {
                    self.appState.restoreFloatingCorrectionTarget(sessionID: session.id)
                }
                self.collapseFloatingWindow(
                    session: session,
                    language: self.appState.settings.appLanguage
                )
            },
            confirm: { [weak self, weak panel] session, correctedText in
                guard let self,
                      let panel,
                      !panel.isSuppressingContentAction else {
                    return
                }
                let confirmationAccepted = self.appState.confirmFloatingCorrection(
                    sessionID: session.id,
                    correctedText: correctedText
                )
                guard confirmationAccepted,
                      let retainedSession = self.appState.floatingCorrectionSession,
                      retainedSession.id == session.id else {
                    return
                }
                self.collapseFloatingWindow(
                    session: retainedSession,
                    language: self.appState.settings.appLanguage
                )
            },
            resize: { [weak self, weak panel] size in
                guard let self,
                      let panel,
                      mode.isEditing,
                      self.floatingWindowMode.isEditing,
                      self.floatingWindowMode.sessionID == mode.sessionID,
                      size.width.isFinite,
                      size.height.isFinite,
                      size.width > 0,
                      size.height > 0 else {
                    return
                }
                self.positionFloatingWindowPanel(
                    panel,
                    size: size,
                    animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    duration: Self.floatingResizeDuration
                )
            }
        )
        return FirstMouseHostingView(rootView: content)
    }

    private func collapseFloatingWindow(
        session: FloatingCorrectionSession,
        language: AppLanguage
    ) {
        guard floatingWindowMode.sessionID == session.id else {
            return
        }

        stopFloatingWindowAutomaticDismissal()
        transitionFloatingWindow(to: .collapsed(session), language: language)
    }

    private func transitionFloatingWindow(
        to targetMode: FloatingWindowMode,
        language: AppLanguage
    ) {
        guard floatingWindowMode != targetMode else {
            return
        }

        stopFloatingWindowAutomaticDismissal()
        floatingWindowMode = targetMode

        guard let panel = floatingWindowPanel,
              panel.isVisible,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let outgoingContent = panel.contentView,
              let targetFrame = floatingWindowFrame(for: panel, size: targetMode.size) else {
            renderFloatingWindow(language: language, animated: false)
            return
        }

        let localizer = AppLocalizer(language: language)
        let incomingContent = makeFloatingWindowContentView(
            mode: targetMode,
            localizer: localizer,
            panel: panel
        )
        let transitionView = FloatingWindowTransitionView(frame: panel.contentView?.bounds ?? .zero)
        outgoingContent.removeFromSuperview()
        outgoingContent.frame = transitionView.bounds
        outgoingContent.autoresizingMask = [.width, .height]
        incomingContent.frame = transitionView.bounds
        incomingContent.autoresizingMask = [.width, .height]
        incomingContent.alphaValue = 0.22
        transitionView.addSubview(outgoingContent)
        transitionView.addSubview(incomingContent)
        panel.contentView = transitionView
        panel.ignoresMouseEvents = true
        configureFloatingPanelActivation(panel, isEditing: targetMode.isEditing)

        if targetMode.isEditing {
            suppressNextActivationPanel()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.floatingTransitionDuration
            context.timingFunction = Self.floatingTransitionTimingFunction
            panel.animator().setFrame(targetFrame, display: true)
            outgoingContent.animator().alphaValue = 0.10
            incomingContent.animator().alphaValue = 1
        } completionHandler: { [weak self, weak panel, weak incomingContent] in
            Task { @MainActor in
                guard let self,
                      let panel,
                      let incomingContent else {
                    return
                }
                guard self.floatingWindowMode == targetMode else {
                    if self.floatingWindowMode != .hidden,
                       !self.isFloatingWindowFadingOut {
                        panel.ignoresMouseEvents = false
                    }
                    return
                }

                incomingContent.removeFromSuperview()
                incomingContent.frame = NSRect(origin: .zero, size: targetMode.size)
                incomingContent.autoresizingMask = [.width, .height]
                incomingContent.alphaValue = 1
                panel.contentView = incomingContent
                panel.ignoresMouseEvents = false
                self.configureFloatingWindowAutomaticDismissal()
            }
        }
    }

    private func configureFloatingWindowAutomaticDismissal() {
        stopFloatingWindowAutomaticDismissal()
        guard case .transcript(let session) = floatingWindowMode else {
            return
        }

        let presentationTimestamp = ProcessInfo.processInfo.systemUptime
        let duration = FloatingWindowBehavior.displayDuration(for: session.correctionText)
        floatingWindowAutoCollapseTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self?.collapseFloatingTranscript(sessionID: session.id)
        }

        let eventMask: NSEvent.EventTypeMask = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        floatingWindowGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            guard !FloatingWindowAutomaticDismissalPolicy.shouldIgnore(
                eventTimestamp: event.timestamp,
                presentationTimestamp: presentationTimestamp,
                isSynthetic: ShuoSyntheticEventMarker.isMarked(event)
            ) else {
                Self.floatingWindowLogger.info(
                    "Ignored synthetic or pre-presentation event for floating transcript dismissal"
                )
                return
            }
            let eventWindowNumber = event.windowNumber
            Task { @MainActor in
                guard let self,
                      eventWindowNumber != self.floatingWindowPanel?.windowNumber else {
                    return
                }
                Self.floatingWindowLogger.notice(
                    "Collapsing floating transcript after external event; type=\(String(describing: event.type), privacy: .public)"
                )
                self.collapseFloatingTranscript(sessionID: session.id)
            }
        }
        floatingWindowLocalEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            guard !FloatingWindowAutomaticDismissalPolicy.shouldIgnore(
                eventTimestamp: event.timestamp,
                presentationTimestamp: presentationTimestamp,
                isSynthetic: ShuoSyntheticEventMarker.isMarked(event)
            ) else {
                return event
            }
            let eventWindowNumber = event.windowNumber
            Task { @MainActor in
                guard let self,
                      eventWindowNumber != self.floatingWindowPanel?.windowNumber else {
                    return
                }
                self.collapseFloatingTranscript(sessionID: session.id)
            }
            return event
        }
    }

    private func stopFloatingWindowAutomaticDismissal() {
        floatingWindowAutoCollapseTask?.cancel()
        floatingWindowAutoCollapseTask = nil

        if let floatingWindowGlobalEventMonitor {
            NSEvent.removeMonitor(floatingWindowGlobalEventMonitor)
            self.floatingWindowGlobalEventMonitor = nil
        }
        if let floatingWindowLocalEventMonitor {
            NSEvent.removeMonitor(floatingWindowLocalEventMonitor)
            self.floatingWindowLocalEventMonitor = nil
        }
    }

    private func configureReplacementTargetSafetyMonitoring(sessionID: UUID?) {
        guard replacementSafetySessionID != sessionID else {
            return
        }
        stopReplacementTargetSafetyMonitoring()
        guard let sessionID else {
            return
        }
        replacementSafetySessionID = sessionID

        let eventMask: NSEvent.EventTypeMask = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        replacementSafetyEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            guard !ShuoSyntheticEventMarker.isMarked(event) else {
                Self.floatingWindowLogger.info(
                    "Ignored Shuo-generated event for replacement safety"
                )
                return
            }
            let isKeyEvent = event.type == .keyDown
            let eventWindowNumber = event.windowNumber
            let mouseLocation = isKeyEvent ? nil : NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else {
                    return
                }
                // A click can resize/reposition the floating panel before this
                // main-actor task runs. Prefer the originating window number so
                // that a legitimate click in Shuo is never mistaken for an edit
                // in the target application.
                if eventWindowNumber == self.floatingWindowPanel?.windowNumber {
                    return
                }
                if let mouseLocation,
                   self.floatingWindowPanel?.frame
                    .insetBy(dx: -4, dy: -4)
                    .contains(mouseLocation) == true {
                    return
                }
                if NSApp.isActive || self.floatingWindowPanel?.isKeyWindow == true {
                    return
                }
                let frontmostApplication = NSWorkspace.shared.frontmostApplication
                Self.floatingWindowLogger.notice(
                    "Marked replacement interaction; type=\(String(describing: event.type), privacy: .public) frontmostBundle=\(frontmostApplication?.bundleIdentifier ?? "unknown", privacy: .public) frontmostPID=\(String(frontmostApplication?.processIdentifier ?? 0), privacy: .public) eventWindow=\(eventWindowNumber, privacy: .public)"
                )
                self.appState.notePreviousInsertionTargetInteraction(sessionID: sessionID)
                self.stopReplacementTargetSafetyMonitoring()
            }
        }
    }

    private func stopReplacementTargetSafetyMonitoring() {
        if let replacementSafetyEventMonitor {
            NSEvent.removeMonitor(replacementSafetyEventMonitor)
            self.replacementSafetyEventMonitor = nil
        }
        replacementSafetySessionID = nil
    }

    private func collapseFloatingTranscript(sessionID: UUID) {
        guard case .transcript(let session) = floatingWindowMode,
              session.id == sessionID else {
            return
        }
        collapseFloatingWindow(
            session: session,
            language: appState.settings.appLanguage
        )
    }

    private func makeFloatingWindowPanelIfNeeded() -> FloatingWindowPanel {
        if let panel = floatingWindowPanel {
            return panel
        }

        let panel = FloatingWindowPanel(
            contentRect: NSRect(origin: .zero, size: FloatingWindowMode.idle.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.styleMask.remove(.resizable)
        panel.onUserDragBegan = { [weak self] in
            self?.stopFloatingWindowAutomaticDismissal()
        }
        panel.onUserDragMoved = { [weak self] center in
            self?.floatingWindowCenter = center
        }
        panel.onUserDragEnded = { [weak self] center in
            guard let self else {
                return
            }
            self.floatingWindowCenter = center
            FloatingWindowPositionStore.save(center)
            self.configureFloatingWindowAutomaticDismissal()
        }
        panel.contextMenuProvider = { [weak self] in
            self?.makeFloatingWindowContextMenu()
        }
        panel.onContextMenuWillOpen = { [weak self] in
            self?.stopFloatingWindowAutomaticDismissal()
        }
        panel.onContextMenuDidClose = { [weak self] in
            self?.configureFloatingWindowAutomaticDismissal()
        }
        floatingWindowPanel = panel
        return panel
    }

    private func configureFloatingPanelActivation(
        _ panel: NSPanel,
        isEditing: Bool
    ) {
        if isEditing {
            panel.styleMask.remove(.nonactivatingPanel)
        } else {
            panel.styleMask.insert(.nonactivatingPanel)
        }
    }

    private func positionFloatingWindowPanel(
        _ panel: NSPanel,
        size: NSSize,
        animated: Bool,
        duration: TimeInterval? = nil
    ) {
        guard let frame = floatingWindowFrame(for: panel, size: size) else {
            panel.setContentSize(size)
            panel.center()
            return
        }

        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration ?? Self.floatingTransitionDuration
            context.timingFunction = Self.floatingTransitionTimingFunction
            panel.animator().setFrame(frame, display: true)
        }
    }

    private static var floatingTransitionTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.18, 1.0)
    }

    private func floatingWindowFrame(for panel: NSPanel, size: NSSize) -> NSRect? {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let floatingWindowCenter,
           let frame = FloatingWindowPlacement.frame(
               size: size,
               centeredAt: floatingWindowCenter,
               visibleFrames: visibleFrames
           ) {
            return frame
        }

        guard let screen = panel.screen ?? NSScreen.main else {
            return nil
        }
        return FloatingWindowPlacement.defaultFrame(
            size: size,
            visibleFrame: screen.visibleFrame
        )
    }

    private func makeFloatingWindowContextMenu() -> NSMenu {
        let localizer = AppLocalizer(language: appState.settings.appLanguage)
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let actions: [Selector] = [
            #selector(hideFloatingWindowFromContextMenu),
            #selector(openShuoFromFloatingWindowContextMenu),
            #selector(quitShuoFromFloatingWindowContextMenu)
        ]
        for (title, action) in zip(
            FloatingWindowContextMenuCopy.titles(localizer: localizer),
            actions
        ) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    @objc private func hideFloatingWindowFromContextMenu() {
        appState.setPluginEnabled(.smartCorrectionWindow, isEnabled: false)
    }

    @objc private func openShuoFromFloatingWindowContextMenu() {
        showMainPanel()
    }

    @objc private func quitShuoFromFloatingWindowContextMenu() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let state = statusIconState
        configureActivityTimer(
            isActive: state.isAnimated
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let displayedOpacities = state.artworkStyle == .transcribing
            ? transcriptionBarOpacities
            : StatusIconArtwork.bars(style: state.artworkStyle).map(\.opacity)
        floatingWindowActivity.style = state.artworkStyle
        floatingWindowActivity.frame = activityFrame
        floatingWindowActivity.barOpacities = displayedOpacities

        button.image = StatusIconArtwork.image(
            style: state.artworkStyle,
            frame: activityFrame,
            transcribingOpacities: displayedOpacities
        )
        button.contentTintColor = nil
        button.alphaValue = 1
        button.toolTip = state.toolTip
        button.setAccessibilityLabel(state.toolTip)
        recordingIndicatorView.isHidden = !state.artworkStyle.showsRecordingIndicator
        recordingIndicatorView.needsDisplay = state.artworkStyle.showsRecordingIndicator
    }

    private var statusIconState: StatusIconState {
        let localizer = AppLocalizer(language: appState.settings.appLanguage)

        if appState.isPreparingMicrophone {
            return StatusIconState(
                artworkStyle: .transcribing,
                toolTip: appState.statusMessage,
                isAnimated: true
            )
        }

        if appState.isRecording {
            return StatusIconState(
                artworkStyle: .recording,
                toolTip: appState.statusMessage,
                isAnimated: false
            )
        }

        if appState.isCheckingAudio {
            return StatusIconState(
                artworkStyle: .transcribing,
                toolTip: appState.statusMessage,
                isAnimated: true
            )
        }

        if appState.isTranscribing {
            return StatusIconState(
                artworkStyle: .transcribing,
                toolTip: appState.statusMessage,
                isAnimated: true
            )
        }

        if appState.settings.pushToTalkEnabled,
           appState.isPushToTalkRunning {
            return StatusIconState(
                artworkStyle: .ready,
                toolTip: "\(AppBuildIdentity.displayName) — \(localizer.status(.ready))",
                isAnimated: false
            )
        }

        let inactiveTooltip: String
        if !appState.pushToTalkStatusMessage.isEmpty {
            inactiveTooltip = appState.pushToTalkStatusMessage
        } else if appState.settings.pushToTalkEnabled {
            inactiveTooltip = localizer.setupNeededStatusLabel()
        } else {
            inactiveTooltip = localizer.dictationOffStatusLabel()
        }

        return StatusIconState(
            artworkStyle: .disabled,
            toolTip: inactiveTooltip,
            isAnimated: false
        )
    }

    private func configureActivityTimer(isActive: Bool) {
        guard isActive else {
            activityTimer?.invalidate()
            activityTimer = nil
            activityFrame = 0
            transcriptionBarOpacities = Array(
                repeating: 1,
                count: TranscriptionFlickerSequence.barCount
            )
            return
        }

        guard activityTimer == nil else {
            return
        }

        transcriptionFlickerSeed &+= 0x9E37_79B9_7F4A_7C15
        transcriptionFlickerSequence = TranscriptionFlickerSequence(
            seed: transcriptionFlickerSeed
        )
        transcriptionBarOpacities = transcriptionFlickerSequence.opacities

        activityTimer = Timer.scheduledTimer(
            withTimeInterval: Self.activityInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.activityFrame += 1
                self.transcriptionBarOpacities = self.transcriptionFlickerSequence.advance()
                self.updateStatusItem()
            }
        }
    }

    private func showMainWindow(selectedSection: AppPanelSection) {
        appState.selectedPanelSection = selectedSection
        showMainPanel()
    }

    private func showMainPanelWindow() {
        let contentViewController = NSHostingController(
            rootView: AppPanelView()
                .environmentObject(appState)
        )

        if mainWindow == nil {
            mainWindow = makeWindow(
                title: AppBuildIdentity.displayName,
                size: NSSize(width: 1020, height: 720),
                contentViewController: contentViewController
            )
        } else {
            mainWindow?.contentViewController = contentViewController
        }

        presentWindow(mainWindow, title: AppBuildIdentity.displayName)
    }

    private func showMainPanel() {
        showMainPanelWindow()
    }

    private func makeWindow(
        title: String,
        size: NSSize,
        contentViewController: NSViewController
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func presentWindow(_ window: NSWindow?, title: String) {
        guard let window else {
            return
        }

        closeStatusMenuPanel()

        window.title = title
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private enum FloatingWindowMode: Equatable {
    case hidden
    case idle
    case collapsed(FloatingCorrectionSession)
    case transcript(FloatingCorrectionSession)
    case editing(FloatingCorrectionSession)

    var sessionID: UUID? {
        switch self {
        case .collapsed(let session), .transcript(let session), .editing(let session):
            return session.id
        case .hidden, .idle:
            return nil
        }
    }

    var size: NSSize {
        switch self {
        case .hidden:
            return .zero
        case .idle, .collapsed:
            return NSSize(width: 54, height: 18)
        case .transcript(let session):
            return FloatingWindowBehavior.windowSize(for: session.correctionText)
        case .editing(let session):
            return FloatingWindowBehavior.editingWindowSize(for: session.correctionText)
        }
    }

    var isEditing: Bool {
        if case .editing = self {
            return true
        }
        return false
    }

    func updatingSession(_ session: FloatingCorrectionSession) -> FloatingWindowMode {
        guard sessionID == session.id else {
            return self
        }

        switch self {
        case .collapsed:
            return .collapsed(session)
        case .transcript:
            return .transcript(session)
        case .editing:
            return .editing(session)
        case .hidden, .idle:
            return self
        }
    }
}

private final class StatusMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FloatingWindowPanel: NSPanel {
    var contextMenuProvider: (() -> NSMenu?)?
    var onContextMenuWillOpen: (() -> Void)?
    var onContextMenuDidClose: (() -> Void)?
    var onUserDragBegan: (() -> Void)?
    var onUserDragMoved: ((NSPoint) -> Void)?
    var onUserDragEnded: ((NSPoint) -> Void)?

    private(set) var isSuppressingContentAction = false

    private var dragStartMouseLocation: NSPoint?
    private var dragStartFrame: NSRect?
    private var tracksCurrentMouseDrag = false
    private var isHandlingUserDrag = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .rightMouseDown:
            resetDragTracking()
            guard let contentView,
                  let menu = contextMenuProvider?() else {
                super.sendEvent(event)
                return
            }
            onContextMenuWillOpen?()
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            onContextMenuDidClose?()
        case .leftMouseDown:
            beginDragTracking(for: event)
            super.sendEvent(event)
        case .leftMouseDragged:
            updateDragTracking()
            super.sendEvent(event)
        case .leftMouseUp:
            let completedDrag = isHandlingUserDrag
            if completedDrag {
                // Button actions are delivered while forwarding mouse-up. Keep
                // this asserted until the next run loop so a drag never also
                // expands, collapses, or confirms the floating content.
                isSuppressingContentAction = true
            }
            super.sendEvent(event)
            if completedDrag {
                onUserDragEnded?(NSPoint(x: frame.midX, y: frame.midY))
                DispatchQueue.main.async { [weak self] in
                    self?.isSuppressingContentAction = false
                }
            }
            resetDragTracking()
        default:
            super.sendEvent(event)
        }
    }

    private func beginDragTracking(for event: NSEvent) {
        resetDragTracking()
        guard !isEditableTextInteraction(event) else {
            return
        }
        tracksCurrentMouseDrag = true
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartFrame = frame
    }

    private func updateDragTracking() {
        guard tracksCurrentMouseDrag,
              let dragStartMouseLocation,
              let dragStartFrame else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let deltaX = mouseLocation.x - dragStartMouseLocation.x
        let deltaY = mouseLocation.y - dragStartMouseLocation.y
        if !isHandlingUserDrag {
            let distanceSquared = deltaX * deltaX + deltaY * deltaY
            guard distanceSquared >= 9 else {
                return
            }
            isHandlingUserDrag = true
            isSuppressingContentAction = true
            onUserDragBegan?()
        }

        let proposedFrame = NSRect(
            x: dragStartFrame.minX + deltaX,
            y: dragStartFrame.minY + deltaY,
            width: dragStartFrame.width,
            height: dragStartFrame.height
        )
        let constrainedFrame = FloatingWindowPlacement.frame(
            byDragging: proposedFrame,
            cursor: mouseLocation,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        setFrame(constrainedFrame, display: true)
        onUserDragMoved?(NSPoint(x: constrainedFrame.midX, y: constrainedFrame.midY))
    }

    private func resetDragTracking() {
        dragStartMouseLocation = nil
        dragStartFrame = nil
        tracksCurrentMouseDrag = false
        isHandlingUserDrag = false
    }

    private func isEditableTextInteraction(_ event: NSEvent) -> Bool {
        guard let contentView else {
            return false
        }
        let point = contentView.convert(event.locationInWindow, from: nil)
        var candidate = contentView.hitTest(point)
        while let view = candidate {
            if let textView = view as? NSTextView,
               textView.isEditable || textView.isSelectable {
                return true
            }
            if let textField = view as? NSTextField,
               textField.isEditable || textField.isSelectable {
                return true
            }
            let className = NSStringFromClass(type(of: view)).lowercased()
            if className.contains("textfield") || className.contains("texteditor") {
                return true
            }
            candidate = view.superview
        }
        return false
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class FloatingWindowTransitionView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

enum FloatingCorrectionKeyboardConfirmationPolicy {
    static func shouldConfirm(
        hasCommandModifier: Bool,
        hasConfirmableDraft: Bool
    ) -> Bool {
        hasCommandModifier && hasConfirmableDraft
    }
}

private struct FloatingWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mode: FloatingWindowMode
    let localizer: AppLocalizer
    @ObservedObject var activity: FloatingWindowActivityModel
    let expand: (FloatingCorrectionSession) -> Void
    let beginCorrection: (FloatingCorrectionSession) -> Void
    let collapse: (FloatingCorrectionSession) -> Void
    let confirm: (FloatingCorrectionSession, String) -> Void
    let resize: (NSSize) -> Void

    @State private var draft: String
    @State private var editorSize: NSSize
    @State private var editorWindowWidth: CGFloat
    @FocusState private var isEditorFocused: Bool

    init(
        mode: FloatingWindowMode,
        localizer: AppLocalizer,
        activity: FloatingWindowActivityModel,
        expand: @escaping (FloatingCorrectionSession) -> Void,
        beginCorrection: @escaping (FloatingCorrectionSession) -> Void,
        collapse: @escaping (FloatingCorrectionSession) -> Void,
        confirm: @escaping (FloatingCorrectionSession, String) -> Void,
        resize: @escaping (NSSize) -> Void
    ) {
        self.mode = mode
        self.localizer = localizer
        self.activity = activity
        self.expand = expand
        self.beginCorrection = beginCorrection
        self.collapse = collapse
        self.confirm = confirm
        self.resize = resize
        switch mode {
        case .collapsed(let session), .transcript(let session), .editing(let session):
            let initialEditorSize = FloatingWindowBehavior.editingWindowSize(
                for: session.correctionText
            )
            _draft = State(initialValue: session.correctionText)
            _editorSize = State(initialValue: initialEditorSize)
            _editorWindowWidth = State(initialValue: initialEditorSize.width)
        case .hidden, .idle:
            _draft = State(initialValue: "")
            _editorSize = State(initialValue: .zero)
            _editorWindowWidth = State(initialValue: 0)
        }
    }

    @ViewBuilder
    var body: some View {
        switch mode {
        case .hidden:
            EmptyView()
        case .idle:
            compactView(session: nil)
        case .collapsed(let session):
            compactView(session: session)
        case .transcript(let session):
            transcriptView(session: session)
        case .editing(let session):
            editorView(session: session)
        }
    }

    @ViewBuilder
    private func compactView(session: FloatingCorrectionSession?) -> some View {
        if let session {
            Button {
                expand(session)
            } label: {
                compactGlyph
            }
            .buttonStyle(.plain)
            .help(localizer.floatingWindowExpandHint())
            .accessibilityLabel(localizer.floatingWindowExpandHint())
        } else {
            compactGlyph
                .help(localizer.floatingWindowIdleHint())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localizer.floatingWindowIdleHint())
        }
    }

    private var compactGlyph: some View {
        FloatingWindowGlyph(activity: activity)
            .frame(width: 30, height: 12)
            .padding(.horizontal, 12)
            .frame(width: FloatingWindowMode.idle.size.width, height: FloatingWindowMode.idle.size.height)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.13), lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
    }

    private func transcriptView(session: FloatingCorrectionSession) -> some View {
        HStack(spacing: 8) {
            Button {
                beginCorrection(session)
            } label: {
                Text(session.correctionText)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(FloatingWindowBehavior.maximumVisibleLineCount)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizer.floatingWindowTranscriptHint())

            actionRail(
                session: session,
                submit: { beginCorrection(session) },
                submitHelp: localizer.floatingWindowEditActionHint()
            )
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .floatingWindowSurface(size: mode.size)
    }

    private func editorView(session: FloatingCorrectionSession) -> some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, axis: .vertical)
                .font(.system(size: 13.5, weight: .regular))
                .textFieldStyle(.plain)
                .accessibilityLabel(localizer.floatingWindowEditActionHint())
                .lineLimit(1...FloatingWindowBehavior.maximumVisibleLineCount)
                .fixedSize(horizontal: false, vertical: true)
                .focused($isEditorFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onKeyPress(keys: [.return], phases: .down) { keyPress in
                    let shouldConfirm = FloatingCorrectionKeyboardConfirmationPolicy.shouldConfirm(
                        hasCommandModifier: keyPress.modifiers.contains(.command),
                        hasConfirmableDraft: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    guard shouldConfirm else {
                        return .ignored
                    }
                    confirm(session, draft)
                    return .handled
                }

            actionRail(
                session: session,
                submit: { confirm(session, draft) },
                submitHelp: localizer.floatingWindowConfirmActionHint(),
                isSubmitDisabled: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .floatingWindowSurface(size: editorSize)
        .onAppear {
            // Let the panel's expand-to-edit transition finish before the
            // field accepts typing and starts producing resize callbacks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                isEditorFocused = true
            }
        }
        .onChange(of: draft) { _, newValue in
            let size = FloatingWindowBehavior.editingWindowSize(
                for: newValue,
                fixedWindowWidth: editorWindowWidth
            )
            guard abs(size.height - editorSize.height) > 0.5 else {
                return
            }
            if reduceMotion {
                editorSize = size
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    editorSize = size
                }
            }
            resize(size)
        }
    }

    private func actionRail(
        session: FloatingCorrectionSession,
        submit: @escaping () -> Void,
        submitHelp: String,
        isSubmitDisabled: Bool = false
    ) -> some View {
        VStack(spacing: 5) {
            Button {
                collapse(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .help(localizer.collapseLabel())
            .accessibilityLabel(localizer.collapseLabel())

            Button(action: submit) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .help(submitHelp)
            .accessibilityLabel(submitHelp)
            .disabled(isSubmitDisabled)
        }
        .buttonStyle(FloatingWindowIconButtonStyle())
        .foregroundStyle(.secondary)
        .frame(width: 24)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private extension View {
    func floatingWindowSurface(size: NSSize) -> some View {
        frame(width: size.width, height: size.height)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.13), lineWidth: 0.6)
            )
    }
}

private struct FloatingWindowIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(isEnabled ? 0.10 : 0.045), lineWidth: 0.5)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
    }
}

private struct FloatingWindowGlyph: View {
    private static let heightRatios: [CGFloat] = [0.50, 0.72, 0.58, 1.00, 0.58, 0.72, 0.50]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var activity: FloatingWindowActivityModel

    var body: some View {
        GeometryReader { proxy in
            let readyBars = StatusIconArtwork.bars(style: .ready)
            let activeBars = StatusIconArtwork.bars(
                style: activity.style,
                frame: activity.frame
            )
            let regularBarWidth = readyBars[0].frame.width
            let baseBarWidth = max(1.3, proxy.size.width * 0.055)
            let gap = max(1.4, (proxy.size.width - baseBarWidth * 7) / 6)

            ZStack {
                ForEach(Self.heightRatios.indices, id: \.self) { index in
                    let widthScale = activeBars[index].frame.width / regularBarWidth
                    let opacity = activity.style == .transcribing
                        ? activity.barOpacities[index]
                        : activeBars[index].opacity
                    let presentation = FloatingWindowGlyphMotion.presentation(
                        artworkOpacity: opacity
                    )
                    let centerX = baseBarWidth / 2 + CGFloat(index) * (baseBarWidth + gap)
                    Capsule(style: .continuous)
                        .frame(
                            width: baseBarWidth * widthScale * presentation.widthScale,
                            height: max(
                                3,
                                proxy.size.height
                                    * Self.heightRatios[index]
                                    * presentation.heightScale
                            )
                        )
                        .opacity(presentation.opacity)
                        .position(
                            x: centerX,
                            y: proxy.size.height / 2 + presentation.verticalOffset
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Color.primary.opacity(0.90))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: activity.style)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: activity.frame)
        .accessibilityHidden(true)
    }
}
