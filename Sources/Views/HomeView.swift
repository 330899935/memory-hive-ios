import SwiftUI
import PhotosUI

/// 首页 —— 记忆蜂巢的落地页（科幻版）
/// 定位：承接记忆的落点，不是「扫描器」。
/// 触角 = 手动接入（API / MCP / 自带 agent / 主脑），不扫描发现。
struct HomeView: View {
    @Binding var selectedTab: HiveTab
    @EnvironmentObject private var store: ThoughtStore
    @EnvironmentObject private var config: HiveConfig
    @StateObject private var recorder = AudioRecorder()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var photoItem: PhotosPickerItem?
    @State private var photoItem2: PhotosPickerItem?
    @State private var pulse = false
    @State private var greeted = false
    @State private var isScrolling = false

    /// ④ 问候气泡点开 → 「选择做什么」菜单
    @State private var showGreetingMenu = false
    /// 拍照 / 拖图 改为可程序化触发的 picker（⑥⑦ 差异化铺路 + ④ 菜单入口）
    @State private var showCameraPicker = false
    @State private var showGalleryPicker = false
    /// ⑥⑦：拍照 = 直接调相机（UIImagePickerController）；模拟器无相机则 fallback 相册
    @State private var showCameraSheet = false
    /// ⑩ 最近接住点开看详情
    @State private var detailThought: PendingThought?
    // 2026-09-18（任务 B）：拍照/选图/录音后不再必弹起名层 —— 落库即走，
    // 名字/摘要/分仓交给后台 /api/understand 自动补；想改去详情页「改名」。

    /// P2-3：问候语提到「照片」时，拍照入口呼吸 2 秒（每日首次）
    @State private var photoGlow = false

    /// 蜂巢「自主」建议（第②步第一刀：首页「蜂巢对你说」卡片）
    @State private var suggestion: HiveSuggestion?
    @State private var suggestState: HiveSuggestService.SuggestOutcome = .notReady
    /// 第三刀：独立规划页（从「蜂巢对你说」卡片点开）
    @State private var showPlan = false
    /// 14 条修复第 3 条：点开看「蜂巢对你说」全文（message + points）
    @State private var showFullSuggest = false

    /// 动效总开关：退后台 / 滚动中 / 减弱动态效果 时冻结背景动画（省电）
    private var motionActive: Bool {
        !reduceMotion && scenePhase == .active && !isScrolling
    }

    /// 离线（有念头在排队回家）：流光变蓝灰、呼吸变慢——真实数据驱动，不读文字就知状态
    private var isOffline: Bool {
        store.thoughts.contains { !$0.synced }
    }

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()          // 六边形网格背景
            ambientGlow        // 环境光晕

