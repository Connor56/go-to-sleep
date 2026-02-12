import SwiftUI
import AppKit

struct PermissionsGuideView: View {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    @ObservedObject private var settings = AppSettings.shared
    @State private var accessibilityGranted = false
    @State private var daemonRegistered = false

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Welcome to Go To Sleep")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("A couple of things to set up before bedtime.")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 20) {
                // Step 1: Accessibility
                HStack(spacing: 12) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(accessibilityGranted ? .green : .secondary)
                        .font(.title2)

                    VStack(alignment: .leading) {
                        Text("Grant Accessibility Permission")
                            .fontWeight(.medium)
                        Text("Required for kiosk mode (full-screen lock).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !accessibilityGranted {
                        Button("Open Settings") {
                            requestAccessibility()
                        }
                    }
                }

                // Step 2: Daemon
                HStack(spacing: 12) {
                    Image(systemName: daemonRegistered ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(daemonRegistered ? .green : .secondary)
                        .font(.title2)

                    VStack(alignment: .leading) {
                        Text("Enable Background Daemon")
                            .fontWeight(.medium)
                        Text("Keeps the app persistent during bedtime hours.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !daemonRegistered {
                        Button("Enable") {
                            registerDaemon()
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .frame(maxWidth: 450)

            HStack(spacing: 16) {
                Button("Check Again") {
                    checkStatus()
                }

                Button("Done") {
                    settings.hasCompletedSetup = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!accessibilityGranted)
            }
        }
        .padding(40)
        .frame(width: 540, height: 480)
        .onAppear {
            print("\(debugMarker) PermissionsGuideView appeared")
            checkStatus()
        }
    }

    private func requestAccessibility() {
        print("\(debugMarker) requestAccessibility called")
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        // Give the user a moment, then re-check
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("\(debugMarker) requestAccessibility delayed status check")
            checkStatus()
        }
    }

    private func registerDaemon() {
        print("\(debugMarker) registerDaemon called from setup guide")
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.registerDaemon()
            daemonRegistered = true
            print("\(debugMarker) daemonRegistered set to true")
        } else {
            print("\(debugMarker) ERROR: NSApp.delegate is not AppDelegate in registerDaemon")
        }
    }

    private func checkStatus() {
        accessibilityGranted = AXIsProcessTrusted()
        print("\(debugMarker) checkStatus accessibilityGranted=\(accessibilityGranted)")
    }
}
