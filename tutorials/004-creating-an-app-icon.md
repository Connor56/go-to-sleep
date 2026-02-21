# Creating an App Icon

The asset catalog at `GoToSleep/Resources/Assets.xcassets/AppIcon.appiconset/`
has all the size slots defined in `Contents.json` but no actual image files. The
build produces no `AppIcon.icns` and no `Assets.car`, so the app shows a generic
blank icon in Finder and the Dock.

The menu bar icon is fine — the code uses `NSImage(systemSymbolName: "moon.fill")`
(a built-in SF Symbol), not the empty `MenuBarIcon.imageset`. No work needed
there.

---

## What You Need

macOS app icons require a single design rendered at these sizes:

| Size    | Scale | Pixels        | Filename (suggested) |
|---------|-------|---------------|----------------------|
| 16x16   | 1x    | 16 x 16      | icon_16x16.png       |
| 16x16   | 2x    | 32 x 32      | icon_16x16@2x.png    |
| 32x32   | 1x    | 32 x 32      | icon_32x32.png       |
| 32x32   | 2x    | 64 x 64      | icon_32x32@2x.png    |
| 128x128 | 1x    | 128 x 128    | icon_128x128.png     |
| 128x128 | 2x    | 256 x 256    | icon_128x128@2x.png  |
| 256x256 | 1x    | 256 x 256    | icon_256x256.png     |
| 256x256 | 2x    | 512 x 512    | icon_256x256@2x.png  |
| 512x512 | 1x    | 512 x 512    | icon_512x512.png     |
| 512x512 | 2x    | 1024 x 1024  | icon_512x512@2x.png  |

Note: 16x16@2x and 32x32@1x are both 32px, and 32x32@2x and 128x128@0.5x
overlap at 64px, etc. You still need separate files for each slot even if the
pixel dimensions match — just use the same image.

---

## Step 1: Create the Master Icon

Start with a single **1024 x 1024 PNG** image. This is your master icon. Design
it however you like. Some approaches:

### Option A: Design in any image editor

Use Figma, Sketch, Photoshop, GIMP, Pixelmator, or whatever you prefer. Export
as a 1024x1024 PNG with transparency.

### Option B: Quick-and-dirty with macOS built-in tools

If you just want something functional to test with, you can use Preview.app:

1. Open Preview.
2. File > New from Clipboard (or create a new blank image).
3. Draw/paste your design.
4. Export as PNG at 1024x1024.

### Option C: Use an SF Symbol as a starting point

Since the app already uses `moon.fill` for the menu bar, you could screenshot
an SF Symbol and use it. But for a proper app icon, you'd want something more
polished.

### Design tips for macOS icons

- macOS icons should **not** be circular or have a rounded-rect mask (that's
  iOS). macOS icons are traditionally a freeform shape on a transparent
  background, or a rounded rectangle with a slight perspective tilt.
- Keep it simple — a moon/sleep motif works well for this app.
- Use a transparent background so the icon looks good on any desktop wallpaper.

---

## Step 2: Generate All Sizes

Once you have your `icon_1024x1024.png` master file, use `sips` (built into
macOS) to generate all required sizes. Run these commands from Terminal:

```bash
cd GoToSleep/Resources/Assets.xcassets/AppIcon.appiconset

# Copy your master file here first, then:
sips -z 16 16 icon_1024x1024.png --out icon_16x16.png
sips -z 32 32 icon_1024x1024.png --out icon_16x16@2x.png
sips -z 32 32 icon_1024x1024.png --out icon_32x32.png
sips -z 64 64 icon_1024x1024.png --out icon_32x32@2x.png
sips -z 128 128 icon_1024x1024.png --out icon_128x128.png
sips -z 256 256 icon_1024x1024.png --out icon_128x128@2x.png
sips -z 256 256 icon_1024x1024.png --out icon_256x256.png
sips -z 512 512 icon_1024x1024.png --out icon_256x256@2x.png
sips -z 512 512 icon_1024x1024.png --out icon_512x512.png
sips -z 1024 1024 icon_1024x1024.png --out icon_512x512@2x.png
```

You can delete the master `icon_1024x1024.png` from this directory afterwards
if you like (or keep it — it won't hurt anything, xcodebuild ignores files not
referenced in Contents.json).

---

## Step 3: Update Contents.json

**File:**
`GoToSleep/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

The current file has all the size entries but no `"filename"` keys. You need to
add a `"filename"` to each entry. Replace the entire file with:

```json
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

---

## Step 4: Build and Verify

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  clean build
```

Check that the icon was compiled:

```bash
ls build/Build/Products/Debug/GoToSleep.app/Contents/Resources/
```

You should now see `AppIcon.icns` and `Assets.car` in the listing.

To see the icon visually, open the app bundle location in Finder:

```bash
open build/Build/Products/Debug/
```

The `GoToSleep.app` should display your custom icon instead of the generic
blank document icon.

---

## Troubleshooting

**Icon still shows as generic/blank after building:**

macOS aggressively caches app icons. To force a refresh:

```bash
# Clear the icon cache
sudo find /private/var/folders/ -name com.apple.dock.iconcache -exec rm {} \;
sudo find /private/var/folders/ -name com.apple.iconservices -exec rm -rf {} \;

# Restart the Dock
killall Dock
```

**Build warning about missing icon sizes:**

If you see warnings like "A 1024x1024 app icon is required", make sure all 10
PNG files are present in the `AppIcon.appiconset` directory and all `"filename"`
entries in `Contents.json` match exactly.

**sips produces blurry small icons:**

`sips` does basic bilinear downscaling. For the tiny sizes (16x16, 32x32), the
icon might look mushy. If you care about pixel-perfect small icons, hand-craft
the 16x16 and 32x32 versions separately in an image editor with simpler shapes
and fewer details.
