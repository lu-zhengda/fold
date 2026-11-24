import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class FoldSettings: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginError: String?
    @Published private(set) var installsAutomatically = false
    @Published private(set) var canCheck = false

    init() {
        let updater = controller.updater
        // Earlier versions allowed scheduled checks without automatic installation.
        if updater.automaticallyChecksForUpdates && !updater.automaticallyDownloadsUpdates {
            updater.automaticallyChecksForUpdates = false
        }
        controller.startUpdater()
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$installsAutomatically)
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    func setStartAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { loginError = error.localizedDescription }
        refreshLoginStatus()
    }

    func setAutomaticInstallation(_ enabled: Bool) {
        let updater = controller.updater
        // Sparkle accepts a download preference only while checks are enabled.
        if enabled {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
        } else {
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = false
        }
    }

    func checkNow() { controller.checkForUpdates(nil) }
}

struct FoldSettingsView: View {
    @ObservedObject var settings: FoldSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start at login", isOn: Binding(
                    get: { settings.loginStatus == .enabled || settings.loginStatus == .requiresApproval },
                    set: settings.setStartAtLogin
                ))
                if settings.loginStatus == .requiresApproval {
                    Button("Allow Fold in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = settings.loginError { Text(error).foregroundStyle(.secondary) }
            }
            Section("Updates") {
                Toggle("Automatically install updates", isOn: Binding(
                    get: { settings.installsAutomatically },
                    set: settings.setAutomaticInstallation
                ))
                LabeledContent("Fold " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")) {
                    Button("Check for Updates…", action: settings.checkNow).disabled(!settings.canCheck)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { settings.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLoginStatus()
        }
    }
}
