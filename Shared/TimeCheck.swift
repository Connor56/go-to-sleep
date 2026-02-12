import Foundation

enum TimeCheck {
    private static let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    /// Check if the current time falls within a bedtime window.
    /// Handles the midnight-crossing case (e.g., startHour=21, endHour=7 means 9 PM to 7 AM).
    static func isWithinBedtimeWindow(startHour: Int, endHour: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        print("\(debugMarker) isWithinBedtimeWindow called start=\(startHour) end=\(endHour) nowHour=\(hour)")

        if startHour <= endHour {
            // Simple case: e.g., 8 AM to 5 PM
            let isWithinWindow = hour >= startHour && hour < endHour
            print("\(debugMarker) isWithinBedtimeWindow simpleCase result=\(isWithinWindow)")
            return isWithinWindow
        } else {
            // Midnight-crossing case: e.g., 9 PM to 7 AM
            let isWithinWindow = hour >= startHour || hour < endHour
            print("\(debugMarker) isWithinBedtimeWindow overnightCase result=\(isWithinWindow)")
            return isWithinWindow
        }
    }
}
