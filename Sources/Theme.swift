import SwiftUI

/// 暗夜琥珀 · 设计令牌（Design System v3）
/// 来源：手机版视觉规范_DesignSystem_v1.md（v3 定稿）
enum HiveTheme {
    // 底色
    static let bgVoid = Color(hex: 0x050505)
    static let gridHex = Color(hex: 0xFFB84D).opacity(0.07)   // P1-1：底纹压到 7%，不跟内容抢戏

    // 高亮（琥珀）
    static let amber = Color(hex: 0xFFB84D)
    static let amberDeep = Color(hex: 0xC97E0E)
    static let amberLight = Color(hex: 0xFFD9A0)

    // 功能色
    static let cyan = Color(hex: 0x6B9FFF)
    static let green = Color(hex: 0x4C9B83)
    static let red = Color(hex: 0xE05A4F)
    static let purple = Color(hex: 0xB48CFF)
    static let cold = Color(hex: 0xBCC2CC)

    // 文字灰阶
    static let textTitle = Color(hex: 0xF5F1E8)
    static let textStrong = Color(hex: 0xD8D1C2)   // 强调/卡片正文：柔和暖灰（原 0xE8E2DA 过亮眩光，已降）
    static let textBody = Color(hex: 0xC4BCAC)      // 大段正文专用：更柔的暖灰，暗底可读不刺眼
    static let textSecondary = Color(hex: 0xB0AA9C)
    static let textCaption = Color(hex: 0x9E978A)
    static let textMuted = Color(hex: 0x6B6350)

    // 玻璃面板
    static let holoTop = Color(hex: 0x100E0B).opacity(0.86)
    static let holoBottom = Color(hex: 0x060504).opacity(0.72)

    // 缝线内容安全区（老铁 2026-09-10 定：文字/文案收入缝线内，间距协调，不突兀不脱节）
    static let contentInset: CGFloat = 24   // 内容水平内边距（首页缝线净空 18pt / 其余页角弧线净空 ≥17pt）
    static let contentTop: CGFloat = 16     // 内容顶部内边距
    static let contentBottom: CGFloat = 40  // 内容底部内边距
}

extension Color {
    /// 从 RGB 十六进制构造颜色
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// 全息玻璃卡片背景
struct HoloCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [HiveTheme.holoTop, HiveTheme.holoBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [HiveTheme.amber.opacity(0.55), HiveTheme.amberDeep.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 14)
    }
}

extension View {
    func holoCard() -> some View { modifier(HoloCard()) }
}

