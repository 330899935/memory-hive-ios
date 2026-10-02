# Memory Hive

**Your AI assistants forget you the moment the context window closes.** Memory Hive is a personal memory store that runs on your own machine — one place every agent can read from and write back to, so what you told one assistant is still there when you ask the next one.

<p align="center">
  <a href="https://apps.apple.com/app/id6816318170"><b>⬇︎ Memory Hive for iPhone / iPad — free</b></a>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="https://apps.apple.com/app/id6806992983"><b>⬇︎ Memory Hive for Mac — where a Hive lives</b></a>
</p>

<p align="center"><sub><a href="README.zh.md">中文说明 →</a></sub></p>

---

## Start here: bring your existing notes into a Hive (~1 minute)

[`tools/hive-import`](tools/hive-import) is a zero-dependency CLI in this repository. It takes a folder of notes you already have — Markdown, plain text, JSON — and converts them into what your own Hive accepts.

```bash
git clone https://github.com/330899935/memory-hive-ios
cd memory-hive-ios

# 1. See what would be imported, without writing anything
python3 tools/hive-import/hive-import.py convert ~/my-notes --dry-run

# 2. Produce the import file
python3 tools/hive-import/hive-import.py convert ~/my-notes -o hive_import.json

# 3. Feed it into your own Hive (key comes from your own machine)
export HIVE_MASTER_KEY=<your key>
python3 tools/hive-import/hive-import.py send hive_import.json
```

Python 3.8+, standard library only. Nothing is uploaded anywhere: the single network call is the final POST to the Hive address **you** pass in.

→ Full usage and conversion rules: [`tools/hive-import/README.md`](tools/hive-import/README.md)

## How the pieces fit together

| Piece | What it is | Where |
|---|---|---|
| **A Hive** | the memory store itself — your memories as files on your own disk, served locally | **Mac app** — <https://apps.apple.com/app/id6806992983> |
| **Pocket client** | record a thought on your phone; it syncs home to your Hive when both are on the same network | **iOS app** (free) — <https://apps.apple.com/app/id6816318170> |
| **`tools/hive-import`** | brings the notes you already have into a Hive | this repo |
| **`Sources/`** | the iOS app's UI and utility layer | this repo |

Worth being clear about the direction of dependency: **a Hive is the thing; the phone is a door into it.** The iOS app keeps what you record and syncs it home — with no Hive of your own to sync to, it's a well-made notebook.

## What is in this repository

**▶ Runnable today — [`tools/hive-import`](tools/hive-import)**
A small Python CLI: notes → Hive ingest format → optionally send. No dependencies, no telemetry, your key is never written to disk.

**📖 Reference code — [`Sources/`](Sources)**
The iOS app's UI and utility layer: views and navigation, the design system (theme, icons, motion, haptics), media pickers, and Simplified Chinese / English localization. 22 Swift files.

⚠️ **Honest note:** `Sources/` is a subset of modules, published to be *read*, not to be built. The Xcode project and the closed modules listed below are not part of this repository, so `xcodebuild` will not produce a runnable app from this tree alone. To run the real thing, use the App Store links above.

## What is **not** in this repository

🔒 Closed source — the part that connects an app to a Hive:

- Device **pairing** (QR handshake and one-time pairing codes)
- **Credential** storage and the on-device keychain wrapper
- The authenticated **handshake / authorization** between the app and your Hive

These modules implement the controlled-access design at the heart of Memory Hive. They stay closed so that the security boundary is not something anyone can fork and quietly weaken. Everything you need for the *experience* is here; everything that *authorizes* it is not.

## License

Released under the **MIT License** — see [LICENSE](LICENSE).

## Contact

Questions and bug reports: please [open an issue](https://github.com/330899935/memory-hive-ios/issues).
