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
build/Release/GoToSleep.app
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

## Step 3: Create the .dmg (Simple Method)

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

The output is `GoToSleep-1.0.dmg` in your current directory. This works, but
the window that opens looks like a plain Finder folder. If you want the polished
look you see from apps like 1Password, Figma, or Discord, read the next section.

### Test the .dmg

```bash
open GoToSleep-1.0.dmg
```

Finder should mount a volume called "Go To Sleep" showing the app and the
Applications shortcut. Try dragging the app to Applications.

---

## Step 3b: Create a Professional .dmg (Optional)

The reason your `.dmg` looks like a plain folder while apps like 1Password have
a slick drag-to-install window is that those `.dmg` files contain **embedded
Finder view settings**: a custom background image, pre-positioned icons, a fixed
window size, and the toolbar/sidebar hidden. `hdiutil` alone can't set any of
this — it just packs files into an image.

The polished `.dmg` is essentially a Finder window styled to look like a
mini-installer, with a designed background image that has an arrow graphic
saying "drag here".

### What's inside a professional .dmg

- A **background image** (e.g. 660x400 PNG) with your branding and an arrow
  pointing from the app icon to the Applications folder icon
- **Icon positions** set so the app sits on the left and the Applications
  symlink sits on the right, aligned with the arrow in the background
- **Finder view settings** baked into a `.DS_Store` file: icon view mode, large
  icon size, hidden toolbar/sidebar, fixed window dimensions
- The background image stored in a hidden `.background/` folder inside the
  volume

### Install create-dmg

The easiest way to build one of these is with `create-dmg`, a shell script that
automates all the Finder metadata manipulation:

```bash
brew install create-dmg
```

### Design a background image

Create a PNG image at the exact size you want the `.dmg` window to be. A common
size is **660 x 400 pixels**. The image should:

- Have your app's branding/colours
- Show an arrow pointing from left to right (where the app icon and Applications
  icon will be positioned)
- Optionally include your app name and a "Drag to install" label

You can design this in Figma, Sketch, Photoshop, Pixelmator, or even Keynote
(export a slide as PNG). Keep it simple — a dark gradient with a subtle arrow
works well.

Save it somewhere like `dmg-resources/background.png`.

### Build the .dmg with create-dmg

When using `create-dmg`, stage **only** the `.app` — do not add an `Applications`
symlink to `dmg-staging/`. The `--app-drop-link` flag creates that link for you.
If you add it yourself, create-dmg will try to create it again and hit
`ln: .../Applications/Applications: File exists`.

```bash
# Create a directory for dmg resources if you haven't already
mkdir -p dmg-resources

# Stage only the app (create-dmg adds the Applications link via --app-drop-link)
rm -rf dmg-staging
mkdir -p dmg-staging
cp -R build/Release/GoToSleep.app dmg-staging/

# Build the professional .dmg
create-dmg \
  --volname "Go To Sleep" \
  --volicon "GoToSleep/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
  --background "dmg-resources/background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "GoToSleep.app" 160 200 \
  --app-drop-link 500 200 \
  --hide-extension "GoToSleep.app" \
  --no-internet-enable \
  GoToSleep-1.0.dmg \
  dmg-staging/
```

Flags explained:

- `--volname "Go To Sleep"` — volume name shown in Finder's title bar and
  sidebar
- `--volicon "..."` — the icon for the mounted volume itself (shown on the
  desktop). Use your app icon. Omit this flag if you don't have an icon yet.
- `--background "dmg-resources/background.png"` — your custom background image.
  Gets copied into a hidden `.background/` folder inside the volume.
- `--window-pos 200 120` — where the window appears on screen when opened (x y
  from top-left). Pick something centred-ish.
- `--window-size 660 400` — must match your background image dimensions exactly.
- `--icon-size 128` — the size of the icons inside the window. 128px is the
  sweet spot — large enough to see clearly, small enough to fit the layout.
- `--icon "GoToSleep.app" 160 200` — positions the app icon at x=160, y=200
  (centred vertically, left side of the window). Adjust these coordinates to
  align with your background image's arrow.
- `--app-drop-link 500 200` — creates the Applications folder shortcut and
  positions it at x=500, y=200 (right side, same vertical position as the app).
