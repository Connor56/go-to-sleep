import SwiftUI

struct SettingsView: View {

  @AppStorage(
    "requestedSettingsChangeTimestamp", store: UserDefaults(suiteName: AppSettings.suiteName))
  private var requestedSettingsChangeTimestamp: Int = 0

  private let twentyMinutesInSeconds: Int = 1200

  func inAlterationWindow(currentTime: Int, start: Int, end: Int) -> Bool {
    let afterStart = currentTime >= start
    let beforeEnd = currentTime <= end

    if afterStart && beforeEnd {
      return true
    }

    return false
  }

  @State private var tickCount = 0

  var body: some View {
    let settingsAlterationWindowStart = requestedSettingsChangeTimestamp + twentyMinutesInSeconds
    let settingsAlterationWindowEnd = requestedSettingsChangeTimestamp + 2 * twentyMinutesInSeconds
    let currentTimestamp = Int(Date().timeIntervalSince1970)

    let showUnlocked = inAlterationWindow(
      currentTime: currentTimestamp, start: settingsAlterationWindowStart,
      end: settingsAlterationWindowEnd)

    Group {
      if showUnlocked {
        UnlockedSettingsView()
      } else {
        LockedSettingsView(startTime: settingsAlterationWindowStart, currentTime: currentTimestamp)
      }
    }
    .frame(width: 400, height: 500)
    .id(tickCount)
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
      tickCount += 1
    }
  }
}

struct UnlockedSettingsView: View {
  @AppStorage(
    "requestedSettingsChangeTimestamp", store: UserDefaults(suiteName: AppSettings.suiteName))
  private var requestedSettingsChangeTimestamp: Int = 0

  @ObservedObject private var settings = AppSettings.shared
  private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"

  private let gracePeriodOptions = [
    (15, "15 minutes"),
    (30, "30 minutes"),
    (60, "1 hour"),
    (120, "2 hours"),
  ]

  var body: some View {
    VStack {
      Text("Settings")
        .padding(.bottom, 32)
        .font(.title)

      Form {
        Section {
          Picker("Bedtime starts at", selection: $settings.bedtimeStartHour) {
            ForEach(0..<24, id: \.self) { hour in
              Text(formatHour(hour)).tag(hour)
            }
          }

          Picker("Bedtime ends at", selection: $settings.bedtimeEndHour) {
            ForEach(0..<24, id: \.self) { hour in
              Text(formatHour(hour)).tag(hour)
            }
          }.padding(.bottom, 32)
        } header: {
          Text("Schedule")
            .font(.title3)
            .fontWeight(.semibold)

        }

        Section {
          Stepper(
            "Questions per session: \(settings.questionsPerSession)",
            value: $settings.questionsPerSession, in: 1...10
          ).padding(.bottom, 32)
        } header: {
          Text("Questions")
            .font(.title3)
            .fontWeight(.semibold)
        }

        Section {
          SkillTagTogglesView()
            .padding(.bottom, 32)
        } header: {
          Text("Question Skills")
            .font(.title3)
            .fontWeight(.semibold)
        }

        Section {
          Picker("Grace period", selection: $settings.gracePeriodMinutes) {
            ForEach(gracePeriodOptions, id: \.0) { value, label in
              Text(label).tag(value)
            }
          }.padding(.bottom, 32)
        } header: {
          Text("After Completion")
            .font(.title3)
            .fontWeight(.semibold)
        }
      }
      .padding(.horizontal, 32)

      Button("Lock Settings") {
        requestedSettingsChangeTimestamp = 0
      }
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

struct SkillTagTogglesView: View {
  @ObservedObject private var settings = AppSettings.shared
  private let store = QuestionStore()

  var body: some View {
    let allTags = store.allAvailableTags.sorted()
    let enabledTags = settings.getEnabledTags()

    if allTags.isEmpty {
      Text("No calculation questions available")
        .foregroundColor(.secondary)
    } else {
      ForEach(allTags, id: \.self) { tag in
        Toggle(
          friendlyName(for: tag),
          isOn: Binding(
            get: { enabledTags.contains(tag) },
            set: { enabled in
              var tags = settings.getEnabledTags()
              if enabled { tags.insert(tag) } else { tags.remove(tag) }
              settings.setEnabledTags(tags)
            }
          ))
      }
    }
  }

  private func friendlyName(for tag: String) -> String {
    tag.split(separator: "-")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
  }
}

struct LockedSettingsView: View {
  @AppStorage(
    "requestedSettingsChangeTimestamp", store: UserDefaults(suiteName: AppSettings.suiteName))
  private var requestedSettingsChangeTimestamp: Int = 0

  let startTime: Int

  let currentTime: Int

  var body: some View {
    VStack {
      Image(systemName: "lock.fill")
        .font(.system(size: 32))
        .foregroundColor(.secondary)

      Text("Settings are locked")
        .font(.title)
        .padding(.bottom, 16)

      if startTime > currentTime {
        Text("Opens in \(startTime - currentTime) seconds")
          .padding(.bottom, 16)

        Button("Cancel Request") {
          requestedSettingsChangeTimestamp = 0
        }
      } else {
        Text("On request, settings will open after 20 minutes, and stay open for 20 minutes.")
          .padding(.horizontal, 32)
          .padding(.bottom, 16)
          .multilineTextAlignment(.center)

        Button("Request Change") {
          requestedSettingsChangeTimestamp = currentTime
        }
      }
    }
  }
}
