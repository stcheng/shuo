import Foundation

struct CrashRecoveryReport {
    let reportURL: URL
    let reportText: String
}

struct CrashReportService {
    private struct SessionMarker: Codable {
        let sessionID: UUID
        let launchedAt: Date
        let processIdentifier: Int32
        let appVersion: String
        let buildNumber: String
        let operatingSystemVersion: String
    }

    private struct ExpectedRestartMarker: Codable {
        let reason: String
        let createdAt: Date
    }

    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = Self.defaultBaseDirectory(),
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    func startSession(now: Date = Date()) -> CrashRecoveryReport? {
        let previousMarker = readPreviousSessionMarker()
        let expectedRestartMarker = readExpectedRestartMarker()
        let recoveryReport: CrashRecoveryReport? = previousMarker.flatMap { marker in
            if shouldSuppressRecoveryReport(for: marker, expectedRestartMarker: expectedRestartMarker) {
                return nil
            }

            return writeRecoveryReport(for: marker, detectedAt: now)
        }

        removeExpectedRestartMarker()
        writeSessionMarker(now: now)
        return recoveryReport
    }

    func markExpectedRestart(reason: String, now: Date = Date()) {
        let marker = ExpectedRestartMarker(reason: reason, createdAt: now)

        do {
            try fileManager.createDirectory(
                at: expectedRestartMarkerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(marker).write(to: expectedRestartMarkerURL, options: .atomic)
        } catch {
            // Expected restart markers are best-effort and should not block updates.
        }
    }

    func markCleanExit() {
        try? fileManager.removeItem(at: sessionMarkerURL)
    }

    private static func defaultBaseDirectory() -> URL {
        AppStoragePaths.applicationSupportDirectory()
    }

    private var sessionMarkerURL: URL {
        baseDirectory
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("active-session.json")
    }

    private var expectedRestartMarkerURL: URL {
        baseDirectory
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("expected-restart.json")
    }

    private var crashReportsDirectory: URL {
        baseDirectory
            .appendingPathComponent("CrashReports", isDirectory: true)
    }

    private func readPreviousSessionMarker() -> SessionMarker? {
        guard let data = try? Data(contentsOf: sessionMarkerURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionMarker.self, from: data)
    }

    private func readExpectedRestartMarker() -> ExpectedRestartMarker? {
        guard let data = try? Data(contentsOf: expectedRestartMarkerURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ExpectedRestartMarker.self, from: data)
    }

    private func removeExpectedRestartMarker() {
        try? fileManager.removeItem(at: expectedRestartMarkerURL)
    }

    private func shouldSuppressRecoveryReport(
        for marker: SessionMarker,
        expectedRestartMarker: ExpectedRestartMarker?
    ) -> Bool {
        guard let expectedRestartMarker else {
            return false
        }

        return expectedRestartMarker.createdAt >= marker.launchedAt.addingTimeInterval(-5)
    }

    private func writeSessionMarker(now: Date) {
        let marker = SessionMarker(
            sessionID: UUID(),
            launchedAt: now,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )

        do {
            try fileManager.createDirectory(
                at: sessionMarkerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(marker).write(to: sessionMarkerURL, options: .atomic)
        } catch {
            // Crash monitoring must not become a source of crashes.
        }
    }

    private func writeRecoveryReport(for marker: SessionMarker, detectedAt: Date) -> CrashRecoveryReport? {
        do {
            try fileManager.createDirectory(at: crashReportsDirectory, withIntermediateDirectories: true)

            let reportURL = crashReportsDirectory.appendingPathComponent(
                "ShuoCrash-\(Self.fileTimestampString(for: detectedAt)).txt"
            )
            let diagnosticReportURL = recentSystemDiagnosticReport(since: marker.launchedAt)
            let reportText = recoveryReportText(
                marker: marker,
                detectedAt: detectedAt,
                reportURL: reportURL,
                diagnosticReportURL: diagnosticReportURL
            )

            try reportText.write(to: reportURL, atomically: true, encoding: .utf8)
            return CrashRecoveryReport(reportURL: reportURL, reportText: reportText)
        } catch {
            return nil
        }
    }

    private func recoveryReportText(
        marker: SessionMarker,
        detectedAt: Date,
        reportURL: URL,
        diagnosticReportURL: URL?
    ) -> String {
        let diagnosticReportLine = diagnosticReportURL?.path ?? "Not found"

        return """
        Shuo Crash Recovery Report
        ==========================

        Reason: Previous Shuo session did not exit cleanly.
        Detected At: \(Self.iso8601String(for: detectedAt))
        Report File: \(reportURL.path)
        macOS Diagnostic Report: \(diagnosticReportLine)

        Previous Session
        ----------------
        Session ID: \(marker.sessionID.uuidString)
        Launched At: \(Self.iso8601String(for: marker.launchedAt))
        Process ID: \(marker.processIdentifier)
        App Version: \(marker.appVersion)
        Build Number: \(marker.buildNumber)
        OS Version: \(marker.operatingSystemVersion)

        Notes
        -----
        This report is generated on the next launch after an unclean exit. If macOS produced a .ips or .crash file for Shuo, the path is listed above.
        """
    }

    private func recentSystemDiagnosticReport(since launchDate: Date) -> URL? {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let diagnosticDirectories = [
            homeDirectory.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Logs/CrashReporter", isDirectory: true)
        ]

        let candidates = diagnosticDirectories.flatMap { directory -> [URL] in
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return urls.filter { url in
                let filename = url.lastPathComponent.lowercased()
                guard filename.contains("shuo"),
                      filename.hasSuffix(".ips") || filename.hasSuffix(".crash") else {
                    return false
                }

                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return (modifiedAt ?? .distantPast) >= launchDate.addingTimeInterval(-30)
            }
        }

        return candidates.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }.first
    }

    private static func iso8601String(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func fileTimestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
