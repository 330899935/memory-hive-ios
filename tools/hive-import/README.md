# hive-import

A tiny, dependency-free Python CLI that converts your existing notes (Markdown / plain text / JSON) into the format Memory Hive's `/api/ingest` accepts — and optionally feeds them straight into your own Hive.

## Why this exists

You have years of notes scattered across Markdown files, `.txt` files, and JSON exports. Moving them into Memory Hive by hand is painful. `hive-import` turns that migration into one command.

## What it does **not** do

- It does **not** embed any Hive address or key.
- It does **not** touch Hive's internal storage, index, or auth — it only formats data and forwards it over HTTP.
- Your key is passed in by you (`--key` or the `HIVE_MASTER_KEY` env var) and is never written to disk.

## Usage

```bash
# 1. Convert a folder of notes into Hive ingest JSON
python3 hive-import.py convert ./my-notes -o hive_import.json

# 2. Preview without writing a file
python3 hive-import.py convert ./my-notes --dry-run

# 3. Feed them into your Hive (key passed on the command line or via env)
python3 hive-import.py send hive_import.json --url http://127.0.0.1:8768 --key YOUR_KEY

# Safer: keep the key out of your shell history
export HIVE_MASTER_KEY=YOUR_KEY
python3 hive-import.py send hive_import.json
```

## Conversion rules

| Source | title | content |
|---|---|---|
| `.md` / `.markdown` | first `#` heading (falls back to filename) | everything else |
| `.txt` | first non-empty line | the rest |
| `.json` | `title` / `name` / `summary` field | `content` / `text` / `body` field |

> Hive's quality gate requires **title ≥ 5 chars AND content ≥ 20 chars**. The tool warns you when an entry is likely to be rejected — fix those notes before sending.

## Safety

- Zero third-party dependencies (Python 3.8+ stdlib only).
- No telemetry, no network calls except the `send` command to **your own** Hive URL.
- Your key appears only in the request body, in memory, never on disk.

## License

MIT
