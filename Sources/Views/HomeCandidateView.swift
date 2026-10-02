import SwiftUI

/// 家页 —— 收件箱（触角投的念头，等你点头才回家）
/// 视觉语言：候选区 + 状态色圆环（待确认琥珀 / 敏感红）
///
/// 2026-09-18（家页指令书）：
///   - 接入 tab 导航（此前 `ContentView` 的 tab 里没有「家」，整页生产代码引用为 0）
///   - 接真数据：去掉写死的 `CandidateItem.samples`，改走 `GET /api/pending`
///   - 每行两个动作：归档（`POST /api/approve`，后端要求 PIN）/ 拒绝（`POST /api/pending_delete`，无 PIN 门）
///   - 加载中 / 空态 / 连不上 / 熔断 / 未配置 —— 五态都有明确人话，不留白屏
///
/// 2026-09-18（家页**体验**指令书）：
///   - P0-1 归档选仓：点「归档」弹层列公开仓，默认高亮后端建议仓（敏感候选跳过，后端强制改道隐私仓）
///   - P0-2 回收站：右上角入口 + 列表 + 恢复（下标要同步前移，见 `HiveTrashSheet.restore`）
///   - P1-1 角标：条数变化广播 `.hiveInboxChanged`，根视图据此刷「家」tab 角标
///   - P1-2 滑动手势：**不做**，理由见回报（与根视图横向切 tab 手势真冲突）
struct 家页: View {
    @EnvironmentObject private var config: HiveConfig

    @State private var filter = "全部"
    @State private var items: [CandidateItem] = []
    @State private var state: LoadState = .idle
    /// 家里是否设了隐私 PIN：true 时手机端的「归档」需输密码（遥控器语义）；
    /// nil = 还没问出来（离线/接口失败）→ 不据此限制任何操作
    @State private var hasPrivacyPin: Bool?
    /// 归档用的隐私 PIN（临时缓存内存，5 分钟有效，与后端 require_pin 注释一致）
    @State private var cachedPin: String?
    @State private var cachedPinExpire: Date?
    /// 正在等用户输 PIN 的条目（非 nil → 弹「输入电脑端密码」层）
    @State private var pinPromptItem: CandidateItem?
    /// 正在处理中的条目 id（按钮转圈）
    @State private var busyID: String?
    /// 操作结果一行提示（成功/失败都在这说人话）
    @State private var resultText = ""
    /// 正在等用户选仓的条目（非 nil → 弹「存到哪个仓」层）
    @State private var picking: CandidateItem?
    /// 回收站层开关
    @State private var showTrash = false
    /// 14 条修复第 4 条：收件箱条目可点开看详情（标题/全文/图片/录音）
    @State private var detailItem: CandidateItem?

