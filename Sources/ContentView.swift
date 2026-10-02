import SwiftUI
import UIKit

/// 根导航：自定义底部 Tab 栏（去等级 / 本体退守后台 / 去自我中心）
/// 2026-09-11：改用自绘 TabBar —— iOS 26 Liquid Glass 的 .badge() 颜色强制系统红，
/// 无法随暗夜琥珀主题，自绘角标为琥珀色，消除「红尾巴」。
/// 底部 Tab 的身份标识（解 R1：**身份与中文显示名解耦**）
///
/// 旧写法把「中文显示名」同时当状态标识、屏幕文字、角标判据 —— 一切换语言状态全乱。
/// 现在：**状态比较一律用 enum，显示名走文案层** `title`（`HiveCopy.tabTitle`）。
enum HiveTab: String, CaseIterable, Identifiable {
    case home, save, inbox, ask, antenna, settings

    var id: String { rawValue }

    /// 显示名（随语言）。**只用于界面显示，绝不参与状态比较。**
    var title: String { HiveCopy.tabTitle(self) }
}

struct ContentView: View {
    @State private var selectedTab: HiveTab = .home

    /// 读一次语言设置，让**根视图在语言变化时重算整棵树**。
    ///
    /// ⚠️ 光挂属性包装器**不够**（2026-09-18 第二阶段任务5 查明的坑）：
    /// `@AppStorage` 变化确实会让本 `body` 重算，但**子视图是「无存储属性的 struct」**
    /// （`家页()` / `问页()` / `设置页()` 全是 `Xxx()` 形态）—— SwiftUI 比对后判定"值没变"，
    /// **会跳过它们的 `body`**，于是 `HiveLang.current` 永远不会被重新读 ⇒ 界面不刷。
    /// ⇒ 必须配 `.id(langRaw)` 显式**换身份**、强制重建子树（见下方 Group）。
    /// 代价：子树里的 `@State`（滚动位置 / 输入焦点）会被重置 —— 切语言时这个代价可接受。
    @AppStorage(HiveLang.defaultsKey) private var langRaw: String = ""
    @StateObject private var store = ThoughtStore()
    @StateObject private var config = HiveConfig()
    @Environment(\.scenePhase) private var scenePhase

    /// 键盘是否弹出：弹出时隐藏底部 Tab 栏（P0-1 · 输入路径不顺 = 全盘不顺）
    @State private var keyboardVisible = false

    /// 待同步角标数（存 tab 上的琥珀小角标，提醒「还有念头没送回家」）
    private var pendingBadge: Int {
        store.thoughts.filter { !$0.synced }.count
    }

    /// 收件箱角标数（家 tab）：**家里候选区**的待确认条数（服务端口径，不是本机口径）
    /// 2026-09-18 家页体验指令书 P1-1。
    @State private var inboxBadge = 0
    /// 上一次取收件箱的时间 —— 给「补一次」设节流，避免请求风暴
    @State private var inboxFetchedAt = Date.distantPast

