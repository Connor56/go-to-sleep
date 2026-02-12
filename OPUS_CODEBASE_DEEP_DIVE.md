# Go To Sleep — A Complete Technical Deep Dive

This document is a teaching walkthrough of the entire Go To Sleep codebase. It assumes you are an experienced software developer — comfortable with TypeScript, Go, and Python — but have never written Swift and know nothing about Apple platform internals. Every concept is explained from the ground up. Nothing is assumed. If a term appears, it gets defined. If a mechanism exists, it gets explained — not just named.

This is not a summary. This is not an architecture diagram with boxes and arrows. This is a line-by-line, file-by-file walkthrough of what every piece of this codebase does, why it exists, how it behaves at runtime, and how it connects to everything else.

---

## 1. Introduction: What This Project Does

Go To Sleep is a macOS application that does one thing: it makes you go to bed.

Here is the user experience, end to end. You install the app on your Mac. A small moon icon appears in your menu bar — that strip of tiny icons in the top-right corner of your screen, next to the Wi-Fi symbol and the clock. The app has no Dock icon. It has no main window. It lives entirely in that menu bar icon, quietly, in the background.

You click the moon icon. A small dropdown appears. You can toggle the app on or off, see your bedtime schedule, open settings, or quit. In settings, you configure what hours count as "bedtime" (say, 9 PM to 7 AM), how many reflective questions you want to answer per session, and how long of a grace period you get after completing a session before the app bothers you again.

Then you forget about it. You go about your evening. You keep working, scrolling, coding — whatever you do when you should be sleeping.

At 9 PM (or whatever you configured), something happens. Your entire screen goes dark. A calm, gradient-filled overlay takes over everything. The Dock disappears. The menu bar disappears. You cannot Cmd+Tab to another app. You cannot Force Quit. You are locked in. The overlay presents you with a reflective question — something like "What's keeping you up right now? Be honest." or "Will staying up another hour be worth it tomorrow morning?" You must type an answer (or pick from multiple choice options). Then the next question appears. After you finish all the questions, the overlay disappears, the Dock comes back, and you get your grace period — an hour, say — before the app will bother you again.

