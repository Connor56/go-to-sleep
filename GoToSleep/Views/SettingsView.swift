import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"

    private let gracePeriodOptions = [
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 hour"),
        (120, "2 hours"),
    ]

    var body: some View {
        Form {
            Section("Schedule") {
                Toggle("Enabled", isOn: $settings.isEnabled)

                Picker("Bedtime starts at", selection: $settings.bedtimeStartHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }

                Picker("Bedtime ends at", selection: $settings.bedtimeEndHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
            }

            Section("Questions") {
                Stepper("Questions per session: \(settings.questionsPerSession)",
                        value: $settings.questionsPerSession, in: 1...10)
            }

            Section("After Completion") {
                Picker("Grace period", selection: $settings.gracePeriodMinutes) {
                    ForEach(gracePeriodOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .onAppear {
            print("\(debugMarker) SettingsView appeared")
        }
        .onChange(of: settings.isEnabled) { newValue in
            print("\(debugMarker) settings.isEnabled changed -> \(newValue)")
        }
        .onChange(of: settings.bedtimeStartHour) { newValue in
            print("\(debugMarker) settings.bedtimeStartHour changed -> \(newValue)")
        }
        .onChange(of: settings.bedtimeEndHour) { newValue in
            print("\(debugMarker) settings.bedtimeEndHour changed -> \(newValue)")
        }
        .onChange(of: settings.questionsPerSession) { newValue in
            print("\(debugMarker) settings.questionsPerSession changed -> \(newValue)")
        }
        .onChange(of: settings.gracePeriodMinutes) { newValue in
            print("\(debugMarker) settings.gracePeriodMinutes changed -> \(newValue)")
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