    var body: some View {
        Group {
            switch selectedTab {
            case .save: 存页()
            case .inbox: 家页()
            case .ask: 问页()
            case .antenna: 触角页()
            case .settings: 设置页()
            case .home: HomeView(selectedTab: $selectedTab)
            }
        }
        // 换语言时强制重建子树（理由见 `langRaw` 上的注释）。
        // ⚠️ 只挂在 Group 上：`store`/`config`/`selectedTab` 都是本视图自己的 @State/@StateObject，不受影响。
        .id(langRaw)
        // iPad 限宽居中（2026-09-19）：iPad 满屏铺开内容太散不好看，限宽居中；
        // 值取 700（非 560）：触角体检实测 560 时两侧黑槽 143pt、底栏首格与内容左沿错位 73pt；
        // 700 时黑槽收窄到 67pt×2、底栏首格 69.5pt 与内容左沿 67pt 基本对齐。
        // 真·双栏 / 窗口化迁移 = 上架后 v0.2 路线图，见触角《手机版平板适配体检_20260919》。
        .frame(maxWidth: 700)
        .contentShape(Rectangle())
        .simultaneousGesture(tabSwipeGesture)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 键盘弹出全程 Tab 栏不可见，避免被键盘顶起上下弹跳；失焦后淡入恢复
            if !keyboardVisible {
                HiveTabBar(selectedTab: $selectedTab,
                           pendingBadge: pendingBadge,
                           inboxBadge: inboxBadge)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboardVisible)
        .environmentObject(store)
        .environmentObject(config)
        .tint(HiveTheme.amber)
        .preferredColorScheme(.dark)
        // 家 tab 角标：首帧取一次；之后**家页自己会广播**（它一进页/一归档就发），
        // 这里不再另开轮询，只有「冷启动」和「回前台」两个补数点
        .task { await refreshInboxBadge(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: .hiveInboxChanged)) { note in
            // 家页读了/改了收件箱 → 直接采信它的数字（它手里是权威列表，省一次请求）
            if let n = note.userInfo?["count"] as? Int {
                inboxBadge = n
                inboxFetchedAt = Date()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        // ②第二刀：App 回前台时，蜂巢看时机拍肩膀（每日一次冷却，开关关/无权限/离线则静默）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { @MainActor in
                    _ = await HiveNotificationService.deliverSuggestionIfDue(config: config)
                }
                // 回前台顺手补一次收件箱数字（节流 60s）—— 电脑端在那头归档/拒绝过，这里要跟上
                Task { await refreshInboxBadge() }
                // 三态闭环（2026-09-18）：电脑端在那头确认归巢过 → 回查本机「待确认」念头，
                // 命中就落「已归档」终态。失败静默（checkArchived 兜底空集，不会误标）。
                Task { await HiveSyncService.refreshArchived(store: store, config: config) }
            }
        }
    }

    // MARK: - 收件箱角标取数

    /// 取一次收件箱条数刷新「家」tab 角标。
    /// - 失败**保留上次数字**：把「连不上」显示成 0 会被读成「收件箱是空的」，那是假消息
    /// - 只有冷启动（force）与回前台会走这里；日常进出家页由家页自己广播
    private func refreshInboxBadge(force: Bool = false, minInterval: TimeInterval = 60) async {
        guard config.isReady else {
            inboxBadge = 0
            return
        }
        if !force, Date().timeIntervalSince(inboxFetchedAt) < minInterval { return }
        inboxFetchedAt = Date()
        if case .ok(let list) = await HivePendingService.list(config: config) {
            inboxBadge = list.count
        }
    }

    // MARK: - 左右滑切 Tab（横向手势切页，像上下滑一样丝滑）
    /// 「家」放在「存」与「问」之间：收件箱是「等确认」的入口，跟「存」最近
    /// ⚠️ 顺序即 `HiveTab.allCases` 声明序，与 `HiveTabBar` 共用同一份 ⇒ 不可能再对不上
    private let tabOrder = HiveTab.allCases

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // 只认「明显横向」的滑动，纵向滚动不触发；横向位移需超过纵向 1.2 倍且 > 60pt
                guard abs(dx) > abs(dy) * 1.2, abs(dx) > 60 else { return }
                if dx < 0 {
                    switchToNext()
                } else {
                    switchToPrev()
                }
            }
    }

    private func switchToNext() {
        guard let idx = tabOrder.firstIndex(of: selectedTab),
              idx < tabOrder.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tabOrder[idx + 1]
        }
    }

    private func switchToPrev() {
        guard let idx = tabOrder.firstIndex(of: selectedTab),
              idx > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tabOrder[idx - 1]
        }
    }
}

/// 自绘底部导航栏：暗夜琥珀风格，角标随主题（琥珀底 + 深色字），不再用系统红
/// 图标用蜂巢专属粒子点阵（HiveTabGlyph），替换通用 SF Symbols（外脑 #3）。
struct HiveTabBar: View {
    @Binding var selectedTab: HiveTab
    let pendingBadge: Int
    /// 家 tab 角标：家里候选区待确认条数（0 = 不显示）
    var inboxBadge: Int = 0

    private struct TabItem: Identifiable {
        let id: HiveTab
        let glyph: HiveTabGlyph
    }

    /// 与 `HiveTab.allCases` 同序同项（自带图标映射，插 case 时这里要同步补）
    private let tabs: [TabItem] = [
        TabItem(id: .home, glyph: .home),
        TabItem(id: .save, glyph: .save),
        TabItem(id: .inbox, glyph: .inbox),
        TabItem(id: .ask, glyph: .ask),
        TabItem(id: .antenna, glyph: .antenna),
        TabItem(id: .settings, glyph: .settings),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selectedTab = tab.id
                } label: {
                    tabLabel(tab)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [HiveTheme.holoTop, HiveTheme.holoBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HiveTheme.amber.opacity(0.16))
                .frame(height: 0.5)
        }
    }

    private func tabLabel(_ tab: TabItem) -> some View {
        let active = selectedTab == tab.id
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ParticleIcon(
                    glyph: tab.glyph,
                    color: active ? HiveTheme.amber : HiveTheme.textCaption
                )
                .frame(width: 44, height: 30)

                if tab.id == .save { badge(pendingBadge) }
                // 家 tab 用同一套角标样式（琥珀底 + 深色字），语义：收件箱还有几条等你点头
                if tab.id == .inbox { badge(inboxBadge) }
            }
            Text(tab.id.title)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? HiveTheme.amber : HiveTheme.textCaption)
        }
        .animation(.easeInOut(duration: 0.18), value: active)
    }

    /// 角标（0 不画）：琥珀底 + 深色字，不用系统红
    @ViewBuilder
    private func badge(_ n: Int) -> some View {
        if n > 0 {
            Text("\(n)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(HiveTheme.bgVoid)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(HiveTheme.amber)
                .clipShape(Capsule())
                .shadow(color: HiveTheme.amber.opacity(0.5), radius: 4)
                .offset(x: 14, y: -6)
        }
    }
}

#Preview {
    ContentView()
}
