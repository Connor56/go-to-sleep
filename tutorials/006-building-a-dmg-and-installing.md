# Building a .dmg and Installing the App

This tutorial covers how to build a release `.app` bundle, package it into a
`.dmg` disk image, install it on your machine, and what happens when you upgrade
from a debug build or a previous version.

---

## How macOS Apps Actually Work

Before diving in, it helps to understand how macOS thinks about apps:

- A `.app` is just a folder with a specific structure (`Contents/MacOS/`,
  `Contents/Resources/`, etc.). Finder displays it as a single icon.
- macOS identifies apps by their **bundle identifier** (`com.gotosleep.app`),
  not by where they live on disk.
- There is no "installer" in the Windows sense. You just drag the `.app` to
  `/Applications` (or anywhere). That's the install.
- A `.dmg` is a disk image — a read-only virtual drive. It's the standard way
  to distribute Mac apps outside the App Store. The user opens the `.dmg`,
  drags the app out, and ejects the image.

---

## Step 1: Build for Release

Debug builds include debug symbols, assertions, and no optimisation. For
distribution you want a Release build.

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Release \
  clean build
```

The built app lands at:

```
build/Build/Products/Release/GoToSleep.app
```

### Verify the bundle

```bash
# Check both binaries are present
ls build/Release/GoToSleep.app/Contents/MacOS/

# Check resources
ls build/Release/GoToSleep.app/Contents/Resources/

# Check code signing
codesign -dvvv build/Release/GoToSleep.app
```

---

## Step 2: Create a Staging Directory

The `.dmg` will contain whatever you put in a staging folder. At minimum, you
want the `.app` and a symbolic link to `/Applications` so users can drag-install.

```bash
# Create a clean staging area
mkdir -p dmg-staging

# Copy the release app into it
cp -R build/Release/GoToSleep.app dmg-staging/

# Create a symlink to /Applications for drag-install
ln -s /Applications dmg-staging/Applications
```

Your staging folder now looks like:

```
dmg-staging/
  GoToSleep.app
  Applications -> /Applications
```

When the user opens the `.dmg`, they see the app on the left and the
Applications folder on the right — they drag one to the other.

---

## Step 3: Create the .dmg

Use `hdiutil` (built into macOS) to create the disk image:

```bash
hdiutil create \
  -volname "Go To Sleep" \
  -srcfolder dmg-staging \
  -ov \
  -format UDZO \
  GoToSleep-1.0.dmg
```

Flags explained:

- `-volname "Go To Sleep"` — the name shown in Finder when the image is mounted
- `-srcfolder dmg-staging` — the folder whose contents go into the image
- `-ov` — overwrite if a `.dmg` with this name already exists
- `-format UDZO` — compressed, read-only format (standard for distribution)

The output is `GoToSleep-1.0.dmg` in your current directory.

### Test the .dmg

```bash
open GoToSleep-1.0.dmg
```

Finder should mount a volume called "Go To Sleep" showing the app and the
Applications shortcut. Try dragging the app to Applications.

---

## Step 4: Install to /Applications

You can either drag from the mounted `.dmg` in Finder, or do it from the
terminal:

```bash
# If you have an old version, remove it first
rm -rf /Applications/GoToSleep.app

