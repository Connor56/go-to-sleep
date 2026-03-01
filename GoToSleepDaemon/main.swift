import AppKit
import Foundation

let showOverlayNotificationName = Notification.Name("com.gotosleep.showOverlayNow")
let dismissOverlayNotificationName = Notification.Name("come.gotosleep.dismissOverlayNow")

// MARK: - Main loop

func main() {
  Paths.ensureDirectoryExists()
  // print("[GoToSleepDaemon] Started at \(Date())")

  var killTimestamps: [Date] = []

  while true {
    // Still process events whilst waiting for 10 seconds
    // This method is compatible with older macOS versions.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 10))

    let timestamp = Date()
    // print("[GoToSleepDaemon] Running, and time is \(timestamp)")

    let settings = readSettings()

    guard
      TimeCheck.isWithinBedtimeWindow(
        startHour: settings.bedtimeStartHour,
        endHour: settings.bedtimeEndHour
      )
    else {
      // If the main app is running, dismiss the overlay
      if isMainAppRunning() {
        // print(
        //   "[GoToSleepDaemon] Main app already running - dismissing overlay"
        // )
        requestOverlayDismissalFromRunningApp()
      }
      continue
    }

    // Check grace period — was a session completed recently?
    if let completedDate = Paths.readTimestamp(from: Paths.sessionCompletedPath) {
      let elapsed = Date().timeIntervalSince(completedDate)
      let gracePeriod = TimeInterval(settings.gracePeriodMinutes * 60)
      if elapsed < gracePeriod {
        continue
      }
    }

    // If the main app is running (menu bar mode), tell it to show the overlay.
    if isMainAppRunning() {
      // print(
      //   "[GoToSleepDaemon] Main app already running — requesting overlay via distributed notification"
      // )
      requestOverlayFromRunningApp()
      continue
    }

    // Launch the main app with --bedtime flag
    // print("[GoToSleepDaemon] Bedtime — launching main app")
    let exitedCleanly = launchAndMonitor()

    if !exitedCleanly {
      // App exited without writing completion marker — it was killed
      let now = Date()
      killTimestamps.append(now)
      logKill(timestamps: killTimestamps)

      // Clean up stale timestamps (keep last 10 minutes)
      killTimestamps = killTimestamps.filter { now.timeIntervalSince($0) < 600 }

      print("[GoToSleepDaemon] App killed (\(killTimestamps.count) kills in last 10 min)")

      // Safety valve: 5 kills in 10 minutes = automatic grace period
      if killTimestamps.count >= 5 {
        print("[GoToSleepDaemon] Safety valve triggered — granting grace period")
        Paths.writeTimestamp(to: Paths.sessionCompletedPath)
        killTimestamps.removeAll()
      }
    } else {
      // print("[GoToSleepDaemon] Session completed normally")
    }
  }
}

// MARK: - Settings

struct DaemonSettings {
  var isEnabled: Bool
  var bedtimeStartHour: Int
  var bedtimeEndHour: Int
  var gracePeriodMinutes: Int
}

func readSettings() -> DaemonSettings {
  let defaults = UserDefaults(suiteName: "com.gotosleep.shared")
  return DaemonSettings(
    isEnabled: defaults?.object(forKey: "isEnabled") as? Bool ?? true,
    bedtimeStartHour: defaults?.object(forKey: "bedtimeStartHour") as? Int ?? 21,
    bedtimeEndHour: defaults?.object(forKey: "bedtimeEndHour") as? Int ?? 7,
    gracePeriodMinutes: defaults?.object(forKey: "gracePeriodMinutes") as? Int ?? 60
  )
}

// MARK: - Process management

func resolveMainAppPath() -> String? {
  // The daemon binary lives at:
  //   GoToSleep.app/Contents/Library/LaunchDaemons/GoToSleepDaemon
  // (or similar path inside the bundle)
  // The main app binary lives at:
  //   GoToSleep.app/Contents/MacOS/GoToSleep
  let daemonPath = ProcessInfo.processInfo.arguments[0]
  let url = URL(fileURLWithPath: daemonPath)

  // Walk up to find the .app bundle
  var current = url.deletingLastPathComponent()
  for _ in 0..<10 {
    if current.lastPathComponent.hasSuffix(".app") {
      return current.appendingPathComponent("Contents/MacOS/GoToSleep").path
    }
    current = current.deletingLastPathComponent()
  }

  // Fallback: try to find it by bundle identifier
  if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.gotosleep.app") {
    return appURL.appendingPathComponent("Contents/MacOS/GoToSleep").path
  }

  return nil
}

func isMainAppRunning() -> Bool {
  let apps = NSWorkspace.shared.runningApplications
  return apps.contains { $0.bundleIdentifier == "com.gotosleep.app" }
}

func requestOverlayFromRunningApp() {
  DistributedNotificationCenter.default().post(
    name: showOverlayNotificationName,
    object: "com.gotosleep.app"
  )
}

func requestOverlayDismissalFromRunningApp() {
  DistributedNotificationCenter.default().post(
    name: dismissOverlayNotificationName,
    object: "com.gotosleep.app"
  )
}

/// Launch the main app and wait for it to exit.
/// Returns true if the session was completed (marker file exists), false if killed.
func launchAndMonitor() -> Bool {
  // Remove any stale completion marker
  Paths.removeFile(at: Paths.sessionCompletedPath)

  guard let appPath = resolveMainAppPath() else {
    print("[GoToSleepDaemon] ERROR: Cannot find main app binary")
    return true  // don't count as a kill
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: appPath)
  process.arguments = ["--bedtime"]

  do {
    try process.run()
  } catch {
    print("[GoToSleepDaemon] ERROR: Failed to launch main app: \(error)")
    return true
  }

  process.waitUntilExit()

  // Check if completion marker was written
  return Paths.fileExists(at: Paths.sessionCompletedPath)
}

// MARK: - Kill logging

func logKill(timestamps: [Date]) {
  let intervals = timestamps.map { $0.timeIntervalSince1970 }
  if let data = try? JSONEncoder().encode(intervals) {
    try? data.write(to: Paths.killLogPath)
  }
}

// MARK: - Entry point

main()
