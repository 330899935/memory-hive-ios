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

<!-- filled once the source package lands -->

```
.
├── LICENSE
├── README.md
└── ...
```

## Building

<!-- filled once the source package lands -->

## License

Released under the **MIT License** — see [LICENSE](LICENSE).

## Contact

- Issues and questions: please open a GitHub issue.
- App Store: [Memory Hive Mobile](https://apps.apple.com/app/id6816318170)
