# Dockerset

A macOS Dock manager: saved Dock layouts, a custom floating Dock with widgets, layout switching from a Focus, and backup/restore.

Project site: https://tk120404.github.io/dockerset/

## Download

Get the latest `Dockerset-<version>.zip` from [Releases](https://github.com/tk120404/dockerset/releases/latest). It runs on Apple silicon and Intel Macs with macOS 15 or later.

1. Unzip it and move **Dockerset.app** to **Applications**.
2. Open it. macOS will say it can't verify the app, because Dockerset isn't notarized by Apple. Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down to the message about Dockerset, and click **Open Anyway**.

You only do this once. Prefer the Terminal? This does the same:

```bash
xattr -dr com.apple.quarantine /Applications/Dockerset.app
```

## Build & run

Requires macOS 15+ and the Swift toolchain (Command Line Tools are enough, no Xcode needed).

```bash
scripts/build-app.sh          # builds build/Dockerset.app
scripts/build-app.sh --run    # builds, then (re)launches it
scripts/package-release.sh    # universal build zipped for a GitHub Release
```

Dockerset runs from the menu bar (dock icon). Settings opens automatically on first launch. After that, any of these opens it:

- right-click the Dockerset Dock's background → **Dockerset Settings…**
- open Dockerset again from Finder, Spotlight or Launchpad
- the menu bar item → **Settings…** (may be hidden behind the notch on a crowded menu bar)
- `open dockerset://settings`

## Features

| Area | What it does |
|---|---|
| **Layouts** | Multiple named layouts of apps, folders, links, spacers and widgets. Switch from the menu bar, Settings, or a URL. "Capture Current macOS Dock" turns your existing Dock into a layout. |
| **Which Dock** | *macOS Dock*, *Dockerset Dock*, or *Both*. Switching layouts rewrites the macOS Dock (`com.apple.dock`) unless you're in Dockerset-only mode. In Dockerset-only mode the macOS Dock is hidden while the app runs and comes back when you quit. |
| **Custom Dock** | Icon size, position (bottom/left/right), material (Liquid Glass, HUD, Popover, …), opacity, corner radius, hover magnification, auto-hide, running-app dots, folder stacks, right-click menus, drag-and-drop to add. |
| **Minimized windows** | Shows minimized windows in the Dock; click one to restore it. Needs Accessibility permission. |
| **macOS Dock appearance** | Set the macOS Dock's size and position from Settings → Appearance. |
| **Focus** | Make a Shortcuts Focus automation that opens `dockerset://layout/<name>` (Settings → Focus has copyable URLs). |
| **Widgets** | Now Playing (Spotify / Apple Music), Calendar & Reminders (next event, Join button for Zoom/Meet/Teams/…, complete reminders), Weather (current location or a chosen city, °C/°F, forecast width, background), Shortcuts, Battery (Mac + connected Bluetooth devices), Sticky Notes (from the Stickies app), Focus Timer (Pomodoro), Hydration (drink reminders). |
| **AI Limits** | Remaining/used allowance and reset times as Rings, Bars or Numbers. Claude via an opt-in Claude Code status-line bridge (Pro/Max), Codex from its session logs (ChatGPT login), Copilot via `gh` (uses GitHub's internal `copilot_internal/user` endpoint). |
| **AI Activity** | Token, session and tool-call history from local Claude Code and Codex logs: Today, L7, L30 or MTD, as a Sparkline, Bars or Totals. |
| **Backup** | Export/import a JSON backup (optionally including macOS Dock settings) to restore later or move to another Mac. The macOS Dock is also saved automatically before Dockerset first changes it, and can be restored from Settings → Backup. |

### URL scheme

```
dockerset://layout/<name>              switch to a layout (case-insensitive, percent-encode spaces)
dockerset://next                       cycle to the next layout
dockerset://mode/native|custom|both    choose which Dock is shown
dockerset://settings                   open Settings
```

## Permissions

macOS asks for these the first time each one is needed:

- **Calendars / Reminders**: Calendar widget
- **Automation (Spotify, Music)**: Now Playing widget
- **Accessibility**: minimized windows (System Settings → Privacy & Security → Accessibility)

The build is ad-hoc signed, so macOS treats every rebuild as a new app. You may have to toggle Accessibility off and on again after rebuilding.

## Data

`~/Library/Application Support/Dockerset/`
- `config.json`: layouts and settings
- `original-dock.plist`: your macOS Dock from before Dockerset first changed it

## Roadmap

- More AI providers (Cursor, Gemini CLI)
- Multi-display support (the custom Dock currently lives on the main display)

## License

MIT. See [LICENSE](LICENSE).
