import AppKit
import Darwin
import Foundation

@MainActor
final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()

    private var lockFileDescriptor: CInt = -1
    private let lockPath: String

    private init() {
        let bundleIdentifier = AppBuildIdentity.bundleIdentifier
        lockPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("\(bundleIdentifier).singleton.lock")
    }

    func acquireOrActivateExistingAndExit() {
        guard !AppRuntime.isRunningUnderXCTest else {
            return
        }

        lockFileDescriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        guard lockFileDescriptor >= 0 else {
            return
        }

        if flock(lockFileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            writeCurrentProcessID()
            return
        }

        activateExistingInstance()
        exit(0)
    }

    deinit {
        guard lockFileDescriptor >= 0 else {
            return
        }

        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
    }

    private func writeCurrentProcessID() {
        let processID = "\(getpid())\n"
        ftruncate(lockFileDescriptor, 0)
        lseek(lockFileDescriptor, 0, SEEK_SET)
        processID.withCString { pointer in
            _ = write(lockFileDescriptor, pointer, strlen(pointer))
        }
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let existingApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessID }

        existingApp?.activate(options: [.activateAllWindows])
    }
}
