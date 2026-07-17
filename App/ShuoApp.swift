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
#if DIRECT_DISTRIBUTION
        if !AppRuntime.isRunningUnderXCTest,
           MachineUpdateCoordinator.shared.shouldBlockLaunch(
               currentBuildVersion: MachineUpdateCoordinator.currentBuildVersion
           ) {
            DispatchQueue.main.async { [weak self] in
                self?.presentBlockedLaunchAlertAndTerminate()
            }
            return
        }
#endif

        appState?.startUpdateController()
        if let appState {
            AppDockIconController.apply(showDockIcon: appState.settings.showDockIcon)
        }

        // NSStatusItem talks to the system menu bar through AppKit/SkyLight.  A
        // SwiftUI App initializer runs before that connection is reliably ready
        // on every launch path, so create the controller only after launch has
        // completed and yielded once to the main event loop.
        DispatchQueue.main.async { [weak self] in
            self?.installStatusItemControllerAfterLaunch()
        }
    }

#if DIRECT_DISTRIBUTION
    private func presentBlockedLaunchAlertAndTerminate() {
        let copy = MachineUpdateCoordinator.blockedLaunchCopy
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = copy.title
        alert.informativeText = copy.detail
        alert.addButton(withTitle: copy.button)
        alert.runModal()
        NSApp.terminate(nil)
    }
#endif

    private func installStatusItemControllerAfterLaunch() {
        guard statusItemController == nil, let appState else {
            return
        }

        statusItemController = StatusItemController(appState: appState)

        if appState.shouldShowOnboarding {
            statusItemController?.showMainPanelFromExternalActivation()
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
    @StateObject private var appState: AppState

    init() {
        let singleInstanceGuard = SingleInstanceGuard.shared
        singleInstanceGuard.acquireOrActivateExistingAndExit()
        self.singleInstanceGuard = singleInstanceGuard

        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)
        appDelegate.appState = appState
    }

    var body: some Scene {
        Settings {
            AppPanelView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(AppLocalizer(language: appState.settings.appLanguage).aboutAppLabel()) {
                    appDelegate.statusItemController?.showMainPanelFromExternalActivation(selectedSection: .about)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button(AppLocalizer(language: appState.settings.appLanguage).text(.settings)) {
                    appDelegate.statusItemController?.showMainPanelFromExternalActivation(selectedSection: .transcription)
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