If you force-kill the app (via Activity Monitor, or `kill` from the terminal), it comes right back. A background process — the daemon — is watching. It notices the app died without completing the session, and it relaunches the app with the overlay. If you kill it five times in ten minutes, the daemon gives up and grants you a grace period anyway (a safety valve, so you're never truly trapped in an infinite loop).

That's the product. Now let's understand how it's built.

### The Two Programs

This project compiles into **two completely separate executable programs** that run as **two separate processes** on your Mac:

1. **GoToSleep** — the main app. This is the thing with the menu bar icon, the settings window, and the full-screen overlay. It is a macOS GUI application written with a mix of SwiftUI (Apple's modern declarative UI framework — think of it like React for macOS) and AppKit (Apple's older, imperative UI framework — think of it like directly manipulating the DOM with vanilla JavaScript).

2. **GoToSleepDaemon** — the background enforcer. This is a headless command-line program with no UI at all. It runs in an infinite loop, checking the clock every 10 seconds. When it's bedtime, it either tells the already-running app to show the overlay, or it launches the app from scratch if it isn't running. It is managed by `launchd`, which is macOS's equivalent of `systemd` on Linux — the system-level process supervisor that keeps background services alive.

These two programs communicate with each other through three channels, which we will explore in great detail later:
- **Shared files on disk** (marker files that say "a session is active" or "a session was completed")
- **Shared preferences** (a key-value store that both processes can read and write to — the user's settings)
- **Cross-process notifications** (a message bus that lets the daemon poke the app and say "show the overlay now")

### The File Layout

Here is every source file in the project, organized by where it lives:

```
GoToSleep/
├── App/
│   ├── GoToSleepApp.swift          ← the app's entry point (where the process starts)
│   └── AppDelegate.swift           ← lifecycle coordinator (orchestrates overlay, settings, daemon registration)
├── Views/
│   ├── MenuBarView.swift           ← the dropdown that appears when you click the moon icon
│   ├── SettingsView.swift          ← the settings window UI
│   ├── OverlayView.swift           ← the full-screen bedtime questionnaire
│   ├── QuestionView.swift          ← renders a single question (free text or multiple choice)
│   └── PermissionsGuideView.swift  ← a setup wizard (exists but not currently wired into the app)
├── Models/
│   ├── AppSettings.swift           ← persistent user settings (bedtime hours, question count, etc.)
│   ├── Question.swift              ← data type representing a single question
│   ├── SessionLog.swift            ← data type representing a logged answer
│   └── QuestionStore.swift         ← loads questions from a JSON file and picks random subsets
├── Services/
│   ├── OverlayWindowController.swift ← creates and manages the kiosk-mode fullscreen window
│   ├── FocusEnforcer.swift           ← reclaims focus if another app steals it during overlay
│   └── AnswerLogger.swift            ← writes answers to a JSONL file on disk
├── Resources/
│   ├── questions.json              ← the bank of reflective questions
│   └── Assets.xcassets/            ← app icons and images
├── Info.plist                      ← app configuration metadata (tells macOS this is a menu-bar-only app)
└── GoToSleep.entitlements          ← security permissions (sandbox disabled)

GoToSleepDaemon/
├── main.swift                      ← the daemon's entire codebase (one file)
└── Info.plist                      ← daemon bundle metadata

Shared/
├── Paths.swift                     ← file path constants and helpers (used by both app and daemon)
└── TimeCheck.swift                 ← bedtime window calculation (used by both app and daemon)

Resources/
└── com.gotosleep.daemon.plist      ← tells macOS how to run the daemon as a background service

GoToSleep.xcodeproj/
└── project.pbxproj                 ← the Xcode project file (tells the build system what to compile)
```

Every one of these files will be explained in full. Let's start from the outside in — with how macOS apps are structured at the operating system level, before we look at a single line of Swift.

---

## 2. How macOS Apps Work — Bundles, Targets, and the .app Directory

### An .app Is Not a File — It's a Folder

When you see `GoToSleep.app` in Finder, it looks like a single file. You double-click it, the app launches. But this is a lie that macOS tells you to keep things simple. An `.app` is actually a **directory** — a folder with a specific internal structure that macOS knows how to interpret. Apple calls this a **bundle**.

If you right-click `GoToSleep.app` in Finder and choose "Show Package Contents", or if you `ls` it from the terminal, you'll see something like:

```
GoToSleep.app/
└── Contents/
    ├── MacOS/
    │   ├── GoToSleep          ← the actual compiled binary (the executable you run)
    │   └── GoToSleepDaemon    ← the daemon binary, also lives inside the app bundle
    ├── Resources/
    │   ├── questions.json     ← data files the app needs at runtime
    │   ├── Assets.car         ← compiled asset catalog (icons, images)
    │   └── com.gotosleep.daemon.plist  ← config file for the daemon's background service
    └── Info.plist             ← metadata about the app (name, version, behavior flags)
```

This is roughly analogous to how a Go binary might be a single executable, but a Node.js project is a directory with `package.json`, `node_modules/`, and source files — except macOS bundles have a very specific structure that the operating system itself understands and enforces.

The key insight: **everything the app needs to run is packaged inside this one `.app` folder**. The executable, the daemon executable, the question data, the icons, the configuration files — all of it. When a user drags `GoToSleep.app` into their Applications folder, they're copying this entire directory tree. That's the entire "installation" process on macOS — there is no installer wizard, no `apt-get`, no registry entries. Just copy the folder.

### What Is a "Target" in Xcode?

If you come from the TypeScript/Node world, think of a target as an entry in a monorepo's workspace configuration — it defines one buildable thing. If you come from Go, think of it as a separate `package main` — a separate binary that gets compiled from its own set of source files.

This project has **two targets**, defined in the Xcode project file (`GoToSleep.xcodeproj/project.pbxproj`):

1. **GoToSleep** — builds into a macOS `.app` bundle (a GUI application). Its product type is `com.apple.product-type.application`.
2. **GoToSleepDaemon** — builds into a bare executable (a command-line tool). Its product type is `com.apple.product-type.tool`.

You can see these defined in the project file:

```
// GoToSleep.xcodeproj/project.pbxproj, lines 226-260

T100000001 /* GoToSleep */ = {
    isa = PBXNativeTarget;
    ...
    name = GoToSleep;
    productName = GoToSleep;
    productReference = P100000001 /* GoToSleep.app */;
    productType = "com.apple.product-type.application";
};
T200000001 /* GoToSleepDaemon */ = {
    isa = PBXNativeTarget;
    ...
    name = GoToSleepDaemon;
    productName = GoToSleepDaemon;
    productReference = P200000001 /* GoToSleepDaemon */;
    productType = "com.apple.product-type.tool";
};
```

Each target has its own list of source files that get compiled into it. This is important because some files are shared between both targets, and some are exclusive to one.

The **GoToSleep app target** compiles 16 Swift source files (lines 312-333 of the pbxproj):

```
// GoToSleep.xcodeproj/project.pbxproj, lines 312-333
S100000001 /* Sources */ = {
    ...
    files = (
        A100000001 /* GoToSleepApp.swift in Sources */,
        A100000002 /* AppDelegate.swift in Sources */,
        A100000003 /* OverlayView.swift in Sources */,
        ...
        A100000015 /* Paths.swift in Sources */,
        A100000016 /* TimeCheck.swift in Sources */,
    );
};
```

The **GoToSleepDaemon target** compiles only 3 Swift source files (lines 335-344):

```
// GoToSleep.xcodeproj/project.pbxproj, lines 335-344
S200000001 /* Sources */ = {
    ...
    files = (
        A200000001 /* main.swift in Sources */,
        A200000002 /* Paths.swift in Sources */,
        A200000003 /* TimeCheck.swift in Sources */,
    );
};
```

Notice that `Paths.swift` and `TimeCheck.swift` appear in **both** target's source lists. That's the `Shared/` folder — those two files are compiled into both executables. This is how the app and the daemon share code without needing a separate library or framework. The same source file gets compiled twice, once into each binary. It's the simplest form of code sharing: literal file sharing at the build level, like having the same `.go` file imported by two separate `main` packages.

### The project.pbxproj File — Xcode's Build Configuration

The file `GoToSleep.xcodeproj/project.pbxproj` is the heart of the build system. It's Xcode's equivalent of `package.json` + `tsconfig.json` + `webpack.config.js` combined, or `go.mod` + your Makefile combined. It defines:

- What targets exist and what type of product each target builds
- Which source files belong to which target
- Which resource files (JSON, images, plists) get bundled into the app
- Build settings (deployment target, Swift version, code signing, etc.)
- Build phases (compile sources, copy resources, link frameworks, copy the daemon binary)

The file format is Apple's proprietary `plist`-like format. It uses hex-like identifiers (in this project, readable ones like `A100000001`, `B100000001`, etc.) to cross-reference objects. You rarely edit this file by hand — Xcode generates and manages it — but this project's pbxproj was hand-written with deliberately readable IDs.

One particularly important section is the build settings for the GoToSleep target:

```
// GoToSleep.xcodeproj/project.pbxproj, lines 419-443
D100000001 /* Debug */ = {
    ...
    buildSettings = {
        ...
        INFOPLIST_FILE = GoToSleep/Info.plist;
        INFOPLIST_KEY_LSUIElement = YES;
        ...
        PRODUCT_BUNDLE_IDENTIFIER = "com.gotosleep.app";
        ...
        SWIFT_VERSION = 5.0;
    };
};
```

`PRODUCT_BUNDLE_IDENTIFIER` is the globally unique identifier for this app — `com.gotosleep.app`. This is how macOS distinguishes your app from every other app on the system. It follows reverse-DNS convention (like Java package names or Android app IDs). The daemon has its own: `com.gotosleep.daemon` (line 475).

`MACOSX_DEPLOYMENT_TARGET = 13.0` (line 377) means this app requires macOS 13 (Ventura) or later. If someone tries to run it on macOS 12, the system will refuse.

Now that you understand the physical structure of a macOS app, let's talk about those configuration files — the plists — in detail.

---

## 3. Property Lists (plists) — What They Are, Mechanically and Conceptually

### What Is a Plist?

A **plist** (short for **Property List**) is Apple's standard format for structured configuration data. Think of it as Apple's answer to JSON — it's a file format for storing key-value data in a standardized way. In fact, you can think of a plist as functionally identical to a JSON file, just written in XML syntax instead of JSON syntax.

Here's a mental model: if you've ever written a `tsconfig.json`, a `pyproject.toml`, or a `go.mod`, you've written a configuration file that a tool reads to understand how to behave. Plists serve the same purpose, but they're used across the entire Apple ecosystem — the operating system reads them, the build system reads them, apps read them, background services read them.

The format looks like this — XML with Apple-specific tags:

```xml
<dict>
    <key>SomeKey</key>
    <string>some value</string>
    <key>AnotherKey</key>
    <true/>
    <key>ANumber</key>
    <integer>42</integer>
</dict>
```

This is equivalent to this JSON:

```json
{
    "SomeKey": "some value",
    "AnotherKey": true,
    "ANumber": 42
}
```

The XML is more verbose, but the information content is identical. Apple chose XML historically (plists predate JSON's popularity), and the format stuck. Modern macOS can actually also store plists in a compact binary format for performance, but the ones in source code are always the XML variant so humans can read them.

This project has **four** plist files, each serving a different purpose. Let's walk through every one.

### 3.1 The App's Info.plist — "Here's What Kind of App I Am"

**File: `GoToSleep/Info.plist` (lines 1-8)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

This file is tiny — it contains exactly one setting. But that one setting is critically important.

**`LSUIElement`** stands for "Launch Services UI Element". The `LS` prefix refers to **Launch Services**, which is the part of macOS that manages launching applications, associating file types with apps, and determining how apps present themselves. Setting this to `true` tells macOS: **"this app should not appear in the Dock."**

Normally, when you launch a macOS app, it gets an icon in the Dock (the bar of app icons at the bottom of your screen), it gets its own menu bar (File, Edit, View, etc.), and it appears in the Cmd+Tab app switcher as a full citizen. An `LSUIElement` app gets **none of that**. It's invisible to the user except through whatever UI it explicitly creates — in this case, a menu bar icon.

This is the standard pattern for **menu bar apps** (also called "menu bar extras" or "status bar apps"). Apps like Dropbox, 1Password's mini icon, or your VPN client's icon — those are all `LSUIElement` apps. They live in the menu bar strip and don't clutter the Dock.

The build settings in the pbxproj also set `INFOPLIST_KEY_LSUIElement = YES` (line 430), which is another way to express this — Xcode can merge plist values from both the file and the build settings. Having it in both places is redundant but harmless.

### 3.2 The Entitlements File — "Here's What I'm Allowed to Do"

**File: `GoToSleep/GoToSleep.entitlements` (lines 1-8)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

**Entitlements** are a security concept unique to Apple platforms. Think of them like Linux capabilities, or like an IAM policy in AWS. They declare what an app is **permitted** to do at the operating system level.

The key one here is `com.apple.security.app-sandbox`, set to `false`. The **App Sandbox** is Apple's security containment system. When sandboxing is enabled, your app runs in a restricted environment — it can only access its own files, it can't read other apps' data, it can't access the network without explicit permission, it can't control other apps' windows, and so on. It's like running in a Docker container with tight security policies.

This app disables the sandbox entirely. Why? Because Go To Sleep needs to do things that a sandboxed app cannot:

- It needs to take over the entire screen with a kiosk-mode window that sits above everything else
- It needs to disable Cmd+Tab, Force Quit, and other system-level key combinations
- It needs to detect when other apps steal focus and forcefully reclaim it
- It needs to launch the daemon as a background service via `SMAppService`
- It needs to read and write files in shared locations that both the app and daemon can access

All of these operations require unsandboxed access. If you ever distribute this on the Mac App Store, Apple would require sandboxing, and many of these features would need to be reworked. For personal use or direct distribution (via `.dmg`), disabling the sandbox is fine.

### 3.3 The Daemon's Info.plist — "Here's Who I Am"

**File: `GoToSleepDaemon/Info.plist` (lines 1-14)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.gotosleep.daemon</string>
    <key>CFBundleName</key>
    <string>GoToSleepDaemon</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
```

This is straightforward metadata. The `CF` prefix stands for **Core Foundation**, which is a low-level Apple framework that provides basic types and utilities. `CFBundle` refers to the bundle abstraction. So `CFBundleIdentifier` means "the globally unique identifier for this bundle" — `com.gotosleep.daemon`. `CFBundleName` is the human-readable name. The version fields track build and marketing versions.

This plist exists so that macOS can identify the daemon as a distinct piece of software with its own identity, separate from the main app.

### 3.4 The LaunchAgent Plist — "Here's How to Run Me as a Background Service"

**File: `Resources/com.gotosleep.daemon.plist` (lines 1-18)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.gotosleep.daemon</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/GoToSleepDaemon</string>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/go-to-sleep-daemon.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/go-to-sleep-daemon.stderr.log</string>
</dict>
</plist>
```

This is the most interesting plist in the project, and it deserves a deep explanation because it introduces a major macOS concept: **launchd and LaunchAgents**. We'll cover what launchd is and how registration works in detail in Section 12, but let's understand what each field in this file means right now:

- **`Label`** (`com.gotosleep.daemon`): The unique name for this background job. Think of it like a service name in `systemd` — it's how the system identifies and refers to this specific background process. No two LaunchAgents on the system can share a label.

- **`BundleProgram`** (`Contents/MacOS/GoToSleepDaemon`): The path to the executable to run, **relative to the app bundle root**. So if the app bundle is at `/Applications/GoToSleep.app/`, the full path to the daemon binary would be `/Applications/GoToSleep.app/Contents/MacOS/GoToSleepDaemon`. This is how macOS knows which binary to actually launch.

- **`KeepAlive`** (`true`): If the daemon process exits for any reason — crashes, gets killed, finishes naturally — macOS will automatically restart it. This is like setting `restart: always` in a Docker Compose file, or `Restart=always` in a systemd unit file. The daemon is meant to always be running.

- **`RunAtLoad`** (`true`): Start the daemon immediately when the job is loaded (registered). Don't wait for some trigger — just launch it right away.

- **`StandardOutPath`** and **`StandardErrorPath`**: Where to write the daemon's `stdout` and `stderr`. Since the daemon has no terminal attached (it's a background process), any `print()` statements go to these log files. They're in `/tmp/` for easy debugging.

This plist is bundled into the app's Resources directory at build time (see the pbxproj resources build phase at line 305: `A300000001 /* com.gotosleep.daemon.plist in Resources */`). It sits inside the `.app` bundle waiting to be registered with the system. We'll see exactly how that registration happens in Section 12.

Now that we understand the physical structure and configuration of the app, let's dive into the Swift code — starting with where the program begins.

---

## 4. The App Entry Point — `@main`, the App Protocol, and How a Swift Program Starts

### The File That Starts Everything

**File: `GoToSleep/App/GoToSleepApp.swift` (all 29 lines)**

```swift
import SwiftUI

@main
struct GoToSleepApp: App {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    init() {
        print("\(debugMarker) GoToSleepApp initialized")
    }

    var body: some Scene {
        MenuBarExtra("Go To Sleep", systemImage: "moon.fill") {
            MenuBarView(appDelegate: appDelegate)
                .onAppear {
                    print("\(debugMarker) MenuBarExtra content appeared")
                }
        }

        Settings {
            SettingsView()
                .onAppear {
                    print("\(debugMarker) Settings scene appeared")
                }
        }
    }
}
```

This is 29 lines of code, but every line is dense with Swift and Apple concepts. Let's unpack everything.

### `import SwiftUI` — What Are You Importing?

Line 1: `import SwiftUI`

In Swift, `import` works similarly to `import` in Python or Go — it brings a module's symbols into scope. **SwiftUI** is Apple's modern UI framework, introduced in 2019. It's a **declarative** UI framework, meaning you describe *what* your UI should look like, and the framework figures out *how* to render it and *when* to update it. If you've used React, Vue, or Svelte, the mental model is nearly identical. You declare components (called "Views" in SwiftUI), they have state, and when state changes, the UI automatically re-renders.

The alternative (and predecessor) is **AppKit**, which is Apple's **imperative** UI framework. AppKit has been around since the 1980s (it originated in NeXTSTEP, the operating system Steve Jobs built before returning to Apple). With AppKit, you create window objects, add button objects to them, wire up click handlers manually — much like manipulating the DOM directly with `document.createElement()` in JavaScript. This project uses **both** SwiftUI and AppKit, which is common and we'll see exactly why later.

### `@main` — How Swift Finds the Entry Point

Line 3: `@main`

Every program needs an entry point — the first thing that runs when the operating system loads the executable into memory and starts executing instructions. In different languages, this looks different:

- **Python**: `if __name__ == "__main__":` at the bottom of a file
- **Go**: `func main()` in `package main`
- **C/TypeScript (Node)**: The runtime just starts executing the file from the top
- **Java**: `public static void main(String[] args)` in a class

In Swift, the entry point mechanism is `@main`. The `@` symbol in Swift denotes an **attribute** — a compile-time annotation that modifies how the compiler treats a declaration. If you're coming from Python, think of `@main` as a decorator. From TypeScript, think of it as a decorator like `@Injectable()` in Angular. The analogy isn't perfect (Swift attributes are resolved at compile time, not runtime), but the syntax and purpose are similar: you're marking a thing with metadata that changes its behavior.

When the Swift compiler sees `@main` on a type, it says: "This is the entry point for the entire program. I will generate the actual `main()` function behind the scenes, and it will create an instance of this type and start the application."

What the compiler literally does is synthesize code equivalent to something like this (you never see this code — it's generated for you):

```swift
// This is what the compiler generates behind the scenes:
func main() {
    let app = GoToSleepApp()       // create the app struct
    // bootstrap the SwiftUI runtime
    // start the macOS event loop (run loop)
    // materialize the scenes declared in app.body
    // begin processing user input, timers, notifications, etc.
    // this function never returns — it runs until the app quits
}
```

The key insight: `@main` is not just a label. It fundamentally changes what happens at process startup. Without it, Swift would expect a traditional `main.swift` file with a top-level `main()` function call (which is exactly what the daemon uses — we'll see that later). With `@main`, you're opting into a framework-managed lifecycle where the framework (SwiftUI, in this case) controls startup, the event loop, and shutdown.

**This is why the project seems to have "multiple entry points"** — a question you specifically asked about. There are two executables, and each one has a *different style* of entry point:

- The **app target** uses `@main struct GoToSleepApp: App` — a SwiftUI-managed lifecycle where the framework handles startup.
- The **daemon target** uses a plain `main()` function call at the bottom of `GoToSleepDaemon/main.swift` (line 166: `main()`). This is the traditional, explicit style, like Go's `func main()`.

They are not competing entry points. They are entry points for two entirely separate programs that happen to live in the same source repository.

### `struct GoToSleepApp: App` — The App Protocol and What "Conformance" Means

Line 4: `struct GoToSleepApp: App {`

Let's break this apart piece by piece.

**`struct`** — Swift has two main kinds of types: `struct` (value type) and `class` (reference type). In Go, you're used to `struct` being the primary way to define types, and that's close to how Swift uses them too. The critical difference from classes is that structs are **value types** — when you assign a struct to a new variable or pass it to a function, you get a **copy**, not a reference to the same object. In Python, everything is a reference. In Go, structs are values (copied on assignment) unless you use pointers. Swift structs behave like Go structs: they copy. This matters because SwiftUI views are all structs, which means the framework can cheaply create, compare, and discard them during re-renders.

**`GoToSleepApp`** — this is just the name of the type. You could call it anything.

**`: App`** — this is the crucial part. The colon means "conforms to". `App` is a **protocol**. A protocol in Swift is the exact same concept as:
- An **interface** in Go or TypeScript
- An **abstract base class** (ABC) or Protocol in Python

It defines a contract: "any type that claims to conform to `App` must provide these specific properties and methods." The `App` protocol, defined by Apple's SwiftUI framework, requires exactly one thing: a property called `body` that returns something conforming to the `Scene` protocol. That's it. The full contract is essentially:

```swift
protocol App {
    associatedtype Body: Scene
    var body: Body { get }
}
```

In TypeScript terms, this would be like:

```typescript
interface App {
    body: Scene;
}
```

Or in Go:

```go
type App interface {
    Body() Scene
}
```

When you write `struct GoToSleepApp: App`, you're saying: "GoToSleepApp is a value type that fulfills the App contract by providing a `body` property that returns scene declarations."

### What the App Protocol Gives You (and What It Replaces)

The `App` protocol is the modern SwiftUI way to define your application. Before SwiftUI existed (pre-2019), the way you started a macOS app was completely different. You would write something like:

```swift
// OLD WAY — pre-SwiftUI, pure AppKit:
import AppKit

let app = NSApplication.shared       // get the global application object
let delegate = MyAppDelegate()       // create your delegate
app.delegate = delegate              // wire the delegate to the app
app.run()                            // start the event loop — blocks forever
```

This is imperative: you manually create objects, wire them together, and start the event loop. The `App` protocol replaces all of this with a declarative approach. Instead of writing startup code, you **declare what your app consists of** (its scenes), and the framework handles the rest.

Think of it like the difference between:
- **Express.js** (imperative): `const app = express(); app.get('/foo', handler); app.listen(3000);`
- **Next.js** (declarative): you put a file at `pages/foo.tsx` and the framework handles routing and serving

The `App` protocol is the Next.js approach. You declare scenes, and macOS figures out the windows, the event loop, the lifecycle.

### `private let debugMarker` and `init()` — Simple Stuff

Lines 5 and 9-11:

```swift
private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"

init() {
    print("\(debugMarker) GoToSleepApp initialized")
}
```

`private` means only accessible within this type (like Go's lowercase-first-letter convention, or TypeScript's `private` keyword). `let` means constant (cannot be reassigned — like `const` in JavaScript or a regular variable in Go that you never reassign). `debugMarker` is just a string tag used to prefix debug log messages so they can be easily found and removed later.

`init()` is Swift's constructor — called when an instance of `GoToSleepApp` is created. This is like `__init__` in Python or a constructor in TypeScript. The `\(...)` syntax is Swift's string interpolation — equivalent to `f"..."` in Python or `` `${...}` `` in TypeScript.

### The Two Remaining Lines — Previewed Now, Explained Fully Soon

Lines 6-7 introduce two critically important concepts that each deserve their own deep explanation:

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
@ObservedObject private var settings = AppSettings.shared
```

Both of these start with `@`, meaning they're using **property wrappers** — a Swift feature that lets you attach custom behavior to property storage and access. We'll unpack `@NSApplicationDelegateAdaptor` fully in Section 6 (it's the bridge between SwiftUI and the older AppKit lifecycle), and `@ObservedObject` in Sections 7 and 8 (it's how SwiftUI views automatically re-render when data changes).

For now, just know:
- `appDelegate` is an instance of `AppDelegate` (defined in `AppDelegate.swift`) that SwiftUI creates and wires into the macOS application lifecycle for us
- `settings` is a reference to the shared settings object, and any changes to settings will cause the UI to update

The `body` property — lines 13-27 — is where scenes are declared. That's the next section.

---

## 5. Scenes — MenuBarExtra, Settings, and What the OS Does With Them

### What Is a Scene?

Let's go back to line 13 of `GoToSleep/App/GoToSleepApp.swift`:

```swift
var body: some Scene {
```

A **Scene** in SwiftUI is a **top-level container** that the operating system manages. If a View is a component (a button, a text field, a list), then a Scene is the *thing the component lives inside of* — a window, a menu bar popover, a settings panel.

Think of it with a real-world analogy: if your UI components (views) are pieces of furniture, then a scene is a **room**. You don't just place a couch in empty space — you need a room to put it in. The operating system manages rooms (creates them, positions them on screen, minimizes them, closes them). Your job is to say what rooms you want and what furniture goes in each room. You don't manually call `CreateWindow()` or position pixels — you declare "I want a menu bar scene with this content" and "I want a settings scene with this content", and macOS handles the rest.

The `some Scene` return type uses Swift's **opaque return types** (the `some` keyword). Don't worry about the mechanics too much — it just means "this property returns something that conforms to the Scene protocol, but I'm not going to spell out the exact type." It's a type-system convenience similar to TypeScript's inferred return types.

### This App Declares Two Scenes

```swift
// GoToSleep/App/GoToSleepApp.swift, lines 13-27
var body: some Scene {
    MenuBarExtra("Go To Sleep", systemImage: "moon.fill") {
        MenuBarView(appDelegate: appDelegate)
            .onAppear {
                print("\(debugMarker) MenuBarExtra content appeared")
            }
    }

    Settings {
        SettingsView()
            .onAppear {
                print("\(debugMarker) Settings scene appeared")
            }
    }
}
```

There are exactly two scenes here: a `MenuBarExtra` and a `Settings`. Let's understand each one.

### Scene 1: `MenuBarExtra` — The Moon Icon in Your Menu Bar

```swift
MenuBarExtra("Go To Sleep", systemImage: "moon.fill") {
    MenuBarView(appDelegate: appDelegate)
}
```

**`MenuBarExtra`** is a SwiftUI scene type (introduced in macOS 13) that creates a **menu bar status item** — one of those small icons in the top-right of your screen, next to the Wi-Fi and battery icons.

Under the hood, this creates an **`NSStatusItem`**. Let's unpack that name:

- **`NS`** stands for **NeXTSTEP**, the operating system that Apple's macOS is descended from. Steve Jobs founded a company called NeXT in 1985 after being fired from Apple, and they built NeXTSTEP. When Apple bought NeXT in 1997, they used NeXTSTEP as the foundation for what became Mac OS X (now macOS). The `NS` prefix has persisted for over 40 years as the naming convention for classes in Apple's older frameworks. `NSWindow`, `NSApplication`, `NSButton`, `NSStatusItem` — they all carry this historical baggage. It's like how JavaScript's `XMLHttpRequest` still has "XML" in the name even though nobody uses it for XML anymore.

- **`StatusItem`** refers to an item in the **status bar** (the right side of the menu bar). Each status item shows an icon or text that the user can click to open a dropdown menu or popover.

So `NSStatusItem` is the AppKit (old, imperative) class for a menu bar icon. `MenuBarExtra` is the SwiftUI (new, declarative) wrapper around this concept. When you write `MenuBarExtra(...)`, SwiftUI creates an `NSStatusItem` behind the scenes, sets its icon to the SF Symbol named "moon.fill" (Apple provides a large library of built-in icons called **SF Symbols** — think of it as a system-wide icon font), and wires up the dropdown content.

The first argument, `"Go To Sleep"`, is a label (used for accessibility — screen readers will read it aloud). The `systemImage: "moon.fill"` sets the icon that appears in the menu bar.

Inside the curly braces is the **content** — what appears when the user clicks the icon. Here, that's `MenuBarView(appDelegate: appDelegate)`. This is where things get interesting.

### Delegate Injection — Why `appDelegate` Is Passed Explicitly

Look at this line carefully:

```swift
MenuBarView(appDelegate: appDelegate)
```

The `appDelegate` being passed here is the `AppDelegate` instance from line 6 of the same file:

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

`MenuBarView` needs access to the `AppDelegate` because the menu bar buttons call methods on it — like `appDelegate.showOverlay()` and `appDelegate.showSettingsWindow()`. The question is: **how does `MenuBarView` get a reference to the `AppDelegate`?**

There are two ways you could do this:

**Option A — Global cast (fragile):** Inside `MenuBarView`, reach into the global `NSApp` object and cast its delegate:
```swift
// BAD approach:
let delegate = NSApp.delegate as? AppDelegate
delegate?.showSettingsWindow()
```

**Option B — Direct injection (robust):** Pass the `AppDelegate` instance as a constructor argument:
```swift
// GOOD approach (what this project does):
MenuBarView(appDelegate: appDelegate)
```

This project uses Option B, and here's why Option A is problematic: In the SwiftUI lifecycle (when you use `@main struct ... : App`), `NSApp.delegate` is **not** your `AppDelegate` class. SwiftUI creates its own internal adaptor object and sets *that* as `NSApp.delegate`. Your `AppDelegate` instance is wrapped inside that adaptor. So when you do `NSApp.delegate as? AppDelegate`, the cast **fails** — `NSApp.delegate` is some SwiftUI internal type, not your `AppDelegate`. The result? Your code silently does nothing. The button appears to work (no crash), but nothing happens when you click it.

This is a classic Swift/SwiftUI gotcha. The `PermissionsGuideView` in this project (which we'll examine later) actually has this exact bug — it uses `NSApp.delegate as? AppDelegate` on line 109 of `GoToSleep/Views/PermissionsGuideView.swift`, and that cast will fail at runtime.

**Direct injection** (Option B) avoids this entirely. You already have the `AppDelegate` instance from the `@NSApplicationDelegateAdaptor` property wrapper, so you just pass it directly to the view that needs it. This is standard **dependency injection** — the same pattern you'd use in Go (passing a database connection to a handler function rather than using a global), TypeScript (constructor injection in Angular or NestJS), or Python (passing dependencies as function arguments rather than importing global singletons).

### Scene 2: `Settings` — The System Settings Window

```swift
Settings {
    SettingsView()
}
```

`Settings` is a built-in SwiftUI scene type specifically for macOS settings/preferences windows. Every macOS app has a "Preferences" or "Settings" menu item (usually under the app menu or accessible with Cmd+,). The `Settings` scene tells SwiftUI: "when the user triggers the settings action, show this view in a standard settings window."

The `SettingsView()` inside is the actual UI content — form fields for configuring bedtime hours, question count, and grace period. We'll walk through it in Section 7.

### What's Notably Absent: No Regular Window Scene

Most macOS apps would have a `WindowGroup` scene — the standard app window that opens when you launch the app:

```swift
// A typical macOS app would have this:
WindowGroup {
    ContentView()
}
```

Go To Sleep doesn't have one. This is intentional. Combined with the `LSUIElement` flag from `Info.plist`, it means the app has **no main window** and **no Dock icon**. It exists entirely as a menu bar icon with a dropdown, plus a settings window that appears on demand, plus the full-screen overlay that appears during bedtime. This is the standard architecture for a menu-bar-only app.

Now let's understand the `AppDelegate` — the object that actually orchestrates all the important behavior.

---

## 6. NSApplicationDelegate, the Adaptor Bridge, and AppDelegate.swift

This section covers what is probably the most confusing part of this codebase if you're new to Apple development: why there's both a `GoToSleepApp.swift` (the `@main` App struct) **and** an `AppDelegate.swift` (a class with lifecycle callbacks). They look like they're competing for control, but they're actually collaborating. Let's untangle this completely.

### The Delegation Pattern — A Foundational Concept

Before we look at any code, we need to understand **delegation**, because it's everywhere in Apple frameworks.

Delegation is a design pattern where one object hands off responsibility for certain decisions or actions to another object. A real-world analogy: imagine you run a restaurant. You're the owner (the delegator), but you hire a manager (the delegate) to handle the day-to-day operations. When a customer complains, you don't handle it yourself — you delegate that responsibility to the manager. The manager has a defined set of responsibilities (handle complaints, manage staff schedules, order supplies), and you call on them when those situations arise.

In code, delegation typically works like this:

1. There's a **delegator** — a framework-provided object that runs the show but needs to ask your code for decisions
2. There's a **protocol** (interface) — a contract defining what questions the delegator might ask or what events it will notify you about
3. There's a **delegate** — your object that conforms to the protocol and provides the answers/handlers

In Go terms, it's like passing an interface implementation to a framework:

```go
// Go equivalent of delegation:
type AppDelegate interface {
    DidFinishLaunching()
    WillTerminate()
}

// The framework calls your methods at the right time:
func RunApp(delegate AppDelegate) {
    // ... startup stuff ...
    delegate.DidFinishLaunching()
    // ... run event loop ...
    delegate.WillTerminate()
}
```

In TypeScript/Angular, it's similar to lifecycle hooks (`ngOnInit`, `ngOnDestroy`) — the framework calls your methods at specific moments in the lifecycle.

### NSApplication and NSApplicationDelegate

On macOS, when your app is running, there is a single global object called `NSApplication.shared` (accessible as `NSApp` for short). This object **is** your running application at the operating system level. It owns the event loop (the infinite loop that processes mouse clicks, key presses, timers, notifications). It manages windows. It talks to the window server (the macOS system process that composites all windows on screen). There is exactly one `NSApplication` per process, and it's created for you automatically.

`NSApplication` is the **delegator**. It runs the show, but it needs to ask your code: "Hey, the app just finished launching — do you want to do anything? A file was dropped on the Dock icon — do you want to open it? The user clicked Quit — should I really quit?"

**`NSApplicationDelegate`** is the **protocol** (the interface) that defines all these questions and events. It has methods like:

- `applicationDidFinishLaunching(_:)` — "The app has finished starting up. Do your setup now."
- `applicationWillTerminate(_:)` — "The app is about to quit. Clean up now."
- `applicationShouldTerminate(_:)` — "The user wants to quit. Should I let them?"
- `application(_:open:)` — "The user dropped files on the app. Here they are."

There are dozens of these methods, all optional. You only implement the ones you care about.

The **`NS`** prefix, as we covered in Section 5, stands for NeXTSTEP — historical naming. `NSObject`, `NSApplication`, `NSWindow`, `NSApplicationDelegate` — all from the NeXTSTEP era.

### Why This App Needs an AppDelegate at All

In a simple SwiftUI app — say, a notes app with a text editor — you might not need an AppDelegate. SwiftUI handles the lifecycle, creates windows, and manages state. You declare views, the framework does the rest.

But Go To Sleep is not a simple SwiftUI app. It needs to do things that SwiftUI's declarative model cannot express:

1. **Respond to command-line arguments at launch** (`--bedtime` flag) — SwiftUI has no built-in way to check process arguments at startup
2. **Create and manage a kiosk-mode window** using AppKit's `NSWindow` directly — SwiftUI doesn't expose the level of window control needed for a fullscreen kiosk
3. **Set `NSApp.presentationOptions`** to disable Cmd+Tab, Force Quit, the Dock — these are imperative AppKit APIs with no SwiftUI equivalent
4. **Register a background daemon** with `SMAppService` — a ServiceManagement API call that needs to happen at a specific lifecycle moment
5. **Listen for cross-process notifications** from the daemon — `DistributedNotificationCenter` observers need to be set up early in the app lifecycle
6. **Manage a settings window manually** via `NSWindowController` — needed to work around issues with SwiftUI's built-in Settings scene in menu bar apps

All of these are imperative operations — "do this thing, then do that thing" — and they require access to AppKit APIs that SwiftUI doesn't wrap. The `AppDelegate` is where all this imperative logic lives.

### `@NSApplicationDelegateAdaptor` — The Bridge

Now the big question: if the app uses `@main struct GoToSleepApp: App` for the SwiftUI lifecycle, how does the `AppDelegate` class get involved? The answer is this line from `GoToSleepApp.swift`, line 6:

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

Let's break apart every piece of this:

**`@NSApplicationDelegateAdaptor`** is a **property wrapper** provided by SwiftUI. A property wrapper in Swift is a way to attach custom behavior to a property's getter and setter. Think of it like a Python `@property` decorator combined with a descriptor class, or like a TypeScript getter/setter pair that's been abstracted into a reusable pattern.

What this specific property wrapper does, step by step at runtime:

1. SwiftUI sees `@NSApplicationDelegateAdaptor(AppDelegate.self)` during initialization
2. It creates an instance of your `AppDelegate` class (calling `AppDelegate()`)
3. It creates an internal adaptor object (a SwiftUI-private class that conforms to `NSApplicationDelegate`)
4. It sets the internal adaptor as `NSApp.delegate` — this is what `NSApplication` actually talks to
5. The internal adaptor forwards relevant lifecycle callbacks to your `AppDelegate` instance
6. Your `AppDelegate` instance is stored in the `appDelegate` property, so you can access it from your SwiftUI code

The reason SwiftUI doesn't just set your `AppDelegate` directly as `NSApp.delegate` is that SwiftUI's own lifecycle machinery needs to intercept and manage some delegate callbacks itself. So it wraps your delegate in its own adaptor. This is why `NSApp.delegate as? AppDelegate` fails — `NSApp.delegate` is the SwiftUI adaptor, not your class.

**`(AppDelegate.self)`** — the `.self` suffix on a type in Swift gives you the **metatype** — a reference to the type itself, not an instance. This is like `AppDelegate.class` in Java, or `type(AppDelegate)` conceptually. You're telling the property wrapper "create an instance of this type."

**`var appDelegate`** — the resulting property. After initialization, `appDelegate` holds a reference to your `AppDelegate` instance. You can pass it to views (like `MenuBarView(appDelegate: appDelegate)`) and call methods on it directly.

### The Three Approaches to macOS App Lifecycle (and Why This One Was Chosen)

There are three ways to structure a macOS app's lifecycle, and understanding all three helps you understand why this project uses its particular hybrid:

**Approach 1: Pure SwiftUI (no AppDelegate)**
```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```
Simplest approach. Good for straightforward apps. But you have no access to AppKit lifecycle events, no way to do low-level window management, and no hook for things like daemon registration. This isn't enough for Go To Sleep.

**Approach 2: Pure AppKit (no SwiftUI lifecycle)**
```swift
// main.swift:
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```
Maximum control. You manage everything imperatively. But you lose all of SwiftUI's declarative convenience — no `MenuBarExtra`, no `Settings` scene, no automatic state-driven re-rendering. You'd have to build all the UI with `NSWindow`, `NSButton`, `NSTextField` manually.

**Approach 3: Hybrid — SwiftUI lifecycle + AppDelegate adaptor (what this project does)**
```swift
@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra(...) { ... }
        Settings { ... }
    }
}
```
Best of both worlds. SwiftUI handles the declarative UI — the menu bar scene, the settings scene, state-driven rendering. The `AppDelegate` handles the imperative stuff — kiosk windows, presentation options, daemon registration, notification observers. This is the right choice for Go To Sleep and is a very common pattern in production macOS apps.

### Walking Through AppDelegate.swift — Top to Bottom

Now let's read through every line of the actual `AppDelegate` class.

**File: `GoToSleep/App/AppDelegate.swift`**

#### The Class Declaration (line 5)

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
```

This declares a **class** (not a struct — because `NSApplicationDelegate` requires a class, since it inherits from Objective-C protocols that need reference semantics). Let's break down what's after the colon:

- **`NSObject`** — the root base class of Apple's Objective-C class hierarchy. Almost every class that interacts with Apple frameworks inherits from `NSObject`. It provides basic functionality like memory management, equality comparison, hashing, and string representation. Think of it like Java's `Object` class, or Python's `object`. The reason it's needed here is that `NSApplicationDelegate` is an Objective-C protocol (the `NS` prefix gives this away), and Objective-C protocols can only be adopted by classes that descend from `NSObject`. Swift structs can't do it.

- **`NSApplicationDelegate`** — the protocol we discussed above. By listing it here, `AppDelegate` promises to implement some or all of the lifecycle callback methods that `NSApplication` will call.

#### The Properties (lines 6-12)

```swift
private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
private let showOverlayNotificationName = Notification.Name("com.gotosleep.showOverlayNow")
private let overlayController = OverlayWindowController()
private let focusEnforcer = FocusEnforcer()
private let questionStore = QuestionStore()
private var isShowingOverlay = false
private var settingsWindowController: NSWindowController?
```

All marked `private` — only accessible from within this class. Let's understand each:

- **`showOverlayNotificationName`** — a `Notification.Name` (a type-safe string wrapper) for the cross-process notification. The string `"com.gotosleep.showOverlayNow"` is the channel name that both the app and daemon agree on for the "show the overlay now" signal.

- **`overlayController`** — an instance of `OverlayWindowController` (defined in `Services/OverlayWindowController.swift`). This object is responsible for creating and managing the full-screen kiosk window. It's created once (with `let`, meaning the reference never changes) and reused.

- **`focusEnforcer`** — an instance of `FocusEnforcer` (defined in `Services/FocusEnforcer.swift`). This object watches for other apps stealing focus during the overlay and forcefully reclaims it.

- **`questionStore`** — an instance of `QuestionStore` (defined in `Models/QuestionStore.swift`). This loads the questions from `questions.json` at initialization time and provides random subsets for each session.

- **`isShowingOverlay`** — a boolean flag that prevents re-entrant overlay calls. If the overlay is already showing, a second call to `showOverlay()` should be a no-op.

- **`settingsWindowController`** — an optional (`?`) reference to an `NSWindowController`. The `?` means this can be `nil` — there is no settings window until the user first opens settings, at which point it gets created and stored here. This is like TypeScript's `NSWindowController | null`, or Go's nil pointer for a pointer type.

#### `applicationDidFinishLaunching` (lines 14-23)

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    print("\(debugMarker) applicationDidFinishLaunching args=\(CommandLine.arguments)")
    registerOverlayNotificationObserver()

    // Check if launched with --bedtime flag (by the daemon)
    if CommandLine.arguments.contains("--bedtime") {
        print("\(debugMarker) Detected --bedtime launch, showing overlay")
        showOverlay()
    }
}
```

This is the most important lifecycle callback. macOS calls this method on the delegate **once**, after the application has fully started — the event loop is running, the UI is ready, the process is alive. This is your "the app is now ready, do your initial setup" moment. It's analogous to `componentDidMount` in React, or `ngOnInit` in Angular, or `func (s *Server) Start()` being called after the HTTP server is listening.

Two things happen here:

1. **`registerOverlayNotificationObserver()`** — sets up a listener for cross-process notifications from the daemon (we'll see this method in detail below)

2. **`CommandLine.arguments.contains("--bedtime")`** — checks the process's command-line arguments (like `sys.argv` in Python or `os.Args` in Go). If `--bedtime` is present, it means the **daemon** launched this app specifically to show the bedtime overlay. In that case, it immediately calls `showOverlay()` without waiting for user interaction.

#### `showOverlay()` (lines 25-49)

```swift
func showOverlay() {
    print("\(debugMarker) showOverlay called. isShowingOverlay=\(isShowingOverlay)")
    guard !isShowingOverlay else { return }
    isShowingOverlay = true

    Paths.ensureDirectoryExists()
    Paths.removeFile(at: Paths.sessionCompletedPath)

    let count = AppSettings.shared.questionsPerSession
    let questions = questionStore.selectQuestions(count: count)
    print("\(debugMarker) selectedQuestionsCount=\(questions.count), requestedCount=\(count)")

    guard !questions.isEmpty else {
        print("\(debugMarker) No questions available, aborting overlay")
        isShowingOverlay = false
        return
    }

    focusEnforcer.start()
    NSApp.activate(ignoringOtherApps: true)

    overlayController.show(questions: questions) { [weak self] in
        self?.completeSession()
    }
}
```

This is the core orchestration method. Let's walk through it:

1. **`guard !isShowingOverlay else { return }`** — `guard` is Swift's early-return mechanism. It's like `if (!condition) return;` in other languages, but it's idiomatic Swift. This prevents showing two overlays at once.

2. **`Paths.ensureDirectoryExists()`** — makes sure the `~/Library/Application Support/GoToSleep/` directory exists (creates it if not).

3. **`Paths.removeFile(at: Paths.sessionCompletedPath)`** — deletes the "session completed" marker file. This is important: before starting a new session, we remove any old completion marker. The daemon checks for this file to know if the session finished legitimately. By removing it before starting, we ensure that if the app gets killed mid-session, there won't be a stale marker file tricking the daemon into thinking the session was completed.

4. **`AppSettings.shared.questionsPerSession`** — reads the user's configured question count from persistent storage (UserDefaults).

5. **`questionStore.selectQuestions(count: count)`** — picks a random subset of questions from the question bank.

6. **`focusEnforcer.start()`** — begins monitoring for focus theft (another app taking foreground).

7. **`NSApp.activate(ignoringOtherApps: true)`** — tells macOS to bring this app to the foreground, even if another app currently has focus. The `ignoringOtherApps: true` parameter means "I don't care if the user is in the middle of using another app — bring me forward anyway." This is necessary because the daemon might trigger the overlay while the user is browsing in Safari.

8. **`overlayController.show(questions: questions) { [weak self] in self?.completeSession() }`** — shows the kiosk overlay window and provides a **completion callback**. The `{ [weak self] in self?.completeSession() }` syntax is a **closure** (anonymous function) — like an arrow function in TypeScript or a lambda in Python. The `[weak self]` part is a **capture list** that tells Swift "hold a weak reference to `self` inside this closure." This is important for memory management: without `weak`, the closure would hold a strong reference to the `AppDelegate`, which could create a **retain cycle** (circular reference that prevents memory from being freed — like a circular reference in Python that confuses the garbage collector, except Swift uses reference counting, not garbage collection, so circular references actually leak memory).

#### `dismissOverlay()` (lines 51-56)

```swift
func dismissOverlay() {
    print("\(debugMarker) dismissOverlay called")
    overlayController.dismiss()
    focusEnforcer.stop()
    isShowingOverlay = false
}
```

Tears down the overlay: removes the window, stops the focus enforcer, and resets the re-entrancy flag.

#### `showSettingsWindow()` (lines 58-79)

```swift
func showSettingsWindow() {
    print("\(debugMarker) AppDelegate.showSettingsWindow() called")
    NSApp.activate(ignoringOtherApps: true)
    print("\(debugMarker) Existing settingsWindowController? \(settingsWindowController != nil)")

    if settingsWindowController == nil {
        print("\(debugMarker) Creating settings window controller")
        let settingsHostingController = NSHostingController(rootView: SettingsView())
        let settingsWindow = NSWindow(contentViewController: settingsHostingController)
        settingsWindow.title = "Go To Sleep Settings"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.setContentSize(NSSize(width: 400, height: 320))
        settingsWindow.center()
        settingsWindow.isReleasedWhenClosed = false

        settingsWindowController = NSWindowController(window: settingsWindow)
    }

    print("\(debugMarker) Presenting settings window")
    settingsWindowController?.showWindow(nil)
    settingsWindowController?.window?.makeKeyAndOrderFront(nil)
}
```

This method creates and shows the settings window using AppKit directly, rather than relying on SwiftUI's `Settings` scene. Here's what's happening and why:

**`NSHostingController`** (line 65) is a bridge class. It takes a SwiftUI view (`SettingsView()`) and wraps it so it can be placed inside an AppKit `NSWindow`. Think of it like an adapter plug that lets you plug a European appliance into an American socket. SwiftUI views can't go directly into `NSWindow` — they need this adapter. (`NSHostingView` serves the same purpose but produces a view instead of a view controller.)

**`NSWindow`** (line 66) is the fundamental AppKit window class. Every window you see on macOS — every app window, dialog, sheet — is an `NSWindow`. Creating one directly gives you full control over its behavior.

**`.styleMask`** (line 68) — determines what the window looks like and how it behaves. `[.titled, .closable, .miniaturizable]` means: "show a title bar, include a close button (the red circle), and include a minimize button (the yellow circle)." Notably absent is `.resizable` — this window can't be resized.

**`.isReleasedWhenClosed = false`** (line 71) — by default, when an AppKit window is closed, it's deallocated (freed from memory). This setting says "don't do that — keep the window object in memory so I can show it again later." Without this, closing and reopening settings would crash because the stored `settingsWindowController` would be pointing at a freed object.

**`.makeKeyAndOrderFront(nil)`** (line 78) — "make this window the key window (the one receiving keyboard input) and bring it to the front of all other windows." The `nil` argument means "I'm sending this message on behalf of no particular object."

Why not just use SwiftUI's `Settings` scene? Because in a menu-bar-only app (no Dock icon, `LSUIElement` is true), the built-in `Settings` scene can have quirky behavior — sometimes the window doesn't appear, or it appears behind other apps, or the responder chain (macOS's system for routing events to the right handler) doesn't work correctly. Creating the window manually with AppKit gives reliable behavior.

#### `completeSession()` (lines 81-86)

```swift
private func completeSession() {
    print("\(debugMarker) completeSession called")
    Paths.writeTimestamp(to: Paths.sessionCompletedPath)
    dismissOverlay()
}
```

Called when the user finishes answering all questions in the overlay. It writes a timestamp to the `session-completed` marker file (so the daemon knows the session finished legitimately) and dismisses the overlay. This file-based signaling is covered in depth in Section 13.

#### `registerOverlayNotificationObserver()` (lines 88-98)

```swift
private func registerOverlayNotificationObserver() {
    DistributedNotificationCenter.default().addObserver(
        forName: showOverlayNotificationName,
        object: "com.gotosleep.app",
        queue: .main
    ) { [weak self] _ in
        print("\(self?.debugMarker ?? "[GTS_DEBUG_REMOVE_ME]") Received distributed overlay request")
        self?.showOverlay()
    }
    print("\(debugMarker) Registered distributed overlay observer")
}
```

This sets up a listener for **cross-process notifications**. `DistributedNotificationCenter` is macOS's inter-process messaging system — it lets one process send a notification that another process receives, without them sharing memory or having a socket connection. Think of it like a pub/sub message broker (like Redis Pub/Sub or NATS), but built into the operating system and limited to processes running on the same machine under the same user account.

- **`forName: showOverlayNotificationName`** — listen for notifications with the name `"com.gotosleep.showOverlayNow"`
- **`object: "com.gotosleep.app"`** — only listen for notifications from this specific sender identifier (a string, not an actual object reference)
- **`queue: .main`** — deliver the notification callback on the main thread (important because UI operations must happen on the main thread in AppKit/SwiftUI)
- The closure `{ [weak self] _ in self?.showOverlay() }` — when the notification arrives, call `showOverlay()`

When the daemon wants the already-running app to show the overlay, it posts to this exact notification name. The app receives it and shows the overlay. We'll see the daemon's side of this in Section 11.

#### `registerDaemon()` and `unregisterDaemon()` (lines 102-128)

```swift
func registerDaemon() {
    print("\(debugMarker) registerDaemon called")
    if #available(macOS 13.0, *) {
        let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
        do {
            try service.register()
            print("\(debugMarker) registerDaemon succeeded")
        } catch {
            print("Failed to register daemon: \(error)")
            print("\(debugMarker) registerDaemon failed: \(error)")
        }
    }
}

func unregisterDaemon() {
    print("\(debugMarker) unregisterDaemon called")
    if #available(macOS 13.0, *) {
        let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
        do {
            try service.unregister()
            print("\(debugMarker) unregisterDaemon succeeded")
        } catch {
            print("Failed to unregister daemon: \(error)")
            print("\(debugMarker) unregisterDaemon failed: \(error)")
        }
    }
}
```

These methods register and unregister the background daemon with macOS's process supervisor (`launchd`). We'll explore this fully in Section 12, but briefly:

- **`if #available(macOS 13.0, *)`** — a compile-time and runtime availability check. `SMAppService` was introduced in macOS 13 (Ventura). This syntax says "only run this code on macOS 13 or later." If you try to use an API without this check when your deployment target is earlier, the compiler will refuse to build. The `*` means "and any future platform."