            // ── 分段P1-2（2026-09-20）────────────────────────────────────────
            // 这里的 GeometryReader **只为一件事存在**：量到 ScrollView 真正拿到的
            // 竖向空间，供下面决定要不要放统计行。
            // 旧写法（`UIScreen.main.bounds.height < 700`）读的是**整块屏幕**，不是本视图
            // 的窗口 ⇒ 一旦窗口比屏幕小（iPad 分屏 / Slide Over / Stage Manager 改窗），
            // 判据就失真。本段把取数来源换成视口实测值，阈值与判据方向都不变。
            // ⚠️ GeometryReader 在这里**不改布局**：它和 ScrollView 一样是「填满父容器」的
            //    贪心容器，ZStack 的尺寸与 safe-area 传递均与改动前一致。
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        greeting
                        radar
                        // `>= 阈值` 等价于原来的 `!isCompact`（原判据是 `< 阈值`）
                        if geo.size.height >= Self.compactViewportHeight { statusStrip }
                        suggestCard
                        feedCard
                        recentCard
                    }
                    .padding(.horizontal, HiveTheme.contentInset)
                    .padding(.top, HiveTheme.contentTop)
                    .padding(.bottom, HiveTheme.contentBottom)
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in isScrolling = true }
                        .onEnded { _ in
                            isScrolling = false
                            // 滚动结束后 0.4s 内保持冻结，避免惯性滚动中频繁启停
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                isScrolling = false
                            }
                        }
                )
            }
            HiveBottomFade()   // 底部渐隐幕布：滚动内容沉回黑暗，不撞底部缝线
            StitchFrame()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .photosPicker(isPresented: $showCameraPicker, selection: $photoItem, matching: .images)
        .photosPicker(isPresented: $showGalleryPicker, selection: $photoItem2, matching: .images)
        .sheet(isPresented: $showCameraSheet) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9), let t = store.add(imageData: data) {
                    HiveHaptics.light()
                    autoUnderstandMedia(t)   // 不再弹起名层，直接后台自动理解
                }
            }
        }
        .sheet(isPresented: $showGreetingMenu) { greetingMenu }
        .sheet(item: $detailThought) { thought in
            ThoughtDetailSheet(thought: thought)
        }
        .sheet(isPresented: $showPlan) {
            规划页()
                .environmentObject(config)
                .environmentObject(store)
        }
        .sheet(isPresented: $showFullSuggest) {
            if let suggestion {
                SuggestionFullSheet(suggestion: suggestion)
            }
        }
        .onAppear {
            if suggestion == nil && suggestState != .offline {
                Task { await loadSuggestion() }
            }
        }
    }

    /// 「紧凑视口」阈值（pt）：**本视图**竖向空间不足此值时隐藏统计行，避免挤爆。
    ///
    /// ── 分段P1-2（2026-09-20）改了什么 ────────────────────────────────────
    /// 旧实现（**查到的**，原文）：
    /// ```swift
    /// private var isCompact: Bool { UIScreen.main.bounds.height < 700 }
    /// ```
    /// 病灶：`UIScreen.main.bounds` 是**整块屏幕**的高，与「本 App 窗口拿到多少竖向空间」
    /// 是两回事。窗口一旦小于屏幕（iPad 分屏 / Slide Over / Stage Manager 改窗），
    /// 判据就与实际可用高度脱钩 ⇒ 该隐藏时显示（挤爆）、不该隐藏时隐藏（莫名少一行）。
    /// 现状之所以看不出来，是因为 `project.yml:46` 还挂着 `UIRequiresFullScreen: YES`
    /// ——**P1-3 一放开多窗口，这条立刻从「边缘」变「日常」**（两条耦合，见交付说明 §6）。
    ///
    /// 改法：阈值提到这里成为常量，**取数来源换成 `body` 里 GeometryReader 量到的视口高**。
    /// 判据方向不变（`!isCompact` ≡ `视口高 >= 阈值`），故**现有机型行为逐条不变**。
    ///
    /// ⚠️ 刻意**没有**用 `verticalSizeClass` 替代（单子上给的另一条路）：
    /// iPhone SE 竖屏的 `verticalSizeClass` 是 `.regular`，照它判会把 SE 判成「非紧凑」
    /// ⇒ 统计行重新挤爆 —— 那是**反向回归**，正是这段要防的事。故不采用。
    private static let compactViewportHeight: CGFloat = 700

    // 注：原 `private var isCompact` 已随本段删除（它再无引用）。
    // 视图层布局的真机行为不在本段可验证范围内（见交付说明「验收总则」）。

    // MARK: - 蜂巢对你说（第②步第一刀）

    /// 拉取蜂巢建议：带装修卡调 /api/suggest，成功/失败都落态供卡片展示
    @MainActor
    private func loadSuggestion() async {
        suggestState = await HiveSuggestService.suggest(config: config)
        if case .ok(let s) = suggestState {
            suggestion = s
        }
    }

    private var suggestCard: some View {
        Group {
            switch suggestState {
            case .ok(let s):
                suggestContent(s)
            case .empty(let msg):
                emptySuggestContent(msg)
            case .noKey:
                quietSuggestContent(String(localized: "大脑还没配钥匙，去设置里接上，我才能替你操心"))
            case .offline:
                quietSuggestContent(String(localized: "连不上家，先存手机，回家我再看"))
            case .notReady:
                notReadySuggestContent
            case .failed:
                quietSuggestContent(String(localized: "今天先不打扰，想起什么随手记"))
            }
        }
    }

    private func suggestContent(_ s: HiveSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.amber)
                Text("蜂巢对你说")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HiveTheme.amber)
                Spacer()
                Button {
                    showFullSuggest = true
                    HiveHaptics.light()
                } label: {
                    HStack(spacing: 3) {
                        Text("看全文")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(HiveTheme.cyan)
                }
                .buttonStyle(.plain)
                Button {
                    Task { await loadSuggestion() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HiveTheme.textCaption)
                }
                .buttonStyle(.plain)
            }
            Text(s.message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
                .fixedSize(horizontal: false, vertical: true)
            if !s.points.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(s.points, id: \.self) { p in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(HiveTheme.amber)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(p)
                                .font(.system(size: 13))
                                .foregroundStyle(HiveTheme.textBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            // 第三刀入口：点开看完整规划
            Button {
                showPlan = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 12))
                    Text("看完整规划")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(HiveTheme.cyan)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func emptySuggestContent(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.amber)
                Text("蜂巢对你说")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HiveTheme.amber)
            }
            Text(msg)
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func quietSuggestContent(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hexagon")
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textMuted)
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textCaption)
            Spacer()
        }
        .padding(16)
        .holoCard()
    }

    /// 首因引导（2026-09-19 引流指令书 §三）：新用户还没连家时，
    /// 给「手机是桥、电脑是家」的心智 + 直达 Mac App Store 的下载入口，别让首分钟撞墙
    private var notReadySuggestContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "hexagon")
                    .font(.system(size: 15))
                    .foregroundStyle(HiveTheme.textMuted)
                Text(String(localized: "手机是桥，电脑是家。"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HiveTheme.textBody)
                Spacer()
            }
            Text(String(localized: "先在电脑上装好蜂巢（Mac 版），再扫电脑上的码连回家。"))
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textCaption)
            Button {
                openURL(HiveConfig.macAppStoreURL)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                    Text(String(localized: "下载 Mac 版"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                }
                .foregroundStyle(HiveTheme.amber)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .holoCard()
    }

    private var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(HiveTheme.amber.opacity(0.10))
                .frame(width: 320)
                .blur(radius: 60)
                .offset(x: -120, y: -280)
            Circle()
                .fill(HiveTheme.cyan.opacity(0.07))
                .frame(width: 260)
                .blur(radius: 55)
                .offset(x: 140, y: 180)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 六边形网格背景（渐变：顶部亮黄 → 往下渐暗沉回黑暗）
struct HexGrid: View {
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let r: CGFloat = 26
                let w = r * CGFloat(3.0.squareRoot())
                let h = r * 1.5
                var row = 0
                var y: CGFloat = -h
                while y < size.height + h {
                    var x: CGFloat = (row % 2 == 0) ? 0 : w / 2
                    while x < size.width + w {
                        ctx.stroke(
                            hexPath(center: CGPoint(x: x, y: y), r: r),
                            with: .color(HiveTheme.gridHex),
                            lineWidth: 0.6
                        )
                        x += w
                    }
                    y += h
                    row += 1
                }
            }
            // 纵向渐变遮罩：顶部不遮（100% 亮）→ 40% 处遮 45% → 底部全遮（沉回黑暗）
            LinearGradient(
                stops: [
                    .init(color: HiveTheme.bgVoid.opacity(0.0), location: 0.0),
                    .init(color: HiveTheme.bgVoid.opacity(0.45), location: 0.40),
                    .init(color: HiveTheme.bgVoid.opacity(1.0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func hexPath(center: CGPoint, r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<6 {
            let angle = CGFloat(i) * 60 - 30
            let x = center.x + r * cos(angle * .pi / 180)
            let y = center.y + r * sin(angle * .pi / 180)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 问候
extension HomeView {
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEMORY HIVE · 记忆蜂巢")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(HiveTheme.amber)
                .shadow(color: HiveTheme.amber.opacity(0.7), radius: 6)
            Text(greetingText)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(HiveTheme.textTitle)
                .shadow(color: HiveTheme.amber.opacity(0.35), radius: 14)
            // ③ 原问候处挂官网链接已移除（14条修复第2条：首页只留设置页官网入口，
            //    问候语不再夹带外跳，避免误触打断「接住」节奏）。
            Text("把在乎的，交给蜂巢记着")
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .opacity(greeted ? 1 : 0)
        .offset(y: greeted ? 0 : 14)
        .animation(.easeOut(duration: 0.6).delay(0.1), value: greeted)
        .onAppear { greeted = true }
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return String(localized: "早上好")
        case 12..<18: return String(localized: "下午好")
        case 18..<23: return String(localized: "晚上好")
        default: return String(localized: "夜深了")
        }
    }

    /// ④ 问候气泡点开 → 「选择做什么」菜单（四入口，直接能下一步操作）
    private var greetingMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今天想记点什么？")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(HiveTheme.textTitle)
                .padding(.bottom, 6)
            menuRow(symbol: "square.and.pencil", label: String(localized: "写字"), tint: HiveTheme.amber) {
                showGreetingMenu = false
                selectedTab = .save
            }
            menuRow(symbol: "camera.fill", label: String(localized: "拍照"), tint: HiveTheme.cyan) {
                showGreetingMenu = false
                showCameraPicker = true
            }
            menuRow(symbol: "photo.on.rectangle", label: String(localized: "从相册选"), tint: HiveTheme.green) {
                showGreetingMenu = false
                showGalleryPicker = true
            }
            menuRow(symbol: recorder.isRecording ? "stop.fill" : "mic.fill",
                    label: recorder.isRecording ? String(localized: "停止录音") : String(localized: "录音"),
                    tint: HiveTheme.purple) {
                if recorder.isRecording {
                    if let url = recorder.stop(), let t = store.add(audioTempURL: url) {
                        HiveHaptics.light()
                        autoUnderstandMedia(t)   // 不再弹起名层
                    }
                } else {
                    recorder.start()
                }
                showGreetingMenu = false
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HiveTheme.bgVoid)
        .presentationDetents([.height(340)])
    }

    private func menuRow(symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HiveTheme.textStrong)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HiveTheme.textMuted)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(HiveTheme.holoTop)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 触角雷达（中央蜂巢 + 已接入触角环绕）
struct AntennaNode: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let color: Color
    let pos: CGPoint   // 相对 0-1

    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * pos.x, y: size.height * pos.y)
    }

    static let samples: [AntennaNode] = [
        AntennaNode(name: String(localized: "家里电脑"), role: String(localized: "电脑蜂巢"), color: HiveTheme.amber, pos: CGPoint(x: 0.5, y: 0.16)),
        AntennaNode(name: String(localized: "云端"), role: String(localized: "API 接入"), color: HiveTheme.cyan, pos: CGPoint(x: 0.14, y: 0.64)),
        AntennaNode(name: "MCP", role: String(localized: "工具触角"), color: HiveTheme.purple, pos: CGPoint(x: 0.86, y: 0.64)),
    ]
}

struct HiveRadar: View {
    let nodes: [AntennaNode]
    var motionActive: Bool = true
    var offline: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, _ in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    // 同心雷达环
                    for radius in [0.46, 0.30, 0.15] {
                        let r = size.width / 2 * radius
                        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(HiveTheme.amber.opacity(0.12)), lineWidth: 0.7)
                    }
                    // 连接线（静态底 + 流动虚线）
                    for node in nodes {
                        var p = Path()
                        p.move(to: c)
                        p.addLine(to: node.point(in: size))
                        ctx.stroke(p, with: .color(node.color.opacity(0.45)), lineWidth: 1)
                    }
                }
                // 扫描扇形（旋转）
                ScanSweep(motionActive: motionActive, offline: offline)
                    .frame(width: size.width, height: size.width)
                    .position(x: size.width / 2, y: size.height / 2)
                    .mask(
                        Circle()
                            .frame(width: size.width, height: size.width)
                            .position(x: size.width / 2, y: size.height / 2)
                    )
                ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                    AntennaNodeView(node: node)
                        .breatheNode(delay: Double(idx) * 0.7)
                        .position(node.point(in: size))
                }
                HiveCore(motionActive: motionActive, offline: offline)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
        .frame(height: 200)
    }
}

