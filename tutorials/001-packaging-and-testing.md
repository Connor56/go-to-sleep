# Packaging Go To Sleep as a macOS App

This tutorial covers fixing the daemon embedding issue by editing
`project.pbxproj` directly, building via `xcodebuild` from the terminal, and
testing locally without a paid Apple Developer account.

---

## Part 1: Fix the Daemon Embedding

The "Copy Daemon" build phase on the GoToSleep target exists but is empty and
has the wrong destination. The daemon binary never gets copied into the `.app`
bundle, so `Contents/MacOS/GoToSleepDaemon` doesn't exist at runtime.

Three things need fixing in `GoToSleep.xcodeproj/project.pbxproj`:

1. No target dependency — GoToSleep doesn't know it needs GoToSleepDaemon built
   first.
2. The copy destination is set to "Products Directory" (`dstSubfolderSpec = 16`)
   instead of "Executables" (`dstSubfolderSpec = 6`, which maps to
   `Contents/MacOS/`).
3. No files are listed in the copy phase.

All three fixes go in the same file: `GoToSleep.xcodeproj/project.pbxproj`.

### Step 1: Add a build file entry for the daemon copy

Find this block (around line 34–37):

```
		/* Daemon plist copied into app bundle */
		A300000001 /* com.gotosleep.daemon.plist in Resources */ = {isa = PBXBuildFile; fileRef = B300000001; };
/* End PBXBuildFile section */
```

Add a new line **before** the `/* End PBXBuildFile section */` comment so it
becomes:

```
		/* Daemon plist copied into app bundle */
		A300000001 /* com.gotosleep.daemon.plist in Resources */ = {isa = PBXBuildFile; fileRef = B300000001; };

		/* Daemon binary copied into app bundle */
		A400000001 /* GoToSleepDaemon in Copy Daemon */ = {isa = PBXBuildFile; fileRef = P200000001 /* GoToSleepDaemon */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };
/* End PBXBuildFile section */
```

This tells Xcode that the built `GoToSleepDaemon` product (`P200000001`) should
be treated as a file to copy, and to re-sign it when copying into the app bundle.

### Step 2: Fix the Copy Daemon build phase

Find this block (around line 40–49):

```
		C100000001 /* Copy Daemon */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 16;
			files = (
			);
			name = "Copy Daemon";
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Change it to:

```
		C100000001 /* Copy Daemon */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 6;
			files = (
				A400000001 /* GoToSleepDaemon in Copy Daemon */,
			);
			name = "Copy Daemon";
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Two changes:

- `dstSubfolderSpec` from `16` to `6` (copies into `Contents/MacOS/` instead of
  the products directory).
- `A400000001` added to the `files` list (the build file entry you created in
  step 1).

### Step 3: Add a target dependency and container item proxy

The GoToSleep target needs to depend on GoToSleepDaemon so it gets built first.
This requires two new sections that don't exist in the file yet.

Find this line (around line 59):

```
/* End PBXCopyFilesBuildPhase section */
```

Add these two new sections **immediately after** it:

```

/* Begin PBXContainerItemProxy section */
		E100000001 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = PRJ0000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = T200000001;
			remoteInfo = GoToSleepDaemon;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
		E200000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = T200000001 /* GoToSleepDaemon */;
			targetProxy = E100000001 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
```

The container item proxy is Xcode's way of referencing another target within the
same project. The target dependency uses that proxy to say "build
GoToSleepDaemon before GoToSleep".

### Step 4: Wire the dependency into the GoToSleep target

Find the GoToSleep target definition (around line 226–243). Look for the empty
`dependencies` list:

```
		T100000001 /* GoToSleep */ = {
			isa = PBXNativeTarget;
			...
			dependencies = (
			);
```

Change it to:

```
			dependencies = (
				E200000001 /* PBXTargetDependency */,
			);
```

This tells Xcode: "before building GoToSleep, build GoToSleepDaemon first."

### Step 5: Verify your changes

Build both targets from the terminal:

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  build
```

Note: you only need to specify the GoToSleep target now — the dependency will
pull in GoToSleepDaemon automatically.

After the build succeeds, check the app bundle:

```bash
ls build/Debug/GoToSleep.app/Contents/MacOS/
```

You should see **both** files:

```
GoToSleep
GoToSleepDaemon
```

If `GoToSleepDaemon` is there, the embedding is fixed.

---

## Part 2: Code Signing Without a Paid Developer Account

You don't need a $99/year Apple Developer Program membership to build and test
locally.

### Ad-hoc signing (what you already have)

The project is configured with `CODE_SIGN_STYLE = Automatic` in the pbxproj.
When you build with `xcodebuild`, it will ad-hoc sign the app using whatever
local certificates are available. This works on **your Mac only**.

If you have an Apple ID, you can optionally set a development team for slightly
better signing. Add this build setting to both the GoToSleep and GoToSleepDaemon
Debug/Release configurations in the pbxproj:

```
DEVELOPMENT_TEAM = <your-team-id>;
```

To find your team ID, run:

```bash
security find-identity -v -p codesigning
```

This lists your available signing certificates. If you've never set one up, the
ad-hoc default is fine — skip this step.

### Build a release version

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Release \
  build
```

The built app lands in `build/Release/GoToSleep.app`. You can
copy it anywhere (e.g. `/Applications`) and double-click to run.

### What happens when someone else tries to run it?

Without notarization (which requires a paid account), other users will see:

> "GoToSleep" can't be opened because Apple cannot check it for malicious
> software.

They can bypass this by:

- Right-clicking the app > **Open** > clicking **Open** in the dialog, OR
- Running `xattr -cr /path/to/GoToSleep.app` in Terminal before opening.

This is fine for personal use and testing with friends.

---

## Part 3: Test the Full Flow

Once the daemon is embedded and you've built successfully:

### 1. Clean build

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  clean build
```

### 2. Verify the bundle structure

```bash
find build/Debug/GoToSleep.app/Contents -type f | sort
```

You should see something like:

```
Contents/
  MacOS/
    GoToSleep              <-- main app binary
    GoToSleepDaemon        <-- daemon binary (the one you just fixed)
  Resources/
    AppIcon.icns
    Assets.car
    questions.json
    com.gotosleep.daemon.plist
  Info.plist
  PkgInfo
  _CodeSignature/
    CodeResources
```

### 3. Run the app

```bash
open build/Debug/GoToSleep.app
```

Check:

- [ ] Menu bar icon appears
- [ ] Settings window opens from the menu
- [ ] Enabling the daemon works (check with `pgrep GoToSleepDaemon`)
- [ ] Daemon logs appear: `cat /tmp/go-to-sleep-daemon.stdout.log`

### 4. Check code signing

```bash
codesign -dvvv build/Debug/GoToSleep.app
```

As long as it doesn't say "code object is not signed at all", you're good for
local testing. You'll likely see `Signature=adhoc` which is expected.

Also check the embedded daemon is signed:

```bash
codesign -dvvv build/Debug/GoToSleep.app/Contents/MacOS/GoToSleepDaemon
```

---

## Part 4: When You're Ready for Real Distribution

When you eventually want to distribute to other people properly, you'll need:

1. **Apple Developer Program membership** ($99/year) for a Developer ID
   certificate.
2. **Notarization** — submit the app to Apple for automated malware scanning.
   This removes the Gatekeeper warning for other users.
3. **Hardened Runtime** — you may need to enable this and add specific
   entitlements for the accessibility APIs the app uses.
4. **DMG or installer** — package the `.app` in a `.dmg` disk image for clean
   distribution.

But none of that is needed just to build, test, and use the app yourself.