- **`SMAppService.agent(plistName:)`** — creates a reference to a LaunchAgent service defined by the named plist file (which must be bundled in the app's Resources). `SM` stands for **Service Management**, the Apple framework for managing background services.

- **`try service.register()`** — the `try` keyword is Swift's error handling. In Swift, functions that can fail are marked with `throws` (like Go returning `error`), and calling them requires `try`. If the call throws an error, execution jumps to the `catch` block. The `do { try ... } catch { ... }` pattern is Swift's equivalent of Go's `if err != nil` pattern or Python's `try/except`.

That's the entire `AppDelegate.swift` walkthrough. Let's move on to the views.

---

## 7. The Views — MenuBarView, SettingsView, OverlayView, QuestionView, and PermissionsGuideView

### The Views/Models/Services Folder Pattern

Before diving into each view, let's address the folder structure. This project organizes its code into `Views/`, `Models/`, and `Services/`. Is this the "standard" way to structure a Swift/SwiftUI project?

**No, there is no standard.** Swift and SwiftUI have no enforced folder architecture — unlike, say, Rails (which enforces `app/models/`, `app/controllers/`, `app/views/`) or Angular (which has a strong convention of `component/service/module` folders). Swift projects can organize files however the developer wants, and the compiler doesn't care. It compiles all `.swift` files listed in the target, regardless of folder structure.

That said, `Views/Models/Services` is a **common and pragmatic** pattern. The alternatives are:

- **MVVM (Model-View-ViewModel)**: `Views/`, `ViewModels/`, `Models/`, `Services/`. Each view gets a paired "ViewModel" class that holds the view's logic and state. More structured but more boilerplate. This project doesn't have ViewModels — the views hold their own state directly.

- **Feature-first**: `Features/Overlay/`, `Features/Settings/`, `Features/MenuBar/`. Groups files by feature rather than by type. Better for large apps where related files should live together. Overkill for a project this size.

- **Flat**: Everything in one folder. Fine for very small projects, messy for anything larger.

The current structure is perfectly reasonable for a project of this size. `Views` holds SwiftUI view declarations, `Models` holds data types and state, `Services` holds operational code that interacts with the OS. Let's walk through each view.

### MenuBarView — The Dropdown That Appears When You Click the Moon Icon

**File: `GoToSleep/Views/MenuBarView.swift` (all 71 lines)**

```swift
// GoToSleep/Views/MenuBarView.swift, lines 1-6
import SwiftUI

struct MenuBarView: View {
    let appDelegate: AppDelegate
    @ObservedObject private var settings = AppSettings.shared
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
```

**`struct MenuBarView: View`** — this declares a SwiftUI view. The `View` protocol (like `App` is a protocol) requires one thing: a `body` property that returns some UI content. Every SwiftUI component is a struct conforming to `View`. This is fundamentally different from React (where components are functions or classes that return JSX) but conceptually similar — you declare what the UI should look like, and the framework renders it.

**`let appDelegate: AppDelegate`** — a stored property holding a reference to the `AppDelegate`. This is set during initialization (when `GoToSleepApp.swift` line 15 creates `MenuBarView(appDelegate: appDelegate)`). This is the dependency injection we discussed in Section 5.

**`@ObservedObject private var settings = AppSettings.shared`** — this is another property wrapper. Let's break it down:

- **`@ObservedObject`** tells SwiftUI: "this property holds an object that can change, and when it changes, re-render this view." It's like `useState` in React, except instead of a single value, it's an entire object with multiple properties that can each trigger re-renders.
- `AppSettings.shared` is a **singleton** — a single instance shared across the app (like a module-level variable in Python or a package-level `var` in Go). We'll examine `AppSettings` fully in Section 8.
- The `$` prefix (used later as `$settings.isEnabled`) creates a **Binding** — a two-way connection between the UI and the data. When you pass `$settings.isEnabled` to a `Toggle`, changes in the Toggle flow back to the `settings` object, and changes in `settings` flow forward to the Toggle. It's like Angular's two-way binding with `[(ngModel)]`, or React's controlled component pattern where you pass both `value` and `onChange`.

```swift
// GoToSleep/Views/MenuBarView.swift, lines 8-45
var body: some View {
    VStack(spacing: 4) {
        Toggle("Enabled", isOn: $settings.isEnabled)

        Divider()

        Text(statusText)
            .font(.caption)
            .foregroundColor(.secondary)

        Divider()

        Button("Test Overlay") {
            print("\(debugMarker) Test Overlay clicked")
            appDelegate.showOverlay()
        }

        Button("Settings...") {
            print("\(debugMarker) Settings button clicked")
            DispatchQueue.main.async {
                print("\(debugMarker) Forwarding to AppDelegate.showSettingsWindow()")
                appDelegate.showSettingsWindow()
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
    ...
}
```

**`VStack(spacing: 4)`** — a vertical stack layout, like `display: flex; flex-direction: column; gap: 4px;` in CSS. SwiftUI doesn't use CSS — layout is done with container views like `VStack` (vertical), `HStack` (horizontal), and `ZStack` (layered/overlapping).

**`Toggle("Enabled", isOn: $settings.isEnabled)`** (line 10) — a toggle switch (on/off). The `$settings.isEnabled` binding means: when the user flips the toggle, it immediately writes the new value to `settings.isEnabled`, which is persisted to UserDefaults via `@AppStorage`. There's no "save" button — changes are immediate and persistent.

**`Button("Test Overlay") { appDelegate.showOverlay() }`** (lines 20-23) — calls `showOverlay()` directly on the injected `appDelegate`. This triggers the full kiosk overlay flow.

**`Button("Settings...") { DispatchQueue.main.async { appDelegate.showSettingsWindow() } }`** (lines 25-31) — notice the `DispatchQueue.main.async { ... }` wrapper. `DispatchQueue.main.async` means "schedule this closure to run on the main thread during the next iteration of the run loop." This is a common pattern in AppKit/SwiftUI when you need to do something after the current event-processing cycle completes. Without it, opening the settings window from inside a menu bar popover can behave strangely because the popover is still in the process of handling the click event.

**`.keyboardShortcut(",", modifiers: .command)`** (line 32) — binds Cmd+, to this button. Cmd+, is the universal macOS shortcut for opening preferences/settings.

**`NSApp.terminate(nil)`** (line 37) — terminates the application process. `NSApp` is the global `NSApplication` instance.

```swift
// GoToSleep/Views/MenuBarView.swift, lines 47-61
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
```

This is a **computed property** — like a Python `@property` or a TypeScript `get` accessor. It's recalculated every time the view re-renders. It uses `TimeCheck.isWithinBedtimeWindow()` (from the shared `Shared/TimeCheck.swift`) to determine whether it's currently bedtime. The `formatHour` helper on lines 63-70 converts an hour integer (like `21`) into a human-readable string (like `"9 PM"`).

### SettingsView — The Configuration Form

**File: `GoToSleep/Views/SettingsView.swift` (all 75 lines)**

```swift
// GoToSleep/Views/SettingsView.swift, lines 3-12
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"

    private let gracePeriodOptions = [
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 hour"),
        (120, "2 hours"),
    ]
```

`gracePeriodOptions` is an array of tuples — Swift tuples are like Python tuples. Each one is a `(Int, String)` pair mapping a value (minutes) to a display label.

```swift
// GoToSleep/Views/SettingsView.swift, lines 14-44
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
```

**`Form`** — a container that automatically styles its children as a macOS form (labels on the left, controls on the right). Think of it like a `<form>` in HTML but with automatic layout.

**`Picker("Bedtime starts at", selection: $settings.bedtimeStartHour)`** — a dropdown picker. The `selection:` parameter is a binding (`$`) to the stored setting. When the user picks a different hour, it immediately writes to `settings.bedtimeStartHour`, which is backed by `@AppStorage` → UserDefaults → persisted to disk. No save button needed.

**`ForEach(0..<24, id: \.self)`** — iterates over a range (0 through 23). `id: \.self` tells SwiftUI to use the value itself as the unique identifier for each item (since these are just integers). `.tag(hour)` associates each rendered `Text` with its integer value, so the picker knows which option maps to which value.

**`Stepper(..., value: $settings.questionsPerSession, in: 1...10)`** — a stepper control (plus/minus buttons). The `in: 1...10` constrains the value to the range 1 to 10. The `...` operator creates a **closed range** in Swift (inclusive on both ends), similar to Python's `range(1, 11)`.

Lines 47-64 are `.onChange(of:)` modifiers that print debug messages when settings change. These are debug instrumentation only — tagged with `[GTS_DEBUG_REMOVE_ME]`.

Every control in this form writes directly to persistent storage through bindings. There is no manual "save" step, no submit handler, no form validation. The moment you change a value, it's saved. This is the expected pattern for macOS settings.

### OverlayView — The Full-Screen Bedtime Questionnaire

**File: `GoToSleep/Views/OverlayView.swift` (all 103 lines)**

```swift
// GoToSleep/Views/OverlayView.swift, lines 3-15
struct OverlayView: View {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    let questions: [Question]
    let onComplete: () -> Void

    @State private var currentIndex = 0
    @State private var answers: [String]

    init(questions: [Question], onComplete: @escaping () -> Void) {
        self.questions = questions
        self.onComplete = onComplete
        self._answers = State(initialValue: Array(repeating: "", count: questions.count))
    }
```

**`let onComplete: () -> Void`** — a stored closure (function value). `() -> Void` is a function type meaning "takes no arguments, returns nothing" — like `() => void` in TypeScript or `Callable[[], None]` in Python. When the user finishes all questions, this closure is called, which ultimately calls `AppDelegate.completeSession()`.

**`@escaping`** in the `init` parameter — this tells the compiler "this closure will be stored and called later, not just during the init call." By default in Swift, closures passed to functions are assumed to be non-escaping (they're used within the function and then discarded). If you want to store a closure in a property, you must mark it `@escaping`. This is a Swift safety feature — it makes you explicitly acknowledge that the closure might outlive the function call, which has implications for memory management.

**`@State`** is another property wrapper — the most fundamental one in SwiftUI. It tells SwiftUI "this property is **owned by this view** and when it changes, re-render the view." Unlike `@ObservedObject` (which observes an external object), `@State` creates and owns the state directly. Think of it as `useState` in React:

```typescript
// React equivalent:
const [currentIndex, setCurrentIndex] = useState(0);
const [answers, setAnswers] = useState(Array(questions.length).fill(""));
```

**`self._answers = State(initialValue: ...)`** (line 14) — this is a workaround for initializing `@State` properties in an `init`. Normally `@State` properties are initialized at declaration (`@State var x = 0`), but when the initial value depends on a constructor parameter (like `questions.count`), you need to use the underscore-prefixed access (`_answers`) which accesses the property wrapper itself rather than the wrapped value. This is a Swift-specific quirk.

```swift
// GoToSleep/Views/OverlayView.swift, lines 17-27
private var currentAnswer: Binding<String> {
    $answers[currentIndex]
}

private var isCurrentAnswered: Bool {
    !answers[currentIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private var isLastQuestion: Bool {
    currentIndex == questions.count - 1
}
```

Three computed properties that derive values from state:
- `currentAnswer` — a binding to the current question's answer in the array. `$answers[currentIndex]` produces a `Binding<String>`, which is a read-write reference that QuestionView uses to update the answer.
- `isCurrentAnswered` — true if the current answer has non-whitespace content.
- `isLastQuestion` — true if we're on the last question.

```swift
// GoToSleep/Views/OverlayView.swift, lines 29-71
var body: some View {
    ZStack {
        // Dark calming background
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                     Color(red: 0.1, green: 0.08, blue: 0.2)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 40) {
            Spacer()

            // Progress indicator
            Text("\(currentIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                ...

            // Question
            QuestionView(question: questions[currentIndex], answer: currentAnswer)
                .frame(maxWidth: 500)
                .id(currentIndex) // force re-render on index change

            // Navigation button
            Button(action: advance) {
                Text(isLastQuestion ? "Finish" : "Next")
                    ...
            }
            .disabled(!isCurrentAnswered)
            .keyboardShortcut(.return, modifiers: [])

            Spacer()
        }
    }
}
```

**`ZStack`** — a "z-axis stack" — layers views on top of each other. The gradient background is at the bottom of the Z stack, and the content is layered on top. Like `position: absolute` layering in CSS.

**`.id(currentIndex)`** (line 53) — a subtle but important modifier. When `currentIndex` changes, SwiftUI would normally try to *update* the existing `QuestionView` in place. The `.id()` modifier says "treat this as a completely new view identity whenever this value changes." This forces SwiftUI to destroy the old `QuestionView` and create a fresh one, resetting any internal state (like text field focus). Without this, switching between questions could leave stale UI state.

**`.keyboardShortcut(.return, modifiers: [])`** (line 66) — pressing Enter/Return triggers this button. `modifiers: []` means no modifier keys required (no Cmd, no Shift — just bare Return).

```swift
// GoToSleep/Views/OverlayView.swift, lines 80-102
private func advance() {
    print("\(debugMarker) OverlayView.advance called index=\(currentIndex)")
    guard isCurrentAnswered else { return }

    let q = questions[currentIndex]
    print("\(debugMarker) Logging answer for questionId=\(q.id)")
    AnswerLogger.log(
        questionId: q.id,
        questionText: q.text,
        answer: answers[currentIndex]
    )

    if isLastQuestion {
        print("\(debugMarker) Last question answered, calling onComplete")
        onComplete()
    } else {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex += 1
        }
    }
}
```

This is the state machine transition function. On each call:
1. Guard: don't advance if the current answer is empty
2. Log the answer to the JSONL file via `AnswerLogger`
3. If this was the last question, call `onComplete()` which triggers `AppDelegate.completeSession()`
4. Otherwise, increment `currentIndex` (wrapped in an animation so the transition is smooth)

The overlay is a **deterministic finite state machine**. The state is `(currentIndex, answers[])`. The only transition is `advance()`, which moves `currentIndex` forward by 1. The terminal state is reaching `isLastQuestion`, which triggers the completion callback and exits the overlay. There's no going back, no skipping, no branching.

### QuestionView — Rendering a Single Question

**File: `GoToSleep/Views/QuestionView.swift` (all 64 lines)**

```swift
// GoToSleep/Views/QuestionView.swift, lines 3-7
struct QuestionView: View {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    let question: Question
    @Binding var answer: String
```

**`@Binding var answer: String`** — a **binding** is a two-way reference to state owned by a parent view. Think of it like a pointer. `OverlayView` owns the `answers` array via `@State`, and it passes a binding (`$answers[currentIndex]`) down to `QuestionView`. When `QuestionView` writes to `answer`, it's actually writing into `OverlayView`'s `answers` array. This is how child components update parent state in SwiftUI — similar to React's pattern of passing `setValue` callbacks, but formalized into a single `Binding` type.

In TypeScript terms, `@Binding` is roughly equivalent to passing both the value and its setter as a bundled pair:
```typescript
// TypeScript equivalent:
type Binding<T> = { get: () => T; set: (v: T) => void };
```

```swift
// GoToSleep/Views/QuestionView.swift, lines 16-21
switch question.type {
case .freeText:
    freeTextInput
case .multipleChoice:
    multipleChoiceInput
}
```

Swift's `switch` statement must be **exhaustive** — you must handle every possible case. Since `QuestionType` is an enum with exactly two cases (`.freeText` and `.multipleChoice`), this switch covers both. If you added a third case to the enum and forgot to handle it here, the compiler would refuse to build.

```swift
// GoToSleep/Views/QuestionView.swift, lines 28-37
private var freeTextInput: some View {
    TextEditor(text: $answer)
        .font(.body)
        .padding(8)
        .frame(height: 120)
        .scrollContentBackground(.hidden)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .foregroundColor(.white)
}
```

`TextEditor` is a multi-line text input (like `<textarea>` in HTML). It binds directly to `$answer`, so every keystroke updates the binding immediately.

```swift
// GoToSleep/Views/QuestionView.swift, lines 39-63
private var multipleChoiceInput: some View {
    VStack(spacing: 12) {
        ForEach(question.choices ?? [], id: \.self) { choice in
            Button {
                answer = choice
            } label: {
                HStack {
                    Text(choice)
                        .foregroundColor(.white)
                    Spacer()
                    if answer == choice {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                .padding(12)
                .background(answer == choice ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
}
```

For multiple choice, each choice is rendered as a button. Clicking a button sets `answer = choice` — the binding flows up to `OverlayView`'s `answers` array. The selected choice gets a blue background and a checkmark icon. `question.choices ?? []` uses the **nil-coalescing operator** (`??`) — if `choices` is `nil` (since it's an optional `[String]?`), default to an empty array. This is like JavaScript's `??` operator or Python's `x or []` pattern.

### PermissionsGuideView — The Setup Wizard (Currently Unused)

**File: `GoToSleep/Views/PermissionsGuideView.swift` (all 122 lines)**

This view is a first-run setup wizard that guides the user through granting accessibility permissions and enabling the background daemon. However, **it is not currently wired into the app's scene graph** — neither `GoToSleepApp.swift`'s `body` nor any other active code path creates a `PermissionsGuideView`. It exists in the source code but is effectively dead code.

The interesting part to note is lines 107-116:

```swift
// GoToSleep/Views/PermissionsGuideView.swift, lines 107-116
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
```

This uses the **problematic `NSApp.delegate as? AppDelegate` pattern** we discussed in Section 5. In the SwiftUI lifecycle, `NSApp.delegate` is SwiftUI's internal adaptor object, not your `AppDelegate`. So `NSApp.delegate as? AppDelegate` evaluates to `nil`, the `if let` fails, and the daemon never gets registered. The `else` branch prints an error message, but the button in the UI would appear to do nothing. If this view were ever wired into the app, this bug would need to be fixed by passing `AppDelegate` via dependency injection (the same pattern `MenuBarView` uses).

---

## 8. The Models — AppSettings, Question, SessionLog, and QuestionStore

### What "Models" Means in This Project

In strict MVVM (Model-View-ViewModel) architecture — a pattern common in Swift/iOS development — "Models" would mean pure data types with no behavior: simple containers that hold data, like DTOs (Data Transfer Objects) in TypeScript or plain dataclasses in Python. They'd have no knowledge of the UI, no persistence logic, no side effects.

This project's `Models/` folder is **not that strict**. It contains a mix of:

1. **Pure data types** (actual DTOs) — `Question` and `SessionLog`
2. **A stateful singleton with persistence logic** — `AppSettings`
3. **A data-loading service** — `QuestionStore`

Is this wrong? No. It's pragmatic. In a small project, having `AppSettings` in Models (even though it has persistence behavior) is fine — it's where you'd naturally look for "the settings." Having `QuestionStore` in Models (even though it loads from a file) makes sense because it's closely tied to the `Question` data type. Strict architectural purity matters more in large team projects. In a solo project of this size, this organization is perfectly clear and navigable.

### Question — A Pure Data Type

**File: `GoToSleep/Models/Question.swift` (all 13 lines)**

```swift
// GoToSleep/Models/Question.swift, lines 1-13
import Foundation

enum QuestionType: String, Codable {
    case freeText = "free_text"
    case multipleChoice = "multiple_choice"
}

struct Question: Codable, Identifiable {
    let id: String
    let text: String
    let type: QuestionType
    let choices: [String]?
}
```

This is one of the simplest files in the project, but it demonstrates several important Swift concepts.

**`enum QuestionType: String, Codable`** — an enumeration (sum type). In Go terms, this is like defining a set of typed constants. In TypeScript, it's like a string union type: `type QuestionType = "free_text" | "multiple_choice"`. The `: String` means each case has a raw string value. The `: Codable` is a **protocol conformance** — let's explain Codable now.

**`Codable`** is a Swift protocol that means "this type can be automatically serialized to and deserialized from external formats like JSON." It's like:
- `json.Marshal`/`json.Unmarshal` with struct tags in Go
- `JSON.parse`/`JSON.stringify` with TypeScript interfaces (but type-safe at compile time)
- `@dataclass` with `json.loads`/`json.dumps` or Pydantic's `BaseModel` in Python

When you mark a type as `Codable` and all its properties are themselves `Codable` (which `String`, `Int`, `Bool`, `[String]`, and optionals of `Codable` types all are), Swift automatically generates the JSON encoding/decoding code at compile time. You don't write a parser, a serializer, or a schema — the compiler does it for you based on the property names and types. The enum's raw string values (`"free_text"`, `"multiple_choice"`) are what appear in the JSON.

**`Identifiable`** — a protocol that requires the type to have an `id` property. SwiftUI uses this when iterating over collections (in `ForEach`) to uniquely identify each item for efficient re-rendering. It's like React's `key` prop, but enforced at the type level.

**`let choices: [String]?`** — the `?` makes this an **optional**. An optional in Swift means "this value might be present, or it might be nil." It's like:
- `string[] | null` in TypeScript (but enforced — you can't accidentally use it without checking for nil)
- `*[]string` in Go (a pointer that might be nil)
- `Optional[List[str]]` in Python's type hints

For free-text questions, `choices` is `nil`. For multiple-choice questions, it's an array of strings.

### SessionLog — Another Pure Data Type

**File: `GoToSleep/Models/SessionLog.swift` (all 8 lines)**

```swift
// GoToSleep/Models/SessionLog.swift, lines 1-8
import Foundation

struct SessionLog: Codable {
    let timestamp: Date
    let questionId: String
    let questionText: String
    let answer: String
}
```

This represents a single logged answer. `Date` is Swift's date/time type (like Go's `time.Time` or Python's `datetime.datetime`). Because it conforms to `Codable`, instances of `SessionLog` can be directly serialized to JSON using `JSONEncoder`. The `AnswerLogger` service (Section 9) uses this type to write entries to the `answers.jsonl` file.

### AppSettings — The Stateful Singleton With Persistence

**File: `GoToSleep/Models/AppSettings.swift` (all 33 lines)**

```swift
// GoToSleep/Models/AppSettings.swift, lines 1-33
import SwiftUI

/// Central settings store using @AppStorage backed by a shared UserDefaults suite.
/// The shared suite ("com.gotosleep.shared") lets the daemon read these settings too.
class AppSettings: ObservableObject {
    static let suiteName = "com.gotosleep.shared"
    static let shared = AppSettings()
    static let debugMarker = "[GTS_DEBUG_REMOVE_ME]"

    @AppStorage("questionsPerSession", store: UserDefaults(suiteName: suiteName))
    var questionsPerSession: Int = 3

    @AppStorage("gracePeriodMinutes", store: UserDefaults(suiteName: suiteName))
    var gracePeriodMinutes: Int = 60

    @AppStorage("bedtimeStartHour", store: UserDefaults(suiteName: suiteName))
    var bedtimeStartHour: Int = 21

    @AppStorage("bedtimeEndHour", store: UserDefaults(suiteName: suiteName))
    var bedtimeEndHour: Int = 7

    @AppStorage("isEnabled", store: UserDefaults(suiteName: suiteName))
    var isEnabled: Bool = true

    @AppStorage("hasCompletedSetup", store: UserDefaults(suiteName: suiteName))
    var hasCompletedSetup: Bool = false

    private init() {
        print("\(Self.debugMarker) AppSettings initialized")
        ...
    }
}
```

This is the most concept-dense file in the Models folder. Let's unpack everything.

**`class AppSettings: ObservableObject`** — this is a `class` (not a `struct`), because `ObservableObject` requires reference semantics. **`ObservableObject`** is a SwiftUI protocol that says "this object publishes changes, and any SwiftUI view observing it should re-render when it changes." It's the publisher in a pub/sub relationship. When any `@AppStorage` property on this object changes, SwiftUI automatically notifies all views that hold this object via `@ObservedObject`, and those views re-render.

Think of it like a reactive store — similar to MobX in React, or Vuex/Pinia in Vue. You mutate a property, and all subscribed UI components automatically update.

**`static let shared = AppSettings()`** — the **singleton pattern**. `static let` creates a type-level constant (like a class variable in Python or a package-level `var` in Go). There is exactly one `AppSettings` instance for the entire app, created the first time this property is accessed (Swift guarantees thread-safe lazy initialization for `static let`). Every view that does `AppSettings.shared` gets the same instance.

**`private init()`** — the constructor is `private`, which means only `AppSettings` itself can create instances. This enforces the singleton pattern — outside code can't accidentally create a second `AppSettings()`.

**`@AppStorage`** — this is where the real magic happens. Let's go deep.

`@AppStorage` is a SwiftUI property wrapper that creates a **persistent, reactive binding to UserDefaults**. Let me unpack both halves of that:

**UserDefaults** is macOS's built-in key-value storage system. Think of it as:
- `localStorage` in a web browser
- A simple INI/config file that the OS manages for you
- A lightweight, persistent dictionary on disk

Every macOS app has a default UserDefaults store where it can save simple values (strings, numbers, booleans, dates, small data blobs). The data is persisted across app launches — it survives quitting and relaunching the app, even rebooting the machine. Under the hood, UserDefaults writes to a plist file in `~/Library/Preferences/`.

**Suite name**: Normally, each app has its own isolated UserDefaults store. But by specifying a **suite name** (`"com.gotosleep.shared"`), you create a **shared** store that multiple processes can access. This is how the app and daemon share settings — both open the same suite and read/write the same keys. It's like two programs opening the same Redis instance, except it's a built-in macOS feature.

So when you see:

```swift
@AppStorage("bedtimeStartHour", store: UserDefaults(suiteName: suiteName))
var bedtimeStartHour: Int = 21
```

What actually happens at runtime:

1. When `bedtimeStartHour` is **read**, the property wrapper checks UserDefaults for the key `"bedtimeStartHour"` in the `"com.gotosleep.shared"` suite. If the key exists, it returns the stored value. If it doesn't exist (first run), it returns the default value `21`.

2. When `bedtimeStartHour` is **written** (e.g., the user picks a new hour in the Settings picker), the property wrapper writes the new value to UserDefaults. This write is automatically persisted to disk. Simultaneously, because `AppSettings` is an `ObservableObject`, the write triggers a change notification, and all observing SwiftUI views re-render.

3. In another process (the daemon), `UserDefaults(suiteName: "com.gotosleep.shared")?.object(forKey: "bedtimeStartHour")` reads the same value from the same file on disk.

The `= 21` is the default value — used only if the key has never been set in UserDefaults. For a fresh install, bedtime starts at 9 PM (hour 21), ends at 7 AM (hour 7), 3 questions per session, 60-minute grace period, enabled by default.

### QuestionStore — Loading Questions From a JSON File

**File: `GoToSleep/Models/QuestionStore.swift` (all 27 lines)**

```swift
// GoToSleep/Models/QuestionStore.swift, lines 3-18
class QuestionStore {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private let questions: [Question]

    init() {
        print("\(debugMarker) QuestionStore init started")
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Question].self, from: data) else {
            print("\(debugMarker) QuestionStore failed to load questions.json")
            questions = []
            return
        }
        print("\(debugMarker) QuestionStore loaded questions count=\(decoded.count)")
        questions = decoded
    }
```

**`Bundle.main`** is a reference to the running application's **bundle** — the `.app` directory structure we discussed in Section 2. `Bundle.main.url(forResource: "questions", withExtension: "json")` asks: "do you have a file called `questions.json` in the app's Resources?" At build time, the pbxproj file specifies that `questions.json` should be copied into the bundle's Resources folder (line 303: `A100000017 /* questions.json in Resources */`). At runtime, this method returns the URL to that bundled copy.

Think of it like how a Go binary can embed files with `//go:embed`, or how a webpack-bundled Node app imports a JSON file — the data file is packaged alongside the code.

**`guard let ... else { ... return }`** — this is Swift's pattern for chaining multiple failable operations with early exit. The `guard` checks three things in sequence:
1. Can we find the `questions.json` file in the bundle?
2. Can we read its contents into a `Data` blob?
3. Can we decode that data as a JSON array of `Question` objects?

If any step fails, execution jumps to the `else` block, which sets `questions` to an empty array and returns. `try?` is a variant of `try` that converts errors into `nil` rather than throwing — it's like Go's `result, _ := someFunction()` where you intentionally ignore the error.

**`JSONDecoder().decode([Question].self, from: data)`** — decodes JSON data into a Swift type. `[Question].self` is the metatype for "an array of Question" — it tells the decoder what type to produce. Because `Question` conforms to `Codable`, the decoder knows how to map JSON keys to struct properties automatically.

```swift
// GoToSleep/Models/QuestionStore.swift, lines 20-27
/// Returns a random selection of questions for a session.
func selectQuestions(count: Int) -> [Question] {
    let selectedQuestions = Array(questions.shuffled().prefix(count))
    print("\(debugMarker) selectQuestions requested=\(count), returned=\(selectedQuestions.count)")
    return selectedQuestions
}
```

`questions.shuffled()` returns a randomly reordered copy of the array (like Python's `random.sample` or lodash's `_.shuffle`). `.prefix(count)` takes the first `count` elements (like Python's `[:count]` slice). The result is a random subset of questions for this session.

### The Questions Data File

**File: `GoToSleep/Resources/questions.json` (all 44 lines)**

This file contains 7 questions — a mix of free-text and multiple-choice:

```json
[
    {
        "id": "reflect-today",
        "text": "What's one thing that went well today?",
        "type": "free_text",
        "choices": null
    },
    {
        "id": "energy-level",
        "text": "How would you describe your energy level right now?",
        "type": "multiple_choice",
        "choices": ["Wired — I could keep going for hours",
                    "Tired but fighting it",
                    "Genuinely exhausted",
                    "Somewhere in between"]
    },
    ...
]
```

The JSON keys map directly to the `Question` struct properties thanks to `Codable`. The `type` field's string values (`"free_text"`, `"multiple_choice"`) map to the `QuestionType` enum's raw values. The `choices` field is `null` for free-text questions and an array of strings for multiple-choice.

---

## 9. The Services — OverlayWindowController, FocusEnforcer, and AnswerLogger

The `Services/` folder contains the operational code that interacts directly with the operating system — creating windows, monitoring application focus, and writing files. These are the files where SwiftUI's declarative world meets AppKit's imperative reality.

### OverlayWindowController — The Kiosk Mode Window

**File: `GoToSleep/Services/OverlayWindowController.swift` (all 66 lines)**

This is arguably the most interesting file in the project from an Apple-platform perspective, because it directly manipulates macOS's window server to create a locked-down kiosk experience.

#### KioskWindow — A Custom NSWindow Subclass

```swift
// GoToSleep/Services/OverlayWindowController.swift, lines 1-9
import AppKit
import SwiftUI

/// NSWindow subclass that refuses to close and always stays key.
class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func close() { /* no-op — cannot be closed by the system */ }
}
```

**`import AppKit`** — we're importing AppKit (the old, imperative framework), not SwiftUI. This file works directly with macOS window management at the AppKit level because SwiftUI doesn't expose the low-level window control needed for kiosk mode.

**`class KioskWindow: NSWindow`** — this creates a subclass of `NSWindow`. `NSWindow` is the fundamental window class in macOS — every window on your screen (app windows, dialog boxes, menus, the Dock itself) is an `NSWindow` or subclass. Think of it as the macOS equivalent of a browser's `window` object, but for a native desktop window.

**Subclassing** in Swift works like in Python or TypeScript classes — you inherit all the parent's behavior and can selectively override methods. The `: NSWindow` syntax declares inheritance (like `class KioskWindow(NSWindow):` in Python or `class KioskWindow extends NSWindow` in TypeScript).

Three things are overridden:

- **`override var canBecomeKey: Bool { true }`** — the "key window" in macOS is the window that receives keyboard input. Think of it as "which window has focus." By always returning `true`, we ensure this window can always receive keyboard input (needed so the user can type answers into the text fields).

- **`override var canBecomeMain: Bool { true }`** — the "main window" is the primary window of the app. Returning `true` ensures the kiosk window is treated as the app's primary window. Borderless windows (windows without title bars) normally can't become key or main — these overrides force it.

- **`override func close() { /* no-op */ }`** — this is the critical trick. Normally, calling `close()` on an `NSWindow` removes it from the screen and releases it. By overriding `close()` to do nothing, the window **cannot be closed by the operating system or by any code that calls the standard `close()` method**. This is like overriding `window.close()` in JavaScript to be a no-op — except at the native OS level. Cmd+W, the close button (if there were one), and any system process that tries to close windows will all call this method and hit the no-op.

#### Creating the Overlay Window

```swift
// GoToSleep/Services/OverlayWindowController.swift, lines 12-55
class OverlayWindowController {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private var window: KioskWindow?

    func show(questions: [Question], onComplete: @escaping () -> Void) {
        ...
        guard let screen = NSScreen.main else { ... return }

        let window = KioskWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let overlayView = OverlayView(questions: questions, onComplete: onComplete)
        window.contentView = NSHostingView(rootView: overlayView)

        window.makeKeyAndOrderFront(nil)
        ...
```

Let's understand each of these window properties:

**`contentRect: screen.frame`** — the window's size and position. `NSScreen.main` is the primary display (the screen with the menu bar). `.frame` gives the screen's full rectangle (position and dimensions in points). So the window is created at exactly the size of the screen — full-screen coverage.

**`styleMask: .borderless`** — the window has no title bar, no close/minimize/maximize buttons, no border — just raw content filling the entire frame. A regular window would use `.titled` for a title bar, `.closable` for the red close button, etc. Borderless means nothing — just your content and the window edges.

**`backing: .buffered`** — this controls how the window's content is drawn. `.buffered` means the content is drawn into an off-screen buffer first, then composited onto the screen. This is the standard choice for virtually all modern windows. The alternative (`.nonretained`) is rarely used.

**`window.level = .screenSaver`** — **this is critically important**. macOS manages windows in layers, called "levels." Normal app windows are at a standard level. The Dock is at a higher level. The menu bar is even higher. `.screenSaver` is the level used by screen savers — it sits above almost everything, including the Dock and most other windows. By setting the overlay to this level, it appears on top of all other content. The only things above `.screenSaver` are system-level overlays like the login screen.

Think of it like CSS `z-index` — `.screenSaver` is a very high z-index.

**`window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`** — macOS has a concept of "Spaces" (virtual desktops, like Linux workspaces). `.canJoinAllSpaces` means the window appears on every Space, so the user can't escape by switching desktops. `.fullScreenAuxiliary` means the window can coexist with full-screen apps rather than being pushed off to a separate Space.

**`window.contentView = NSHostingView(rootView: overlayView)`** — **`NSHostingView`** is the SwiftUI-in-AppKit bridge (the sibling of `NSHostingController` that we saw in `showSettingsWindow()`). It takes a SwiftUI view (`OverlayView`) and wraps it into an AppKit `NSView` that can be placed as the window's content. This is how the SwiftUI overlay UI gets into the AppKit window.

#### The Presentation Options — Locking Down the System

```swift
// GoToSleep/Services/OverlayWindowController.swift, lines 43-52
// Kiosk presentation options — blocks Cmd+Tab, force quit, hides dock/menu
// CRITICAL: .disableProcessSwitching MUST include .hideDock or it crashes
NSApp.presentationOptions = [
    .hideDock,
    .hideMenuBar,
    .disableProcessSwitching,
    .disableForceQuit,
    .disableSessionTermination,
]
```

**`NSApp.presentationOptions`** is a process-level setting that changes how the entire operating system behaves while this app is in the foreground. This is not a window-level setting — it affects the entire system:

- **`.hideDock`** — hides the Dock (the bar of app icons at the bottom of the screen). The user can't click on other apps in the Dock.
- **`.hideMenuBar`** — hides the menu bar (the bar at the top of the screen with File, Edit, etc., plus the clock, Wi-Fi, battery). The user can't click any menu bar items.
- **`.disableProcessSwitching`** — disables Cmd+Tab (the app switcher) and Mission Control. The user cannot switch to another app.
- **`.disableForceQuit`** — disables Cmd+Option+Esc (the Force Quit dialog). The user cannot force-quit apps through the normal UI.
- **`.disableSessionTermination`** — prevents the user from logging out while the overlay is active.

The comment on line 44 is important: **`.disableProcessSwitching` MUST be combined with `.hideDock` or `.autoHideDock`**. If you try to set `.disableProcessSwitching` without one of those, macOS will crash your app. This is an undocumented or poorly-documented requirement in AppKit — the system enforces that you can't disable app switching without also hiding the Dock (presumably because leaving the Dock visible while app switching is disabled would be a confusing state).

Together, these options create a **kiosk-mode experience** — the user's entire screen is taken over, and the normal escape routes (Cmd+Tab, Force Quit, clicking the Dock) are all disabled. The only way out is to answer the questions, or to force-kill the app process from a terminal or Activity Monitor (and even then, the daemon will relaunch it).

#### Dismissing the Overlay

```swift
// GoToSleep/Services/OverlayWindowController.swift, lines 57-65
func dismiss() {
    print("\(debugMarker) OverlayWindowController.dismiss called")
    NSApp.presentationOptions = []
    window?.orderOut(nil)
    // Use the NSWindow direct close (bypass our KioskWindow override)
    window?.setValue(nil, forKey: "contentView")
    window = nil
    print("\(debugMarker) Overlay window dismissed and released")
}
```

- **`NSApp.presentationOptions = []`** — resets all presentation options to default. The Dock comes back, the menu bar comes back, Cmd+Tab works again.
- **`window?.orderOut(nil)`** — removes the window from the screen without calling `close()` (which we overrode as a no-op). `orderOut` means "take this window out of the visible window list."
- **`window?.setValue(nil, forKey: "contentView")`** — sets the content view to nil via Key-Value Coding (KVC), which releases the SwiftUI hosting view and its entire view tree. This is necessary because simply setting `window = nil` might not immediately release the content if there are remaining references.
- **`window = nil`** — releases the window reference. Since nothing else holds a reference to the KioskWindow, it gets deallocated (freed from memory).

### FocusEnforcer — Reclaiming Focus From Other Apps

**File: `GoToSleep/Services/FocusEnforcer.swift` (all 40 lines)**

The `FocusEnforcer` is a backup security measure. The presentation options (`.disableProcessSwitching`) should prevent app switching entirely, but edge cases exist — system dialogs, accessibility-triggered focus changes, or other processes that bypass normal focus rules. `FocusEnforcer` monitors for these edge cases and forcefully reclaims focus.

```swift
// GoToSleep/Services/FocusEnforcer.swift, lines 6-18
class FocusEnforcer {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private var observer: Any?

    func start() {
        print("\(debugMarker) FocusEnforcer.start called")
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }
    }
```

**`NSWorkspace`** is an AppKit class that represents the user's desktop environment. `NSWorkspace.shared` is the singleton instance. Its `notificationCenter` is a **local** notification center (not `DistributedNotificationCenter` — this one is process-internal, but it receives system-wide workspace events within the current user session).

**`NSWorkspace.didActivateApplicationNotification`** is a notification name that fires whenever **any application** on the system becomes the active (foreground) application. By observing this, the `FocusEnforcer` gets a callback every time the user (or the system) switches to a different app.

```swift
// GoToSleep/Services/FocusEnforcer.swift, lines 30-39
private func handleActivation(_ notification: Notification) {
    print("\(debugMarker) FocusEnforcer.handleActivation notification received")
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
          app.bundleIdentifier != Bundle.main.bundleIdentifier else {
        return
    }
    // Another app stole focus — reclaim it
    print("\(debugMarker) Focus stolen by \(app.bundleIdentifier ?? "unknown"), re-activating app")
    NSApp.activate(ignoringOtherApps: true)
}
```

The logic: when any app activates, extract the `NSRunningApplication` from the notification's `userInfo` dictionary. If it's a *different* app (its bundle identifier doesn't match ours), forcefully re-activate our app with `NSApp.activate(ignoringOtherApps: true)`. If it's our own app activating (which also triggers this notification), do nothing.

**`notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication`** — `userInfo` is an optional dictionary attached to the notification containing extra context. The `as?` is a **conditional cast** — it tries to cast the dictionary value to `NSRunningApplication` and returns `nil` if the cast fails. The `guard let ... else { return }` pattern checks both that the cast succeeded and that the bundle identifier is different, and returns early if either check fails.

```swift
// GoToSleep/Services/FocusEnforcer.swift, lines 20-28
func stop() {
    print("\(debugMarker) FocusEnforcer.stop called")
    if let observer = observer {
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
        print("\(debugMarker) FocusEnforcer observer removed")
    }
}
```

Cleanup: removes the observer when the overlay is dismissed, so the `FocusEnforcer` stops intercepting focus changes during normal operation.

### AnswerLogger — Writing Answers to Disk

**File: `GoToSleep/Services/AnswerLogger.swift` (all 46 lines)**

```swift
// GoToSleep/Services/AnswerLogger.swift, lines 3-9
enum AnswerLogger {
    private static let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
```

**`enum AnswerLogger`** — using an `enum` with no cases as a "namespace" is a common Swift pattern. Since this enum has no cases, you can never create an instance of it — which is exactly the point. It's a container for static methods and properties only. This is like having a class with all static methods in TypeScript, or a module of pure functions in Python. In Go, you'd just have package-level functions.

**`private static let encoder: JSONEncoder = { ... }()`** — a static, lazily-initialized `JSONEncoder` configured with ISO 8601 date formatting. The `{ ... }()` syntax creates a closure and immediately invokes it (an IIFE — Immediately Invoked Function Expression, if you know JavaScript). The encoder is created once and reused for every log call. `.iso8601` means dates are formatted like `"2024-01-15T22:30:00Z"` in the JSON output.

```swift
// GoToSleep/Services/AnswerLogger.swift, lines 12-45
static func log(questionId: String, questionText: String, answer: String) {
    print("\(debugMarker) AnswerLogger.log called questionId=\(questionId)")
    Paths.ensureDirectoryExists()

    let entry = SessionLog(
        timestamp: Date(),
        questionId: questionId,
        questionText: questionText,
        answer: answer
    )

    guard let data = try? encoder.encode(entry),
          let line = String(data: data, encoding: .utf8) else {
        print("\(debugMarker) AnswerLogger.log failed to encode entry")
        return
    }

    let lineWithNewline = line + "\n"

    if FileManager.default.fileExists(atPath: Paths.answersPath.path) {
        guard let handle = try? FileHandle(forWritingTo: Paths.answersPath) else {
            print("\(debugMarker) AnswerLogger failed to open existing file handle")
            return
        }
        handle.seekToEndOfFile()
        handle.write(lineWithNewline.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? lineWithNewline.write(to: Paths.answersPath, atomically: true, encoding: .utf8)
    }
}
```

The storage format is **JSONL** (JSON Lines) — one JSON object per line. This is a common format for append-only log files because you can append new entries without reading/parsing the existing file. Each line is a standalone JSON object that can be decoded independently.

The write logic has two branches:

1. **File already exists** — open a `FileHandle` (like a file descriptor in C or Go's `*os.File`), seek to the end, and append the new line. This is more efficient than reading the entire file, adding a line, and rewriting it.

2. **File doesn't exist** — create it with the first line using `String.write(to:atomically:encoding:)`, which atomically writes a new file (writes to a temp file first, then renames — preventing partial writes if the process is killed mid-write).

The file is written to `Paths.answersPath`, which resolves to `~/Library/Application Support/GoToSleep/answers.jsonl`.

---

## 10. Shared Utilities — Paths and TimeCheck

The `Shared/` folder contains two files that are compiled into **both** the app and the daemon (as we saw in the pbxproj source lists in Section 2). These are the shared language that both processes use to agree on file locations and time calculations.

### Paths — File Locations and Marker File Operations

**File: `Shared/Paths.swift` (all 51 lines)**

```swift
// Shared/Paths.swift, lines 1-10
import Foundation

enum Paths {
    private static let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    static let appSupportDir: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let resolvedPath = base.appendingPathComponent("GoToSleep")
        print("\(debugMarker) appSupportDir resolved: \(resolvedPath.path)")
        return resolvedPath
    }()
```

Again, `enum Paths` is a caseless enum used as a namespace.

**`FileManager.default`** is macOS's file system API — like Node's `fs` module or Python's `os`/`pathlib`. `.urls(for: .applicationSupportDirectory, in: .userDomainMask)` asks the OS: "where is the Application Support directory for the current user?" On macOS, this resolves to `~/Library/Application Support/`. The `.first!` grabs the first (and usually only) result. The `!` is a **force unwrap** — it says "I know this optional has a value; crash if it doesn't." In production code, force unwraps are generally discouraged (you'd prefer `guard let` or `??`), but for a well-known system directory, it's reasonable to assume it always exists.

`Application Support` is the standard macOS location for app-specific data that isn't user documents — databases, caches, configuration files, logs. It's the macOS equivalent of `~/.config/` on Linux or `%APPDATA%` on Windows. The app creates a `GoToSleep` subdirectory within it.

```swift
// Shared/Paths.swift, lines 12-15
static let sessionActivePath = appSupportDir.appendingPathComponent("session-active")
static let sessionCompletedPath = appSupportDir.appendingPathComponent("session-completed")
static let answersPath = appSupportDir.appendingPathComponent("answers.jsonl")
static let killLogPath = appSupportDir.appendingPathComponent("kills.json")
```

Four file paths under `~/Library/Application Support/GoToSleep/`:

- **`session-active`** — marker file indicating a session is in progress (defined but not actively used in the current code)
- **`session-completed`** — the critical marker file. When this file exists with a recent timestamp, the daemon knows a session was completed and respects the grace period. When the daemon launches the app, it checks whether this file exists after the app exits to determine if the session completed legitimately.
- **`answers.jsonl`** — the append-only log of all answered questions
- **`kills.json`** — timestamps of recent force-kills, used by the daemon's safety valve logic

These marker files are the simplest possible form of inter-process communication (IPC). Instead of sockets, pipes, shared memory, or RPC calls, both processes just check whether a file exists on disk and read its contents. It's crude but effective for this use case — the daemon only needs to ask "did the session complete, and when?" — and it avoids all the complexity of setting up a proper IPC channel between two processes.

```swift
// Shared/Paths.swift, lines 17-51
static func ensureDirectoryExists() {
    print("\(debugMarker) ensureDirectoryExists at \(appSupportDir.path)")
    try? FileManager.default.createDirectory(
        at: appSupportDir, withIntermediateDirectories: true
    )
}

static func readTimestamp(from url: URL) -> Date? {
    ...
    guard let data = try? Data(contentsOf: url),
          let string = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
          let interval = TimeInterval(string) else {
        ...
        return nil
    }
    return Date(timeIntervalSince1970: interval)
}

static func writeTimestamp(to url: URL, date: Date = Date()) {
    ensureDirectoryExists()
    let string = String(date.timeIntervalSince1970)
    try? string.write(to: url, atomically: true, encoding: .utf8)
}

static func removeFile(at url: URL) {
    try? FileManager.default.removeItem(at: url)
}

static func fileExists(at url: URL) -> Bool {
    let exists = FileManager.default.fileExists(atPath: url.path)
    return exists
}
```

The timestamp format is simple: the file contains a single number — a Unix timestamp (seconds since January 1, 1970). `Date.timeIntervalSince1970` produces this value. It's written as a plain text string and read back by parsing the string as a `TimeInterval` (which is just a `Double`).

`writeTimestamp` has a default parameter: `date: Date = Date()`. `Date()` with no arguments creates a `Date` representing "right now" — like `time.Now()` in Go or `datetime.now()` in Python. This means you can call `writeTimestamp(to: path)` without specifying a date and it'll use the current time.

### TimeCheck — Bedtime Window Calculation

**File: `Shared/TimeCheck.swift` (all 25 lines)**

```swift
// Shared/TimeCheck.swift, lines 3-25
enum TimeCheck {
    private static let debugMarker = "[GTS_DEBUG_REMOVE_ME]"

    static func isWithinBedtimeWindow(startHour: Int, endHour: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        if startHour <= endHour {
            // Simple case: e.g., 8 AM to 5 PM
            let isWithinWindow = hour >= startHour && hour < endHour
            return isWithinWindow
        } else {
            // Midnight-crossing case: e.g., 9 PM to 7 AM
            let isWithinWindow = hour >= startHour || hour < endHour
            return isWithinWindow
        }
    }
}
```

This function answers one question: "Is the current time within the bedtime window?"

**`Calendar.current`** returns the user's current calendar (Gregorian, in most cases). `.component(.hour, from: now)` extracts the hour (0-23) from the current date/time. This is like `datetime.now().hour` in Python or `time.Now().Hour()` in Go.

The logic handles two cases:

1. **Non-crossing window** (`startHour <= endHour`, like 8 AM to 5 PM): the current hour must be >= start AND < end. This is the straightforward case.

2. **Midnight-crossing window** (`startHour > endHour`, like 9 PM to 7 AM): the current hour must be >= start OR < end. At 10 PM (hour 22), `22 >= 21` is true, so we're in the window. At 3 AM (hour 3), `3 < 7` is true, so we're still in the window. At 2 PM (hour 14), neither `14 >= 21` nor `14 < 7` is true, so we're outside the window.

This is the same logic both the app (in `MenuBarView`'s status text) and the daemon (in its polling loop) use to determine whether it's bedtime. Because the function is in `Shared/`, the same code is compiled into both binaries.

---

## 11. The Daemon — GoToSleepDaemon/main.swift, End to End

The daemon is the enforcement engine. It's a separate executable that runs in the background, checks the clock, and makes sure the bedtime overlay happens whether or not the user has the main app open. It's a single file — 166 lines — and it uses a completely different architectural style from the main app.

**File: `GoToSleepDaemon/main.swift` (all 166 lines)**

### Why main.swift Instead of @main?

The daemon uses a traditional `main()` function call (line 166: `main()`) instead of the `@main struct ... : App` pattern the main app uses. Why?

Because the daemon has **no UI whatsoever**. It's a headless command-line program — like a Go program that runs an infinite loop, or a Python script that polls a database every 10 seconds. It doesn't need SwiftUI, it doesn't need scenes, it doesn't need a menu bar, it doesn't need windows. The `App` protocol exists to manage UI-based applications. Using it for a headless daemon would be like importing React to write a cron job.

In Swift, when you have a file literally named `main.swift`, the compiler treats its top-level code as the program's entry point. This is the equivalent of Python's implicit `if __name__ == "__main__"` behavior — the code at the top level of `main.swift` just runs. Line 166 calls `main()`, which is a function defined at lines 8-66 of the same file. The function never returns (it contains a `while true` loop), so the process runs until it's killed or the system shuts down.

```swift
// GoToSleepDaemon/main.swift, lines 1-4
import AppKit
import Foundation

let showOverlayNotificationName = Notification.Name("com.gotosleep.showOverlayNow")
```

**`import AppKit`** — the daemon imports AppKit even though it has no UI. This is because it uses `NSWorkspace` (to check if the main app is running and to find the app's bundle path) and `NSRunningApplication` (to inspect running processes). On macOS, these APIs live in AppKit. Note: command-line tool targets in Xcode don't automatically link AppKit — it had to be explicitly imported. This is different from app targets where AppKit is always available.

The notification name string on line 4 is the same string used in the app's `AppDelegate.swift` (line 7). Both processes must agree on this exact string for cross-process notifications to work. It's like two services agreeing on a Kafka topic name or a Redis channel name.

### The Main Loop

```swift
// GoToSleepDaemon/main.swift, lines 8-66
func main() {
    Paths.ensureDirectoryExists()
    print("[GoToSleepDaemon] Started at \(Date())")

    var killTimestamps: [Date] = []

    while true {
        sleep(10)

        let settings = readSettings()

        guard settings.isEnabled else { continue }
        guard TimeCheck.isWithinBedtimeWindow(
            startHour: settings.bedtimeStartHour,
            endHour: settings.bedtimeEndHour
        ) else {
            continue
        }

        // Check grace period
        if let completedDate = Paths.readTimestamp(from: Paths.sessionCompletedPath) {
            let elapsed = Date().timeIntervalSince(completedDate)
            let gracePeriod = TimeInterval(settings.gracePeriodMinutes * 60)
            if elapsed < gracePeriod {
                continue
            }
        }

        // If the main app is running, tell it to show the overlay
        if isMainAppRunning() {
            print("[GoToSleepDaemon] Main app already running — requesting overlay")
            requestOverlayFromRunningApp()
            continue
        }

        // Launch the main app with --bedtime flag
        print("[GoToSleepDaemon] Bedtime — launching main app")
        let exitedCleanly = launchAndMonitor()

        if !exitedCleanly {
            let now = Date()
            killTimestamps.append(now)
            logKill(timestamps: killTimestamps)

            killTimestamps = killTimestamps.filter {
                now.timeIntervalSince($0) < 600
            }

            print("[GoToSleepDaemon] App killed (\(killTimestamps.count) kills in last 10 min)")

            if killTimestamps.count >= 5 {
                print("[GoToSleepDaemon] Safety valve triggered — granting grace period")
                Paths.writeTimestamp(to: Paths.sessionCompletedPath)
                killTimestamps.removeAll()
            }
        } else {
            print("[GoToSleepDaemon] Session completed normally")
        }
    }
}
```

This is a classic polling loop — the same pattern you'd write in any language for a background service. Every 10 seconds, it wakes up, checks a series of conditions, and decides what to do. Let's walk through each gate:

**Gate 1: `guard settings.isEnabled else { continue }`** — if the user has disabled the app in settings, skip this cycle. `continue` in Swift works exactly like `continue` in Go, Python, or TypeScript — it jumps to the next iteration of the loop.

**Gate 2: `guard TimeCheck.isWithinBedtimeWindow(...) else { continue }`** — if it's not currently bedtime, skip.

**Gate 3: Grace period check** — if a session was completed recently (the `session-completed` marker file exists and its timestamp is within the grace period), skip. `if let completedDate = ...` is Swift's **optional binding** — it unwraps the optional return value of `readTimestamp()`. If the function returned `nil` (the file doesn't exist), the `if let` body is skipped entirely. This is like Go's `if val, ok := ...` pattern.

After passing all three gates, we know: the app is enabled, it's bedtime, and there's no active grace period. Time to enforce.

**Branch A: App is already running** — if `isMainAppRunning()` returns true, post a cross-process notification asking the running app to show the overlay. Don't launch a second instance.

**Branch B: App is not running** — launch the app with `--bedtime` and wait for it to exit. Then check whether the session completed legitimately.

**Kill tracking** — if the app exited without writing the completion marker (meaning the user force-killed it), record the kill timestamp. Filter out timestamps older than 10 minutes (`.filter { now.timeIntervalSince($0) < 600 }` — 600 seconds = 10 minutes). If there have been 5 or more kills in the last 10 minutes, trigger the **safety valve**: write a completion marker (granting a grace period) and stop relaunching. This prevents an infinite loop where the user kills the app, the daemon relaunches it, the user kills it again, forever.

### DaemonSettings and readSettings()

```swift
// GoToSleepDaemon/main.swift, lines 70-85
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
```

The daemon can't use `@AppStorage` (that's a SwiftUI property wrapper, and the daemon doesn't use SwiftUI). Instead, it reads directly from `UserDefaults` using the same suite name (`"com.gotosleep.shared"`) that `AppSettings` in the main app writes to. The `as? Bool ?? true` pattern attempts to cast the value to the expected type, and falls back to a default if the key doesn't exist or the cast fails.

Note that `DaemonSettings` is a local struct — it's a simple container used only within the daemon. It's not shared with the app. This is fine because the daemon only needs to read a few settings, not expose them to a UI.

### Process Management

```swift
// GoToSleepDaemon/main.swift, lines 89-113
func resolveMainAppPath() -> String? {
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
    if let appURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.gotosleep.app"
    ) {
        return appURL.appendingPathComponent("Contents/MacOS/GoToSleep").path
    }

    return nil
}
```

The daemon needs to find the main app's executable to launch it. The clever approach: since the daemon binary itself lives inside the `.app` bundle (at `GoToSleep.app/Contents/MacOS/GoToSleepDaemon`), it can find the app by walking up the directory tree from its own location until it finds a directory ending in `.app`. Then it appends `Contents/MacOS/GoToSleep` to get the main app's binary path.

`ProcessInfo.processInfo.arguments[0]` is the daemon's own executable path (like `os.Args[0]` in Go or `sys.argv[0]` in Python). The `for _ in 0..<10` loop walks up at most 10 directory levels to find the `.app` bundle. The `_` means "I don't care about the loop variable, I just want to iterate."

The fallback uses `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` — which asks Launch Services (the macOS subsystem that tracks installed applications) where the app with bundle ID `"com.gotosleep.app"` lives. This works even if the daemon somehow isn't inside the app bundle.

```swift
// GoToSleepDaemon/main.swift, lines 115-118
func isMainAppRunning() -> Bool {
    let apps = NSWorkspace.shared.runningApplications
    return apps.contains { $0.bundleIdentifier == "com.gotosleep.app" }
}
```

`NSWorkspace.shared.runningApplications` returns an array of all running GUI applications. `.contains { $0.bundleIdentifier == "com.gotosleep.app" }` is a closure-based search — `$0` is shorthand for "the first argument to the closure" (like an implicit parameter name). It's equivalent to Python's `any(app.bundle_identifier == "com.gotosleep.app" for app in apps)`.

```swift
// GoToSleepDaemon/main.swift, lines 120-125
func requestOverlayFromRunningApp() {
    DistributedNotificationCenter.default().post(
        name: showOverlayNotificationName,
        object: "com.gotosleep.app"
    )
}
```

This is the daemon's side of the cross-process notification channel. It posts a notification with the agreed-upon name (`"com.gotosleep.showOverlayNow"`) and sender ID (`"com.gotosleep.app"`). The app's observer (set up in `AppDelegate.registerOverlayNotificationObserver()`) receives this and calls `showOverlay()`.

```swift
// GoToSleepDaemon/main.swift, lines 129-153
func launchAndMonitor() -> Bool {
    Paths.removeFile(at: Paths.sessionCompletedPath)

    guard let appPath = resolveMainAppPath() else {
        print("[GoToSleepDaemon] ERROR: Cannot find main app binary")
        return true // don't count as a kill
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

    return Paths.fileExists(at: Paths.sessionCompletedPath)
}
```

**`Process()`** is Swift's class for launching and managing child processes — like `exec.Command` in Go, `subprocess.Popen` in Python, or `child_process.spawn` in Node.js. Setting `.executableURL` and `.arguments` configures what to run. `process.run()` launches it. `process.waitUntilExit()` blocks the current thread until the child process terminates — like `cmd.Wait()` in Go or `process.wait()` in Python.

The return value is the result of checking whether the `session-completed` marker file exists. If the app completed the session normally, it wrote this file (via `AppDelegate.completeSession()`), and this function returns `true`. If the user force-killed the app, the file was never written, and this function returns `false`.

Note that `Paths.removeFile(at: Paths.sessionCompletedPath)` is called at the start — any stale completion marker from a previous session is cleaned up before launching. This ensures a fresh start.

```swift
// GoToSleepDaemon/main.swift, lines 157-162
func logKill(timestamps: [Date]) {
    let intervals = timestamps.map { $0.timeIntervalSince1970 }
    if let data = try? JSONEncoder().encode(intervals) {
        try? data.write(to: Paths.killLogPath)
    }
}
```

Writes the kill timestamps to `kills.json` for debugging/observability. The timestamps are stored as Unix timestamps in a JSON array.

```swift
// GoToSleepDaemon/main.swift, line 166
main()
```

The entry point. This single line at the top level of `main.swift` calls the `main()` function, which runs the infinite loop. The process never exits normally — it runs until killed or the system shuts down.

---

## 12. LaunchAgent Registration, launchd, and .dmg Distribution

### What Is launchd?

**`launchd`** is macOS's process supervisor — the system process (PID 1) responsible for starting, stopping, and managing background processes. If you're familiar with Linux, `launchd` is the macOS equivalent of `systemd`. If you're more familiar with Docker, think of it as the container runtime's process manager — it keeps your services alive, restarts them if they crash, and starts them at the right time.

Every macOS system has `launchd` running. It manages two categories of background jobs:

- **LaunchDaemons** — system-level services that run regardless of whether any user is logged in. They run as root. Think of these like Linux system services (`systemctl` services). Examples: the SSH server, the DNS resolver, Time Machine backup.

- **LaunchAgents** — user-level services that run only when a specific user is logged in. They run as that user, with that user's permissions. This is what Go To Sleep's daemon is — it only needs to run while you're logged in and using your Mac.

The distinction matters: LaunchAgents can interact with the user's desktop (access their files, show notifications, use the display), while LaunchDaemons cannot (they have no user context — no desktop, no Display, no user home directory).

### How launchd Knows What to Run — The Plist Job Definition

`launchd` doesn't just magically know about your background process. You have to tell it, and the way you tell it is with a **plist file** that describes the job. We covered this file's contents in Section 3.4, but now let's understand how it gets from "a file sitting in the app bundle" to "an active background service that launchd manages."

The plist file is at `Resources/com.gotosleep.daemon.plist`. During the build process, this file is copied into the app bundle's Resources folder (the pbxproj build phase at line 305 includes it: `A300000001 /* com.gotosleep.daemon.plist in Resources */`). So when the built app is sitting on disk, the plist is at:

```
GoToSleep.app/Contents/Resources/com.gotosleep.daemon.plist
```

But having a plist file in the bundle does **nothing** by itself. `launchd` doesn't scan app bundles looking for plist files. The plist must be **registered** — explicitly handed to `launchd` through an API call.

### SMAppService — The Registration API

**`SMAppService`** (Service Management App Service) is the modern Apple API (macOS 13+) for registering LaunchAgents that are bundled inside an app. The `SM` stands for **Service Management**, which is the framework name.

Here's the registration code from `GoToSleep/App/AppDelegate.swift`, lines 102-114:

```swift
func registerDaemon() {
    if #available(macOS 13.0, *) {
        let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
        do {
            try service.register()
        } catch {
            print("Failed to register daemon: \(error)")
        }
    }
}
```

When `service.register()` is called, here is what happens at the operating system level:

1. **`SMAppService.agent(plistName:)`** looks inside the calling app's bundle for a plist file with the given name in the Resources directory. It reads the plist and validates its structure.

2. **`service.register()`** tells `launchd`: "Here is a new job definition. Please start managing this background process." `launchd` reads the plist's fields:
   - **`Label: "com.gotosleep.daemon"`** — registers the job under this unique name
   - **`BundleProgram: "Contents/MacOS/GoToSleepDaemon"`** — resolves this relative path against the app bundle to find the daemon executable at `GoToSleep.app/Contents/MacOS/GoToSleepDaemon`
   - **`RunAtLoad: true`** — starts the daemon immediately
   - **`KeepAlive: true`** — if the daemon process ever exits, restart it automatically

3. The daemon process launches. It starts its `main()` function, enters the infinite polling loop, and begins checking the clock every 10 seconds.

4. The job also appears in **System Settings > General > Login Items** — the user can see that Go To Sleep has a background process and can disable it from there.

### How This Works When Distributed via .dmg

A `.dmg` (Disk Image) is macOS's standard distribution format for apps outside the App Store. Think of it as a `.zip` file with a nice UI — the user double-clicks it, a virtual disk appears, and they drag the `.app` file into their Applications folder. That's the entire installation process.

Here's the critical thing to understand: **installing the app does not register the daemon.** Dragging `GoToSleep.app` to `/Applications/` just copies files. Nothing about the daemon gets activated.

The registration happens **at runtime**, the first time the user runs the app. The sequence is:

1. User downloads `GoToSleep.dmg`
2. User mounts the DMG and drags `GoToSleep.app` to `/Applications/`
3. User double-clicks `GoToSleep.app` to launch it for the first time
4. The app starts (SwiftUI lifecycle boots, `AppDelegate.applicationDidFinishLaunching` fires)
5. At some point, `registerDaemon()` is called (currently this would need to be triggered by the user through the PermissionsGuideView, or wired into the launch sequence)
6. `SMAppService.agent(plistName:).register()` tells `launchd` about the daemon
7. `launchd` starts the daemon process
8. From this point on, even if the user quits the main app, the daemon keeps running (because `KeepAlive: true`)
9. The daemon survives logout/login and reboots (the job registration persists until explicitly unregistered)

If the user moves the `.app` to a different location after registration, `launchd` may lose track of the daemon binary (because `BundleProgram` was resolved relative to the original app bundle location). This is why macOS apps are conventionally placed in `/Applications/` and left there.

### The Older Way — For Historical Context

Before `SMAppService` (pre-macOS 13), the way to install a LaunchAgent was to manually copy the plist file to `~/Library/LaunchAgents/` and then call `launchctl load ~/Library/LaunchAgents/com.gotosleep.daemon.plist` from the command line. The app would have to do this file copy programmatically, handle permissions issues, and manage the lifecycle manually. `SMAppService` abstracts all of this away into a single API call and integrates with System Settings' Login Items UI.

---

## 13. Cross-Process Communication — How the App and Daemon Talk

The app and daemon are two separate processes — they have separate memory spaces, separate threads, separate everything. They cannot call functions on each other directly. To coordinate, they use three distinct communication channels, each chosen for a specific purpose.

### Channel 1: Shared UserDefaults — For Configuration

**What it is:** A shared key-value store on disk that both processes can read and write to.

**How it works:** Both processes open the same UserDefaults suite by name:

```swift
// In the app (GoToSleep/Models/AppSettings.swift, line 6):
static let suiteName = "com.gotosleep.shared"

// In the daemon (GoToSleepDaemon/main.swift, line 78):
let defaults = UserDefaults(suiteName: "com.gotosleep.shared")
```

Under the hood, UserDefaults stores data in a plist file at `~/Library/Preferences/com.gotosleep.shared.plist`. Both processes read from and write to this same file. macOS handles the file locking and cache coherency — you don't need to worry about concurrent access corruption.

**What it's used for:** The user's settings — bedtime start/end hours, whether the app is enabled, the grace period duration, the number of questions per session. The app writes these settings (when the user changes them in `SettingsView`). The daemon reads them (in `readSettings()` on every polling cycle).

**Why this channel for this purpose:** Settings are persistent, rarely-changing data that both processes need to read. UserDefaults is purpose-built for exactly this — it's Apple's blessed solution for app preferences. It's simple, it's persistent across reboots, it requires no setup, and it handles concurrent access safely.

**Analogies:**
- It's like two microservices reading from the same Redis hash
- Or two Python scripts importing the same `.env` file
- Or two Go programs reading from the same SQLite database
- Except it's a built-in macOS feature that requires zero infrastructure

### Channel 2: Marker Files on Disk — For State Signaling

**What it is:** Simple files whose existence (or non-existence) and contents convey state between the two processes.

**How it works:** Both processes use the `Paths` utility (from `Shared/Paths.swift`) to read, write, and delete files in `~/Library/Application Support/GoToSleep/`. The key marker file is `session-completed`:

**The lifecycle of the `session-completed` marker:**

1. The daemon calls `launchAndMonitor()`, which first **deletes** the marker file (`GoToSleepDaemon/main.swift`, line 131: `Paths.removeFile(at: Paths.sessionCompletedPath)`). This ensures a clean slate.

2. The daemon launches the main app with `--bedtime` and blocks on `process.waitUntilExit()`.

3. While the app is running, if the user completes all the questions, `AppDelegate.completeSession()` **writes** the marker file (`GoToSleep/App/AppDelegate.swift`, line 84: `Paths.writeTimestamp(to: Paths.sessionCompletedPath)`).

4. The app exits (either naturally or force-killed by the user).

5. The daemon resumes after `waitUntilExit()` and **checks** whether the marker file exists (`GoToSleepDaemon/main.swift`, line 152: `return Paths.fileExists(at: Paths.sessionCompletedPath)`).

6. If the file exists → the session completed legitimately → respect the grace period.
7. If the file doesn't exist → the user killed the app before finishing → count it as a kill, potentially relaunch.

**What it's used for:** Answering the question "did the user complete the session, or did they force-kill the app?" and "when was the last completed session?" (for grace period calculation).

**Why this channel for this purpose:** The communication is asynchronous and persisted — the daemon writes a timestamp, then the next polling cycle (potentially many seconds later) reads it. File existence is the simplest possible binary signal (exists = true, doesn't exist = false). No sockets, no message queues, no serialization protocol. Just "is there a file here?"

**Analogies:**
- It's like a lockfile (like `package-lock.json` or `/var/run/nginx.pid`) — the existence of the file signals state
- Or like how some deployment systems use a `HEALTHY` file that a health checker looks for
- Or like leaving a note on someone's desk — low-tech, reliable, and asynchronous

### Channel 3: DistributedNotificationCenter — For Real-Time Signals

**What it is:** A macOS system service that lets one process broadcast a message that another process receives immediately.

**How it works:**

The daemon **posts** a notification:
```swift
// GoToSleepDaemon/main.swift, lines 121-124
DistributedNotificationCenter.default().post(
    name: showOverlayNotificationName,
    object: "com.gotosleep.app"
)
```

The app **observes** the same notification:
```swift
// GoToSleep/App/AppDelegate.swift, lines 89-96
DistributedNotificationCenter.default().addObserver(
    forName: showOverlayNotificationName,
    object: "com.gotosleep.app",
    queue: .main
) { [weak self] _ in
    self?.showOverlay()
}
```

When the daemon posts, the app's observer callback fires almost immediately (within milliseconds). The notification carries no payload data — it's a pure signal, like someone ringing a doorbell. The only information is "the notification happened."

**What it's used for:** The specific case where the main app is **already running** (in menu-bar mode) when bedtime arrives. The daemon detects the app is running (`isMainAppRunning()` returns true), and instead of launching a second instance, it sends this notification to tell the existing instance to show the overlay.

**Why this channel for this purpose:** This is a real-time, one-way signal — "hey, do this now." File-based communication would require the app to poll a file, which adds latency and wastes CPU. UserDefaults is for persistent data, not ephemeral commands. `DistributedNotificationCenter` is purpose-built for exactly this: one process saying "something happened" and another process reacting instantly.

**Why not use other IPC mechanisms?**
- **XPC (Apple's recommended IPC)** — more powerful (bidirectional, type-safe, supports complex data), but more complex to set up. Requires a service definition and connection management. Overkill for a one-way "show the overlay" signal.
- **Unix sockets/pipes** — lower level, requires managing connection lifecycle, error handling, reconnection. More work for no benefit here.
- **HTTP/TCP** — way too heavy for two processes on the same machine. You'd need a server, port management, serialization — absurd for a doorbell.
- **Shared memory** — complex, error-prone, and unnecessary for infrequent signals.

`DistributedNotificationCenter` is the right tool: zero setup, zero infrastructure, fire-and-forget semantics, built into the OS.

### Summary of Communication Channels

| Channel | Direction | Purpose | Mechanism | Latency |
|---------|-----------|---------|-----------|---------|
| Shared UserDefaults | App → Daemon | Settings (bedtime hours, enabled, grace period) | Shared plist file on disk | Seconds (daemon polls every 10s) |
| Marker files | App → Daemon | "Session completed" signal + timestamp | File existence + content | Seconds (daemon checks after app exits) |
| DistributedNotificationCenter | Daemon → App | "Show overlay now" command | OS notification bus | Milliseconds |

---

## 14. End-to-End Runtime Flows — Every Scenario Walked Through

Now that we've understood every file, every class, every function, and every communication channel, let's trace through the complete runtime behavior for each real-world scenario. These walkthroughs follow exact function calls with file paths and line numbers so you can verify every step.

### Scenario 1: User Launches the App Manually and Clicks Around

This is the simplest scenario — the user just wants to check their settings or test the overlay.

**Step 1: Process starts.** The OS loads `GoToSleep.app/Contents/MacOS/GoToSleep` into memory. The Swift runtime initializes. Because `GoToSleepApp` (in `GoToSleep/App/GoToSleepApp.swift`, line 3) has the `@main` attribute, the compiler-generated entry point creates an instance of `GoToSleepApp`.

**Step 2: The `@NSApplicationDelegateAdaptor` initializes.** SwiftUI sees the property wrapper on line 6 of `GoToSleepApp.swift`. It creates an `AppDelegate` instance (calling `AppDelegate.init()`), which in turn creates `OverlayWindowController`, `FocusEnforcer`, and `QuestionStore` (lines 8-10 of `AppDelegate.swift`). The `QuestionStore` constructor loads and decodes `questions.json` from the app bundle (lines 9-11 of `QuestionStore.swift`).

**Step 3: SwiftUI materializes the scenes.** It reads the `body` property (line 13 of `GoToSleepApp.swift`). It creates an `NSStatusItem` in the menu bar (from the `MenuBarExtra` scene) and prepares the `Settings` scene.

**Step 4: `applicationDidFinishLaunching` fires.** The SwiftUI adaptor forwards this lifecycle event to `AppDelegate` (line 14 of `AppDelegate.swift`). The method calls `registerOverlayNotificationObserver()` (line 16), which sets up the `DistributedNotificationCenter` listener (lines 88-98). It checks `CommandLine.arguments` for `--bedtime` (line 19) — there is no such flag in a manual launch, so the overlay is not shown.

**Step 5: The app is now idle.** A moon icon appears in the menu bar. The app sits in the background, consuming negligible resources, waiting for user interaction.

**Step 6: User clicks the moon icon.** The `MenuBarExtra`'s content appears as a dropdown. `MenuBarView` renders (line 8 of `MenuBarView.swift`). The `statusText` computed property (lines 47-61) checks whether it's currently bedtime using `TimeCheck.isWithinBedtimeWindow()` and displays an appropriate message.

**Step 7: User clicks "Settings..."** The button handler (lines 25-31 of `MenuBarView.swift`) calls `appDelegate.showSettingsWindow()` inside a `DispatchQueue.main.async` wrapper. `showSettingsWindow()` (lines 58-79 of `AppDelegate.swift`) activates the app, lazily creates an `NSWindowController` with an `NSHostingController`-wrapped `SettingsView`, and shows the window. The settings form appears with the current values loaded from `@AppStorage`/UserDefaults.

**Step 8: User changes a setting.** For example, they change the bedtime start hour from 9 PM to 10 PM. The `Picker`'s binding (`$settings.bedtimeStartHour`, line 19 of `SettingsView.swift`) immediately writes the new value to the `@AppStorage` property on `AppSettings` (line 17 of `AppSettings.swift`), which writes to `UserDefaults(suiteName: "com.gotosleep.shared")`. The value is now persisted. The next time the daemon reads `readSettings()`, it will see `bedtimeStartHour = 22`.

### Scenario 2: Daemon-Triggered Overlay — App Is Not Running

It's 9 PM. The user is browsing the web. The Go To Sleep app is not running (they never launched it, or they quit it). But the daemon is running in the background.

**Step 1: Daemon polling cycle fires.** The daemon wakes up from `sleep(10)` (line 15 of `GoToSleepDaemon/main.swift`).

**Step 2: Read settings.** `readSettings()` (line 17) opens `UserDefaults(suiteName: "com.gotosleep.shared")` and reads: `isEnabled = true`, `bedtimeStartHour = 21`, `bedtimeEndHour = 7`, `gracePeriodMinutes = 60`.

**Step 3: Gate checks pass.** `settings.isEnabled` is true (line 19). `TimeCheck.isWithinBedtimeWindow(startHour: 21, endHour: 7)` returns true because it's 9 PM (hour 21, and `21 >= 21` satisfies the overnight case on line 20 of `TimeCheck.swift`). No `session-completed` marker file exists (or it's older than the grace period), so the grace period check on lines 26-32 passes.

**Step 4: App is not running.** `isMainAppRunning()` (line 35) returns false — no process with bundle identifier `"com.gotosleep.app"` is in `NSWorkspace.shared.runningApplications`.

**Step 5: Launch and monitor.** `launchAndMonitor()` is called (line 43). It deletes any stale `session-completed` marker (line 131). It resolves the main app path by walking up from its own executable path to find the `.app` bundle (lines 95-105). It creates a `Process`, sets `arguments` to `["--bedtime"]`, and calls `process.run()` (lines 138-143).

**Step 6: The main app launches with --bedtime.** A new process starts. The SwiftUI lifecycle boots. `applicationDidFinishLaunching` fires (line 14 of `AppDelegate.swift`). It calls `registerOverlayNotificationObserver()` (line 16). Then it checks `CommandLine.arguments` (line 19) — `--bedtime` IS present, so it calls `showOverlay()` (line 21).

**Step 7: Overlay appears.** `showOverlay()` (lines 25-49 of `AppDelegate.swift`) sets `isShowingOverlay = true`, deletes any stale completion marker, reads the questions-per-session setting (e.g., 3), selects 3 random questions from the store, starts the `FocusEnforcer`, activates the app (`NSApp.activate`), and calls `overlayController.show()`.

**Step 8: Kiosk window takes over.** `OverlayWindowController.show()` (lines 16-55 of `OverlayWindowController.swift`) creates a `KioskWindow` the size of the screen, sets its level to `.screenSaver`, sets `NSApp.presentationOptions` to disable Cmd+Tab/Force Quit/Dock/menu bar, and makes it the key window. The user's entire screen is now the bedtime overlay.

**Step 9: User answers questions.** The user types answers or selects choices. Each time they press "Next", `OverlayView.advance()` (line 80 of `OverlayView.swift`) logs the answer via `AnswerLogger.log()` (lines 87-91) and increments `currentIndex`. When they answer the last question and press "Finish", `advance()` calls `onComplete()` (line 95), which is the closure that calls `AppDelegate.completeSession()`.

**Step 10: Session completes.** `completeSession()` (lines 81-86 of `AppDelegate.swift`) writes the current timestamp to the `session-completed` marker file, then calls `dismissOverlay()`. `dismissOverlay()` resets `NSApp.presentationOptions` to empty (restoring Dock, menu bar, Cmd+Tab), orders out the kiosk window, stops the focus enforcer, and sets `isShowingOverlay = false`.

**Step 11: Back in the daemon.** The main app exits. `process.waitUntilExit()` returns (line 149 of `GoToSleepDaemon/main.swift`). `Paths.fileExists(at: Paths.sessionCompletedPath)` returns `true` (line 152) — the session completed legitimately. `launchAndMonitor()` returns `true`. The daemon prints "Session completed normally" (line 63) and continues its loop.

**Step 12: Grace period.** On the next polling cycle (10 seconds later), the daemon reads the `session-completed` marker's timestamp (lines 26-31). If less than 60 minutes have elapsed, it `continue`s — the user gets their grace period. After 60 minutes, the grace period expires, and the next polling cycle that's still within the bedtime window will launch the overlay again.

### Scenario 3: Daemon-Triggered Overlay — App Is Already Running

It's 9 PM. The user has the Go To Sleep app running in the menu bar (they launched it earlier to adjust settings, and it's still sitting there).

**Steps 1-3:** Same as Scenario 2 — the daemon wakes up, reads settings, passes all gate checks.

**Step 4: App IS running.** `isMainAppRunning()` (line 35 of `GoToSleepDaemon/main.swift`) returns `true` — a process with bundle identifier `"com.gotosleep.app"` is found in the running applications list.

**Step 5: Send notification.** `requestOverlayFromRunningApp()` (line 37) posts a distributed notification with name `"com.gotosleep.showOverlayNow"` (lines 121-124).

**Step 6: App receives notification.** The observer registered in `AppDelegate.registerOverlayNotificationObserver()` (lines 88-98 of `AppDelegate.swift`) fires its callback on the main queue. The callback calls `self?.showOverlay()`.

**Steps 7-10:** Same as Scenario 2, steps 7-10 — the overlay appears, the user answers questions, the session completes.

**Step 11: App continues running.** Unlike Scenario 2, the app doesn't exit after dismissing the overlay — it returns to its normal menu-bar-idle state. The daemon's `continue` on line 38 skips to the next polling cycle, and the grace period check prevents further overlays.

### Scenario 4: User Force-Kills the App During an Overlay

The overlay is showing (launched by the daemon as in Scenario 2). The user opens Terminal (or Activity Monitor — since Cmd+Tab is disabled, they might use a second Mac, SSH, or a pre-opened Terminal window) and runs `kill <pid>` on the GoToSleep process.

**Step 1: App process terminates.** The `SIGTERM` signal kills the process. `completeSession()` was never called, so the `session-completed` marker file was **never written**. The kiosk window disappears because the process that owned it no longer exists.

**Step 2: Daemon resumes.** `process.waitUntilExit()` (line 149 of `GoToSleepDaemon/main.swift`) returns. `Paths.fileExists(at: Paths.sessionCompletedPath)` (line 152) returns `false` — no completion marker. `launchAndMonitor()` returns `false`.

**Step 3: Kill tracking.** The daemon enters the `!exitedCleanly` branch (line 45). It appends the current timestamp to `killTimestamps` (line 48), writes the timestamps to `kills.json` via `logKill()` (line 49), and filters out timestamps older than 10 minutes (line 52). It prints how many kills have happened in the last 10 minutes (line 54).

**Step 4: Check safety valve.** If `killTimestamps.count < 5`, the safety valve doesn't trigger. The daemon's `while true` loop continues, `sleep(10)` happens, and on the next cycle, all the gate checks pass again (it's still bedtime, still enabled, no grace period). The daemon launches the app again with `--bedtime`. The overlay appears again. The user is back in the kiosk.

### Scenario 5: User Kills the App 5 Times — Safety Valve Triggers

Same as Scenario 4, but the user is persistent. They kill the app, the daemon relaunches it, they kill it again.

**Kills 1-4:** Each time, a timestamp is appended to `killTimestamps`. The daemon relaunches the app each time.

**Kill 5:** After the fifth kill within 10 minutes, `killTimestamps.count >= 5` (line 57 of `GoToSleepDaemon/main.swift`). The safety valve triggers:

```swift
Paths.writeTimestamp(to: Paths.sessionCompletedPath)
killTimestamps.removeAll()
```

The daemon writes a `session-completed` marker file (as if the session had completed normally) and clears the kill counter. On the next polling cycle, the grace period check on lines 26-31 will find the marker and its recent timestamp, and `continue` — the user gets their grace period (default 60 minutes) before the daemon will try again.

This prevents a truly adversarial situation where the user and the daemon are locked in an infinite fight. After 5 kills in 10 minutes, the system concedes: "Okay, you really don't want to do this right now. Come back in an hour."

---

## Final Notes

### Debug Instrumentation

Every file in this codebase contains `print()` statements tagged with `[GTS_DEBUG_REMOVE_ME]`. These are debug traces added during development to trace the full control flow. They output to:
- The Xcode console (when running from Xcode)
- `/tmp/go-to-sleep-daemon.stdout.log` (for the daemon, as configured in the LaunchAgent plist on line 14 of `Resources/com.gotosleep.daemon.plist`)

They are intended to be removed before production distribution — searching for `GTS_DEBUG_REMOVE_ME` across the codebase will find all of them.

### What's Not Yet Wired Up

**`PermissionsGuideView`** (`GoToSleep/Views/PermissionsGuideView.swift`) exists as a first-run setup wizard that walks the user through granting accessibility permissions and registering the daemon. However, it is not currently referenced in `GoToSleepApp.swift`'s scene graph — no code path creates or shows it. Additionally, its `registerDaemon()` method on line 109 uses the problematic `NSApp.delegate as? AppDelegate` pattern that fails in the SwiftUI lifecycle (as discussed in Section 5). If this view were activated, it would need to receive `AppDelegate` via injection instead.

**Daemon registration** (`AppDelegate.registerDaemon()`) is defined but not automatically called during app launch. The user currently has no automatic way to register the daemon on first launch — it would need to be either called from `applicationDidFinishLaunching`, triggered from `PermissionsGuideView`, or wired into the `MenuBarView`.

### The Architecture, Summarized

Two processes. Three communication channels. One goal.

```
┌─────────────────────────────────────────────────────────┐
│                    GoToSleep.app                         │
│                                                         │
│  @main GoToSleepApp ──→ MenuBarExtra (moon icon)        │
│       │                      │                          │
│       ├─ @NSApplicationDelegateAdaptor                   │
│       │       │                                         │
│       │   AppDelegate                                   │
│       │       ├─ showOverlay() ──→ OverlayWindowController│
│       │       │                       └─ KioskWindow     │
│       │       ├─ showSettingsWindow() ──→ NSWindow       │
│       │       ├─ registerDaemon() ──→ SMAppService       │
│       │       └─ DistributedNotificationCenter.observe() │
│       │                                                 │
│       └─ Settings ──→ SettingsView ──→ AppSettings       │
│                                          │              │
│                                    UserDefaults         │
│                                   "com.gotosleep.shared" │
└────────────────────────┬────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │ Shared UserDefaults           │ Marker files
         │ (settings)                    │ (session-completed)
         │                               │
         │ DistributedNotificationCenter │
         │ ("show overlay now")          │
         ├───────────────┼───────────────┤
                         │
┌────────────────────────┴────────────────────────────────┐
│                  GoToSleepDaemon                         │
│                                                         │
│  main() ──→ while true { sleep(10); ... }               │
│       │                                                 │
│       ├─ readSettings() ──→ UserDefaults                │
│       ├─ TimeCheck.isWithinBedtimeWindow()              │
│       ├─ isMainAppRunning() ──→ NSWorkspace             │
│       ├─ requestOverlayFromRunningApp()                 │
│       │       └─ DistributedNotificationCenter.post()   │
│       └─ launchAndMonitor()                             │
│               └─ Process() ──→ GoToSleep --bedtime      │
│                                                         │
│  Managed by: launchd (KeepAlive, RunAtLoad)             │
│  Configured by: com.gotosleep.daemon.plist              │
└─────────────────────────────────────────────────────────┘
```
