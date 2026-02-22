# Code Signing and Notarisation

This tutorial explains the full chain of trust for distributing a macOS app
outside the Mac App Store: what code signing is, what notarisation is, how to
set them up, and how likely Go To Sleep is to pass Apple's notarisation checks.

---

## The Three Layers of macOS App Trust

When a user downloads and opens your app, macOS checks three things in order:

### 1. Code signing

"Was this app built by a known developer?"

Every app is signed with a cryptographic certificate. macOS checks that the
binary hasn't been tampered with and traces the signature back to a known
identity. There are several levels:

| Signing type | Who can use it | What it means to macOS |
|---|---|---|
| **Unsigned** | Anyone | macOS refuses to open it (Gatekeeper blocks it) |
| **Ad-hoc** | Anyone (no account needed) | Only runs on the machine that built it |
| **Apple Development** | Free Apple ID | Runs on your machine during development |
| **Developer ID Application** | Paid Developer Program ($99/yr) | Trusted for distribution outside the App Store |

You currently have ad-hoc signing. For distribution, you need "Developer ID
Application".

### 2. Notarisation

"Has Apple scanned this app and found nothing malicious?"

Notarisation is an automated process where you upload your signed app to Apple.
Their servers scan it for malware, known-bad code patterns, and policy
violations. If it passes, Apple issues a "ticket" that gets stapled to your app.

Notarisation is **not** App Review. There's no human reviewer. It's an
automated scan that typically takes 1–15 minutes. It checks for:

- Valid Developer ID signature
- Hardened Runtime enabled
- No embedded malware signatures
- No private API usage (that they can detect)
- All executables and dylibs are signed

### 3. Gatekeeper

"Should I let this app run?"

Gatekeeper is the macOS subsystem that enforces all of this. When a user opens
a downloaded app, Gatekeeper checks:

1. Is it code signed with a Developer ID? If not → blocked.
2. Is it notarised? If not → warning dialog ("can't check for malicious
   software").
3. Has it been tampered with since signing? If yes → blocked.

If all three pass, the app opens silently with no warnings.

---

## What You Need to Get Started

### Apple Developer Program membership

**Cost:** $99 USD/year.
**Sign up:** https://developer.apple.com/programs/

This gives you access to:
- Developer ID certificates (for signing apps distributed outside the App Store)
- Notarisation service
- Access to beta OS releases, developer forums, etc.

You do **not** need this for the Mac App Store path (which requires a different
certificate type), and Go To Sleep can't go on the Mac App Store anyway because
it disables sandboxing.

### Xcode command line tools

You already have these if you're building with `xcodebuild`.

---

## Step 1: Create a Developer ID Certificate

After enrolling in the Developer Program:

1. Open Xcode.
2. Go to **Xcode > Settings > Accounts**.
3. Select your Apple ID, then select your team.
4. Click **Manage Certificates**.
5. Click the **+** button and choose **Developer ID Application**.

Xcode creates the certificate and installs it in your Keychain. You can verify
it exists:

```bash
security find-identity -v -p codesigning
```

You should see an entry like:

```
"Developer ID Application: Your Name (TEAMID1234)"
```

Note your **Team ID** (the alphanumeric string in parentheses). You'll need it.

---

## Step 2: Enable Hardened Runtime

Notarisation requires Hardened Runtime. This restricts what your app can do at
runtime (no code injection, no unsigned memory execution, etc.) unless you
explicitly opt in via entitlements.

### In the pbxproj

Add this build setting to both the GoToSleep **and** GoToSleepDaemon target
configurations (Debug and Release):

```
ENABLE_HARDENED_RUNTIME = YES;
```

For example, in the GoToSleep Release config (`D100000002`), add it alongside
the existing settings:

```
D100000002 /* Release */ = {
    isa = XCBuildConfiguration;
    buildSettings = {
        ...
        ENABLE_HARDENED_RUNTIME = YES;
        ...
    };
    name = Release;
};
```

Do the same for `D100000001` (GoToSleep Debug), `D200000001` (Daemon Debug),
and `D200000002` (Daemon Release).

### Entitlements you may need

Hardened Runtime disables certain capabilities by default. If the app crashes
after enabling it, you may need to add entitlements. Edit
`GoToSleep/GoToSleep.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

The `automation.apple-events` entitlement may be needed because the daemon uses
`NSWorkspace` APIs and launches processes. Test with Hardened Runtime enabled
and add entitlements only if something breaks — don't add them preemptively.

---

## Step 3: Sign with Developer ID

### Update the pbxproj for manual signing

Change the code signing settings in the **Release** configurations for both
targets. You can leave Debug as automatic.

For GoToSleep Release (`D100000002`):

```
CODE_SIGN_STYLE = Manual;
CODE_SIGN_IDENTITY = "Developer ID Application";
DEVELOPMENT_TEAM = YOUR_TEAM_ID;
```

For GoToSleepDaemon Release (`D200000002`):

```
CODE_SIGN_STYLE = Manual;
CODE_SIGN_IDENTITY = "Developer ID Application";
DEVELOPMENT_TEAM = YOUR_TEAM_ID;
```

Replace `YOUR_TEAM_ID` with your actual Team ID from Step 1.

### Build for release

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Release \
  clean build
```

### Verify the signature

```bash
codesign -dvvv build/Build/Products/Release/GoToSleep.app
```

You should see:

```
Authority=Developer ID Application: Your Name (TEAMID)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
```

That's a full chain of trust — your cert, Apple's intermediate cert, Apple's
root cert.

Also verify the embedded daemon:

```bash
codesign -dvvv build/Build/Products/Release/GoToSleep.app/Contents/MacOS/GoToSleepDaemon
```

---

## Step 4: Notarise the App

### Create a .zip or .dmg for upload

Notarisation accepts `.zip`, `.dmg`, or `.pkg` files. If you've already built a
`.dmg` (from tutorial 006), use that. Otherwise, zip the app:

```bash
cd build/Build/Products/Release
zip -r GoToSleep.zip GoToSleep.app
cd -
```

### Store your App Store Connect credentials

Notarisation authenticates via an app-specific password. Create one at
https://appleid.apple.com (Sign In > App-Specific Passwords).

Store it in your Keychain so you don't have to paste it every time:

```bash
xcrun notarytool store-credentials "GoToSleep-notary" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "your-app-specific-password"
```

This saves the credentials under the profile name "GoToSleep-notary".

### Submit for notarisation

```bash
xcrun notarytool submit GoToSleep-1.0.dmg \
  --keychain-profile "GoToSleep-notary" \
  --wait
```

The `--wait` flag makes it block until Apple's servers return a result.
Typically takes 1–15 minutes. You'll see output like:

```
Conducting pre-submission checks for GoToSleep-1.0.dmg...
Uploading... done
Waiting for processing to complete...
Processing complete
  id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  status: Accepted
```

If it fails, get the full log:

```bash
xcrun notarytool log <submission-id> \
  --keychain-profile "GoToSleep-notary"
```

This returns a JSON report telling you exactly what failed and why.

### Staple the ticket

After notarisation succeeds, "staple" the ticket to your `.dmg` so it works
offline (users don't need an internet connection for Gatekeeper to verify it):

```bash
xcrun stapler staple GoToSleep-1.0.dmg
```

Verify the staple:

```bash
xcrun stapler validate GoToSleep-1.0.dmg
```

---

## Step 5: Distribute

Your `GoToSleep-1.0.dmg` is now signed, notarised, and stapled. When any user
downloads it and opens the app, macOS will:

1. Check the Developer ID signature — valid.
2. Check the notarisation ticket — present and valid.
3. Open the app with no warnings or Gatekeeper dialogs.

---

## Will Go To Sleep Pass Notarisation?

Here's an honest assessment of each aspect of the app:

### Things that are fine

| Aspect | Status | Notes |
|--------|--------|-------|
| Pure Swift code | Pass | No private API calls detected |
| NSWorkspace APIs | Pass | Public API, commonly used |
| UserDefaults | Pass | Standard framework |
| FileManager operations | Pass | Standard framework |
| DistributedNotificationCenter | Pass | Public API |
| Process (launching daemon) | Pass | Public API |
| Bundle resources (JSON, assets) | Pass | No issues |

### Things that need attention

| Aspect | Risk | Notes |
|--------|------|-------|
| **Sandbox disabled** | Low risk for notarisation | Notarisation doesn't require sandboxing. Plenty of notarised apps run unsandboxed (VS Code, iTerm, Alfred, etc.). This only blocks Mac App Store distribution. |
| **Presentation options (kiosk mode)** | Low risk | `.disableProcessSwitching`, `.disableForceQuit`, `.disableSessionTermination` are all public AppKit APIs. They're unusual but not prohibited. Apple uses them in their own apps (Classroom.app, for example). |
| **launchctl load/unload** | Medium risk | Calling `/bin/launchctl` via `Process()` is a common pattern but could potentially trigger a warning. The Hardened Runtime may require the `com.apple.security.automation.apple-events` entitlement for this to work. Test this. |
| **Hardened Runtime compatibility** | Test required | The kiosk mode presentation options, process launching, and `AXIsProcessTrusted` calls should all work under Hardened Runtime, but test to confirm nothing breaks. |

### Things that will definitely NOT block notarisation

- **Disabled sandbox** — Notarisation is separate from sandboxing. Apple
  explicitly supports notarisation of unsandboxed apps.
- **Accessibility APIs** — `AXIsProcessTrusted()` is a public API. You're
  checking for permission, not bypassing it.
- **Kiosk behaviour** — The presentation options are public API. Apple won't
  reject an app for using them. They exist specifically for apps like this.
- **Background daemon** — LaunchAgents are a supported macOS feature.

### Overall likelihood

**High probability of passing.** The app uses only public APIs, doesn't load
any third-party libraries or frameworks, doesn't use JIT compilation, doesn't
inject code into other processes, and doesn't do anything that would trigger
Apple's malware heuristics.

The main thing to watch for is Hardened Runtime compatibility — enable it, build,
and run through the full flow (menu bar, settings, overlay, daemon registration)
to make sure nothing breaks before submitting.

---

## Quick Reference: Full Notarisation Flow

```bash
# 1. Build with Developer ID signing
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Release \
  clean build

# 2. Stage and create .dmg
rm -rf dmg-staging
mkdir -p dmg-staging
cp -R build/Build/Products/Release/GoToSleep.app dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create \
  -volname "Go To Sleep" \
  -srcfolder dmg-staging \
  -ov \
  -format UDZO \
  GoToSleep-1.0.dmg

# 3. Submit for notarisation
xcrun notarytool submit GoToSleep-1.0.dmg \
  --keychain-profile "GoToSleep-notary" \
  --wait

# 4. Staple the ticket
xcrun stapler staple GoToSleep-1.0.dmg

# 5. Verify
xcrun stapler validate GoToSleep-1.0.dmg
spctl -a -t open --context context:primary-signature GoToSleep-1.0.dmg
```

---

## Cost Summary

| What | Cost | Required? |
|------|------|-----------|
| Apple Developer Program | $99/year | Yes, for Developer ID + notarisation |
| Xcode | Free | Already have it |
| Code signing certificates | Free (included with Program) | Yes |
| Notarisation | Free (included with Program) | Yes, for warning-free distribution |
| Mac App Store listing | N/A | Not possible (sandbox disabled) |

The only cost is the $99/year Developer Program membership. Everything else
is included.