struct AntennaNodeView: View {
    let node: AntennaNode

    var body: some View {
        VStack(spacing: 5) {
            Circle()
                .fill(node.color)
                .frame(width: 13, height: 13)
                .shadow(color: node.color.opacity(0.9), radius: 9)
                .shadow(color: node.color.opacity(0.5), radius: 18)
            Text(node.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text(node.role)
                .font(.system(size: 9))
                .foregroundStyle(HiveTheme.textMuted)
        }
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<6 {
            let angle = CGFloat(i) * 60 - 30
            let x = center.x + r * cos(angle * .pi / 180)
            let y = center.y + r * sin(angle * .pi / 180)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

struct HiveCore: View {
    var motionActive: Bool = true
    var offline: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor: TimeInterval = 0
    @State private var frozenT: TimeInterval = 0

    /// 离线降温：呼吸周期 2.2s→3.6s（变慢）、内芯/光晕变蓝灰
    private var breatheCycle: Double { offline ? 3.6 : 2.2 }
    private var coreColor: Color { offline ? HiveTheme.cold : HiveTheme.amber }
    private var glowColor: Color { offline ? HiveTheme.cyan.opacity(0.22) : HiveTheme.amber.opacity(0.35) }

    /// 呼吸幅度：时间驱动，0~1 往返；reduceMotion 时固定 0.5（不呼吸）
    private func breathe(at now: TimeInterval) -> Double {
        guard motionActive, !reduceMotion else { return 0.5 }
        let phase = ((now - anchor).truncatingRemainder(dividingBy: breatheCycle) / breatheCycle)
        // 三角波：0→1→0，正弦波用 cos 往返
        return (cos(2 * .pi * phase) + 1) / 2
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let t = motionActive && !reduceMotion ? (now - anchor) : frozenT
            let spin = (t.truncatingRemainder(dividingBy: 14.0) / 14.0) * 360
            let spinBack = -((t.truncatingRemainder(dividingBy: 10.0) / 10.0) * 360)
            let breath = breathe(at: now)
            let scale = reduceMotion ? 1.0 : 0.9 + breath * 0.24   // 0.9↔1.14

            ZStack {
                // 外层径向光晕
                Circle()
                    .fill(RadialGradient(
                        colors: [glowColor, HiveTheme.amber.opacity(0.0)],
                        center: .center, startRadius: 0, endRadius: 62
                    ))
                    .frame(width: 124, height: 124)
                    .blur(radius: 5)

                // 慢速旋转外环（六边形虚线，扫描旋转语言）
                HexagonShape()
                    .stroke(HiveTheme.amber.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [4, 6]))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(spin))

                // 反向旋转内环（细实线）
                HexagonShape()
                    .stroke(HiveTheme.cyan.opacity(0.35), lineWidth: 0.8)
                    .frame(width: 62, height: 62)
                    .rotationEffect(.degrees(spinBack))

                // 行星环绕（金木水火土五行，暗夜降饱和配色，不挂字只留寓意；外圈越远越慢，仿宇宙公转）
                Planet(radius: 30, duration: 7.0,  delay: 0.0, size: 8,  tint: HiveTheme.cyan.opacity(0.98), shade: Color(hex: 0x3A5F96).opacity(0.6), motionActive: motionActive)   // 水（内圈最快）
                Planet(radius: 39, duration: 11.5, delay: 1.3, size: 9,  tint: HiveTheme.amberLight,              shade: HiveTheme.amberDeep,                motionActive: motionActive)   // 金
                Planet(radius: 48, duration: 16.0, delay: 2.6, size: 9,  tint: Color(hex: 0xC0644A),              shade: Color(hex: 0x6E3322),                motionActive: motionActive)   // 火（赤铜暗红降饱和）
                Planet(radius: 57, duration: 22.5, delay: 3.9, size: 11, tint: Color(hex: 0x6BAF8E),              shade: Color(hex: 0x2F5E46),                motionActive: motionActive)   // 木（青绿降饱和，最大）
                Planet(radius: 63, duration: 30.0, delay: 5.2, size: 10, tint: Color(hex: 0xC98E4A),              shade: HiveTheme.amberDeep,                motionActive: motionActive)   // 土（外圈最慢）

                // 内芯六边形 + 呼吸（唯一「呼吸」档）
                ZStack {
                    HexagonShape()
                        .fill(coreColor.opacity(0.28))
                        .frame(width: 44, height: 44)
                    HexagonShape()
                        .stroke(coreColor, lineWidth: 1.6)
                        .frame(width: 44, height: 44)
                }
                .shadow(color: coreColor.opacity(0.85), radius: 14)
                .shadow(color: coreColor.opacity(0.4), radius: 28)
                .scaleEffect(scale)

                // 中心亮点（缩小压暗，别让它像第 6 颗行星）
                Circle()
                    .fill(offline ? HiveTheme.cyan.opacity(0.7) : HiveTheme.amberLight)
                    .frame(width: 5, height: 5)
                    .blur(radius: 1.2)
                    .shadow(color: coreColor.opacity(0.55), radius: 5)
            }
        }
        .onAppear { anchor = Date().timeIntervalSinceReferenceDate }
        .onChange(of: motionActive) { _, active in
            let now = Date().timeIntervalSinceReferenceDate
            if active {
                anchor = now - frozenT     // 从冻结位恢复
            } else {
                frozenT = now - anchor     // 记录已流逝时间
            }
        }
        .onChange(of: offline) { _, _ in
            let now = Date().timeIntervalSinceReferenceDate
            anchor = now
        }
    }
}

extension HomeView {
    private var radar: some View {
        VStack(spacing: 10) {
            HiveRadar(nodes: AntennaNode.samples, motionActive: motionActive, offline: isOffline)
            ActiveGreeting(paused: recorder.isRecording, photoGlow: $photoGlow, onTapAction: { showGreetingMenu = true })
            Text("已接入 \(antennaCount) 个触角 · 手动接入 · 非扫描")
                .font(.system(size: 11))
                .foregroundStyle(HiveTheme.textCaption)
        }
    }
}

// MARK: - 状态条
extension HomeView {
    /// 三态统计（定稿 2026-09-18）：Local = 待同步 / Sent = **已投递** / Archived = 已归档
    ///
    /// ⚠️ 2026-09-18 家页体验指令书 P0-3（两个「待确认」撞名）——选**方案 A**：
    /// 这一格从「待确认」改叫「已投递」。理由是**两处口径本来就不同**：
    ///   - 这里数的是**本机**投出去的（`synced && !archived`，只有这台手机存的念头）；
    ///   - 家页数的是**整个收件箱**（`GET /api/pending` 四桶，含别的触角投的）。
    /// 同名不同数最容易被读成「数据对不上」。改名后：投递是「我送出去了」，
    /// 待确认是「家里还有几条等我点头」，一眼分得开；数字仍与「存」页一致，所以仍跳「存」。
    /// （选 B「指向家 tab」会把本机口径的数字和全量列表摆在一起，更容易困惑，故不取。）
    private var statusStrip: some View {
        let archived = store.thoughts.filter { $0.archived }.count
        let sent = store.thoughts.filter { $0.synced && !$0.archived }.count
        let local = store.thoughts.filter { !$0.synced }.count
        return HStack(spacing: 12) {
            statButton(value: "\(archived)", label: String(localized: "已归档"), tint: HiveTheme.amber) { selectedTab = .ask }
            statButton(value: "\(sent)", label: String(localized: "已投递"), tint: HiveTheme.amberDeep) { selectedTab = .save }
            statButton(value: "\(local)", label: String(localized: "待同步"), tint: HiveTheme.green) { selectedTab = .save }
        }
    }

