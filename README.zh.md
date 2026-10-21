# 记忆蜂巢 · Memory Hive

**你的 AI 都记得你——但每一个都只记得一部分，而且没有一份在你手里。**
记忆蜂巢是它们共用的那一份记忆：一个跑在你自己机器上的本地记忆库，通过 Model Context Protocol 接入。

[![PyPI](https://img.shields.io/pypi/v/memory-hive-mcp.svg)](https://pypi.org/project/memory-hive-mcp/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-compatible-8A2BE2.svg)](https://modelcontextprotocol.io)

<p align="center">
  <a href="https://apps.apple.com/app/id6806992983"><b>⬇︎ Mac 版（蜂巢本体所在）</b></a>
  &nbsp;·&nbsp;
  <a href="https://apps.apple.com/app/id6816318170"><b>⬇︎ 口袋客户端 iPhone / iPad（免费）</b></a>
</p>
<p align="center"><sub><a href="README.md">English →</a> &nbsp;·&nbsp; <a href="https://hello-fengchao.com/mcp.html">MCP 接入文档</a></sub></p>

---

## MCP 服务 —— 用 Claude Desktop、Cursor 或任何 MCP 客户端的人从这里开始

```bash
pip install memory-hive-mcp
```

把桥接器加进你的 MCP 客户端配置。Claude Desktop 示例
（`~/Library/Application Support/Claude/claude_desktop_config.json`）：

```json
{
  "mcpServers": {
    "hive-memory": {
      "command": "memory-hive-mcp",
      "env": {
        "HIVE_AGENT_ID": "你的-agent-id",
        "HIVE_AGENT_TOKEN": "你的-access-token"
      }
    }
  }
}
```

Python 3.8+，纯标准库。这个包是一个**薄桥**——它不含记忆引擎，不打开任何数据文件，只把 MCP 协议流量转发给你机器上的蜂巢 App（默认 `127.0.0.1:8768`，可用 `HIVE_MCP_URL` 覆盖）。

> **需要先有一个属于你自己的蜂巢。** 桥要有东西可连：
> <https://apps.apple.com/app/id6806992983>。在蜂巢里注册一个 agent
> （`POST /api/agent/register`），拿到 `agent_id` 和 `access_token`。

| 环境变量 | 必填 | 说明 |
|---|---|---|
| `HIVE_AGENT_ID` | 是 | 由你自己的蜂巢签发的 agent id |
| `HIVE_AGENT_TOKEN` | 是 | 注册时签发的访问令牌，请保密 |
| `HIVE_MCP_URL` | 否 | 蜂巢 MCP 地址，默认 `http://127.0.0.1:8768/mcp` |

### 四个工具

| 工具 | 方向 | 做什么 |
|---|---|---|
| `recall` | 读 | 在你的记忆里做语义检索。`{"query": "上次说的那个项目", "limit": 10, "compact": true}`，可选 `vaults` 限定仓库 |
| `propose` | 写 → **进候选区** | 提交一条记忆等待你批准。`{"content": "...", "title": "...", "vault": "...", "tags": [...]}`，重复时返回 `conflict_warning` |
| `manage` | 管理 | 按 `action` 路由：`list_pending` / `forget`（软删除）/ `restore` / `get_by_id` |
| `get_context` | 开场 | 拉取「当前主线 + 待办执行」两仓的最近记忆，作为会话上下文底座。`{"limit": 8}` |

一次典型会话：开场 `get_context` 了解你最近在忙什么 → 对话中 `recall` 调出旧事 → 你说「这个存一下」，它 `propose` → 你在 Mac 上的蜂巢里确认归巢。

### 触角只能 propose，不能 self-confirm

这是记忆蜂巢和「记忆缓存」的分界线。

**Agent 可以 `propose` 一条记忆，但它无法确认一条记忆。** 它写的东西落进候选区，一直待到你**在蜂巢里亲手接受**。没有 `self-confirm`，没有静默的后台写入，没有任何一条路径能让模型自己决定「关于你的什么才是真的」。

记忆按仓库分区，边界由蜂巢执行，而不是靠 prompt 的自觉：

| 触角类型 | 公开四仓 | 隐私四仓 |
|---|---|---|
| 云端触角（`mcp` / `mobile`） | ✅ 全开放 | 🔒 锁死 |
| 本地触角（非 cloud） | ✅ 全开放 | ✅ 放开 |

不在注册表里的「幽灵触角」默认锁死。上面每一条限制都在蜂巢那一侧检查——也就是你能控制的那一侧。

## 为什么不干脆让平台自己记？

因为你的 AI 记忆现在有三个处境：

1. **是孤岛。** 你跟 Claude 说过的话，Cursor 不知道；你跟一个 agent 磨出来的默契，换一个就要从头再讲一遍。
2. **不在你手里。** 它躺在供应商的服务器上，格式不开放，导不出、迁不走、也查不清。
3. **边界由别人定。** 该记什么、该忘什么、谁能读——那是产品决策，不是你的决策。

如果你只用一个 AI，平台自带的记忆大概够用，你不需要这个。如果你同时用三个以上，你早就知道「每天重新介绍自己一遍」的成本。记忆蜂巢是给你这种人的。

## 其他入口

### 把你已有的笔记搬进蜂巢（约 1 分钟）

[`tools/hive-import`](tools/hive-import) 是本仓库里的一个零依赖命令行工具。它把你自己攒的 Markdown / 纯文本 / JSON 笔记，转成蜂巢能接收的格式。

```bash
git clone https://github.com/330899935/memory-hive-ios
cd memory-hive-ios

# 1. 先看会导入什么，不写任何文件
python3 tools/hive-import/hive-import.py convert ~/my-notes --dry-run

# 2. 生成导入文件
python3 tools/hive-import/hive-import.py convert ~/my-notes -o hive_import.json

# 3. 投喂到你自己的蜂巢（钥匙来自你自己的机器）
export HIVE_MASTER_KEY=<你的钥匙>
python3 tools/hive-import/hive-import.py send hive_import.json
```

只要 Python 3.8+，仅用标准库。**数据不上传到任何地方**——唯一一次联网，是最终 POST 到由你指定的那个蜂巢地址。

→ 完整用法与转换规则：[`tools/hive-import/README.md`](tools/hive-import/README.md)

### 口袋客户端

手机上随手记一条，回到同一网络时同步回你的蜂巢。**蜂巢本体才是那个「东西」，手机是通向它的一扇门。** 如果没有属于你自己的蜂巢可同步，iOS 版只是一个做得不错的笔记本。

<p align="center">
  <img src="docs/screenshots/01-tentacle.png" width="190" alt="记忆蜂巢——你的记忆，列在这里">
  <img src="docs/screenshots/02-save.png" width="190" alt="接住一个念头">
  <img src="docs/screenshots/03-ask.png" width="190" alt="掏出来问自己的蜂巢">
</p>
<p align="center"><sub>iOS 客户端 —— 界面还原图，非设备实拍。</sub></p>

## 各部件怎么拼在一起

| 部件 | 是什么 | 在哪 |
|---|---|---|
| **蜂巢本体** | 记忆真正存放的地方——你的记忆以文件形式存在你自己的磁盘上，本机提供服务 | **Mac 版** — <https://apps.apple.com/app/id6806992983> |
| **`memory-hive-mcp`** | 让任何 agent 读写这份记忆的 MCP 服务 | **PyPI** — <https://pypi.org/project/memory-hive-mcp/> |
| **`tools/hive-import`** | 把已有的笔记搬进来 | 本仓库 |
| **口袋端** | 手机上随手记一条，同步回家 | **iOS 版**（免费）— <https://apps.apple.com/app/id6816318170> |
| **`Sources/`** | iOS 版的界面与工具层代码 | 本仓库 |

## 本仓库里有什么

**▶ 现在就能跑 —— [`tools/hive-import`](tools/hive-import)**
一个小型 Python 命令行工具：笔记 → 蜂巢投喂格式 → 可选直接发送。零依赖、无遥测，钥匙不落盘。

**🔌 MCP 服务 —— [`memory-hive-mcp`](https://pypi.org/project/memory-hive-mcp/)**
已发布到 PyPI，用法见上。桥接器的源码属于闭源的 MCP 接口层，包本身用 `pip` 安装。

**📖 参考代码 —— [`Sources/`](Sources)**
iOS 版的界面与工具层：视图与导航、设计系统（主题、图标、动效、触感）、媒体选择器，以及简体中文 / 英文本地化。共 22 个 Swift 文件。

⚠️ **一句实话：** `Sources/` 是模块子集，发布出来是给人**读**的，不是用来构建的。Xcode 工程文件和下面列的闭源模块都不在本仓库里，所以 `xcodebuild` 从这棵树里跑不出可运行的 App。要真正用起来，请走上面的 App Store 链接。

## 本仓库里**没有**什么

🔒 闭源——把 agent 连到蜂巢的那一层：

- 设备**配对**（二维码握手与一次性配对码）
- **凭证**存储与本机钥匙串封装
- agent 与你的蜂巢之间的**认证握手 / 授权**
- **记忆引擎本体**——存储、检索、仓库边界

这些模块承载着记忆蜂巢最核心的受控接入设计。它们保持闭源，是为了让这道安全边界不会被人 fork 之后悄悄削弱。关于**体验**的东西都在这里；关于**授权**的东西不在这里。

## 许可

**MIT** —— 见 [LICENSE](LICENSE)。

## 联系

问题与 bug：[开一个 issue](https://github.com/330899935/memory-hive-ios/issues)。
