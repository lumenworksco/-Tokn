# Tokn

<img src="Tokn/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Tokn icon" />

Track your Claude.ai session and weekly usage from the macOS menu bar — built from scratch so you know exactly what it does with your session key.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)](https://github.com/lumenworksco/Tokn/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/lumenworksco/Tokn?color=blueviolet)](https://github.com/lumenworksco/Tokn/releases/latest)

---

## Download

<div align="center">

<a href="https://github.com/lumenworksco/Tokn/releases/latest">
  <img src="https://img.shields.io/badge/Download_for_macOS-%23000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" height="48"/>
</a>

<br/>
<sub>macOS 14.0 Sonoma or later &nbsp;·&nbsp; Apple Silicon &amp; Intel &nbsp;·&nbsp; Free &amp; open source</sub>

</div>

<br/>

1. Download the `.dmg` from the [latest release](https://github.com/lumenworksco/Tokn/releases/latest)
2. Open it and drag **Tokn** into the **Applications** folder
3. Launch it — a coloured dot and percentage appear in your menu bar

> **First launch:** macOS will say "unidentified developer" since Tokn isn't notarized yet. Right-click **Tokn.app** → **Open** → **Open** to bypass it once.

---

## What it shows

- **Session (5h)** — usage within the current 5-hour rolling window, with exact time until reset
- **Weekly (7d)** — usage across the current 7-day window
- Colour-coded status: green (safe) → orange (≥50%) → red (≥80%)
- Menu bar dot updates colour in real time so you can tell at a glance without opening the popover
- **Burn rate ETA** — when you're on track to hit the limit before the window resets, the card footer shows both the reset time and "~2h at this pace" simultaneously; disappears automatically when usage slows or the window resets first (appears after a few minutes of use)
- **Usage history chart** — tap the sparkline on any card to expand a full history chart with dashed warning/critical threshold lines and a time-span label
- **Smart notifications** — configurable first threshold (50–90%) plus a fixed 100% alert; resets automatically when usage drops so future spikes notify again
- **Game over** — when the weekly limit is used up, the menu bar shows "☠ GAME OVER" until it resets
- **Auto-updates** — checks for new versions on launch and installs them with one click (or automatically, if you turn that on in Settings). Updates are only installed after the DMG's SHA-256 matches the digest GitHub publishes for the release asset, the app's bundle ID and code signature check out, and the swap is atomic (your current app is untouched if anything fails)

---

## Setup

1. Open [claude.ai](https://claude.ai) in Chrome or Safari
2. Open DevTools (`⌘⌥I`)
3. Go to **Application → Cookies → `claude.ai`**
4. Copy the value of the `sessionKey` cookie — it starts with `sk-ant-`
5. Click the Tokn icon in your menu bar and paste it in

Your session key is stored **only in the macOS Keychain** — never written to disk or sent anywhere other than `claude.ai`.

---

## Usage

| Action | How |
|--------|-----|
| Open popover | Click the Tokn dot/percentage in your menu bar |
| Refresh now | Click the **↻** button in the top-right of the popover |
| Expand history chart | Tap the sparkline on any card |
| Change refresh interval | **Settings** → Refresh |
| Change notification threshold | **Settings** → Notifications → threshold picker |
| Check for updates | **Settings** → Updates → check for updates |
| Remove session key | **Settings** → Remove session key |
| Quit | **quit** in the popover footer |

---

## Building from source

Requires Xcode 16+ and macOS 14+.

```bash
git clone https://github.com/lumenworksco/Tokn.git
cd Tokn
open Tokn.xcodeproj
```

Hit **⌘R** in Xcode. No dependencies, no package manager.

Or from the command line:

```bash
xcodebuild -project Tokn.xcodeproj -scheme Tokn -configuration Release \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```


---

## How it gets your usage

Anthropic doesn't offer a public API for claude.ai subscription limits (the 5-hour session and weekly windows). Tokn reads the same internal endpoint the claude.ai web app uses, authenticated with your `sessionKey` cookie. That means:

- It can break without notice if Anthropic changes the endpoint or response format.
- It isn't an officially supported integration.
- Your key never leaves your Mac except in requests to `claude.ai`.

---

## Architecture

| Layer | Files |
|---|---|
| Entry point | `Tokn/ToknApp.swift` |
| App state | `Tokn/App/AppModel.swift` |
| Models | `Tokn/Models/` |
| Keychain + Settings | `Tokn/Repositories/` |
| Network + Usage + Updates | `Tokn/Services/` |
| UI | `Tokn/Views/` |

Two API endpoints are used — `GET /api/organizations` (resolves your org UUID on first run) and `GET /api/organizations/{id}/usage` (fetches the usage data). All source is plain Swift with zero third-party dependencies, so the full behaviour is auditable in a few hundred lines.

---

## Contributing

Pull requests are welcome. For major changes please open an issue first to discuss the approach.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## License

[MIT](LICENSE) © 2026 lumenworksco