    /// 触角数：暂为占位，待「触角接入」后接真实（主脑不算触角）
    private var antennaCount: Int { 2 }

    private func statButton(value: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            statCell(value: value, label: label, tint: tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statCell(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(HiveTheme.textTitle)
                .shadow(color: tint.opacity(0.5), radius: 8)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .holoCard()
    }
}

// MARK: - 喂记忆（主 CTA，四入口接真实录入）
extension HomeView {
    /// 空状态呼吸：家是空的（0 记忆）时，四入口面板琥珀呼吸，邀请用户接住第一条
    private var welcomeGlow: Bool {
        store.thoughts.isEmpty
    }

    private var feedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一段记忆")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(HiveTheme.textStrong)
            // ⑧ 录音中醒目提示条
            if recorder.isRecording {
                recordingBanner
            }
            HStack(spacing: 12) {
                Button {
                    openCamera()
                } label: {
                    feedLabel(symbol: "camera.fill", label: String(localized: "拍照"), tint: HiveTheme.cyan)
                        .modifier(BreatheGlow(active: photoGlow, tint: HiveTheme.cyan))
                }
                .buttonStyle(.plain)
                Button {
                    showGalleryPicker = true
                } label: {
                    feedLabel(symbol: "photo.on.rectangle", label: String(localized: "拖图"), tint: HiveTheme.green)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button {
                    if recorder.isRecording {
                        if let url = recorder.stop(), let t = store.add(audioTempURL: url) {
                            HiveHaptics.light()
                            autoUnderstandMedia(t)   // 不再弹起名层
                        }
                    } else {
                        recorder.start()
                    }
                } label: {
                    feedLabel(symbol: recorder.isRecording ? "stop.fill" : "mic.fill",
                              label: recorder.isRecording ? String(localized: "停止") : String(localized: "录音"),
                              tint: HiveTheme.purple)
                }
                .buttonStyle(.plain)
                Button {
                    selectedTab = .save
                } label: {
                    feedLabel(symbol: "square.and.pencil", label: String(localized: "写字"), tint: HiveTheme.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
        .modifier(BreatheGlow(active: welcomeGlow, tint: HiveTheme.amber, cornerRadius: 20))
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
        .onChange(of: photoItem2) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
    }

    /// ⑧ 录音中提示条：红点呼吸 + 文字，让用户明确知道正在录
    private var recordingBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(HiveTheme.red)
                .frame(width: 8, height: 8)
                .shadow(color: HiveTheme.red.opacity(0.9), radius: 5)
            Text("正在录音…点「停止」结束")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HiveTheme.red)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(HiveTheme.red.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HiveTheme.red.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// ⑥⑦：拍照优先相机，无相机 fallback 相册
    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCameraSheet = true
        } else {
            showCameraPicker = true
        }
    }

    private func feedLabel(symbol: String, label: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.7), radius: 8)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HiveTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(HiveTheme.holoTop)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if let t = store.add(imageData: data) {
                HiveHaptics.light()
                autoUnderstandMedia(t)   // 不再弹起名层
            }
        }
        photoItem = nil
        photoItem2 = nil
    }

