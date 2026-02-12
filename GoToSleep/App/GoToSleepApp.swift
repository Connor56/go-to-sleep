import SwiftUI

@main
struct GoToSleepApp: App {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    init() {
        print("\(debugMarker) GoToSleepApp initialized")
    }

    var body: some Scene {
        MenuBarExtra("Go To Sleep", systemImage: "moon.fill") {
            MenuBarView(appDelegate: appDelegate)
                .onAppear {
                    print("\(debugMarker) MenuBarExtra content appeared")
                }
        }

        Settings {
            SettingsView()
                .onAppear {
                    print("\(debugMarker) Settings scene appeared")
                }
        }
    }
}
