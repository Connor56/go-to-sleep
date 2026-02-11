import SwiftUI

@main
struct GoToSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("Go To Sleep", systemImage: "moon.fill") {
            MenuBarView()
        }

        Settings {
            SettingsView()
        }
    }
}
