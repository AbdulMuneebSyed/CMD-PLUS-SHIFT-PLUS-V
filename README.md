# CopyOnScreenShot

Lightweight macOS menu bar utility that keeps a five-item clipboard history, opens a compact picker with `Cmd+Shift+V`, and still auto-copies new screenshots into the clipboard if you want that enabled.

## Features

- Runs as a menu bar app with no Dock icon
- Keeps the latest 5 clipboard items
- Opens a compact clipboard picker with `Cmd+Shift+V`
- Focuses the first item automatically so you can use the keyboard immediately
- Press `Enter` to paste the selected item or `Esc` to close the picker
- Clicking an item pastes it back into the previously focused app
- Watches `~/Desktop`, `~/Pictures/Screenshots`, and the active macOS screenshot location from `com.apple.screencapture`
- Detects new screenshot files without polling by using `DispatchSource` directory watchers
- Waits 0.5 seconds before reading each new screenshot so the file is fully written
- Copies the screenshot image to `NSPasteboard` as an `NSImage`
- Shows a native notification: `Screenshot copied to clipboard`
- Menu controls:
  - `Show Clipboard History`
  - `Auto-copy Screenshots: On/Off`
  - `Delete After Copy: On/Off`
  - `Launch at Login: On/Off`
  - `Quit`

## Build

```bash
./Scripts/build_app.sh
```

The packaged app is created at:

```bash
dist/CopyOnScreenShot.app
```

## Run

Open the packaged app from Finder, or run:

```bash
open dist/CopyOnScreenShot.app
```

## Notes

- macOS may ask for notification permission so the app can show the copied banner.
- If macOS asks for access to `Desktop`, approve it so the app can watch screenshots saved there.
- macOS may also ask for Accessibility permission the first time you use the picker to paste back into another app. Without that, the app will still copy the selected item to the clipboard but cannot trigger the paste keystroke automatically.
- `Launch at Login` is implemented with a user LaunchAgent, so it does not require a helper app.
