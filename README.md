<h1 align="center">
  <a href="https://github.com/Nytuo/Diapason_iOS">
    <img src="logo.png" alt="Diapason" width="auto" height="200">
  </a>
</h1>

<div align="center">
<h2>Diapason for Apple TV</h2>
The native Apple TV music player for Subsonic, Plex, and local libraries
<br />
<br />
<a href="https://github.com/Nytuo/Diapason_iOS/issues/new?assignees=&labels=bug&template=01_BUG_REPORT.md&title=bug%3A+">Report a Bug</a>
·
<a href="https://github.com/Nytuo/Diapason_iOS/issues/new?assignees=&labels=enhancement&template=02_FEATURE_REQUEST.md&title=feat%3A+">Request a Feature</a>
·
<a href="https://github.com/Nytuo/Diapason_iOS/discussions">Ask a Question</a>
</div>

<div align="center">
<br />

[![code with love by Nytuo](https://img.shields.io/badge/%3C%2F%3E%20with%20%E2%99%A5%20by-Nytuo-ff1414.svg?style=flat-square)](https://github.com/Nytuo)

</div>

<details open="open">
<summary>Table of Contents</summary>

- [About](#about)
- [Features](#features)
- [Technologies](#technologies)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Build \& run](#build--run)
  - [First launch](#first-launch)
- [Authors \& contributors](#authors--contributors)
- [License](#license)

</details>

---

## About

Diapason for Apple TV is a native SwiftUI music client for tvOS. It connects to your
Subsonic / Navidrome or Plex server and delivers a lean-back listening experience on
the big screen.

It is part of the [Diapason](https://github.com/Nytuo) ecosystem and speaks the
**Diapason Connect** protocol, so the Flutter app on your phone or desktop can drive it
— or hand it a queue — over the local network.

**The iPhone and iPad app has been removed.** Phones, tablets and desktops are served by
[diapason_flutter](https://github.com/Nytuo/diapason_flutter), which covers Jellyfin,
Plex, Subsonic/Navidrome and local files in one app. This repository now keeps only what
Flutter cannot target: Apple TV, and the watchOS app.

**The Apple Watch app is standalone.** It no longer installs as the companion of an
iPhone app — there isn't one — and it no longer uses WatchConnectivity, which can only
ever reach the iOS app that embeds it. It speaks Diapason Connect over the network
instead, like every other Diapason device.

It does three things:

- **Offline** — tracks downloaded onto the watch. No phone, no signal, no server.
- **Library** — everything the phone told it about, streamed straight from your music
  server. Needs a network, but *not* the phone.
- **Remote** — drive the phone app, when the phone is around.

The phone is needed only to *sync the catalogue*. Stream URLs point at your music
server, not at the phone, so once synced the watch works on its own.

Diapason for Apple TV is a fork of [Cassette](https://github.com/mathieudubart/Cassette),
a Subsonic/OpenSubsonic music client, originally licensed under the **Mozilla Public
License 2.0**. All original Cassette source files retain their MPL 2.0 header. New and
modified files added as part of this fork are licensed under the **GNU General Public
License v3.0** — see [License](#license) below.

## Features

**Playback**
- Lock-screen controls
- Playback cache manager for smooth streaming

**Library**
- Subsonic / Navidrome server support
- Plex Media Server support
- Local file library via folder picker
- Album, Artist, Song, Playlist views
- Full-text search

**Now Playing**
- Synced lyrics viewer with tap-to-seek
- System volume slider
- Queue management

**Diapason Connect**
- Bonjour / mDNS auto-discovery of Diapason desktop instances on the LAN
- Control the desktop app from your phone
- Use the iOS app as a playback receiver

**Discovery & Scrobbling**
- Last.fm scrobbling + Now Playing
- ListenBrainz scrobbling
- Music discovery via Last.fm / ListenBrainz playlist generation
- YouTube / yt-dlp track resolution for discovered songs
- Offline downloads

**Other**
- Playlist management (create, edit, reorder)
- i18n: English + French
- iOS 16+ target
- iPodOS like experience (beta)

## Technologies

<div style="display: flex; align-items: center; gap: 10px;">
  <img src="https://img.shields.io/badge/Swift-black?style=for-the-badge&logo=swift"/>
  <img src="https://img.shields.io/badge/SwiftUI-black?style=for-the-badge&logo=swift"/>
  <img src="https://img.shields.io/badge/AVFoundation-black?style=for-the-badge&logo=apple"/>
  <img src="https://img.shields.io/badge/iOS_16+-black?style=for-the-badge&logo=apple"/>
  <img src="https://img.shields.io/badge/XcodeGen-black?style=for-the-badge&logo=xcode"/>
</div>

## Getting Started

### Prerequisites

- macOS with **Xcode 15+** installed
- **XcodeGen** (`brew install xcodegen`)
- An iOS 16+ device or simulator

### Build & run

```bash
# 1. Clone the repo
git clone https://github.com/Nytuo/Diapason_iOS.git
cd Diapason_iOS

# 2. Generate the Xcode project
cd src
xcodegen generate

# 3. Open in Xcode and run
open Diapason.xcodeproj
# Select your device or simulator and press Run (⌘R)
```

### First launch

Open the **Settings** tab and enter your server details:
- **Subsonic / Navidrome** — server URL, username, password
- **Plex** — server URL + token
- **Local files** — tap the folder picker to grant access to your music folder

## Authors & contributors

Created by [Arnaud BEUX](https://github.com/Nytuo).

For a full list of contributors, see the [contributors page](https://github.com/Nytuo/Diapason_iOS/contributors).

## License

Diapason for iOS is a modification of [Cassette](https://github.com/mathieudubart/Cassette), which is licensed under the **Mozilla Public License 2.0** (see [LICENSE-Cassette](src/Sources/LICENSE-Cassette)). Source files carried over from Cassette remain under MPL 2.0 and keep their original header.

All changes, additions, and new files introduced in this fork — including the new backends, Diapason Connect, and the iPod mode — are licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.
