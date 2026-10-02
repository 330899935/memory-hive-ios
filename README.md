# Memory Hive — iOS Client

**A local-first memory system for AI agents.** This repository contains the open-source iOS client of Memory Hive: the interface and utility layer you actually touch.

<p align="center">
  <a href="https://apps.apple.com/app/id6816318170"><b>⬇︎ Download on the App Store</b></a>
</p>

---

## What is Memory Hive?

AI assistants forget you the moment the context window closes. Memory Hive is a **personal, local-first memory store** that runs on your own machine — your memories stay with you, stored locally, rather than in someone else's cloud. Agents connect to it, read from it, and write back to it, so what you told one assistant is still there the next time you ask another.

The iOS app is the **pocket client**: it records a thought on the phone, keeps it locally, and syncs it home to your own Hive node when the two are on the same network.

## What is in this repository

✅ **Open source (this repo)** — the iOS **UI and utility layer**:

- Views, navigation and app shell
- Design system: theme, icons, motion, haptics
- Media utilities: camera picker, document picker, media capture
- On-device presentation logic and localization (Simplified Chinese / English)

## What is **not** in this repository

🔒 **Closed source** — the part that connects the app to a Hive node:

- Device **pairing** (QR handshake and one-time pairing codes)
- **Credential** storage and the on-device keychain wrapper
- The authenticated **handshake / authorization** between the app and your Hive node

These modules implement the controlled-access design at the heart of Memory Hive. They stay closed so the security boundary is not something anyone can fork and quietly weaken. Everything you need for the *experience* is here; everything that *authorizes* it is not.

> Note: because the client is split into modules, this open-source subset is intended to be read, studied and reused as UI code. It is **not** a standalone build of the shipping app — a full build also requires the closed modules above. See **Getting the app** below for the real thing.

## Getting the app

| Platform | Where |
|---|---|
| **iPhone / iPad** (free) | <https://apps.apple.com/app/id6816318170> |
| **Mac** (the Hive server) | <https://apps.apple.com/app/id6806992983> |

The Mac app is where a Hive actually lives. The iOS app is the way to reach it from your pocket.

## Repository layout

```
.
├── LICENSE
├── README.md
└── Sources/                      # the open-source UI / utility layer
    ├── 记忆蜂巢App.swift          # app entry point (@main)
    ├── ContentView.swift          # root shell & tab container
    ├── Theme.swift                # design system: colors, type, spacing
    ├── HiveTabIcons.swift         # tab-bar iconography
    ├── HiveHaptics.swift          # haptic feedback helpers
    ├── HomeMotion.swift           # home-screen motion / animation
    ├── CameraPicker.swift         # camera capture wrapper
    ├── DocumentPicker.swift       # document picker wrapper
    ├── MediaCapture.swift         # shared media-capture plumbing
    ├── InfoSheet.swift            # about / info sheet
    ├── ThoughtNameSheet.swift     # naming sheet for a thought
    ├── HiveManualSheet.swift      # in-app manual / help content
    ├── Localizable.xcstrings      # UI strings (Simplified Chinese / English)
    ├── InfoPlist.xcstrings        # Info.plist usage-string localization
    ├── Assets.xcassets/           # asset catalog (app icon, colors)
    └── Views/                     # the screens
        ├── HomeView.swift
        ├── HomeCandidateView.swift
        ├── AskView.swift
        ├── AskOfflineView.swift
        ├── DetailView.swift
        ├── SaveView.swift
        ├── ThoughtDetailSheet.swift
        ├── AntennaDetailView.swift
        ├── PlaceholderPage.swift
        └── 规划页.swift            # Planning screen
```

22 Swift files in total: 12 at the `Sources/` root (app shell + utility
layer) and 10 under `Sources/Views/` (the screens).

## Building

This subset is published as **readable reference code**, not as a buildable
project. The Xcode project file and the closed modules listed above are not
part of the repository, so `xcodebuild` will not produce a runnable app from
this tree alone.

To compile the shipping app, get it from the App Store (see **Getting the
app**). To study or reuse the UI layer on its own, copy the files you need
into your own SwiftUI project — the views and the design system under
`Sources/` are self-contained apart from the closed service layer they talk
to at runtime.

## License

Released under the **MIT License** — see [LICENSE](LICENSE).

## Contact

- Issues and questions: please open a GitHub issue.
- App Store: [Memory Hive Mobile](https://apps.apple.com/app/id6816318170)
