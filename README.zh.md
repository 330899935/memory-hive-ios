# 记忆蜂巢 · Memory Hive

**AI 助手在你关掉对话窗口的那一刻就把你忘了。** 记忆蜂巢是一个跑在你自己机器上的个人记忆库——所有 agent 都能读、都能写回来，所以你跟一个助手说过的事，换另一个助手问它还在。

<p align="center">
  <img src="docs/screenshots/01-tentacle.png" width="190" alt="记忆蜂巢——你的记忆，列在这里">
  <img src="docs/screenshots/02-save.png" width="190" alt="接住一个念头">
  <img src="docs/screenshots/03-ask.png" width="190" alt="掏出来问自己的蜂巢">
</p>
<p align="center"><sub>口袋客户端（iPhone）——随手接住一个念头，回到家里自动同步进你自己的蜂巢。<i>界面还原图，非设备实拍。</i></sub></p>

<p align="center">
  <a href="https://apps.apple.com/app/id6816318170"><b>⬇︎ iPhone / iPad 版（免费）</b></a>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="https://apps.apple.com/app/id6806992983"><b>⬇︎ Mac 版（蜂巢本体所在）</b></a>
</p>

<p align="center"><sub><a href="README.md">English →</a></sub></p>

---

## 从这里开始：把你已有的笔记搬进蜂巢（约 1 分钟）

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

## 各部件怎么拼在一起

| 部件 | 是什么 | 在哪 |
|---|---|---|
| **蜂巢本体** | 记忆真正存放的地方——你的记忆以文件形式存在你自己的磁盘上，本机提供服务 | **Mac 版** — <https://apps.apple.com/app/id6806992983> |
| **口袋端** | 手机上随手记一条，回到同一网络时同步回你的蜂巢 | **iOS 版**（免费）— <https://apps.apple.com/app/id6816318170> |
| **`tools/hive-import`** | 把已有的笔记搬进来 | 本仓库 |
| **`Sources/`** | iOS 版的界面与工具层代码 | 本仓库 |

方向上有件事值得说清楚：**蜂巢本体才是那个「东西」，手机是通向它的一扇门。** iOS 版把你记的内容存好、同步回家——如果没有属于你自己的蜂巢可同步，它只是一个做得不错的笔记本。

## 本仓库里有什么

**▶ 现在就能跑 —— [`tools/hive-import`](tools/hive-import)**
一个小型 Python 命令行工具：笔记 → 蜂巢投喂格式 → 可选直接发送。零依赖、无遥测，钥匙不落盘。

**📖 参考代码 —— [`Sources/`](Sources)**
iOS 版的界面与工具层：视图与导航、设计系统（主题、图标、动效、触感）、媒体选择器，以及简体中文 / 英文本地化。共 22 个 Swift 文件。

⚠️ **一句实话：** `Sources/` 是模块子集，发布出来是给人**读**的，不是用来构建的。Xcode 工程文件和下面列的闭源模块都不在本仓库里，所以 `xcodebuild` 从这棵树里跑不出可运行的 App。要真正用起来，请走上面的 App Store 链接。

## 本仓库里**没有**什么

🔒 闭源——连接 App 与蜂巢的那一层：

- 设备**配对**（二维码握手与一次性配对码）
- **凭证**存储与本机钥匙串封装
- App 与你的蜂巢之间的**认证握手 / 授权**

这些模块承载着记忆蜂巢最核心的受控接入设计。它们保持闭源，是为了让这道安全边界不会被人 fork 之后悄悄削弱。关于**体验**的东西都在这里；关于**授权**的东西不在这里。

## 许可

**MIT** —— 见 [LICENSE](LICENSE)。

## 联系

问题与 bug：[开一个 issue](https://github.com/330899935/memory-hive-ios/issues)。
