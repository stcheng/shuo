import AppKit
import Darwin
import Foundation

#if DIRECT_DISTRIBUTION
import Sparkle
#endif

struct RunningApplicationProcess: Equatable {
    let processIdentifier: pid_t
    let userIdentifier: uid_t
    let command: String
    let executablePath: String?
}

enum OtherUserShuoProcessDetector {
    static func isOtherUserInstance(
        _ process: RunningApplicationProcess,
        currentProcessIdentifier: pid_t = getpid(),
        currentUserIdentifier: uid_t = getuid(),
        expectedExecutableURL: URL? = Bundle.main.executableURL
    ) -> Bool {
        guard process.processIdentifier != currentProcessIdentifier,
              process.userIdentifier != currentUserIdentifier,
              let expectedExecutableURL else {
            return false
        }

        let expectedURL = expectedExecutableURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        if let executablePath = process.executablePath, !executablePath.isEmpty {
            let processURL = URL(fileURLWithPath: executablePath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            return processURL == expectedURL
        }

        // proc_pidpath can be unavailable across a user boundary. In that case,
        // prefer a harmless false positive over replacing the shared app while
        // another Shuo process may still be running.
        return process.command == expectedURL.lastPathComponent
    }

    static func hasOtherUserInstance(
        expectedExecutableURL: URL? = Bundle.main.executableURL
    ) throws -> Bool {
        try processSnapshot().contains {
            isOtherUserInstance($0, expectedExecutableURL: expectedExecutableURL)
        }
    }

    static func processSnapshot() throws -> [RunningApplicationProcess] {
        let stride = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]

        for _ in 0 ..< 3 {
            var byteCount = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &byteCount, nil, 0) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            var processes = [kinfo_proc](
                repeating: kinfo_proc(),
                count: max(1, byteCount / stride + 32)
            )
            let result = processes.withUnsafeMutableBytes { buffer in
                sysctl(
                    &mib,
                    UInt32(mib.count),
                    buffer.baseAddress,
                    &byteCount,
                    nil,
                    0
                )
            }
            if result != 0 {
                guard errno == ENOMEM else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                continue
            }

            return processes.prefix(byteCount / stride).compactMap { process in
                let processIdentifier = process.kp_proc.p_pid
                guard processIdentifier > 0 else {
                    return nil
                }
                return RunningApplicationProcess(
                    processIdentifier: processIdentifier,
                    userIdentifier: process.kp_eproc.e_ucred.cr_uid,
                    command: commandName(for: process),
                    executablePath: executablePath(for: processIdentifier)
                )
            }
        }

