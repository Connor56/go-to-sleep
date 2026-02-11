import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 4) {
            Toggle("Enabled", isOn: $settings.isEnabled)

            Divider()

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Button("Test Overlay") {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.showOverlay()
                }
            }

            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var statusText: String {
        if !settings.isEnabled {
            return "Disabled"
        }

        let start = formatHour(settings.bedtimeStartHour)
        let end = formatHour(settings.bedtimeEndHour)

        if TimeCheck.isWithinBedtimeWindow(startHour: settings.bedtimeStartHour,
                                            endHour: settings.bedtimeEndHour) {
            return "Bedtime active (\(start)–\(end))"
        } else {
            return "Next bedtime: \(start)–\(end)"
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
