import SwiftUI

/// 问页（在线）—— 掏出来问（检索公开四仓）
/// 视觉语言：文字渐显 + 关键词墨晕高亮
/// 2026-09-11 外脑意见三落点：①搜索框加取消 ②预览区随选中变化 + 选中态 ③公开四仓锁提示
/// 2026-09-11 问页接真数据：SearchResult.samples 假数据 → HiveSearchService.search 调 /api/search
struct 问页: View {
    @EnvironmentObject private var config: HiveConfig
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var selected: HiveSearchResult?
    @State private var showDetail = false

    // 检索状态机
    @State private var results: [HiveSearchResult] = []
    @State private var total = 0
    @State private var state: SearchState = .idle

    /// ③ 问页进化「能答」：搜原文 ↔ 直接问蜂巢 两个模式
    @State private var askMode = false
    @State private var answer: HiveAnswer?
    @State private var askState: HiveAskService.AskOutcome = .notReady
    @State private var asking = false

    /// 离线降级：家睡着了 → 切 Dig In 翻手边副本（P4 断连自动跳）
    @State private var digIn = false
    @State private var reconnecting = false

    // ── 分段P0-5 · 隐私区解锁（只在问页；解锁态与 PIN 都由 HiveConfig 存内存）────
    /// PIN 输入弹层是否展开
    @State private var privacySheet = false
    @State private var pinInput = ""
    @State private var pinError: String?
    @State private var pinBusy = false
    /// 家里是否设了隐私 PIN（`GET /api/privacy/status`，公开接口）。
    /// 未问到 = 当作「没设」→ 直接放行（与后端 `require_pin` 的「未设 PIN 本机信任放行」同口径）。
    @State private var houseHasPin = false
    /// 解锁态下点「问蜂巢」时就地说明，不切模式（理由见 `modeToggle`）
    @State private var askBlockedHint = false
    /// 14 条修复第 5 条：问蜂巢引用记忆可点开看全文
    @State private var selectedRef: HiveAnswerRef?

    enum SearchState {
        case idle          // 还没搜过（展示空态引导）
        case loading
        case ready         // 有结果
        case empty         // 搜了没结果
        case offline       // 连不上家
        case failed(String)
    }

    var body: some View {
        Group {
            if digIn {
                离线问页(onReconnect: reconnectFromDigIn, reconnecting: reconnecting)
            } else {
                onlineContent
            }
        }
        .task { await probeOnAppear() }
        // 离开问页即上锁。可靠性来自 ContentView 的 tab 是 `switch selectedTab`（ContentView.swift:52）——
        // 切页会**销毁**本视图 ⇒ onDisappear 必触发，不是「大概会」。
        .onDisappear {
            config.lockPrivacy()
            askBlockedHint = false
        }
    }

