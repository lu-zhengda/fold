import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class FoldSettings: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginError: String?
    @Published private(set) var checksAutomatically = false
    @Published private(set) var installsAutomatically = false
    @Published private(set) var canCheck = false

    init() {
        let updater = controller.updater
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$checksAutomatically)
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

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticInstallation(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
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
                Toggle("Automatically check for updates", isOn: Binding(get: { settings.checksAutomatically }, set: settings.setAutomaticChecks))
                Toggle("Automatically install updates", isOn: Binding(
                    get: { settings.checksAutomatically && settings.installsAutomatically },
                    set: settings.setAutomaticInstallation
                )).disabled(!settings.checksAutomatically)
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
