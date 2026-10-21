# Memory Hive

**Your AIs all remember you — but each one only remembers a part, and none of it lives in your hands.**
Memory Hive is the memory your agents share: one local store, reached over the Model Context Protocol, running on your own machine.

[![PyPI](https://img.shields.io/pypi/v/memory-hive-mcp.svg)](https://pypi.org/project/memory-hive-mcp/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-compatible-8A2BE2.svg)](https://modelcontextprotocol.io)

<p align="center">
  <a href="https://apps.apple.com/app/id6806992983"><b>⬇︎ Memory Hive for Mac — where a Hive lives</b></a>
  &nbsp;·&nbsp;
  <a href="https://apps.apple.com/app/id6816318170"><b>⬇︎ Pocket client for iPhone / iPad — free</b></a>
</p>
<p align="center"><sub><a href="README.zh.md">中文说明 →</a> &nbsp;·&nbsp; <a href="https://hello-fengchao.com/mcp.html">MCP docs</a></sub></p>

---

## MCP server — start here if you use Claude Desktop, Cursor, or any MCP client

```bash
pip install memory-hive-mcp
```

Add the bridge to your host's MCP config. Claude Desktop example
(`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "hive-memory": {
      "command": "memory-hive-mcp",
      "env": {
        "HIVE_AGENT_ID": "your-agent-id",
        "HIVE_AGENT_TOKEN": "your-access-token"
      }
    }
  }
}
```

Python 3.8+, standard library only. This package is a **thin bridge** — it embeds no
memory engine and opens no data files. It relays MCP traffic to the Hive app on your
machine (`127.0.0.1:8768` by default; override with `HIVE_MCP_URL`).

> **A Hive of your own is required.** The bridge needs something to talk to:
> <https://apps.apple.com/app/id6806992983>. Register an agent inside it
> (`POST /api/agent/register`) to obtain an `agent_id` and `access_token`.

| Variable | Required | |
|---|---|---|
| `HIVE_AGENT_ID` | yes | Agent id issued by your own Hive |
| `HIVE_AGENT_TOKEN` | yes | Access token issued at registration — keep it secret |
| `HIVE_MCP_URL` | no | Hive MCP endpoint. Defaults to `http://127.0.0.1:8768/mcp` |

### The four tools

| Tool | Direction | What it does |
|---|---|---|
| `recall` | read | Semantic search over your memory. `{"query": "that project we discussed", "limit": 10, "compact": true}` — optional `vaults` narrows the search |
| `propose` | write → **pending** | Submits a memory for your approval. `{"content": "...", "title": "...", "vault": "...", "tags": [...]}` — returns a `conflict_warning` when a near-duplicate already exists |
| `manage` | admin | Routed by `action`: `list_pending` / `forget` (soft delete) / `restore` / `get_by_id` |
| `get_context` | session start | Pulls recent memory from your active threads and open tasks to seed a conversation. `{"limit": 8}` |

A typical session: `get_context` on open → `recall` mid-conversation → when you say
"keep this", it `propose`s → you confirm in your Hive on the Mac.

### Your agent can propose. It cannot decide.

This is the part that makes Memory Hive different from a memory cache.

**An agent can `propose` a memory. It cannot confirm one.** What it writes lands in a
pending queue and stays there until *you* accept it in your own Hive. There is no
`self-confirm`, no silent background write, no path by which a model quietly decides
what is true about you.

Memory is partitioned into vaults, and the boundary is enforced by the Hive rather than
promised by a prompt:

| Agent type | Public vaults | Private vaults |
|---|---|---|
| Cloud agent (`mcp` / `mobile`) | ✅ open | 🔒 sealed |
| Local agent (non-cloud) | ✅ open | ✅ open |

Agents missing from the registration table are sealed by default. Every one of these
limits is checked on the Hive side — the side you control.

## Why not just let the platform remember?

Because your AI's memory today is:

1. **An island.** What you told Claude, Cursor doesn't know. What you worked out with
   one agent, the next one makes you re-explain from scratch.
2. **Not yours.** It sits on a vendor's server, in a format you can't export, migrate,
   or verify.
3. **Governed by someone else.** What gets kept, what gets forgotten, who may read it —
   those are product decisions, not yours.

If you use one AI, its built-in memory is probably enough — you don't need this. If you
use three or more, you already know the cost of re-introducing yourself. Memory Hive is
for you.

## Other ways in

### Bring your existing notes into a Hive (~1 minute)

[`tools/hive-import`](tools/hive-import) is a zero-dependency CLI in this repository. It
takes a folder of notes you already have — Markdown, plain text, JSON — and converts them
into what your own Hive accepts.

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

Python 3.8+, standard library only. Nothing is uploaded anywhere: the single network
call is the final POST to the Hive address **you** pass in.

→ Full usage and conversion rules: [`tools/hive-import/README.md`](tools/hive-import/README.md)

### The pocket client

Record a thought on your phone; it syncs home to your Hive when both are on the same
network. **The Mac app is the thing; the phone is a door into it.** With no Hive of your
own to sync to, the iOS app is a well-made notebook.

<p align="center">
  <img src="docs/screenshots/01-tentacle.png" width="190" alt="Memory Hive — your memories, listed">
  <img src="docs/screenshots/02-save.png" width="190" alt="Catch a thought">
  <img src="docs/screenshots/03-ask.png" width="190" alt="Ask your own Hive">
</p>
<p align="center"><sub>iOS client — UI renders, not device captures.</sub></p>

## How the pieces fit together

| Piece | What it is | Where |
|---|---|---|
| **A Hive** | the memory store itself — your memories as files on your own disk, served locally | **Mac app** — <https://apps.apple.com/app/id6806992983> |
| **`memory-hive-mcp`** | the MCP server that lets any agent read and write through it | **PyPI** — <https://pypi.org/project/memory-hive-mcp/> |
| **`tools/hive-import`** | brings the notes you already have into a Hive | this repo |
| **Pocket client** | record a thought on your phone, sync it home | **iOS app** (free) — <https://apps.apple.com/app/id6816318170> |
| **`Sources/`** | the iOS app's UI and utility layer | this repo |

## What is in this repository

**▶ Runnable today — [`tools/hive-import`](tools/hive-import)**
A small Python CLI: notes → Hive ingest format → optionally send. No dependencies, no
telemetry, your key is never written to disk.

**🔌 The MCP server — [`memory-hive-mcp`](https://pypi.org/project/memory-hive-mcp/)**
Published on PyPI and documented above. The source of the bridge is part of the closed
MCP interface layer; the package itself is installed with `pip`.

**📖 Reference code — [`Sources/`](Sources)**
The iOS app's UI and utility layer: views and navigation, the design system (theme,
icons, motion, haptics), media pickers, and Simplified Chinese / English localization.
22 Swift files.

⚠️ **Honest note:** `Sources/` is a subset of modules, published to be *read*, not to be
built. The Xcode project and the closed modules listed below are not part of this
repository, so `xcodebuild` will not produce a runnable app from this tree alone. To run
the real thing, use the App Store links above.

## What is **not** in this repository

🔒 Closed source — the part that connects an agent to a Hive:

- Device **pairing** (QR handshake and one-time pairing codes)
- **Credential** storage and the on-device keychain wrapper
- The authenticated **handshake / authorization** between an agent and your Hive
- The **memory engine** itself — the store, the retrieval, the vault boundary

These modules implement the controlled-access design at the heart of Memory Hive. They
stay closed so that the security boundary is not something anyone can fork and quietly
weaken. Everything you need for the *experience* is here; everything that *authorizes*
it is not.

## License

Released under the **MIT License** — see [LICENSE](LICENSE).

## Contact

Questions and bug reports: please [open an issue](https://github.com/330899935/memory-hive-ios/issues).