- `--hide-extension "GoToSleep.app"` — hides the `.app` extension so it shows
  as just "GoToSleep".
- `--no-internet-enable` — skips the legacy internet-enable flag (not needed on
  modern macOS).

#### Potential Issues

If you see the following:

```sh
Making link to Applications dir...
/Volumes/dmg.hO4HXl
ln: /Volumes/dmg.hO4HXl/Applications/Applications: File exists
```

It's because you still have the the Applications symlink in the `dmg-staging` directory.
Remove it and this error will go too.

### Tweaking the icon positions

The x/y coordinates for `--icon` and `--app-drop-link` are relative to the
window's content area. If things don't look right:

1. Open the `.dmg` and see where the icons land.
2. Adjust the coordinates and rebuild.
3. The y coordinate is measured from the **top** of the window.

A good starting point for a 660x400 window:

| Element           | x   | y   | Placement    |
| ----------------- | --- | --- | ------------ |
| App icon          | 160 | 200 | Left-centre  |
| Applications link | 500 | 200 | Right-centre |

Adjust to match wherever your background image's arrow graphic points.

### If you don't have a background image yet

You can still get a cleaner look than the default by using `create-dmg` without
`--background`. It will still set the icon positions, window size, and hide the
toolbar, which is already a big improvement:

```bash
create-dmg \
  --volname "Go To Sleep" \
  --volicon "GoToSleep/Resources/Assets.xcassets/AppIcon.appiconset/go-to-sleep-logo_512x512.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "GoToSleep.app" 160 200 \
  --app-drop-link 500 200 \
  --hide-extension "GoToSleep.app" \
  --no-internet-enable \
  GoToSleep-1.0.dmg \
  dmg-staging/
```

This gives you the clean two-icon layout on a plain white background, which is
already much better than the raw Finder folder view.

### The manual way (for reference)

If you don't want to install `create-dmg`, you can do it by hand. This is
tedious but educational:

1. Create a **read-write** `.dmg`:

   ```bash
   hdiutil create \
     -volname "Go To Sleep" \
     -srcfolder dmg-staging \
     -ov \
     -format UDRW \
     GoToSleep-rw.dmg
   ```

2. Mount it:

   ```bash
   hdiutil attach GoToSleep-rw.dmg
   ```

3. Open the mounted volume in Finder. Then manually:
   - Switch to icon view (Cmd+1)
   - Open View > Show View Options (Cmd+J)
   - Set icon size to 128
   - Set grid spacing to max
   - Set background to your image (drag the PNG into the "Drag image here" well)
   - Drag the two icons into position
   - Resize the window to your desired size
   - Hide the toolbar (View > Hide Toolbar) and sidebar (View > Hide Sidebar)

4. Eject the volume:

   ```bash
   hdiutil detach /Volumes/Go\ To\ Sleep
   ```

5. Convert to read-only compressed format:
   ```bash
   hdiutil convert GoToSleep-rw.dmg \
     -format UDZO \
     -o GoToSleep-1.0.dmg
   rm GoToSleep-rw.dmg
   ```

As you can see, `create-dmg` saves a lot of pain.

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

# Stage (for simple hdiutil: include Applications symlink)
rm -rf dmg-staging
mkdir -p dmg-staging
cp -R build/Release/GoToSleep.app dmg-staging/
ln -s /Applications dmg-staging/Applications

# Package (simple)
hdiutil create \
  -volname "Go To Sleep" \
  -srcfolder dmg-staging \
  -ov \
  -format UDZO \
  GoToSleep-1.0.dmg

# Package (professional — requires: brew install create-dmg)
# Use a staging dir with only the .app (no Applications link); create-dmg adds it via --app-drop-link
rm -rf dmg-staging && mkdir -p dmg-staging && cp -R build/Release/GoToSleep.app dmg-staging/
create-dmg \
  --volname "Go To Sleep" \
  --background "dmg-resources/background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "GoToSleep.app" 160 200 \
  --app-drop-link 500 200 \
  --hide-extension "GoToSleep.app" \
  --no-internet-enable \
  GoToSleep-1.0.dmg \
  dmg-staging/

# Install
open GoToSleep-1.0.dmg
# Drag to Applications in Finder, then:
open /Applications/GoToSleep.app
```