    /// 在线问页主界面（保持原有视觉，未变）
    private var onlineContent: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchBox
                    modeToggle
                    if askMode {
                        askContent
                    } else {
                        scopeBar
                        content
                    }
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            StitchAccent().allowsHitTesting(false)
        }
        .sheet(isPresented: $showDetail) {
            if let selected {
                记忆详情页(result: selected)
            }
        }
        .sheet(isPresented: $privacySheet) {
            privacyUnlockSheet
        }
        .sheet(item: $selectedRef) { ref in
            AnswerRefDetailSheet(ref: ref)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEMORY HIVE · 问")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(HiveTheme.amber)
            Text("掏出来问")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(HiveTheme.textTitle)
            Text("搜内容、搜时间、搜图里的字")
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textCaption)
        }
    }

    /// 搜索框：聚焦时出现「取消」，点它收起键盘（外脑点①）
    private var searchBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textMuted)
            TextField("找一句话、一个时刻、一张图里的字", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textStrong)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    if askMode { runAsk() } else { runSearch() }
                }
            if searchFocused {
                Button("取消") {
                    searchFocused = false
                }
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.amber)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .holoCard()
    }

    /// 模式切换：搜原文 ↔ 直接问蜂巢（③ 问页进化「能答」）
    private var modeToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // ⚠️ 图标不再靠「`title` 是否等于某个中文字面量」判断（2026-09-18 第二阶段修）：
                //    原先形参拿到的是 `String(localized: "问蜂巢")`（已本地化），
                //    而 `title == "问蜂巢"` 拿中文去比 —— 英文态永远不成立 ⇒
                //    **英文界面下「Ask the Hive」旁边的 sparkles 图标会凭空消失**（中英态不一致的隐 bug）。
                //    ⇒ 改成显式传 `icon` 参数，身份判断不再依赖文案内容。
                modeChip(title: String(localized: "搜原文"), active: !askMode) {
                    askMode = false
                    askBlockedHint = false
                }
                modeChip(title: String(localized: "问蜂巢"), icon: "sparkles", active: askMode) {
                    // 分段P0-5 · 解锁态下**不切**模式，就地说明。
                    // 理由：问蜂巢走 `/api/llm/chat`，它的检索范围**不受本页 `scopeBar` 控制** ——
                    // 切过去会让用户以为「现在问的就是隐私区」。宁可直说，不制造范围错觉。
                    config.privacyAutoLockIfNeeded()
                    if config.privacyUnlocked {
                        askBlockedHint = true
                    } else {
                        askMode = true
                        askBlockedHint = false
                    }
                }
                Spacer()
            }
            if askBlockedHint {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("隐私区已解锁，先在上面搜；要直接问蜂巢，请先上锁")
                        .font(.system(size: 11))
                }
                .foregroundStyle(HiveTheme.textCaption)
            }
        }
    }

    private func modeChip(title: String, icon: String? = nil, active: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // `title` 已由调用方本地化；身份（要不要小图标）走 `icon`，**不与文案耦合**
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? HiveTheme.bgVoid : HiveTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(active ? HiveTheme.amber : HiveTheme.holoTop)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(active ? HiveTheme.amber : HiveTheme.textMuted.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // ══════════════════════════════════════════════════════════════════════
    // MARK: - 分段P0-5 · 检索范围栏（原 `publicScopeHint` 升级为可操作）
    // ══════════════════════════════════════════════════════════════════════
    //
    // 原先是纯静态提示（外脑点③）：「仅搜索公开记忆，隐私区需解锁后单独问」——
    // 用户看到后**无处可去**，是一句死提示。现在它是**范围开关**：
    // 锁定态给「解锁」入口、解锁态给「上锁」入口。

    /// 范围栏。锁定/解锁两态共用一条，只有图标、文案、动作不同。
    ///
    /// ⚠️ 刻意**不显示倒计时**：`HiveConfig.privacyAutoLockIfNeeded()` 是惰性检查、
    /// 不挂常驻 Timer（理由见 `HiveConfig.swift` 该函数注释）⇒ 渲染出来的秒数**不会自己走**。
    /// 显示一个冻住的数字 = 假绿灯，故只写「5 分钟到点自动上锁」这句事实。
    ///
    /// ⚠️ 解锁动作**不在本视图判 PIN**：家里设没设 PIN 由 `houseHasPin` 决定
    /// （`probeOnAppear` 从公开接口 `/api/privacy/status` 问来的，与后端 `require_pin` 同口径）：
    /// 设了 → 弹 `privacyUnlockSheet` 收 PIN；没设 → 直接解锁（后端在那条路上也是直接放行）。
    private var scopeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: config.privacyUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(config.privacyUnlocked ? HiveTheme.amber : HiveTheme.textMuted)
            Text(config.privacyUnlocked
                 ? String(localized: "隐私区已解锁 · 5 分钟到点或离开本页自动上锁")
                 : String(localized: "仅搜索公开记忆，隐私区需解锁后单独问"))
                .font(.system(size: 11))
                .foregroundStyle(config.privacyUnlocked ? HiveTheme.textSecondary : HiveTheme.textCaption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Button(config.privacyUnlocked
                   ? String(localized: "上锁")
                   : String(localized: "解锁隐私区")) {
                togglePrivacy()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(HiveTheme.amber)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(Capsule().stroke(
            (config.privacyUnlocked ? HiveTheme.amber : HiveTheme.textMuted).opacity(0.3),
            lineWidth: 1))
    }

    /// 范围开关：解锁 / 上锁。
    private func togglePrivacy() {
        if config.privacyUnlocked {
            lockPrivacyNow()
        } else if houseHasPin {
            pinInput = ""
            pinError = nil
            privacySheet = true
        } else {
            // 家里没设 PIN（或没问到）→ 与后端 `require_pin`「未设 PIN 本机信任放行」同口径，直接解锁
            config.unlockPrivacy(pin: nil)
        }
    }

    /// 上锁并**清掉当前结果**。
    ///
    /// 为什么必须清：上锁后列表里若还留着刚搜出来的隐私仓条目，UI 就在说
    /// 「已经锁上了」而屏幕上仍是明文 —— 那是自相矛盾的状态。宁可回到空态。
    private func lockPrivacyNow() {
        config.lockPrivacy()
        askBlockedHint = false
        pinInput = ""
        pinError = nil
        results = []
        total = 0
        selected = nil
        state = .idle
    }

    /// 收 PIN 的弹层。只在 `houseHasPin == true` 时会被打开。
    private var privacyUnlockSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(HiveTheme.amber)
                Text("解锁隐私区")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(HiveTheme.textTitle)
            }

            Text("输入家里的隐私 PIN。解锁后，下面的搜索会带上隐私四仓（关系 · 个人 · 财务 · 私事）。")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("隐私 PIN", text: $pinInput)
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textStrong)
                .textFieldStyle(.plain)
                .submitLabel(.go)
                .onSubmit { submitPin() }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .holoCard()

            if let pinError {
                Text(pinError)
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.amberLight)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("取消") {
                    privacySheet = false
                    pinInput = ""
                    pinError = nil
                }
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textSecondary)
                .buttonStyle(.plain)

                Button(pinBusy ? String(localized: "校验中…") : String(localized: "解锁")) {
                    submitPin()
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HiveTheme.bgVoid)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(HiveTheme.amber)
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .disabled(pinBusy || pinInput.isEmpty)
                .opacity(pinBusy || pinInput.isEmpty ? 0.5 : 1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HiveTheme.bgVoid)
    }

    /// 校验 PIN。
    ///
    /// **校验器复用读隐私四仓那个接口**（`HiveSettingsService.fetchPrivacyCounts`）：
    /// 后端 `/api/privacy/load` 是 `require_master` + `require_pin` 双门（`hive_media.py:111-115`），
    /// 200 ⇒ PIN 对，403 ⇒ 不对。所以不必求后端新加一个「验 PIN」口。
    /// 代价（该函数注释已写明）：这一次会把解密后的四仓全文拉一遍。已列待裁项。
    private func submitPin() {
        let pin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pin.isEmpty, !pinBusy else { return }
        pinBusy = true
        pinError = nil
        Task {
            let outcome = await HiveSettingsService.fetchPrivacyCounts(config: config, pin: pin)
            pinBusy = false
            switch outcome {
            case .ok:
                config.unlockPrivacy(pin: pin)
                pinInput = ""
                privacySheet = false
            case .locked:
                // ⚠️ `.locked` 在服务层同时代表「403（PIN 不对 / 卡不对）」与「熔断锁写」两种情形
                // （`HiveSettingsService.fetchPrivacyCounts` 注释），接口层分不出，所以**不编**是哪一种。
                pinError = String(localized: "没能解锁：PIN 不对，或蜂巢正在熔断锁写")
            case .offline:
                pinError = String(localized: "连不上家，检查网络后再试")
            case .notReady:
                pinError = String(localized: "还没填家地址，去「设置 · 家连接」配好再来")
            case .failed(let msg):
                pinError = String(localized: "解锁失败：\(msg)")
            }
        }
    }

    /// 内容区：按状态机切换（空态引导 / 加载 / 结果列表+预览 / 无结果 / 断连 / 失败）
    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            idleHint
        case .loading:
            loadingHint
        case .ready:
            resultHeader
            ForEach(results) { r in
                resultCard(r)
            }
            if let selected {
                detailPreview(selected)
            }
        case .empty:
            emptyHint
        case .offline:
            offlineHint
        case .failed(let msg):
            failedHint(msg)
        }
    }

    /// 首屏空态：还没搜过，给一句引导
    private var idleHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 44))
                .foregroundStyle(HiveTheme.textMuted)
            Text("输入一句话，把记忆捞回来")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text("比如「手机版的脸」「那个淡蓝底色」")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var loadingHint: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(HiveTheme.amber)
            Text("正在翻蜂巢的记忆…")
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Text("没找到「\(query)」相关记忆")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text("换个词试试，或者这段记忆还没归档")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var offlineHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(HiveTheme.cyan)
            Text("连不上家")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text("家里的蜂巢没回应，检查家地址或网络后重试")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
                .multilineTextAlignment(.center)
            Button("重试") { runSearch() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HiveTheme.amber)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.6), lineWidth: 1))
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func failedHint(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text("检索出问题了")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
                .multilineTextAlignment(.center)
            Button("重试") { runSearch() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HiveTheme.amber)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.6), lineWidth: 1))
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var resultHeader: some View {
        HStack {
            Text(query.isEmpty ? String(localized: "最近") : String(localized: "「\(query)」"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Spacer()
            Text("\(total) 条 · 工作区")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .padding(.top, 4)
    }

    /// 结果卡片：可点选中，选中态左侧金色竖线（外脑点②）
    private func resultCard(_ r: HiveSearchResult) -> some View {
        let isSelected = selected?.id == r.id
        return Button {
            selected = r
            HiveHaptics.light()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(HiveWarehouses.displayName(r.wh)) · \(r.displayTime)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HiveTheme.amber)
                    Spacer()
                    Text(r.typeLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HiveTheme.amberLight)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(HiveTheme.amber.opacity(0.15))
                        .clipShape(Capsule())
                }
                HighlightedText(text: r.title, highlight: query)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HiveTheme.textStrong)
                Text(r.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .holoCard()
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(HiveTheme.amber)
                        .frame(width: 3)
                        .padding(.vertical, 10)
                        .shadow(color: HiveTheme.amber.opacity(0.6), radius: 4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    /// 底部预览区：随选中的记忆变化（外脑点②）+ 看全文入口
    private func detailPreview(_ r: HiveSearchResult) -> some View {
        Button {
            showDetail = true
            HiveHaptics.light()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11))
                        .foregroundStyle(HiveTheme.amber)
                    Text("记忆详情 · \(HiveWarehouses.displayName(r.wh))")
                        .font(.system(size: 12))
                        .foregroundStyle(HiveTheme.textCaption)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("看全文")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(HiveTheme.amber)
                }
                Text(r.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HiveTheme.textStrong)
                Text(r.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textSecondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(HiveTheme.amber.opacity(0.5))
                    .frame(width: 2)
            }
            .background(HiveTheme.holoTop)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(HiveTheme.amber.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 离线降级探测

    /// 打开问页时探测一次：家没回应 → 自动降级 Dig In（没配家地址则不探测）
    ///
    /// 分段P0-5：连通之后**顺手问一次「家里设没设隐私 PIN」**，决定「解锁隐私区」要不要收 PIN。
    /// 复用 `HivePendingService.privacyPinSet`（同一个公开接口 `/api/privacy/status`、
    /// 同一套取值口径，家页与问页共用一份实现，不另写一个 fetch）。
    /// 问不到（离线/异常）⇒ 按「没设」处理，与后端 `require_pin` 的「未设 PIN 放行」同口径；
    /// 真设了而这里误判成没设，也只是**解锁动作顺利、随后检索被后端拒**，
    /// 不会静默放行隐私数据（搜索失败会走到 `.failed`，如实报错）。
    private func probeOnAppear() async {
        guard !config.baseURL.isEmpty else { return }
        let reachable = await HiveSearchService.ping(config: config)
        if !reachable {
            digIn = true
            return
        }
        houseHasPin = await HivePendingService.privacyPinSet(config: config) ?? false
    }

    /// Dig In 里点「重试连接」：真探测，家回来了就切回在线问页
    private func reconnectFromDigIn() {
        guard !reconnecting else { return }
        reconnecting = true
        Task {
            let ok = await HiveSearchService.ping(config: config)
            reconnecting = false
            if ok {
                digIn = false
                state = .idle
                query = ""
                selected = nil
            }
        }
    }

    // MARK: - 检索动作

    // MARK: - ③ 问蜂巢（直接答）

    /// 问蜂巢内容区：按 askState 切换（引导 / 加载 / 回答+引用 / 无钥匙 / 断连 / 失败）
    @ViewBuilder
    private var askContent: some View {
        if asking {
            HStack(spacing: 10) {
                ProgressView().tint(HiveTheme.amber)
                Text("蜂巢正在翻记忆、组织回答…")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            switch askState {
            case .notReady:
                askIdleHint
            case .ok(let a):
                answerCard(a)
            case .noKey:
                askQuietHint(String(localized: "大脑还没配钥匙，去设置里接上，我才能直接回答"))
            case .offline:
                askQuietHint(String(localized: "连不上家，先搜手边副本，或回家再问"))
            case .failed(let msg):
                askQuietHint(String(localized: "回答失败：\(msg)"))
            }
        }
    }

    private var askIdleHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(HiveTheme.amber)
            Text("直接问，蜂巢替你翻记忆作答")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text("比如「我这周在忙什么」「手机版还有哪些没做完」")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func answerCard(_ a: HiveAnswer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(HiveTheme.amber)
                Text("蜂巢的回答")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(HiveTheme.amber)
            }
            Text(a.answer)
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textBody)
                .fixedSize(horizontal: false, vertical: true)
            if !a.refs.isEmpty {
                Divider().overlay(HiveTheme.textMuted.opacity(0.3))
                Text("引用记忆")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HiveTheme.textCaption)
                ForEach(a.refs) { ref in
                    Button {
                        selectedRef = ref
                        HiveHaptics.light()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(HiveWarehouses.displayName(ref.wh))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(HiveTheme.amber)
                                Spacer()
                                Text(String(ref.timestamp.prefix(10)))
                                    .font(.system(size: 10))
                                    .foregroundStyle(HiveTheme.textMuted)
                            }
                            if !ref.title.isEmpty {
                                Text(ref.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(HiveTheme.textStrong)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 3) {
                                Text("看全文")
                                    .font(.system(size: 10, weight: .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(HiveTheme.cyan)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(HiveTheme.holoTop)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func askQuietHint(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textCaption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func runAsk() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchFocused = false
        asking = true
        Task {
            let outcome = await HiveAskService.ask(question: q, config: config)
            asking = false
            askState = outcome
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        // 分段P0-5：每次检索前先做一次惰性到点上锁（`HiveConfig` 刻意不挂常驻 Timer）。
        // 若刚刚**因为到点而掉锁**，不静默降级成公开仓搜索 —— 那正是本项目最忌的假绿灯。
        let wasUnlocked = config.privacyUnlocked
        config.privacyAutoLockIfNeeded()
        if wasUnlocked && !config.privacyUnlocked {
            state = .failed(String(localized: "隐私区已自动上锁（解锁 5 分钟到期），重新解锁后再搜"))
            return
        }
        let scope: HiveSearchService.SearchScope = config.privacyUnlocked ? .includePrivacy : .publicOnly

        searchFocused = false
        selected = nil
        state = .loading
        Task {
            switch await HiveSearchService.search(query: q, config: config, scope: scope) {
            case .ok(let hits, let t):
                results = hits
                total = t
                selected = hits.first
                state = .ready
                SearchCache.save(results: hits, query: q)
            case .empty:
                results = []
                total = 0
                state = .empty
            case .offline:
                digIn = true   // 断连自动跳 Dig In
            case .notReady:
                state = .failed(String(localized: "还没填家地址，去「设置 · 家连接」配好再来问"))
            case .failed(let msg):
                state = .failed(msg)
            }
        }
    }
}

/// 关键词墨晕高亮文本（用 AttributedString 给关键词上琥珀底色）
struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        if let range = result.range(of: highlight) {
            result[range].backgroundColor = HiveTheme.amber.opacity(0.35)
        }
        return result
    }
}

#Preview {
    问页()
        .environmentObject(HiveConfig())
}

/// 14 条修复第 5 条：「问蜂巢」引用记忆全文层。
/// 问蜂巢回答下方的引用此前只显示标题，点不开；这里铺开引用记忆的原文全文。
private struct AnswerRefDetailSheet: View {
    let ref: HiveAnswerRef
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text(HiveWarehouses.displayName(ref.wh))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HiveTheme.amber)
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
                    if !ref.title.isEmpty {
                        Text(ref.title)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(HiveTheme.textTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !ref.raw.isEmpty {
                        Text(ref.raw)
                            .font(.system(size: 15))
                            .foregroundStyle(HiveTheme.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(6)
                    }
                    Text("归档于 \(HiveWarehouses.displayName(ref.wh)) · \(ref.timestamp)")
                        .font(.system(size: 11))
                        .foregroundStyle(HiveTheme.textMuted)
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            StitchAccent().allowsHitTesting(false)
        }
    }
}