        throw POSIXError(.ENOMEM)
    }

    private static func commandName(for process: kinfo_proc) -> String {
        var command = process.kp_proc.p_comm
        let capacity = MemoryLayout.size(ofValue: command)
        return withUnsafePointer(to: &command) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private static func executablePath(for processIdentifier: pid_t) -> String? {
        let capacity = Int(MAXPATHLEN) * 4
        var buffer = [CChar](repeating: 0, count: capacity)
        let result = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        guard result > 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}

@MainActor
final class MachineUpdateCoordinator {
    struct Marker: Codable, Equatable {
        let token: UUID
        let ownerUserIdentifier: uid_t
        let ownerProcessIdentifier: pid_t
        let sourceBuildVersion: String
        var refreshedAt: Date
    }

    static let shared = MachineUpdateCoordinator()
    static let markerLifetime: TimeInterval = 5 * 60

    private let markerURL: URL

    init(markerURL: URL = URL(
        fileURLWithPath: "/private/tmp/\(AppBuildIdentity.bundleIdentifier).update-gate"
    )) {
        self.markerURL = markerURL
    }

    func begin(sourceBuildVersion: String, now: Date = Date()) throws -> UUID? {
        try withLockedMarker { descriptor in
            if let marker = try readMarker(from: descriptor),
               isActive(marker, now: now) {
                if marker.ownerUserIdentifier == getuid(),
                   marker.ownerProcessIdentifier == getpid(),
                   marker.sourceBuildVersion == sourceBuildVersion {
                    return marker.token
                }
                return nil
            }

            let marker = Marker(
                token: UUID(),
                ownerUserIdentifier: getuid(),
                ownerProcessIdentifier: getpid(),
                sourceBuildVersion: sourceBuildVersion,
                refreshedAt: now
            )
            try writeMarker(marker, to: descriptor)
            return marker.token
        }
    }

    func refresh(token: UUID, now: Date = Date()) throws -> Bool {
        try withLockedMarker { descriptor in
            guard var marker = try readMarker(from: descriptor),
                  marker.token == token else {
                return false
            }
            marker.refreshedAt = now
            try writeMarker(marker, to: descriptor)
            return true
        }
    }

    func clear(token: UUID) {
        try? withLockedMarker { descriptor in
            guard let marker = try readMarker(from: descriptor) else {
                return
            }
            guard marker.token == token else {
                return
            }
            try truncateMarker(descriptor)
            _ = unlink(markerURL.path)
        }
    }

    func shouldBlockLaunch(
        currentBuildVersion: String,
        currentProcessIdentifier: pid_t = getpid(),
        now: Date = Date()
    ) -> Bool {
        (try? withLockedMarker { descriptor in
            guard let marker = try readMarker(from: descriptor) else {
                return false
            }
            guard isActive(marker, now: now) else {
                try truncateMarker(descriptor)
                return false
            }
            guard marker.sourceBuildVersion == currentBuildVersion else {
                try truncateMarker(descriptor)
                return false
            }
            return marker.ownerProcessIdentifier != currentProcessIdentifier
        }) ?? false
    }

    static var currentBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var blockedLaunchCopy: (title: String, detail: String, button: String) {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferredLanguage.hasPrefix("zh-hant") || preferredLanguage.hasPrefix("zh-tw") {
            return (
                "Shuo 正在更新",
                "另一個 macOS 帳戶正在安裝 Shuo 更新，請稍後再試。",
                "知道了"
            )
        }
        if preferredLanguage.hasPrefix("zh") {
            return (
                "Shuo 正在更新",
                "另一个 macOS 账户正在安装 Shuo 更新，请稍后再试。",
                "知道了"
            )
        }
        if preferredLanguage.hasPrefix("ja") {
            return (
                "Shuoをアップデート中",
                "別のmacOSアカウントがShuoをアップデートしています。しばらくしてからもう一度お試しください。",
                "OK"
            )
        }
        return (
            "Shuo is updating",
            "Another macOS account is installing a Shuo update. Please try again in a moment.",
            "OK"
        )
    }

    private func isActive(_ marker: Marker, now: Date) -> Bool {
        let age = now.timeIntervalSince(marker.refreshedAt)
        return age >= -60 && age <= Self.markerLifetime
    }

    private func withLockedMarker<T>(_ body: (CInt) throws -> T) throws -> T {
        let permissions = mode_t(
            S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH
        )
        let descriptor = open(
            markerURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            permissions
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        var fileStatus = stat()
        guard fstat(descriptor, &fileStatus) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard fileStatus.st_mode & S_IFMT == S_IFREG else {
            throw POSIXError(.EINVAL)
        }

        // open(2) honors the process umask. Make the coordination file writable
        // by every local account; it contains no user data or credentials.
        _ = fchmod(descriptor, permissions)
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body(descriptor)
    }

    private func readMarker(from descriptor: CInt) throws -> Marker? {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            guard count >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
            guard data.count <= 16 * 1_024 else {
                throw POSIXError(.EFBIG)
            }
        }

        guard !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }

    private func writeMarker(_ marker: Marker, to descriptor: CInt) throws {
        let data = try JSONEncoder().encode(marker)
        try truncateMarker(descriptor)

        var writtenByteCount = 0
        try data.withUnsafeBytes { bytes in
            while writtenByteCount < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: writtenByteCount),
                    bytes.count - writtenByteCount
                )
                guard count > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                writtenByteCount += count
            }
        }
        _ = fsync(descriptor)
    }

    private func truncateMarker(_ descriptor: CInt) throws {
        guard ftruncate(descriptor, 0) == 0,
              lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

@MainActor
final class AppUpdateController: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var statusMessage: String?
    var appLanguage = AppLanguage.english

    private var localizer: AppLocalizer {
        AppLocalizer(language: appLanguage)
    }

#if DIRECT_DISTRIBUTION
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var canCheckObservation: NSKeyValueObservation?
    private var automaticChecksObservation: NSKeyValueObservation?
    private var automaticDownloadsObservation: NSKeyValueObservation?
    private var hasStarted = false
    private var updateGateToken: UUID?
    private var waitingInstallHandler: (() -> Void)?
    private var retryTimer: Timer?
    private var hasPendingInstallation = false
    private var terminateWhenOtherUserExits = false
    private var hasShownOtherUserAlert = false
    private var isManualUpdateInformationCheck = false
    private var shouldOfferUpdateAfterInformationCheck = false

    override init() {
        super.init()
    }

    var supportsDirectUpdates: Bool { true }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        updaterController.startUpdater()
        observeUpdaterState()
    }

    func checkForUpdates() {
        start()
        guard updaterController.updater.canCheckForUpdates else {
            statusMessage = localizer.updateCheckAlreadyInProgress()
            return
        }

        statusMessage = localizer.checkingForUpdates()
        isManualUpdateInformationCheck = true
        shouldOfferUpdateAfterInformationCheck = false
        updaterController.updater.checkForUpdateInformation()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            updaterController.updater.automaticallyDownloadsUpdates = false
        }
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard updaterController.updater.automaticallyChecksForUpdates else {
            updaterController.updater.automaticallyDownloadsUpdates = false
            return
        }
        updaterController.updater.automaticallyDownloadsUpdates = enabled
    }

    func shouldAllowApplicationTermination() -> Bool {
        guard hasPendingInstallation || waitingInstallHandler != nil else {
            return true
        }

        guard prepareMachineUpdateGate() else {
            waitForSafeInstallation(terminateWhenReady: true)
            return false
        }
        guard otherUserIsRunning() == false else {
            waitForSafeInstallation(terminateWhenReady: true)
            return false
        }

        return true
    }

    private func observeUpdaterState() {
        let updater = updaterController.updater
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            Task { @MainActor in
                self?.canCheckForUpdates = change.newValue ?? false
            }
        }
        automaticChecksObservation = updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
            Task { @MainActor in
                self?.automaticallyChecksForUpdates = change.newValue ?? false
            }
        }
        automaticDownloadsObservation = updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, change in
            Task { @MainActor in
                self?.automaticallyDownloadsUpdates = change.newValue ?? false
            }
        }
    }

    private func prepareMachineUpdateGate() -> Bool {
        if let updateGateToken {
            if (try? MachineUpdateCoordinator.shared.refresh(token: updateGateToken)) == true {
                return true
            }
            self.updateGateToken = nil
        }

        do {
            updateGateToken = try MachineUpdateCoordinator.shared.begin(
                sourceBuildVersion: MachineUpdateCoordinator.currentBuildVersion
            )
            return updateGateToken != nil
        } catch {
            statusMessage = localizer.updateCoordinationFailed(error.localizedDescription)
            return false
        }
    }

    private func waitForSafeInstallation(
        installHandler: (() -> Void)? = nil,
        terminateWhenReady: Bool = false
    ) {
        if let installHandler {
            waitingInstallHandler = installHandler
        }
        terminateWhenOtherUserExits = terminateWhenOtherUserExits || terminateWhenReady
        statusMessage = localizer.updateWaitingForOtherUser()
        presentOtherUserAlertIfNeeded()

        guard retryTimer == nil else {
            return
        }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.retrySafeInstallation()
            }
        }
    }

    private func retrySafeInstallation() {
        guard prepareMachineUpdateGate() else {
            return
        }
        guard otherUserIsRunning() == false else {
            if let updateGateToken {
                _ = try? MachineUpdateCoordinator.shared.refresh(token: updateGateToken)
            }
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil
        hasShownOtherUserAlert = false
        statusMessage = localizer.updateOtherUserExited()

        if let installHandler = waitingInstallHandler {
            waitingInstallHandler = nil
            terminateWhenOtherUserExits = false
            installHandler()
        } else if terminateWhenOtherUserExits {
            terminateWhenOtherUserExits = false
            NSApp.terminate(nil)
        }
    }

    private func presentOtherUserAlertIfNeeded() {
        guard !hasShownOtherUserAlert else {
            return
        }
        hasShownOtherUserAlert = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = self.localizer.updateBlockedByOtherUserTitle()
            alert.informativeText = self.localizer.updateWaitingForOtherUser()
            alert.addButton(withTitle: self.localizer.updateAlertOK())
            alert.runModal()
        }
    }

    private func resetUpdateCoordination(clearMarker: Bool) {
        retryTimer?.invalidate()
        retryTimer = nil
        waitingInstallHandler = nil
        terminateWhenOtherUserExits = false
        hasPendingInstallation = false
        hasShownOtherUserAlert = false
        if clearMarker, let updateGateToken {
            MachineUpdateCoordinator.shared.clear(token: updateGateToken)
            self.updateGateToken = nil
        }
    }

    private func otherUserIsRunning() -> Bool? {
        do {
            return try OtherUserShuoProcessDetector.hasOtherUserInstance()
        } catch {
            statusMessage = localizer.updateCoordinationFailed(error.localizedDescription)
            return nil
        }
    }