    /// 媒体类自动理解（图片 OCR / 录音 STT）：存完后异步跑，成功自动起名+摘要+归类
    /// 异常分支（失败/离线/未配 key）：补一个时间戳默认名，保证念头可辨认、不丢数据、不卡流程
    @MainActor
    private func autoUnderstandMedia(_ thought: PendingThought) {
        Task {
            if let r = await HiveSyncService.understandMedia(thought: thought, store: store, config: config) {
                store.setUnderstand(thought, name: r.name, summary: r.summary, suggest: r.suggest)
            } else {
                store.ensureDefaultName(thought)
            }
        }
    }
}

// MARK: - 最近接住（记忆流）
extension HomeView {
    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近接住")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HiveTheme.textStrong)
                Spacer()
                Button {
                    selectedTab = .save
                } label: {
                    Text("查看全部")
                        .font(.system(size: 12))
                        .foregroundStyle(HiveTheme.amber)
                }
                .buttonStyle(.plain)
            }
            if store.thoughts.isEmpty {
                emptyState
            } else {
                ForEach(Array(store.thoughts.prefix(3))) { t in
                    recentRow(for: t)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    /// 空状态：新用户首开，0 记忆时的留人时刻（主动邀请，而非被动等待）
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "hexagon")
                .font(.system(size: 30))
                .foregroundStyle(HiveTheme.amber.opacity(0.5))
            Text("家是空的，现在就接住第一条吧")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text("拍照、拖图、录音、写字，都行")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func recentRow(for t: PendingThought) -> some View {
        Button {
            detailThought = t
            HiveHaptics.light()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(for: t.kind))
                    .font(.system(size: 15))
                    .foregroundStyle(tint(for: t.kind))
                    .frame(width: 28, height: 28)
                    .background(tint(for: t.kind).opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.content)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(HiveTheme.textStrong)
                        .lineLimit(1)
                    Text(relativeTime(t.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(HiveTheme.textMuted)
                }
                Spacer()
                Text(t.stage.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(stageTint(t.stage))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stageTint(t.stage).opacity(0.12))
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func symbol(for kind: ThoughtKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .photo: return "photo"
        case .audio: return "mic"
        case .document: return "doc.fill"
        case .video: return "video.fill"
        }
    }

    private func tint(for kind: ThoughtKind) -> Color {
        switch kind {
        case .text: return HiveTheme.cyan
        case .photo: return HiveTheme.green
        case .audio: return HiveTheme.purple
        case .document: return HiveTheme.amber
        case .video: return HiveTheme.red
        }
    }

    /// 三态色：待同步金深 / 待确认琥珀 / 已归档绿
    private func stageTint(_ stage: ThoughtStage) -> Color {
        switch stage {
        case .local: return HiveTheme.amberDeep
        case .awaitingConfirm: return HiveTheme.amber
        case .archived: return HiveTheme.green
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "刚刚") }
        if interval < 3600 { return String(localized: "\(Int(interval / 60)) 分钟前") }
        if interval < 86400 { return String(localized: "\(Int(interval / 3600)) 小时前") }
        if interval < 172800 { return String(localized: "昨天") }
        return date.formatted(date: .numeric, time: .omitted)
    }
}



/// 迈巴赫手工缝线包边（对齐定稿版）：单圈短虚线，沿边方向排布，大圆角，淡金色带发光
struct StitchFrame: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let inset: CGFloat = 6           // 离边缘距离（老铁定：往边上移2mm，从18→6）
            let rect = CGRect(
                x: inset, y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )
            let gold = Color(red: 0.831, green: 0.686, blue: 0.216) // #D4AF37 淡金色

