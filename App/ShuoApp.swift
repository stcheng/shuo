import SwiftUI

@MainActor
final class ShuoApplicationDelegate: NSObject, NSApplicationDelegate {
    var statusItemController: StatusItemController?
    var appState: AppState?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.showMainPanelFromExternalActivation()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        statusItemController?.handleApplicationDidBecomeActive()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState?.startUpdateController()
        if appState?.shouldShowOnboarding == true {
            DispatchQueue.main.async { [weak self] in
                self?.statusItemController?.showMainPanelFromExternalActivation()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.markCleanExit()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appState?.shouldAllowApplicationTermination() == false
            ? .terminateCancel
            : .terminateNow
    }
}

@main
struct ShuoApp: App {
    @NSApplicationDelegateAdaptor(ShuoApplicationDelegate.self) private var appDelegate

    private let singleInstanceGuard: SingleInstanceGuard
    private let statusItemController: StatusItemController
    @StateObject private var appState: AppState

    init() {
#if DIRECT_DISTRIBUTION
        if !AppRuntime.isRunningUnderXCTest,
           MachineUpdateCoordinator.shared.shouldBlockLaunch(
               currentBuildVersion: MachineUpdateCoordinator.currentBuildVersion
           ) {
            let copy = MachineUpdateCoordinator.blockedLaunchCopy
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = copy.title
            alert.informativeText = copy.detail
            alert.addButton(withTitle: copy.button)
            alert.runModal()
            exit(0)
        }
#endif
        let singleInstanceGuard = SingleInstanceGuard.shared
        singleInstanceGuard.acquireOrActivateExistingAndExit()
        self.singleInstanceGuard = singleInstanceGuard

        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)
        let statusItemController = StatusItemController(appState: appState)
        self.statusItemController = statusItemController
        appDelegate.appState = appState
        appDelegate.statusItemController = statusItemController
    }

    var body: some Scene {
        Settings {
            AppPanelView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(AppLocalizer(language: appState.settings.appLanguage).aboutAppLabel()) {
                    statusItemController.showMainPanelFromExternalActivation(selectedSection: .about)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button(AppLocalizer(language: appState.settings.appLanguage).text(.settings)) {
                    statusItemController.showMainPanelFromExternalActivation(selectedSection: .transcription)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            if appState.supportsDirectUpdates {
                CommandGroup(after: .appInfo) {
                    Button(AppLocalizer(language: appState.settings.appLanguage).text(.checkForUpdates)) {
                        appState.checkForUpdates()
                    }
                    .disabled(!appState.canCheckForUpdates)
                }
            }
        }
    }
}
