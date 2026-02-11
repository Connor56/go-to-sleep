import Foundation

enum TimeCheck {
    /// Check if the current time falls within a bedtime window.
    /// Handles the midnight-crossing case (e.g., startHour=21, endHour=7 means 9 PM to 7 AM).
    static func isWithinBedtimeWindow(startHour: Int, endHour: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        if startHour <= endHour {
            // Simple case: e.g., 8 AM to 5 PM
            return hour >= startHour && hour < endHour
        } else {
            // Midnight-crossing case: e.g., 9 PM to 7 AM
            return hour >= startHour || hour < endHour
        }
    }
}