    enum LoadState: Equatable {
        case idle, loading, ready, empty
        case notReady, offline, locked
        case failed(String)
    }

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    filterBar
                    if hasPrivacyPin == true { pinBanner }
                    content
                    if state == .ready && !items.isEmpty { actionHint }
                    if !resultText.isEmpty { resultLine }
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            .refreshable { await load() }
            StitchAccent().allowsHitTesting(false)
        }
        .task { await load() }
        // 归档 → 选仓层（P0-1）；敏感候选后端强制改道隐私仓，不走这里，见 `rowActions`
        .sheet(item: $picking) { c in
            HiveArchivePickerSheet(item: c) { wh in
                Task { await doApprove(c, suggest: wh) }
            }
        }
        // 归档前输电脑端密码（遥控器语义）：家里设了 PIN 且缓存过期时弹，输对再继续
        .sheet(item: $pinPromptItem) { c in
            PinPromptSheet { pin in
                cachedPin = pin
                cachedPinExpire = Date().addingTimeInterval(5 * 60)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    proceedArchive(c)
                }
            }
        }
        // 回收站（P0-2）
        .sheet(isPresented: $showTrash) {
            HiveTrashSheet(config: config) {
                // 恢复 → 条目回候选区，回来把收件箱刷新一遍（角标也随广播更新）
                Task { await load() }
            }
        }
        // 14 条修复第 4 条：点开候选看详情（含图片/录音媒体渲染）
        .sheet(item: $detailItem) { c in
            CandidateDetailSheet(item: c)
                .environmentObject(config)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MEMORY HIVE · 家")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(HiveTheme.amber)
                Text("收件箱")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(HiveTheme.textTitle)
                Text("触角投的念头，等你点头才回家")
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.textCaption)
            }
            Spacer(minLength: 0)
            trashEntry
        }
    }

    /// 回收站入口（拒绝走的软删都在这里，能捞回来）
    private var trashEntry: some View {
        Button {
            showTrash = true
            HiveHaptics.light()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                Text("回收站")
                    .font(.system(size: 10))
            }
            .foregroundStyle(HiveTheme.textCaption)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .overlay(
                Capsule().stroke(HiveTheme.textMuted.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回收站")
    }

    // MARK: - 筛选（计数来自真实列表，不再是写死的 3 / 1）

    private var filterBar: some View {
        HStack(spacing: 10) {
            // ⚠️ **显式分「raw」与「display」两个值**（2026-09-18 第二阶段 · 截图抓到的真事故）：
            //    原先只有 `label` 一个值兼两用，显示那步走 `HiveCopy.dyn(label)` 查表 ——
            //    但「全部」在源码里只出现在**声明位/比较位**，编译器**抽不到这条 key**，
            //    表里没有 ⇒ 英文界面直出中文「全部」（中英混排，与另两个 chip 的英文并排）。
            //    ⇒ 改成把显示值写成 `String(localized:)` 字面量，**编译器就能抽取**，
            //    从根上消灭「漏一条 key 就冒中文」这一类静默故障（不再需要手工补表）。
            //    `raw` 侧仍是裸字面量：`filter == "全部"` 的比较依赖它，绝不能本地化。
            filterChip(raw: "全部", display: String(localized: "全部"),
                       count: items.count, selected: filter == "全部")
            filterChip(raw: "待确认", display: String(localized: "待确认"),
                       count: pendingCount, selected: filter == "待确认")
            filterChip(raw: "敏感", display: String(localized: "敏感"),
                       count: sensitiveCount, selected: filter == "敏感")
        }
    }

    private func filterChip(raw: String, display: String, count: Int, selected: Bool) -> some View {
        Button {
            filter = raw
        } label: {
            HStack(spacing: 4) {
                // `display` 已是本地化后的字符串；`raw` 只进状态，不显示
                Text(display)
                Text("\(count)")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? HiveTheme.textTitle : HiveTheme.textCaption)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(selected ? HiveTheme.holoTop : .clear)
            .overlay(
                Capsule().stroke(
                    selected ? HiveTheme.amber.opacity(0.4) : HiveTheme.textMuted.opacity(0.3),
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 家里设了隐私 PIN 时的告知：手机是遥控器，输电脑端密码即可远程归档
    private var pinBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.amber)
            Text(String(localized: "这是电脑收件箱同步的内容 · 归档时输电脑端密码即可远程完成；手机上也可以直接拒绝（移入回收站）"))
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HiveTheme.amber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 列表主体（五态）

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            loadingState
        case .notReady:
            messageState(symbol: "house", text: String(localized: "先去设置页填「家地址 + 密钥」，才能收到触角投来的念头"))
        case .offline:
            messageState(symbol: "wifi.slash", text: String(localized: "连不上家里电脑，收件箱暂时打不开"))
        case .locked:
            messageState(symbol: "lock.fill", text: String(localized: "蜂巢正在深度睡眠，锁了写；等它醒来再处理"))
        case .failed(let msg):
            messageState(symbol: "exclamationmark.triangle", text: msg)
        case .empty:
            messageState(symbol: "tray", text: String(localized: "收件箱是空的 —— 触角还没投新念头"))
        case .ready:
            if filtered.isEmpty {
                messageState(symbol: "line.3.horizontal.decrease.circle", text: String(localized: "这个筛选下没有条目"))
            } else {
                ForEach(filtered) { c in
                    candidateRow(c)
                }
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().tint(HiveTheme.amber)
            Text("正在取回收件箱…")
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func messageState(symbol: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(HiveTheme.amber.opacity(0.4))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 一行候选

    private func candidateRow(_ c: CandidateItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            statusRing(c)
            VStack(alignment: .leading, spacing: 5) {
                // 14 条修复第 4 条：标题/全文/媒体都可点开看详情
                Button {
                    detailItem = c
                    HiveHaptics.light()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(c.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(HiveTheme.textStrong)
                            .fixedSize(horizontal: false, vertical: true)
                        if !c.content.isEmpty {
                            Text(c.content)
                                .font(.system(size: 12))
                                .foregroundStyle(HiveTheme.textBody)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(c.suggestionLine)
                            .font(.system(size: 12))
                            .foregroundStyle(c.status == .sensitive ? HiveTheme.red : HiveTheme.textSecondary)
                        Text("\(c.source) · \(c.displayTime) · \(c.statusLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(HiveTheme.textMuted)
                        if c.isShort {
                            Text("· 内容偏短，归档前可先补两句")
                                .font(.system(size: 10))
                                .foregroundStyle(HiveTheme.textCaption)
                        }
                        HStack(spacing: 3) {
                            Text("查看详情")
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(HiveTheme.cyan)
                        .padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                rowActions(c)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .holoCard()
    }

    private func statusRing(_ c: CandidateItem) -> some View {
        ZStack {
            Circle()
                .stroke(c.statusColor, lineWidth: 1.6)
                .frame(width: 24, height: 24)
            if c.status == .sensitive {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HiveTheme.red)
            } else {
                Circle()
                    .fill(c.statusColor.opacity(0.6))
                    .frame(width: 8, height: 8)
            }
        }
    }

    /// 两个动作按钮。**不用滑动手势**，理由见回报：
    /// 根视图 `ContentView` 装了横向滑切 tab 的 `simultaneousGesture`，
    /// 卡片上的横滑会与它同时命中 → 会连带切 tab。
    /// 归档：家里设了 PIN 且密码缓存过期时，先弹「输电脑端密码」层，输对再继续（遥控器语义）。
    private func rowActions(_ c: CandidateItem) -> some View {
        HStack(spacing: 8) {
            if busyID == c.id {
                ProgressView()
                    .tint(HiveTheme.amber)
                    .scaleEffect(0.8)
                    .padding(.vertical, 5)
            } else {
                actionButton(title: String(localized: "归档"), symbol: "arrow.down.circle", tint: HiveTheme.green) {
                    if needsPin {
                        pinPromptItem = c
                    } else {
                        proceedArchive(c)
                    }
                }
                actionButton(title: String(localized: "拒绝"), symbol: "xmark.circle", tint: HiveTheme.red) {
                    Task { await doReject(c) }
                }
            }
        }
        .padding(.top, 6)
    }

    /// 是否需要先输电脑端密码才能归档：家里设了 PIN 且密码缓存未命中（没输过 / 已过 5 分钟）
    private var needsPin: Bool {
        guard hasPrivacyPin == true else { return false }
        guard let pin = cachedPin, !pin.isEmpty else { return true }
        if let exp = cachedPinExpire, exp > Date() { return false }
        return true
    }

    /// 密码已确认后继续归档：敏感候选后端强制改道隐私仓（不弹选仓），普通候选弹选仓层
    private func proceedArchive(_ c: CandidateItem) {
        if c.kind == .sensitive {
            // 敏感候选：后端 `nest_to_warehouse` 强制改道隐私仓
            // （storage.py:333 `gatekeeper_status=='sensitive'` 分支），
            // 前端传什么 suggest 都不算数 ⇒ 不弹选仓，别给用户一个假的选项
            Task { await doApprove(c, suggest: nil) }
        } else {
            picking = c
        }
    }

    private func actionButton(title: String, symbol: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var actionHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.amber.opacity(0.6))
            Text("归档 = 存进你选的正式仓；拒绝 = 移入回收站（可恢复）")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var resultLine: some View {
        Text(resultText)
            .font(.system(size: 12))
            .foregroundStyle(HiveTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }

    // MARK: - 计数 / 过滤

    private var filtered: [CandidateItem] {
        switch filter {
        case "待确认": return items.filter { $0.status == .pending }
        case "敏感": return items.filter { $0.status == .sensitive }
        default: return items
        }
    }

    private var pendingCount: Int { items.filter { $0.status == .pending }.count }
    private var sensitiveCount: Int { items.filter { $0.status == .sensitive }.count }

    // MARK: - 动作

    @MainActor
    private func load() async {
        resultText = ""
        guard config.isReady else {
            state = .notReady
            return
        }
        state = .loading

        // PIN 状态与列表并行取；PIN 这个问不到（nil）就维持原值，不影响列表
        async let pin = HivePendingService.privacyPinSet(config: config)
        let outcome = await HivePendingService.list(config: config)
        if let v = await pin { hasPrivacyPin = v }

        switch outcome {
        case .ok(let list):
            items = list
            state = list.isEmpty ? .empty : .ready
            // 只有拿到权威数据才广播条数 —— 离线/失败时不广播，
            // 免得把「连不上」刷成角标 0（0 会被读成「收件箱是空的」）
            broadcastCount()
        case .locked: state = .locked
        case .offline: state = .offline
        case .notReady: state = .notReady
        case .failed(let msg): state = .failed(msg)
        }
    }

    /// 收件箱条数变了 → 广播给根视图刷「家」tab 角标（ContentView 据此更新，不另开轮询）
    private func broadcastCount() {
        NotificationCenter.default.post(name: .hiveInboxChanged,
                                        object: nil,
                                        userInfo: ["count": items.count])
    }

    @MainActor
    private func doApprove(_ c: CandidateItem, suggest: String?) async {
        busyID = c.id
        resultText = ""
        let outcome = await HivePendingService.approve(kind: c.kind, id: c.rawID,
                                                       suggest: suggest, pin: cachedPin, config: config)
        busyID = nil
        switch outcome {
        case .ok(let msg):
            items.removeAll { $0.id == c.id }
            resultText = msg
            HiveHaptics.success()
            broadcastCount()
        case .needPin:
            // 密码不对 / 缓存失效：清掉缓存，重新弹输入
            cachedPin = nil
            cachedPinExpire = nil
            hasPrivacyPin = true
            resultText = String(localized: "密码不对，重新输入")
        case .locked:
            resultText = String(localized: "蜂巢正在深度睡眠，锁了写")
        case .offline:
            resultText = String(localized: "连不上家里电脑，稍后再试")
        case .notReady:
            resultText = String(localized: "先去设置页填「家地址 + 密钥」")
        case .failed(let msg):
            resultText = msg
        }
        if items.isEmpty { state = .empty }
    }

    @MainActor
    private func doReject(_ c: CandidateItem) async {
        busyID = c.id
        resultText = ""
        let outcome = await HivePendingService.reject(kind: c.kind, id: c.rawID, config: config)
        busyID = nil
        switch outcome {
        case .ok(let msg):
            items.removeAll { $0.id == c.id }
            resultText = msg
            HiveHaptics.light()
            broadcastCount()
        case .needPin:
            resultText = String(localized: "这台蜂巢设了隐私 PIN，这条也动不了，得到电脑端处理")
        case .locked:
            resultText = String(localized: "蜂巢正在深度睡眠，锁了写")
        case .offline:
            resultText = String(localized: "连不上家里电脑，稍后再试")
        case .notReady:
            resultText = String(localized: "先去设置页填「家地址 + 密钥」")
        case .failed(let msg):
            resultText = msg
        }
        if items.isEmpty { state = .empty }
    }
}

// MARK: - 候选状态

/// 收件箱里只有两种状态。
/// 「已归档 / 已拒绝」**不在这里** —— 已归档的已经进正式仓（不在收件箱），
/// 已拒绝的是软删进回收站（走 `/api/trash`），收件箱查不到。旧版那两种是假状态。
enum CandidateStatus {
    case pending     // 待确认（普通候选：observe / decision / time）
    case sensitive   // 敏感候选（pending_sensitive 桶）

    var color: Color {
        switch self {
        case .pending: return HiveTheme.amber
        case .sensitive: return HiveTheme.red
        }
    }

    var label: String {
        switch self {
        case .pending: return String(localized: "待确认")
        case .sensitive: return String(localized: "敏感")
        }
    }
}

/// 收件箱里的一条候选（家页一行）
/// 字段名全部来自 `GET /api/pending` 的**实测返回结构**（2026-09-18 对着 `~/蜂巢数据/scratchpad/*.json` 核过）
struct CandidateItem: Identifiable {
    /// ForEach 唯一键：后端 `id` 在同一次返回里唯一，但**跨桶不保证** → 用「桶#id」复合
    var id: String { "\(kind.rawValue)#\(rawID)" }

    let rawID: String            // ts_1789478653_nv50 —— approve / delete 回传用
    let kind: HivePendingService.Kind
    let title: String
    let summary: String
    let content: String
    let rawSuggest: String       // 后端建议仓，可能为空串
    let source: String           // openclaw / workbuddy / 蜂巢进食巡检 …
    let timestamp: String        // 本地时间 ISO8601（无时区，如 2026-09-15T21:24:13.4774）
    let isShort: Bool            // 后端 is_content_short() 的「内容偏短」标记（hive_core.py:134）
    let gatekeeper: String       // allow / sensitive / review
    let mediaPath: String        // 媒体相对路径（14 条修复第 4 条：收件箱点开看详情需用）
    let type: String             // 后端条目 type（image/audio/observe/…）

    var status: CandidateStatus { kind == .sensitive ? .sensitive : .pending }
    var statusColor: Color { status.color }
    var statusLabel: String { status.label }

    /// 「建议归档 · 当前主线」；后端没给建议仓时说人话，不编仓名
    var suggestionLine: String {
        // 敏感候选归档会被后端强制改道隐私仓（storage.py:333 `gatekeeper_status=='sensitive'` 分支）
        if kind == .sensitive { return String(localized: "敏感候选 · 归档会进隐私仓") }
        let wh = rawSuggest.isEmpty ? "" : HiveWarehouses.displayName(rawSuggest)
        return wh.isEmpty ? String(localized: "建议归档 · 落仓由蜂巢判断") : String(localized: "建议归档 · \(wh)")
    }

    /// 后端 `timestamp` 是本机本地时间（`datetime.now().isoformat()`，hive_core.py:543），
    /// 且小数秒位数不定（实测 `.4774` 四位）→ 解析与展示统一走 `HiveTimeText`（与回收站共用一份）
    var parsedDate: Date? { HiveTimeText.parse(timestamp) }

    /// 今天 HH:mm / 昨天 HH:mm / MM-dd HH:mm；解析不出来就原样显示时间戳（不假装）
    var displayTime: String { HiveTimeText.display(timestamp) }

    /// 从后端一条原始字典映射；**没有 id 的直接丢**（没 id 就没法归档/拒绝，收进来只会是个死条目）
    init?(kind: HivePendingService.Kind, raw: [String: Any]) {
        guard let rawID = raw["id"] as? String, !rawID.isEmpty else { return nil }
        self.rawID = rawID
        self.kind = kind

        let t = (raw["title"] as? String) ?? ""
        let s = (raw["summary"] as? String) ?? ""
        let c = (raw["content"] as? String) ?? ""
        // 标题兜底链：title → summary → content 前 24 字（实测 9 条都有 title，兜底只为不出现空行）
        self.title = t.isEmpty ? (s.isEmpty ? String(c.prefix(24)) : s) : t
        self.summary = s
        self.content = c
        self.rawSuggest = (raw["suggest"] as? String) ?? ""
        self.source = (raw["source"] as? String) ?? ""
        self.timestamp = (raw["timestamp"] as? String) ?? ""
        self.isShort = (raw["short"] as? Bool) ?? false
        self.gatekeeper = (raw["gatekeeper_status"] as? String) ?? ""
        self.mediaPath = (raw["media_path"] as? String) ?? ""
        self.type = (raw["type"] as? String) ?? ""
    }
}

// MARK: - 归档选仓层（P0-1）

/// 点「归档」后弹的选仓层。
/// - 列**全部 8 仓**：公开 4 仓（当前主线/待办执行/参考资料/归档历史）+ 隐私 4 仓（关系/个人/财务/私事）
/// - 隐私仓会加密存、查看需输密码，视觉上分组标注
/// - 默认高亮**后端建议仓**（候选的 `suggest` 字段）；不在 8 仓清单里就落到第一个仓
/// - 选完传的是**仓名原文**（如 `归档历史`）—— 显示名只用于界面，进请求体后端就找不到仓了
private struct HiveArchivePickerSheet: View {
    let item: CandidateItem
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: String

    init(item: CandidateItem, onPick: @escaping (String) -> Void) {
        self.item = item
        self.onPick = onPick
        let s = item.rawSuggest
        let preset = HiveWarehouses.all.contains(s)
            ? s
            : HiveWarehouses.publicWarehouses[0]
        _selected = State(initialValue: preset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("存到哪个仓")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(HiveTheme.textTitle)
                Text("这条念头归档后放进哪个正式仓。默认是蜂巢建议的那个，你也能改。")
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(HiveTheme.amber)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(HiveTheme.textStrong)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .holoCard()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("公开仓")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HiveTheme.textMuted)
                    ForEach(HiveWarehouses.publicWarehouses, id: \.self) { raw in
                        warehouseRow(raw)
                    }
                    Text("隐私仓 · 加密存，查看需密码")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HiveTheme.purple)
                        .padding(.top, 8)
                    ForEach(HiveWarehouses.privacyWarehouses, id: \.self) { raw in
                        warehouseRow(raw)
                    }
                }
            }

            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .font(.system(size: 14))
                        .foregroundStyle(HiveTheme.textMuted)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    let wh = selected
                    dismiss()
                    onPick(wh)
                } label: {
                    Text("存进「\(HiveWarehouses.displayName(selected))」")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HiveTheme.bgVoid)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(HiveTheme.amber)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HiveTheme.bgVoid)
        .presentationDetents([.large])
    }

    private func warehouseRow(_ raw: String) -> some View {
        let on = selected == raw
        let isSuggested = item.rawSuggest == raw
        return Button {
            selected = raw
            HiveHaptics.light()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(on ? HiveTheme.amber : HiveTheme.textMuted)
                Text(HiveWarehouses.displayName(raw))
                    .font(.system(size: 14, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? HiveTheme.textTitle : HiveTheme.textStrong)
                if isSuggested {
                    Text("建议")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HiveTheme.bgVoid)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(HiveTheme.amberDeep)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? HiveTheme.holoTop : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(on ? HiveTheme.amber.opacity(0.5) : HiveTheme.textMuted.opacity(0.25),
                            lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 回收站层（P0-2）

/// 回收站：拒绝走的软删都在这儿，能捞回来。
/// 空态 / 加载态 / 连不上 / 熔断 / 未配置 —— 都有明确人话，不留白屏。
private struct HiveTrashSheet: View {
    let config: HiveConfig
    /// 恢复成功后回调（家页据此刷新收件箱）
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [TrashItem] = []
    @State private var state: LoadState = .idle
    @State private var busyIdx: Int?
    @State private var resultText = ""

    enum LoadState: Equatable {
        case idle, loading, ready, empty
        case notReady, offline, locked
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("回收站")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(HiveTheme.textTitle)
                    Text("你拒绝过的念头都在这 · 恢复后回到收件箱")
                        .font(.system(size: 12))
                        .foregroundStyle(HiveTheme.textCaption)
                }
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Text("关闭")
                        .font(.system(size: 13))
                        .foregroundStyle(HiveTheme.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(HiveTheme.textMuted.opacity(0.35), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !resultText.isEmpty {
                Text(resultText)
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .refreshable { await load() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HiveTheme.bgVoid)
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().tint(HiveTheme.amber)
                Text("正在取回收站…")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        case .notReady:
            messageState(symbol: "house", text: String(localized: "先去设置页填「家地址 + 密钥」"))
        case .offline:
            messageState(symbol: "wifi.slash", text: String(localized: "连不上家里电脑，回收站暂时打不开"))
        case .locked:
            messageState(symbol: "lock.fill", text: String(localized: "蜂巢正在深度睡眠，锁了写；等它醒来再处理"))
        case .failed(let msg):
            messageState(symbol: "exclamationmark.triangle", text: msg)
        case .empty:
            messageState(symbol: "trash", text: String(localized: "回收站是空的 —— 拒绝过的念头会先放这儿"))
        case .ready:
            ForEach(items) { item in
                trashRow(item)
            }
        }
    }

    private func messageState(symbol: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(HiveTheme.amber.opacity(0.4))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func trashRow(_ item: TrashItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(item.source) · \(item.displayTime)" + (item.deletedText.isEmpty ? "" : " · \(item.deletedText)"))
                .font(.system(size: 11))
                .foregroundStyle(HiveTheme.textMuted)
            if !item.restoreNote.isEmpty {
                Text(item.restoreNote)
                    .font(.system(size: 10))
                    .foregroundStyle(HiveTheme.amber.opacity(0.8))
            }
            if busyIdx == item.idx {
                ProgressView()
                    .tint(HiveTheme.amber)
                    .scaleEffect(0.8)
                    .padding(.top, 4)
            } else {
                Button {
                    Task { await restore(item) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12))
                        Text("恢复")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(HiveTheme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(HiveTheme.green.opacity(0.5), lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .holoCard()
    }

    @MainActor
    private func load() async {
        resultText = ""
        guard config.isReady else {
            state = .notReady
            return
        }
        state = .loading
        switch await HivePendingService.trashList(config: config) {
        case .ok(let list):
            items = list
            state = list.isEmpty ? .empty : .ready
        case .locked: state = .locked
        case .offline: state = .offline
        case .notReady: state = .notReady
        case .failed(let msg): state = .failed(msg)
        }
    }

    @MainActor
    private func restore(_ item: TrashItem) async {
        busyIdx = item.idx
        resultText = ""
        let outcome = await HivePendingService.trashRestore(idx: item.idx, config: config)
        busyIdx = nil
        switch outcome {
        case .ok(let msg):
            resultText = msg
            // ⚠️ 必须同步前移下标：后端是 `arr.pop(idx)`（hive_warehouse.py:131），
            // 被恢复那条之后的所有条目下标各减 1。不同步的话，再点一次「恢复」
            // 会打到另一条上 —— 静默的错，比报错危险。前移逻辑在 service 里（可被实测覆盖）。
            items = HivePendingService.trashReindex(afterRemoving: item.idx, from: items)
            if items.isEmpty { state = .empty }
            HiveHaptics.success()
            onChanged()
        case .needPin:
            // trash_restore 后端没有 PIN 门（只 require_master），走到这只能是别的接口串了
            resultText = String(localized: "这台蜂巢设了隐私 PIN，恢复要在电脑端做")
        case .locked:
            resultText = String(localized: "蜂巢正在深度睡眠，锁了写")
        case .offline:
            resultText = String(localized: "连不上家里电脑，稍后再试")
        case .notReady:
            resultText = String(localized: "先去设置页填「家地址 + 密钥」")
        case .failed(let msg):
            resultText = msg
        }
    }
}

#Preview {
    家页()
        .environmentObject(HiveConfig())
}

// MARK: - 候选详情层（14 条修复第 4 条）

/// 点开收件箱一条候选看全文：标题 + 正文 + 图片/录音媒体 + 来源/时间/仓建议。
/// 只读展示，归档/拒绝仍在列表行上操作，详情页不做决策（避免误触）。
private struct CandidateDetailSheet: View {
    let item: CandidateItem
    @EnvironmentObject private var config: HiveConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.statusColor)
                            .frame(width: 7, height: 7)
                        Text(item.statusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.statusColor)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(HiveTheme.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(HiveTheme.holoTop)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text(item.title)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(HiveTheme.textTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(HiveTheme.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                    }
                    if !item.content.isEmpty {
                        Text(item.content)
                            .font(.system(size: 15))
                            .foregroundStyle(HiveTheme.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(6)
                    }
                    if item.type == "image" && !item.mediaPath.isEmpty {
                        mediaView
                    }
                    HStack(spacing: 8) {
                        Text("\(item.source) · \(item.displayTime)")
                            .font(.system(size: 11))
                            .foregroundStyle(HiveTheme.textMuted)
                        Spacer()
                        Text(item.suggestionLine)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(item.status == .sensitive ? HiveTheme.red : HiveTheme.textSecondary)
                    }
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            StitchAccent().allowsHitTesting(false)
        }
    }

    private var mediaView: some View {
        AsyncImage(url: mediaURL) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HiveTheme.textMuted.opacity(0.3), lineWidth: 1))
            case .failure:
                Label("图片加载失败", systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textCaption)
            case .empty:
                ProgressView().tint(HiveTheme.amber)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mediaURL: URL? {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/" + item.mediaPath)
    }
}

// MARK: - 归档前输电脑端密码层（遥控器语义）

/// 手机是遥控器：家里设了隐私密码时，归档前先输电脑端密码，输对才能远程归档。
/// 密码只在手机内存临时缓存 5 分钟（与后端 require_pin 注释一致），不落盘。
private struct PinPromptSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("输入电脑端密码")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(HiveTheme.textTitle)
                Text("电脑端和手机端同用一个密码。输入正确后，密码会在手机内存临时存 5 分钟，这期间归档不用重复输。")
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("电脑端密码", text: $pin)
                .font(.system(size: 16))
                .foregroundStyle(HiveTheme.textStrong)
                .keyboardType(.numberPad)
                .submitLabel(.go)
                .onSubmit { submit() }
                .onChange(of: pin) { _, v in
                    let digits = String(v.filter { $0.isNumber }.prefix(6))
                    if digits != v { pin = digits }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .holoCard()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.textSecondary)
                    .buttonStyle(.plain)
                Button("确定") { submit() }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HiveTheme.bgVoid)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(HiveTheme.amber)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .disabled(pin.count != 6)
                    .opacity(pin.count != 6 ? 0.5 : 1)
            }
        }
        .padding(20)
        .presentationDetents([.height(320)])
    }

    private func submit() {
        guard pin.count == 6 else { return }
        dismiss()
        onSubmit(pin)
    }
}