            ZStack {
                Path(roundedRect: rect, cornerRadius: 44)
                    .stroke(
                        gold.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [7, 5])
                    )
                    .shadow(color: gold.opacity(0.6), radius: 5)
                Path(roundedRect: rect, cornerRadius: 44)
                    .stroke(
                        gold.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [7, 5])
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

/// 零星点缀版缝线：落在屏幕四角（贴角），每角一段圆角弧线，中间留白不做满
struct StitchAccent: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let inset: CGFloat = 7          // 贴屏幕圆角内缘（13 Pro 圆角≈47pt，顶点临界≈14pt）
            let arm: CGFloat = 36           // 从角沿两边延伸的长度
            let gold = Color(red: 0.831, green: 0.686, blue: 0.216) // #D4AF37 淡金色
            Canvas { ctx, _ in
                // 每角画一段圆角弧线：从一边端点弧到另一边端点，控制点在角点
                func corner(_ cornerPoint: CGPoint, _ p1: CGPoint, _ p2: CGPoint) {
                    var p = Path()
                    p.move(to: p1)
                    p.addQuadCurve(to: p2, control: cornerPoint)
                    ctx.stroke(p, with: .color(gold.opacity(0.9)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [5, 4]))
                }
                // 左上角
                corner(CGPoint(x: inset, y: inset),
                       CGPoint(x: inset, y: inset + arm),
                       CGPoint(x: inset + arm, y: inset))
                // 右上角
                corner(CGPoint(x: size.width - inset, y: inset),
                       CGPoint(x: size.width - inset - arm, y: inset),
                       CGPoint(x: size.width - inset, y: inset + arm))
                // 左下角
                corner(CGPoint(x: inset, y: size.height - inset),
                       CGPoint(x: inset, y: size.height - inset - arm),
                       CGPoint(x: inset + arm, y: size.height - inset))
                // 右下角
                corner(CGPoint(x: size.width - inset, y: size.height - inset),
                       CGPoint(x: size.width - inset, y: size.height - inset - arm),
                       CGPoint(x: size.width - inset - arm, y: size.height - inset))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environmentObject(ThoughtStore())
}

/// 14 条修复第 3 条：「蜂巢对你说」全文弹层 —— 首页卡片只截断展示，
/// 点「看全文」进来这里，把 message + points 完整铺开。
struct SuggestionFullSheet: View {
    let suggestion: HiveSuggestion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "hexagon.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(HiveTheme.amber)
                        Text("蜂巢对你说")
                            .font(.system(size: 13, weight: .bold))
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
                    Text(suggestion.message)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HiveTheme.textStrong)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                    if !suggestion.points.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(suggestion.points.enumerated()), id: \.offset) { idx, p in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(HiveTheme.amber)
                                        .frame(width: 22, height: 22)
                                        .background(HiveTheme.amber.opacity(0.15))
                                        .clipShape(Circle())
                                    Text(p)
                                        .font(.system(size: 14))
                                        .foregroundStyle(HiveTheme.textBody)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineSpacing(4)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            StitchAccent().allowsHitTesting(false)
        }
    }
}