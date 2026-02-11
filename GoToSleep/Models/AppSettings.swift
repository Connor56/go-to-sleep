import SwiftUI

/// Central settings store using @AppStorage backed by a shared UserDefaults suite.
/// The shared suite ("com.gotosleep.app") lets the daemon read these settings too.
class AppSettings: ObservableObject {
    static let suiteName = "com.gotosleep.app"
    static let shared = AppSettings()

    @AppStorage("questionsPerSession", store: UserDefaults(suiteName: suiteName))
    var questionsPerSession: Int = 3

    @AppStorage("gracePeriodMinutes", store: UserDefaults(suiteName: suiteName))
    var gracePeriodMinutes: Int = 60

    @AppStorage("bedtimeStartHour", store: UserDefaults(suiteName: suiteName))
    var bedtimeStartHour: Int = 21

    @AppStorage("bedtimeEndHour", store: UserDefaults(suiteName: suiteName))
    var bedtimeEndHour: Int = 7

    @AppStorage("isEnabled", store: UserDefaults(suiteName: suiteName))
    var isEnabled: Bool = true

    @AppStorage("hasCompletedSetup", store: UserDefaults(suiteName: suiteName))
    var hasCompletedSetup: Bool = false
}