#else
    override init() {
        super.init()
    }

    var supportsDirectUpdates: Bool { false }

    func start() {}

    func checkForUpdates() {}

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {}
    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {}
    func shouldAllowApplicationTermination() -> Bool { true }
#endif
}

#if DIRECT_DISTRIBUTION
extension AppUpdateController: SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        shouldProceedWithUpdate updateItem: SUAppcastItem,
        updateCheck: SPUUpdateCheck
    ) throws {
        guard updateCheck != .updateInformation else {
            return
        }

        let otherUserIsRunning: Bool
        do {
            otherUserIsRunning = try OtherUserShuoProcessDetector.hasOtherUserInstance()
        } catch {
            let message = localizer.updateCoordinationFailed(error.localizedDescription)
            statusMessage = message
            throw NSError(
                domain: "\(AppBuildIdentity.bundleIdentifier).UpdateCoordination",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        guard !otherUserIsRunning else {
            let message = localizer.updateBlockedByOtherUser()
            statusMessage = message
            throw NSError(
                domain: "\(AppBuildIdentity.bundleIdentifier).UpdateCoordination",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        if isManualUpdateInformationCheck {
            shouldOfferUpdateAfterInformationCheck = true
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        if isManualUpdateInformationCheck {
            shouldOfferUpdateAfterInformationCheck = false
            statusMessage = localizer.updateCheckUpToDate()
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        hasPendingInstallation = true
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        hasPendingInstallation = true
        guard prepareMachineUpdateGate(),
              otherUserIsRunning() == false else {
            waitForSafeInstallation(installHandler: installHandler)
            return true
        }
        return false
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        hasPendingInstallation = true
        return false
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        resetUpdateCoordination(clearMarker: true)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if updateCheck == .updateInformation {
            let shouldOfferUpdate = shouldOfferUpdateAfterInformationCheck
            isManualUpdateInformationCheck = false
            shouldOfferUpdateAfterInformationCheck = false

            if let error {
                statusMessage = error.localizedDescription
                resetUpdateCoordination(clearMarker: true)
            } else if shouldOfferUpdate {
                statusMessage = nil
                updaterController.checkForUpdates(nil)
            } else {
                statusMessage = localizer.updateCheckUpToDate()
                resetUpdateCoordination(clearMarker: true)
            }
            return
        }

        if let error {
            statusMessage = error.localizedDescription
            resetUpdateCoordination(clearMarker: true)
        } else {
            statusMessage = localizer.updateCheckFinished()
            if !hasPendingInstallation {
                resetUpdateCoordination(clearMarker: true)
            }
        }
    }
}
#endif
