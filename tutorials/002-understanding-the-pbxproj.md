# Understanding `project.pbxproj`

A section-by-section breakdown of `GoToSleep.xcodeproj/project.pbxproj` — what every part does, why it exists, and how the pieces connect to produce a working build.

---

## Table of Contents

1. [The File Envelope](#1-the-file-envelope)
2. [PBXBuildFile](#2-pxbbuildfile)
3. [PBXCopyFilesBuildPhase](#3-pbxcopyfilesbuildphase)
4. [PBXFileReference](#4-pbxfilereference)
5. [PBXFrameworksBuildPhase](#5-pbxframeworksbuildphase)
6. [PBXGroup](#6-pbxgroup)
7. [PBXNativeTarget](#7-pbxnativetarget)
8. [PBXProject](#8-pbxproject)
9. [PBXResourcesBuildPhase](#9-pbxresourcesbuildphase)
10. [PBXSourcesBuildPhase](#10-pbxsourcesbuildphase)
11. [XCBuildConfiguration](#11-xcbuildconfiguration)
12. [XCConfigurationList](#12-xcconfigurationlist)
13. [The rootObject](#13-the-rootobject)
14. [How It All Fits Together](#14-how-it-all-fits-together)
15. [Object ID Convention](#15-object-id-convention)

---

## 1. The File Envelope

```
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {
    };
    objectVersion = 50;
    objects = {
        ...
    };
    rootObject = PRJ0000001;
}
```

The file is an **Apple "old-style" property list** (not JSON, not XML — a third, older plist format that Xcode still uses for pbxproj files).

| Field | What it means |
|---|---|
| `// !$*UTF8*$!` | Magic comment declaring UTF-8 encoding. Must be the first line. |
| `archiveVersion = 1` | Always 1. The version of the archive format itself. |
| `classes = {}` | Always empty. Reserved by Apple, never used. |
| `objectVersion = 50` | The pbxproj schema version. 50 corresponds to Xcode 9+. Determines which object types and fields are valid. |
| `objects = { ... }` | The entire project definition — every object lives in this flat dictionary, keyed by its unique ID. |
| `rootObject` | Points to the `PBXProject` object. This is the entry point — Xcode starts here and follows references to discover everything else. |

The file is essentially a **flat relational database**. Every object has a unique ID, an `isa` field declaring its type, and fields that reference other objects by ID. There are no nested structures — relationships are expressed purely through ID references.

---

## 2. PBXBuildFile

```
/* Begin PBXBuildFile section */
    /* GoToSleep app sources */
    A100000020 /* main.swift in Sources */ = {isa = PBXBuildFile; fileRef = B100000022; };
    A100000002 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = B100000002; };
    ...
    A100000017 /* questions.json in Resources */ = {isa = PBXBuildFile; fileRef = B100000017; };
    A100000018 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = B100000018; };
    A100000019 /* AudioMuter.swift in Sources */ = {isa = PBXBuildFile; fileRef = B100000021; };

    /* GoToSleepDaemon sources */
    A200000001 /* main.swift in Sources */ = {isa = PBXBuildFile; fileRef = B200000001; };
    A200000002 /* Paths.swift in Sources */ = {isa = PBXBuildFile; fileRef = B100000015; };
    A200000003 /* TimeCheck.swift in Sources */ = {isa = PBXBuildFile; fileRef = B100000016; };

    /* Daemon plist copied into app bundle */
    A300000001 /* com.gotosleep.daemon.plist in Resources */ = {isa = PBXBuildFile; fileRef = B300000001; };
/* End PBXBuildFile section */
```

### What it is

A **join record** connecting a file to a build phase. A `PBXFileReference` says "this file exists." A `PBXBuildFile` says "include this file in a build step."

### Fields

| Field | Meaning |
|---|---|
| `isa` | Always `PBXBuildFile`. |
| `fileRef` | The ID of a `PBXFileReference` — the actual file on disk this refers to. |

### How it connects

A `PBXBuildFile` does nothing on its own. It must be listed in a build phase's `files` array to take effect. The chain is:

```
PBXNativeTarget → build phase (Sources/Resources/etc.) → PBXBuildFile → PBXFileReference → file on disk
```

### Why the indirection?

Because the same file can participate in multiple targets. Look at `Paths.swift` (`B100000015`):

- `A100000015` includes it in the **GoToSleep** app's Sources phase
- `A200000002` includes it in the **GoToSleepDaemon**'s Sources phase

Same file reference, two build file entries, two different targets. Without this layer, you couldn't share source files across targets.

### The comments

The `/* main.swift in Sources */` comments are cosmetic. Xcode generates them for readability but they have no functional effect. The `in Sources` / `in Resources` part is just a hint about which build phase the entry belongs to — the actual assignment happens in the build phase objects themselves.

---

## 3. PBXCopyFilesBuildPhase

```
/* Begin PBXCopyFilesBuildPhase section */
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
    C200000001 /* CopyFiles */ = {
        isa = PBXCopyFilesBuildPhase;
        buildActionMask = 2147483647;
        dstPath = /usr/share/man/man1;
        dstSubfolderSpec = 0;
        files = (
        );
        runOnlyForDeploymentPostprocessing = 1;
    };
/* End PBXCopyFilesBuildPhase section */
```

### What it is

A build phase that **copies files into specific locations** in the product bundle (or elsewhere on the system). Used to embed helper executables, frameworks, plugins, or man pages into the final product.

### Fields

| Field | Meaning |
|---|---|
| `buildActionMask` | Bitmask controlling when this phase runs. `2147483647` (0x7FFFFFFF) means "always" — it runs for all build actions (build, install, archive, etc.). |
| `dstPath` | Subdirectory within the destination folder. Empty string means the root of the destination. |
| `dstSubfolderSpec` | A numeric code defining the destination base folder. |
| `files` | Array of `PBXBuildFile` IDs to copy. Both are empty here — no files are currently being copied. |
| `name` | Display name for the phase (only present on custom-named phases). |
| `runOnlyForDeploymentPostprocessing` | `0` = runs on every build. `1` = only runs during "install" builds (deployment). |

### dstSubfolderSpec values

| Value | Destination |
|---|---|
| 0 | Absolute path (uses `dstPath` as-is) |
| 1 | Wrapper (the .app bundle root) |
| 6 | Executables (`Contents/MacOS/`) |
| 7 | Resources (`Contents/Resources/`) |
| 10 | Frameworks (`Contents/Frameworks/`) |
| 13 | Shared Frameworks |
| 16 | Executables (same as 6, used by modern Xcode) |

### The two phases in this project

**C100000001 — "Copy Daemon"** (on the GoToSleep app target):
- `dstSubfolderSpec = 16` → copy into the app's `Contents/MacOS/` directory
- Currently empty — this is a placeholder. When wired up, it would copy the built `GoToSleepDaemon` binary into the app bundle so the app can launch it.
- `runOnlyForDeploymentPostprocessing = 0` → runs on every build

**C200000001 — "CopyFiles"** (on the GoToSleepDaemon target):
- `dstSubfolderSpec = 0` with `dstPath = /usr/share/man/man1` → absolute path for man pages
- Also empty — this is Xcode's default copy phase for command-line tool targets. It's where you'd put a man page if you wrote one.
- `runOnlyForDeploymentPostprocessing = 1` → only runs during install/archive, not regular builds

---

## 4. PBXFileReference

```
/* Begin PBXFileReference section */
    /* GoToSleep app */
    P100000001 /* GoToSleep.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = GoToSleep.app; sourceTree = BUILT_PRODUCTS_DIR; };
    B100000022 /* main.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; };
    B100000002 /* AppDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
    ...
    B100000017 /* questions.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = questions.json; sourceTree = "<group>"; };
    B100000018 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
    B100000019 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
    B100000020 /* GoToSleep.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = GoToSleep.entitlements; sourceTree = "<group>"; };

    /* GoToSleepDaemon */
    P200000001 /* GoToSleepDaemon */ = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = GoToSleepDaemon; sourceTree = BUILT_PRODUCTS_DIR; };
    B200000001 /* main.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; };

    /* Resources */
    B300000001 /* com.gotosleep.daemon.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = com.gotosleep.daemon.plist; sourceTree = "<group>"; };
/* End PBXFileReference section */
```

### What it is

The **file registry**. Every file the project knows about — source files, resources, config files, and build products — gets an entry here. This is where Xcode learns what the file is and where it lives.

### Fields

| Field | Meaning |
|---|---|
| `lastKnownFileType` | Xcode's best guess at the file type. Determines which compiler/tool processes the file. Can be overridden by the user in Xcode. |
| `explicitFileType` | A definitive file type (used for build products where the type is known with certainty). Takes precedence over `lastKnownFileType`. |
| `path` | The file name or relative path segment. |
| `sourceTree` | How to resolve the path (see below). |
| `includeInIndex` | Whether to include in Xcode's search index. `0` for build products (they change constantly, no point indexing). |

### sourceTree values

| Value | Meaning |
|---|---|
| `"<group>"` | Relative to the parent `PBXGroup`'s location. The most common value — the full path is built by walking up the group hierarchy, concatenating `path` values. |
| `BUILT_PRODUCTS_DIR` | In the derived data build output folder. Used for product references (the `.app`, the executable). |
| `SOURCE_ROOT` | Relative to the project root directory. |
| `"<absolute>"` | An absolute filesystem path. |
| `SDKROOT` | Relative to the SDK (e.g., system frameworks). |

### File types in this project

| `lastKnownFileType` / `explicitFileType` | Files | What Xcode does with it |
|---|---|---|
| `sourcecode.swift` | All `.swift` files | Compiled by the Swift compiler (`swiftc`) |
| `text.json` | `questions.json` | Copied into the app bundle as-is (via Resources phase) |
| `folder.assetcatalog` | `Assets.xcassets` | Processed by `actool` to compile app icons, images, and colors |
| `text.plist.xml` | `Info.plist`, daemon plist | Info.plist is processed by the build system (variable substitution); daemon plist is copied as a resource |
| `text.plist.entitlements` | `GoToSleep.entitlements` | Fed to `codesign` during code signing |
| `wrapper.application` | `GoToSleep.app` | The output app bundle (product) |
| `compiled.mach-o.executable` | `GoToSleepDaemon` | The output CLI binary (product) |

### Two kinds of file references

**Source files** (e.g., `B100000002`): use `lastKnownFileType` and `sourceTree = "<group>"`. They're files you wrote, living in your source tree. Their full disk path is resolved by walking up through parent groups.

**Product files** (e.g., `P100000001`): use `explicitFileType` and `sourceTree = BUILT_PRODUCTS_DIR`. They're outputs of the build, living in derived data. They don't exist until you build.

### What it doesn't do

A `PBXFileReference` alone doesn't cause anything to be compiled or copied. It just registers the file. To include it in the build, a `PBXBuildFile` must reference it, and that build file must be listed in a build phase. Some files like `Info.plist` and `GoToSleep.entitlements` skip the build file mechanism entirely — they're referenced directly by build settings (`INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS`).

---

## 5. PBXFrameworksBuildPhase

```
/* Begin PBXFrameworksBuildPhase section */
    F100000001 /* Frameworks */ = {
        isa = PBXFrameworksBuildPhase;
        buildActionMask = 2147483647;
        files = (
        );
        runOnlyForDeploymentPostprocessing = 0;
    };
    F200000001 /* Frameworks */ = {
        isa = PBXFrameworksBuildPhase;
        buildActionMask = 2147483647;
        files = (
        );
        runOnlyForDeploymentPostprocessing = 0;
    };
/* End PBXFrameworksBuildPhase section */
```

### What it is

The **linking phase**. This is where you tell the linker which frameworks and libraries to link against your compiled object files. Every target gets one.

### Fields

| Field | Meaning |
|---|---|
| `buildActionMask` | `2147483647` = always runs. |
| `files` | Array of `PBXBuildFile` IDs pointing to framework/library file references. |
| `runOnlyForDeploymentPostprocessing` | `0` = runs on every build (frameworks must always be linked). |

### Why both are empty

Neither target explicitly links any frameworks. This works because:

- **GoToSleep** (the app): has `productType = "com.apple.product-type.application"`. Xcode automatically links `AppKit`, `Foundation`, `SwiftUI`, and other system frameworks for app targets. You only need entries here for third-party frameworks or frameworks outside the default set.
- **GoToSleepDaemon** (the CLI tool): has `productType = "com.apple.product-type.tool"`. CLI tools auto-link `Foundation` but NOT `AppKit`. The daemon's `main.swift` has an explicit `import AppKit` which works because `CLANG_ENABLE_MODULES = YES` at the project level enables automatic module linking — the Swift compiler sees the import and tells the linker to link it.

### When you'd add entries

If you added a third-party framework (like Sparkle for auto-updates), you'd:
1. Add a `PBXFileReference` for the `.framework` file
2. Add a `PBXBuildFile` pointing to it
3. Add that build file ID to this `files` array

---

## 6. PBXGroup

```
/* Begin PBXGroup section */
    G000000001 /* Root */ = {
        isa = PBXGroup;
        children = (
            G100000001 /* GoToSleep */,
            G200000001 /* GoToSleepDaemon */,
            G300000001 /* Shared */,
            G400000001 /* Resources */,
            G500000001 /* Products */,
        );
        sourceTree = "<group>";
    };
    G100000001 /* GoToSleep */ = {
        isa = PBXGroup;
        children = ( ... );
        path = GoToSleep;
        sourceTree = "<group>";
    };
    ...
/* End PBXGroup section */
```

### What it is

The **folder hierarchy** shown in Xcode's Project Navigator sidebar. Groups organise `PBXFileReference` entries and other groups into a tree structure.

### Fields

| Field | Meaning |
|---|---|
| `children` | Ordered list of child IDs (other `PBXGroup`s or `PBXFileReference`s). The order determines display order in Xcode's sidebar. |
| `path` | Maps this group to a directory on disk. When resolving a child's file path, Xcode walks up through parent groups concatenating `path` values. |
| `name` | Display name (used instead of `path` when the group doesn't map to a real directory). |
| `sourceTree` | How to resolve the path. `"<group>"` means relative to the parent group. |

### The full hierarchy

```
G000000001 (Root — project root directory)
├── G100000001 (GoToSleep/)
│   ├── G110000001 (App/)
│   │   ├── B100000022  main.swift          → GoToSleep/App/main.swift
│   │   └── B100000002  AppDelegate.swift   → GoToSleep/App/AppDelegate.swift
│   ├── G120000001 (Views/)
│   │   ├── B100000003  OverlayView.swift   → GoToSleep/Views/OverlayView.swift
│   │   ├── B100000004  QuestionView.swift  → GoToSleep/Views/QuestionView.swift
│   │   ├── B100000005  SettingsView.swift  → GoToSleep/Views/SettingsView.swift
│   │   └── B100000007  PermissionsGuide…   → GoToSleep/Views/PermissionsGuideView.swift
│   ├── G130000001 (Models/)
│   │   ├── B100000008  Question.swift      → GoToSleep/Models/Question.swift
│   │   ├── B100000009  QuestionStore.swift → GoToSleep/Models/QuestionStore.swift
│   │   ├── B100000010  SessionLog.swift    → GoToSleep/Models/SessionLog.swift
│   │   └── B100000011  AppSettings.swift   → GoToSleep/Models/AppSettings.swift
│   ├── G140000001 (Services/)
│   │   ├── B100000012  OverlayWindow…      → GoToSleep/Services/OverlayWindowController.swift
│   │   ├── B100000013  FocusEnforcer.swift → GoToSleep/Services/FocusEnforcer.swift
│   │   ├── B100000014  AnswerLogger.swift  → GoToSleep/Services/AnswerLogger.swift
│   │   └── B100000021  AudioMuter.swift    → GoToSleep/Services/AudioMuter.swift
│   ├── G150000001 (Resources/)
│   │   ├── B100000017  questions.json      → GoToSleep/Resources/questions.json
│   │   └── B100000018  Assets.xcassets     → GoToSleep/Resources/Assets.xcassets
│   ├── B100000019  Info.plist              → GoToSleep/Info.plist
│   └── B100000020  GoToSleep.entitlements  → GoToSleep/GoToSleep.entitlements
├── G200000001 (GoToSleepDaemon/)
│   ├── B200000001  main.swift              → GoToSleepDaemon/main.swift
│   └── B200000002  Info.plist              → GoToSleepDaemon/Info.plist
├── G300000001 (Shared/)
│   ├── B100000015  Paths.swift             → Shared/Paths.swift
│   └── B100000016  TimeCheck.swift         → Shared/TimeCheck.swift
├── G400000001 (Resources/)
│   └── B300000001  com.gotosleep.daemon…   → Resources/com.gotosleep.daemon.plist
└── G500000001 (Products — virtual, no disk path)
    ├── P100000001  GoToSleep.app           → in BUILT_PRODUCTS_DIR
    └── P200000001  GoToSleepDaemon         → in BUILT_PRODUCTS_DIR
```

### path vs name

- Groups with `path` map to real directories on disk. The path contributes to resolving child file locations.
- Groups with `name` (like "Products") are virtual — they're purely organisational in the Xcode sidebar and don't correspond to a filesystem directory.

### Does it affect the build?

**No.** Groups are purely for Xcode's sidebar organisation. They have no effect on what gets compiled, linked, or bundled. The build is entirely driven by build phases. You could flatten all groups into one and the build would be identical — as long as the `PBXFileReference` paths still resolve correctly.

The one indirect contribution is **path resolution**: the group hierarchy with `path` fields is how Xcode resolves `sourceTree = "<group>"` file references to actual disk locations. But this is a property of the filesystem layout, not the grouping itself.

---

## 7. PBXNativeTarget

```
/* Begin PBXNativeTarget section */
    T100000001 /* GoToSleep */ = {
        isa = PBXNativeTarget;
        buildConfigurationList = X100000001;
        buildPhases = (
            S100000001 /* Sources */,
            F100000001 /* Frameworks */,
            R100000001 /* Resources */,
            C100000001 /* Copy Daemon */,
        );
        buildRules = (
        );
        dependencies = (
        );
        name = GoToSleep;
        productName = GoToSleep;
        productReference = P100000001 /* GoToSleep.app */;
        productType = "com.apple.product-type.application";
    };
    T200000001 /* GoToSleepDaemon */ = {
        isa = PBXNativeTarget;
        buildConfigurationList = X200000001;
        buildPhases = (
            S200000001 /* Sources */,
            F200000001 /* Frameworks */,
            C200000001 /* CopyFiles */,
        );
        buildRules = (
        );
        dependencies = (
        );
        name = GoToSleepDaemon;
        productName = GoToSleepDaemon;
        productReference = P200000001 /* GoToSleepDaemon */;
        productType = "com.apple.product-type.tool";
    };
/* End PBXNativeTarget section */
```

### What it is

The **target definition** — the most important object type in the file. A target represents one buildable product. This project has two targets that produce two separate binaries.

### Fields

| Field | Meaning |
|---|---|
| `buildConfigurationList` | Points to an `XCConfigurationList` containing Debug/Release configurations for this target. |
| `buildPhases` | Ordered array of build phase IDs. These execute **in order** during a build. The order matters — sources must compile before resources can be copied. |
| `buildRules` | Custom rules that override how certain file types are processed. Empty here — using all defaults. |
| `dependencies` | Other targets that must build first. Empty here — the two targets are independent. If you wanted the app to automatically build the daemon first, you'd add a `PBXTargetDependency` here. |
| `name` | The target name shown in Xcode's scheme selector. |
| `productName` | The base name for the output product. |
| `productReference` | Points to the `PBXFileReference` for the built product. |
| `productType` | Determines the product type, which controls Xcode's implicit behaviour (auto-linked frameworks, bundle structure, etc.). |

### productType values

| Value | Meaning | Implicit behaviour |
|---|---|---|
| `com.apple.product-type.application` | macOS/iOS app | Creates `.app` bundle, auto-links AppKit/UIKit, generates Info.plist, supports resources |
| `com.apple.product-type.tool` | Command-line tool | Produces a bare Mach-O executable, auto-links Foundation only, no bundle structure |

### Build phase order

**GoToSleep app** builds in this order:
1. `S100000001` — Compile 16 Swift source files
2. `F100000001` — Link frameworks (none explicit, system ones auto-linked)
3. `R100000001` — Copy resources (questions.json, Assets.xcassets, daemon plist) into the .app bundle
4. `C100000001` — Copy Daemon phase (currently empty)

**GoToSleepDaemon** builds in this order:
1. `S200000001` — Compile 3 Swift source files
2. `F200000001` — Link frameworks (none explicit)
3. `C200000001` — Copy man page (empty, deployment-only)

Note the daemon has **no Resources phase** — CLI tools don't have a bundle structure to put resources in.

---

## 8. PBXProject

```
/* Begin PBXProject section */
    PRJ0000001 /* Project object */ = {
        isa = PBXProject;
        attributes = {
            BuildIndependentTargetsInParallel = 1;
            LastSwiftUpdateCheck = 1500;
            LastUpgradeCheck = 1500;
            TargetAttributes = {
                T100000001 = {
                    CreatedOnToolsVersion = 15.0;
                };
                T200000001 = {
                    CreatedOnToolsVersion = 15.0;
                };
            };
        };
        buildConfigurationList = X000000001;
        compatibilityVersion = "Xcode 14.0";
        developmentRegion = en;
        hasScannedForEncodings = 0;
        knownRegions = (
            en,
            Base,
        );
        mainGroup = G000000001;
        productRefGroup = G500000001 /* Products */;
        projectDirPath = "";
        projectRoot = "";
        targets = (
            T100000001 /* GoToSleep */,
            T200000001 /* GoToSleepDaemon */,
        );
    };
/* End PBXProject section */
```

### What it is

The **root object** — the single entry point for the entire project. The `rootObject` field at the bottom of the file points here. Everything else is discovered by following references from this object.

### Fields

| Field | Meaning |
|---|---|
| `attributes` | Metadata about the project and its targets. |
| `buildConfigurationList` | Points to the **project-level** `XCConfigurationList` (Debug/Release settings that apply to all targets unless overridden). |
| `compatibilityVersion` | Minimum Xcode version that can open this project. `"Xcode 14.0"` here. |
| `developmentRegion` | The primary language for the project. `en` = English. |
| `hasScannedForEncodings` | Whether Xcode has scanned files for text encoding. `0` = no. Legacy field. |
| `knownRegions` | Localisation regions the project supports. `en` and `Base` (the base localisation). |
| `mainGroup` | Points to the root `PBXGroup` — the top of the sidebar hierarchy. |
| `productRefGroup` | Points to the "Products" group — where built products appear in the sidebar. |
| `projectDirPath` | Usually empty. Can override the project directory. |
| `projectRoot` | Usually empty. Can set the root for resolving `SOURCE_ROOT` paths. |
| `targets` | The ordered list of all target IDs. This is the master list of what can be built. |

### attributes breakdown

| Attribute | Meaning |
|---|---|
| `BuildIndependentTargetsInParallel = 1` | When building multiple targets, build them in parallel if they don't depend on each other. Since neither target has `dependencies`, both build simultaneously. |
| `LastSwiftUpdateCheck = 1500` | Last Xcode version (15.0.0) that checked for Swift migration opportunities. |
| `LastUpgradeCheck = 1500` | Last Xcode version that ran its project upgrade assistant. |
| `TargetAttributes` | Per-target metadata. `CreatedOnToolsVersion = 15.0` records which Xcode version created each target. |

---

## 9. PBXResourcesBuildPhase

```
/* Begin PBXResourcesBuildPhase section */
    R100000001 /* Resources */ = {
        isa = PBXResourcesBuildPhase;
        buildActionMask = 2147483647;
        files = (
            A100000017 /* questions.json in Resources */,
            A100000018 /* Assets.xcassets in Resources */,
            A300000001 /* com.gotosleep.daemon.plist in Resources */,
        );
        runOnlyForDeploymentPostprocessing = 0;
    };
/* End PBXResourcesBuildPhase section */
```

### What it is

The build phase that **copies resource files into the app bundle**. Resources end up in `GoToSleep.app/Contents/Resources/` on macOS. Only the GoToSleep app target has this phase — the daemon is a CLI tool with no bundle.

### Fields

Same structure as other build phases:

| Field | Meaning |
|---|---|
| `buildActionMask` | `2147483647` = always runs. |
| `files` | Array of `PBXBuildFile` IDs to process. |
| `runOnlyForDeploymentPostprocessing` | `0` = runs on every build. |

### What happens to each resource

| File | Build file ID | What Xcode does |
|---|---|---|
| `questions.json` | A100000017 | Copied as-is into `Contents/Resources/questions.json`. The app reads it at runtime via `Bundle.main`. |
| `Assets.xcassets` | A100000018 | **Not** copied as-is. Processed by `actool` (Asset Catalog compiler) into optimised binary assets. App icons, accent colours, and images get compiled into a single `.car` file. |
| `com.gotosleep.daemon.plist` | A300000001 | Copied as-is into `Contents/Resources/`. The app reads this template at runtime to write the LaunchAgent plist to `~/Library/LaunchAgents/`. |

### Why the daemon target has no Resources phase

CLI tools (product type `com.apple.product-type.tool`) produce a bare executable, not a `.app` bundle. There's no `Contents/Resources/` directory to put things in. If the daemon needed to read a file, it would need to find it by absolute path or receive it as an argument.

---

## 10. PBXSourcesBuildPhase

```
/* Begin PBXSourcesBuildPhase section */
    S100000001 /* Sources */ = {
        isa = PBXSourcesBuildPhase;
        buildActionMask = 2147483647;
        files = (
            A100000020 /* main.swift in Sources */,
            A100000002 /* AppDelegate.swift in Sources */,
            A100000003 /* OverlayView.swift in Sources */,
            A100000004 /* QuestionView.swift in Sources */,
            A100000005 /* SettingsView.swift in Sources */,
            A100000007 /* PermissionsGuideView.swift in Sources */,
            A100000008 /* Question.swift in Sources */,
            A100000009 /* QuestionStore.swift in Sources */,
            A100000010 /* SessionLog.swift in Sources */,
            A100000011 /* AppSettings.swift in Sources */,
            A100000012 /* OverlayWindowController.swift in Sources */,
            A100000013 /* FocusEnforcer.swift in Sources */,
            A100000014 /* AnswerLogger.swift in Sources */,
            A100000015 /* Paths.swift in Sources */,
            A100000016 /* TimeCheck.swift in Sources */,
            A100000019 /* AudioMuter.swift in Sources */,
        );
        runOnlyForDeploymentPostprocessing = 0;
    };
    S200000001 /* Sources */ = {
        isa = PBXSourcesBuildPhase;
        buildActionMask = 2147483647;
        files = (
            A200000001 /* main.swift in Sources */,
            A200000002 /* Paths.swift in Sources */,
            A200000003 /* TimeCheck.swift in Sources */,
        );
        runOnlyForDeploymentPostprocessing = 0;
    };
/* End PBXSourcesBuildPhase section */
```

### What it is

The **compilation phase**. This is where source files get compiled into object files (`.o`), which are then linked into the final binary. Each target has exactly one.

### What happens during this phase

1. The Swift compiler (`swiftc`) receives all files listed in `files` as a single compilation unit (in whole-module mode) or as individual files (in incremental mode).
2. Each `.swift` file is compiled into an object file.
3. The object files are passed to the linker in the Frameworks phase.

### The two phases

**S100000001 — GoToSleep app**: compiles 16 Swift files. This includes:
- The app entry point (`main.swift`)
- The app delegate, all views, models, and services
- The shared files (`Paths.swift`, `TimeCheck.swift`) — compiled again separately for this target

**S200000001 — GoToSleepDaemon**: compiles 3 Swift files:
- Its own `main.swift` (the daemon entry point)
- `Paths.swift` and `TimeCheck.swift` (the shared files, compiled again for this target)

### File order doesn't matter

The order of files in the `files` array has no effect on compilation. Swift compiles all files in a target as a single module — every file can see every other file's public/internal declarations regardless of order. The order only affects display in Xcode's build phase UI.

### Shared files are compiled twice

`Paths.swift` and `TimeCheck.swift` appear in both source phases (via different `PBXBuildFile` entries pointing to the same `PBXFileReference`). Each target compiles its own copy. This is the simplest way to share code without creating a framework — the trade-off is that any types defined in these files are distinct types in each target (they just happen to have the same definition).

---

## 11. XCBuildConfiguration

```
/* Begin XCBuildConfiguration section */
    /* Project-level Debug */
    D000000001 /* Debug */ = {
        isa = XCBuildConfiguration;
        buildSettings = {
            ALWAYS_SEARCH_USER_PATHS = NO;
            ...
            MACOSX_DEPLOYMENT_TARGET = 11.0;
            ...
            SWIFT_OPTIMIZATION_LEVEL = "-Onone";
        };
        name = Debug;
    };
    /* Project-level Release */
    D000000002 /* Release */ = { ... };
    /* GoToSleep target Debug */
    D100000001 /* Debug */ = { ... };
    /* GoToSleep target Release */
    D100000002 /* Release */ = { ... };
    /* GoToSleepDaemon target Debug */
    D200000001 /* Debug */ = { ... };
    /* GoToSleepDaemon target Release */
    D200000002 /* Release */ = { ... };
/* End XCBuildConfiguration section */
```

### What it is

A **named set of build settings** — the compiler flags, linker flags, deployment targets, signing settings, and everything else that controls how a build is performed. Each configuration is either "Debug" or "Release".

### The two layers

Build configurations exist at two levels, and they **merge**:

1. **Project-level** (`D000000001`, `D000000002`) — settings that apply to all targets unless overridden. These are the defaults.
2. **Target-level** (`D100000001`/`D100000002` for GoToSleep, `D200000001`/`D200000002` for the daemon) — settings specific to one target. These override project-level settings when both define the same key.

The final value of any build setting for a target is: **target-level value if set, otherwise project-level value**.

### Project-level Debug settings (D000000001) — annotated

```
ALWAYS_SEARCH_USER_PATHS = NO;          // Don't search ~/Headers. Legacy setting, always NO.
ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                                         // Generate Swift symbols for asset catalog entries.
CLANG_ANALYZER_NONNULL = YES;           // Enable static analysis of nullability annotations.
CLANG_CXX_LANGUAGE_STANDARD = "gnu++20"; // C++ standard (for any C++ code, not used here).
CLANG_ENABLE_MODULES = YES;             // IMPORTANT: enables @import / automatic module linking.
                                         // This is why `import AppKit` in the daemon works
                                         // without an explicit framework link.
CLANG_ENABLE_OBJC_ARC = YES;            // Automatic Reference Counting for Obj-C code.
COPY_PHASE_STRIP = NO;                  // Don't strip symbols during copy phases (Debug).
DEBUG_INFORMATION_FORMAT = dwarf;        // Debug symbols format. "dwarf" = embedded in binary.
                                         // Release uses "dwarf-with-dsym" = separate .dSYM file.
ENABLE_STRICT_OBJC_MSGSEND = YES;       // Type-check Obj-C message sends.
ENABLE_TESTABILITY = YES;               // Allow @testable import in test targets.
ENABLE_USER_SCRIPT_SANDBOXING = YES;    // Sandbox custom build scripts.
GCC_C_LANGUAGE_STANDARD = gnu17;        // C standard (for any C code).
GCC_DYNAMIC_NO_PIC = NO;               // Generate position-independent code.
GCC_NO_COMMON_BLOCKS = YES;            // Don't use "common" symbol linkage.
GCC_OPTIMIZATION_LEVEL = 0;            // -O0: no optimisation (fast builds, debuggable code).
GCC_PREPROCESSOR_DEFINITIONS = (        // #define DEBUG=1 for preprocessor checks.
    "DEBUG=1",
    "$(inherited)",
);
GCC_WARN_64_TO_32_BIT_CONVERSION = YES; // Warn on implicit 64→32 bit truncation.
GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR; // Missing return statement is an error, not warning.
GCC_WARN_UNDECLARED_SELECTOR = YES;     // Warn on @selector() for unknown methods.
GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE; // Aggressively warn on uninitialised variables.
GCC_WARN_UNUSED_FUNCTION = YES;         // Warn on unused functions.
GCC_WARN_UNUSED_VARIABLE = YES;         // Warn on unused variables.
MACOSX_DEPLOYMENT_TARGET = 11.0;        // Minimum macOS version: Big Sur.
MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE; // Metal shader debug info (not used here).
MTL_FAST_MATH = YES;                    // Fast floating-point math for Metal.
ONLY_ACTIVE_ARCH = YES;                 // Only build for the current Mac's architecture
                                         // (arm64 on Apple Silicon, x86_64 on Intel).
                                         // Release omits this → builds universal binary.
SDKROOT = macosx;                       // Build against the macOS SDK.
SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
                                         // Enables #if DEBUG in Swift code.
SWIFT_OPTIMIZATION_LEVEL = "-Onone";    // No Swift optimisation (debuggable).
```

### Project-level Release settings (D000000002) — key differences from Debug

```
DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";  // Separate .dSYM file for crash symbolication.
ENABLE_NS_ASSERTIONS = NO;                     // Disable NSAssert() in production.
// GCC_OPTIMIZATION_LEVEL absent                → defaults to -Os (optimise for size).
// ONLY_ACTIVE_ARCH absent                      → builds for all architectures (universal binary).
// GCC_PREPROCESSOR_DEFINITIONS absent          → no DEBUG=1 defined.
// SWIFT_ACTIVE_COMPILATION_CONDITIONS absent   → #if DEBUG evaluates to false.
SWIFT_COMPILATION_MODE = wholemodule;           // Compile all Swift files together for
                                                 // maximum optimisation (slower builds).
```

### GoToSleep target settings (D100000001 / D100000002)

These are identical for Debug and Release:

```
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;   // Name of the app icon set in Assets.xcassets.
CODE_SIGN_ENTITLEMENTS = GoToSleep/GoToSleep.entitlements;
                                                  // Path to the entitlements file for codesigning.
CODE_SIGN_STYLE = Automatic;                     // Let Xcode manage signing certificates.
COMBINE_HIDPI_IMAGES = YES;                      // Combine @1x and @2x images into multi-res TIFFs.
CURRENT_PROJECT_VERSION = 1;                     // Build number.
ENABLE_APP_SANDBOX = NO;                         // App Sandbox disabled — required because the app
                                                  // uses accessibility APIs, launches processes,
                                                  // and writes to ~/Library/LaunchAgents/.
GENERATE_INFOPLIST_FILE = YES;                   // Xcode generates Info.plist from build settings
                                                  // merged with the INFOPLIST_FILE.
INFOPLIST_FILE = GoToSleep/Info.plist;           // Base Info.plist to merge with.
INFOPLIST_KEY_LSUIElement = YES;                 // LSUIElement = true → the app is an "agent" with
                                                  // no Dock icon. Menu bar apps use this.
INFOPLIST_KEY_NSHumanReadableCopyright = "";     // Copyright string (empty).
LD_RUNPATH_SEARCH_PATHS = (                      // Where to find dynamically linked frameworks
    "$(inherited)",                               // at runtime. @executable_path/../Frameworks
    "@executable_path/../Frameworks",             // is standard for app bundles.
);
MARKETING_VERSION = 1.0;                         // User-facing version string.
PRODUCT_BUNDLE_IDENTIFIER = "com.gotosleep.app"; // The app's bundle ID.
PRODUCT_NAME = "$(TARGET_NAME)";                 // Output name = target name ("GoToSleep").
SWIFT_EMIT_LOC_STRINGS = YES;                    // Extract localisable strings from Swift code.
SWIFT_VERSION = 5.0;                             // Swift language version.
```

### GoToSleepDaemon target settings (D200000001 / D200000002)

Minimal — CLI tools need very few settings:

```
CODE_SIGN_STYLE = Automatic;                      // Automatic signing.
PRODUCT_BUNDLE_IDENTIFIER = "com.gotosleep.daemon"; // Bundle ID for the daemon.
PRODUCT_NAME = "$(TARGET_NAME)";                   // Output name = "GoToSleepDaemon".
SWIFT_VERSION = 5.0;                               // Swift language version.
```

Everything else is inherited from the project-level configuration.

---

## 12. XCConfigurationList

```
/* Begin XCConfigurationList section */
    X000000001 /* Build configuration list for PBXProject "GoToSleep" */ = {
        isa = XCConfigurationList;
        buildConfigurations = (
            D000000001 /* Debug */,
            D000000002 /* Release */,
        );
        defaultConfigurationIsVisible = 0;
        defaultConfigurationName = Release;
    };
    X100000001 /* Build configuration list for PBXNativeTarget "GoToSleep" */ = {
        isa = XCConfigurationList;
        buildConfigurations = (
            D100000001 /* Debug */,
            D100000002 /* Release */,
        );
        defaultConfigurationIsVisible = 0;
        defaultConfigurationName = Release;
    };
    X200000001 /* Build configuration list for PBXNativeTarget "GoToSleepDaemon" */ = {
        isa = XCConfigurationList;
        buildConfigurations = (
            D200000001 /* Debug */,
            D200000002 /* Release */,
        );
        defaultConfigurationIsVisible = 0;
        defaultConfigurationName = Release;
    };
/* End XCConfigurationList section */
```

### What it is

A **container that groups Debug and Release configurations together**. Every project and every target has exactly one. It's the object that `buildConfigurationList` fields point to.

### Fields

| Field | Meaning |
|---|---|
| `buildConfigurations` | Ordered array of `XCBuildConfiguration` IDs (always Debug and Release). |
| `defaultConfigurationIsVisible` | Whether the configuration selector is visible in Xcode's UI. `0` = hidden (you choose via scheme settings instead). |
| `defaultConfigurationName` | Which configuration to use when none is specified. `Release` here — so `xcodebuild` without `-configuration Debug` builds Release. |

### The three lists

| List | Owner | Contains | Purpose |
|---|---|---|---|
| `X000000001` | `PBXProject` | `D000000001` (Debug), `D000000002` (Release) | Project-wide defaults |
| `X100000001` | GoToSleep target | `D100000001` (Debug), `D100000002` (Release) | App-specific overrides |
| `X200000001` | GoToSleepDaemon target | `D200000001` (Debug), `D200000002` (Release) | Daemon-specific overrides |

When you run `xcodebuild -configuration Debug`, Xcode picks the "Debug" configuration from each list. The project-level Debug settings merge with the target-level Debug settings to produce the final build settings.

---

## 13. The rootObject

```
rootObject = PRJ0000001 /* Project object */;
```

This single line at the bottom of the file is the **entry point**. It tells Xcode which object in the `objects` dictionary is the `PBXProject`. From there, Xcode follows references to discover:

- `PRJ0000001` → `mainGroup` → the entire group/file hierarchy
- `PRJ0000001` → `targets` → all targets → their build phases → their files
- `PRJ0000001` → `buildConfigurationList` → project-level settings

Every object in the file is reachable by following reference chains from this root.

---

## 14. How It All Fits Together

When you run `xcodebuild -target GoToSleep -configuration Debug`, here's the resolution chain:

```
rootObject = PRJ0000001
    │
    ├─→ targets: [T100000001, T200000001]
    │       │
    │       └─→ T100000001 (GoToSleep)
    │               │
    │               ├─→ buildConfigurationList: X100000001
    │               │       └─→ D100000001 (target Debug settings)
    │               │           merged with D000000001 (project Debug settings)
    │               │
    │               ├─→ buildPhases (executed in order):
    │               │       │
    │               │       ├─→ S100000001 (Sources)
    │               │       │       └─→ files: [A100000020, A100000002, ...]
    │               │       │               └─→ each fileRef → PBXFileReference → .swift file
    │               │       │               └─→ ALL compiled by swiftc
    │               │       │
    │               │       ├─→ F100000001 (Frameworks)
    │               │       │       └─→ files: [] (system frameworks auto-linked)
    │               │       │       └─→ Object files linked into executable
    │               │       │
    │               │       ├─→ R100000001 (Resources)
    │               │       │       └─→ files: [A100000017, A100000018, A300000001]
    │               │       │               └─→ questions.json, Assets.xcassets, daemon.plist
    │               │       │               └─→ Copied/processed into .app/Contents/Resources/
    │               │       │
    │               │       └─→ C100000001 (Copy Daemon)
    │               │               └─→ files: [] (empty)
    │               │
    │               └─→ productReference: P100000001
    │                       └─→ GoToSleep.app in BUILT_PRODUCTS_DIR
    │
    └─→ buildConfigurationList: X000000001
            └─→ D000000001 (project Debug settings — the base layer)
```

The output is `GoToSleep.app` — a macOS app bundle containing the compiled executable, processed assets, and copied resources.

---

## 15. Object ID Convention

Standard Xcode projects use random 24-character hex UUIDs like `8A3B2F1C09D4E5A7001ABC12`. This project uses a hand-crafted convention with semantic prefixes:

| Prefix | Object type | Example |
|---|---|---|
| `A1xxxxxxxx` | `PBXBuildFile` (GoToSleep) | `A100000002` |
| `A2xxxxxxxx` | `PBXBuildFile` (Daemon) | `A200000001` |
| `A3xxxxxxxx` | `PBXBuildFile` (Shared resources) | `A300000001` |
| `B1xxxxxxxx` | `PBXFileReference` (GoToSleep) | `B100000002` |
| `B2xxxxxxxx` | `PBXFileReference` (Daemon) | `B200000001` |
| `B3xxxxxxxx` | `PBXFileReference` (Shared resources) | `B300000001` |
| `C1/C2` | `PBXCopyFilesBuildPhase` | `C100000001` |
| `D0xxxxxxxx` | `XCBuildConfiguration` (Project) | `D000000001` |
| `D1xxxxxxxx` | `XCBuildConfiguration` (GoToSleep) | `D100000001` |
| `D2xxxxxxxx` | `XCBuildConfiguration` (Daemon) | `D200000001` |
| `F1/F2` | `PBXFrameworksBuildPhase` | `F100000001` |
| `Gxxxxxxxxx` | `PBXGroup` | `G100000001` |
| `P1/P2` | `PBXFileReference` (Products) | `P100000001` |
| `PRJ` | `PBXProject` | `PRJ0000001` |
| `R1` | `PBXResourcesBuildPhase` | `R100000001` |
| `S1/S2` | `PBXSourcesBuildPhase` | `S100000001` |
| `T1/T2` | `PBXNativeTarget` | `T100000001` |
| `X0/X1/X2` | `XCConfigurationList` | `X000000001` |

This is purely cosmetic. Xcode only requires that IDs are unique within the file. The prefixed convention makes the file human-readable and editable by hand — which is how this project's pbxproj was originally written.