/// 底部渐隐幕布：让滚动内容在靠近底部缝线前沉回黑暗，避免硬切/撞线（呼应「巢沉回黑暗」）
struct HiveBottomFade: View {
    var height: CGFloat = 160
    var body: some View {
        VStack {
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: HiveTheme.bgVoid.opacity(0), location: 0.0),
                    .init(color: HiveTheme.bgVoid.opacity(1.0), location: 0.5),
                    .init(color: HiveTheme.bgVoid.opacity(1.0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 文案层（中英双译 · 第一阶段）

/// App 语言（第一阶段：zh-Hans / en 两态）
///
/// 单一来源 = `UserDefaults("hive.lang")`；**未设置时跟随系统首选语言**（zh 开头 → 中文）。
/// ⚠️ 本工程当前**没有**任何本地化资源（无 `.xcstrings` / `.lproj` / `.strings`，pbxproj 未注册）
/// ⇒ 语言由 App 自管，**不走系统 `String(localized:)`**；改走系统本地化必须先动工程文件（待主巢裁）。
enum HiveLang: String, CaseIterable {
    case zhHans = "zh-Hans"
    case en = "en"

    static let defaultsKey = "hive.lang"

    /// 当前语言：先看 App 内设置，再跟随系统首选语言
    static var current: HiveLang {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let lang = HiveLang(rawValue: raw) {
            return lang
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .zhHans : .en
    }

    /// 切换语言（写 `UserDefaults` 即持久化）。第二阶段已接 UI 入口（设置页「语言」卡）。
    ///
    /// ⚠️ **必须同时写 `AppleLanguages`**（2026-09-18 第二阶段任务5 查明的关键点）：
    /// - `HiveCopy`（Tab 名 / 仓名 / 状态词）读的是本文件的 `HiveLang.current` ⇒ 只写 `defaultsKey` 就够。
    /// - 但**390 条 String Catalog 文案**（`Text("中文")` / `String(localized:)`）走的是
    ///   **`Bundle.main` 的本地化选择**，而 Bundle 只看 `AppleLanguages`，**不认 `hive.lang`**
    ///   ⇒ 只写 `defaultsKey` 会得到「Tab 栏英文、正文中文」的半吊子态（正是最该避免的中英混排）。
    /// - `AppleLanguages` 写在**本 App 自己的 UserDefaults 沙盒里**，只影响本 App，不污染系统设置。
    static func set(_ lang: HiveLang) {
        UserDefaults.standard.set(lang.rawValue, forKey: defaultsKey)
        UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
    }
}

/// 文案层（B 层）：收口**被代码依赖**的三类文案 —— ① Tab 名 ② 仓名显示 ③ 核心状态词。
///
/// 为什么必须有这一层：这三类的值**既当显示、又被代码判断或拼参数**，散着放就切不了语言。
/// 后续批量翻译轮（441 处纯展示文案）走资源本地化，**本层只留这三类**。
enum HiveCopy {

    // MARK: ① Tab 名（配 enum HiveTab）

    private static let tabTitles: [HiveLang: [HiveTab: String]] = [
        .zhHans: [.home: "首页", .save: "存", .inbox: "家",
                  .ask: "问", .antenna: "触角", .settings: "设置"],
        .en: [.home: "Home", .save: "Save", .inbox: "Inbox",
              .ask: "Ask", .antenna: "Antenna", .settings: "Settings"],
    ]

    static func tabTitle(_ tab: HiveTab, _ lang: HiveLang = .current) -> String {
        tabTitles[lang]?[tab] ?? tab.rawValue
    }

    // MARK: ② 仓名显示（委托 HiveWarehouses.displayName —— 映射表只有一份）

    static func warehouseName(_ raw: String, _ lang: HiveLang = .current) -> String {
        HiveWarehouses.displayName(raw, lang)
    }

    // MARK: ③ 核心状态词（定稿三态 · 单一来源）

    /// ⚠️ 界面**只能**读这里（经 `PendingThought.stage.label`），禁止别处硬编码同义词
    /// 英文侧 = 主巢 2026-09-18 晚「系统最优版」定稿（「待同步」原拟 To sync，语法别扭，改用 Pending）
    static func stageLabel(_ stage: ThoughtStage, _ lang: HiveLang = .current) -> String {
        switch stage {
        case .local:           return lang == .zhHans ? "待同步" : "Pending"
        case .awaitingConfirm: return lang == .zhHans ? "待确认" : "To confirm"
        case .archived:        return lang == .zhHans ? "已归档" : "Archived"
        }
    }

    // MARK: ④ 动态 key 取值（2026-09-18 中英双译第二阶段）

    /// 给「文案是**变量**」的场合用。查的是同一张 `Localizable` 表。
    ///
    /// ⚠️⚠️ **本轮改造后已无调用点，默认别再用它** —— 理由是一条真事故：
    /// 「变量 key」只有在**该 key 已存在于表里**时才查得到。而一只只在
    /// 声明位/比较位出现的中文串（本次是家页筛选条的「全部」）**编译器抽不到**，
    /// 表里没这条 ⇒ `dyn` 查空 ⇒ 原样回吐中文 ⇒ 英文界面冒中文（中英混排，截图抓到）。
    ///
    /// **首选做法**：把「显示值」写成 `String(localized: "字面量")` 显式传进视图
    /// （`HomeCandidateView.filterChip(raw:display:count:selected:)`、
    /// `AskView.modeChip(title:icon:active:action:)` 现在都是这个形），
    /// 编译器就能抽取该 key，**从根上不可能漏**，也不用手工补表。
    ///
    /// 同理，**身份判断不许拿文案去比**：`title == "问蜂巢"` 这种写法在译文一变就失效
    /// （本轮修掉一个：英文态 sparkles 图标凭空消失）⇒ 改成显式参数（`icon:`）。
    ///
    /// 保留本函数仅作兜底（将来若显示值确实只能以变量形态到达、且该 key 已在表内）。
    static func dyn(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