# Copy from the mounted dmg (or directly from the staging folder)
cp -R dmg-staging/GoToSleep.app /Applications/
```

Then launch it:

```bash
open /Applications/GoToSleep.app
```

---

## What Happens to the Debug Build?

This is the important part. You currently have a debug build running from
somewhere like `build/Debug/GoToSleep.app`. Here's what happens
when you install the release version to `/Applications`:

### The app itself

macOS identifies apps by bundle identifier (`com.gotosleep.app`), not by file
path. Both your debug and release builds have the same bundle identifier. You
can have both `.app` bundles on disk simultaneously — they're just folders.
But macOS features like Launch Services, Spotlight, and "Open With" will
register whichever one was most recently launched or added.

There's no conflict — you just launch whichever one you want. But to avoid
confusion, stop using the debug build once you've installed to `/Applications`.

### UserDefaults / settings

Both builds share the same UserDefaults suite (`com.gotosleep.shared`). Your
settings (bedtime hours, grace period, etc.) carry over automatically. Nothing
to migrate.

### Application Support data

Both builds use `~/Library/Application Support/GoToSleep/`. Session markers,
answer logs, kill logs — all shared. Again, nothing to migrate.

### The daemon (this is the tricky part)

The LaunchAgent plist at `~/Library/LaunchAgents/com.gotosleep.daemon.plist`
contains an **absolute path** to the daemon binary. When you registered it from
the debug build, it wrote something like:

```
/Users/you/Documents/projects/go-to-sleep/build/Debug/GoToSleep.app/Contents/MacOS/GoToSleepDaemon
```

After installing to `/Applications`, the daemon binary is now at:

```
/Applications/GoToSleep.app/Contents/MacOS/GoToSleepDaemon
```

**The old plist still points to the debug path.** The daemon will keep running
from the old location until you re-register it. To fix this:

1. Launch the newly installed app from `/Applications`.
2. Toggle "Enabled" off and back on in the menu bar (this calls
   `unregisterDaemon()` then `registerDaemon()`, which rewrites the plist with
   the new path).
3. Or, if you've wired up auto-registration on launch (from tutorial 003), just
   launching the app will overwrite the plist with the correct path.

You can verify the plist was updated:

```bash
cat ~/Library/LaunchAgents/com.gotosleep.daemon.plist
```

The `ProgramArguments` should now point to `/Applications/GoToSleep.app/...`.

### Accessibility permission

Accessibility permissions in System Settings are granted **per executable
path**. If you granted it to the debug build at
`.../build/Debug/GoToSleep.app`, the release build at
`/Applications/GoToSleep.app` is a different path and will need its own
Accessibility grant. You'll see a new entry appear in System Settings >
Privacy & Security > Accessibility.

You can remove the old debug entry to keep things tidy.

---

## Upgrading to a New Version Later

When you build a new version and want to replace the installed app:

### 1. Stop the daemon

```bash
launchctl unload ~/Library/LaunchAgents/com.gotosleep.daemon.plist
```

Or toggle "Enabled" off in the menu bar before quitting.

### 2. Quit the app

Click the moon icon > Quit, or:

```bash
pkill -f GoToSleep.app/Contents/MacOS/GoToSleep
```

### 3. Replace the app

```bash
rm -rf /Applications/GoToSleep.app
cp -R build/Release/GoToSleep.app /Applications/
```

### 4. Relaunch

```bash
open /Applications/GoToSleep.app
```

The app will re-register the daemon on launch (pointing to the same
`/Applications` path), so the plist doesn't go stale.

### What's preserved across upgrades

| Data                     | Location                                                | Preserved?                        |
| ------------------------ | ------------------------------------------------------- | --------------------------------- |
| Settings                 | `com.gotosleep.shared` UserDefaults                     | Yes                               |
| Session markers          | `~/Library/Application Support/GoToSleep/`              | Yes                               |
| Answer logs              | `~/Library/Application Support/GoToSleep/answers.jsonl` | Yes                               |
| Kill log                 | `~/Library/Application Support/GoToSleep/kills.json`    | Yes                               |
| LaunchAgent plist        | `~/Library/LaunchAgents/com.gotosleep.daemon.plist`     | Yes (but re-registered on launch) |
| Accessibility permission | System Settings                                         | Yes (same path = same grant)      |

---

## Clean Uninstall

If you ever want to completely remove the app:

```bash
# 1. Unload the daemon
launchctl unload ~/Library/LaunchAgents/com.gotosleep.daemon.plist

# 2. Remove the LaunchAgent plist
rm ~/Library/LaunchAgents/com.gotosleep.daemon.plist

# 3. Remove the app
rm -rf /Applications/GoToSleep.app

# 4. Remove app data
rm -rf ~/Library/Application\ Support/GoToSleep

# 5. Remove UserDefaults
defaults delete com.gotosleep.shared

# 6. Remove Accessibility entry
# (Do this manually in System Settings > Privacy & Security > Accessibility)
```

---

## Quick Reference: Full Release Flow

```bash
# Build
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Release \
  clean build

# Stage
rm -rf dmg-staging
mkdir -p dmg-staging
cp -R build/Release/GoToSleep.app dmg-staging/
ln -s /Applications dmg-staging/Applications

# Package
hdiutil create \
  -volname "Go To Sleep" \
  -srcfolder dmg-staging \
  -ov \
  -format UDZO \
  GoToSleep-1.0.dmg

# Install
open GoToSleep-1.0.dmg
# Drag to Applications in Finder, then:
open /Applications/GoToSleep.app
```
