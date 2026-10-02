import SwiftUI

// MARK: - 首页动态组件（扫描 / 数据流 / 主动问候 / 呼吸）
// 遵循设计规范第十二节·动效档位：
//   - 首页仅 HiveCore 能量球一处「呼吸」档（scale 0.9↔1.12）
//   - 扫描扇形 = 「扫描旋转」动效语言（规范第五节）
//   - 节点 / 数据流 / 问候点 = 「克制」档（低幅 opacity）
//   - 开场苏醒 = 「叙事」档（只播一次）
//
// 性能与可访问性（2026-09-11 状态轮）：
//   - ScanSweep 流光改用 TimelineView 时间驱动，锁 30fps，去掉 blur（最贵的高斯模糊），
//     滚动 / 退后台 / 减弱动态效果 时冻结（motionActive=false）
//   - 全部动效尊重「减弱动态效果」(Reduce Motion)：退化为静态

/// 扫描扇形：雷达旋转扫描（循环）
/// 流光最贵处在于逐帧 blur —— 已改为无 blur 的 AngularGradient 描边 + TimelineView 锁 30fps
struct ScanSweep: View {
    /// 动效总开关：退后台 / 滚动中 / 减弱动态效果 时为 false（冻结在当前位置）
    var motionActive: Bool = true
    /// 离线（有念头排队回家）：流光变蓝灰、周期变慢
    var offline: Bool = false

    @State private var startTime: TimeInterval = 0
    @State private var heldAngle: Double = 0
    private var cycle: Double { offline ? 9.0 : 7.0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let angle = motionActive ? scanAngle(at: now) : heldAngle
            sweep
                .rotationEffect(.degrees(angle))
        }
        .allowsHitTesting(false)
        .onAppear { startTime = Date().timeIntervalSinceReferenceDate }
        .onChange(of: motionActive) { _, active in
            let now = Date().timeIntervalSinceReferenceDate
            if active {
                // 恢复：从冻结角度继续，避免跳变
                let elapsed = (heldAngle / 360.0) * cycle
                startTime = now - elapsed
            } else {
                heldAngle = scanAngle(at: now)
            }
        }
        .onChange(of: offline) { _, _ in
            startTime = Date().timeIntervalSinceReferenceDate
            heldAngle = 0
        }
    }

    private func scanAngle(at now: TimeInterval) -> Double {
        ((now - startTime).truncatingRemainder(dividingBy: cycle) / cycle) * 360
    }

    private var sweep: some View {
        let sweepColor = offline ? HiveTheme.cold : HiveTheme.amber
        return ZStack {
            // 扇形主扫（亮）—— AngularGradient 自带渐隐，不再叠 blur
            Circle()
                .trim(from: 0.0, to: 0.12)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: sweepColor.opacity(0.75), location: 0.10),
                            .init(color: sweepColor.opacity(0.25), location: 0.12),
                            .init(color: .clear, location: 0.14),
                            .init(color: .clear, location: 1.0),
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 30, lineCap: .butt)
                )
            // 扫尾光点（轻量阴影）
            Circle()
                .fill(sweepColor)
                .frame(width: 5, height: 5)
                .shadow(color: sweepColor.opacity(0.7), radius: 6)
                .offset(y: -49)
        }
    }
}

/// 连接线数据流（流动虚线），from → to
struct FlowLine: Shape {
    var from: CGPoint
    var to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        return p
    }
}

/// 节点呼吸（克制档：低幅 opacity 呼吸）
/// 减弱动态效果时退化为静态（opacity 固定 1.0）
struct BreatheNode: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var delay: Double = 0
    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1.0 : (on ? 1.0 : 0.5))
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(delay)) {
                        on = true
                    }
                }
            }
    }
}

extension View {
    func breatheNode(delay: Double = 0) -> some View { modifier(BreatheNode(delay: delay)) }
}

/// 入口呼吸光效（问候语提到照片时拍照入口呼吸 2 秒；空状态时四入口面板呼吸）
/// 用 opacity + scale 做一个柔和的呼吸；减弱动效时退化为静态。
struct BreatheGlow: ViewModifier {
    var active: Bool
    var tint: Color
    var cornerRadius: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(tint.opacity(breath ? 0.9 : 0.2), lineWidth: 1.5)
                    .shadow(color: tint.opacity(breath ? 0.8 : 0.0), radius: breath ? 14 : 4)
            )
            .scaleEffect(breath ? 1.02 : 1.0)
            .onChange(of: active) { _, nowActive in
                guard !reduceMotion else { return }
                if nowActive {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        breath = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        breath = false
                    }
                }
            }
    }
}

/// 行星：绕蜂巢公转的小星球，明暗/颜色深浅随公转相位变化（模仿真实行星被恒星照亮）
/// 转到「向阳面」（正对蜂巢）时亮、颜色饱满；转到「背阴面」时暗、褪色。三颗相位错开 → 永远不重样。
/// 用 TimelineView 时间驱动：角度与明暗同步逐帧计算，才能让颜色随相位平滑起伏。
/// 减弱动态效果时退化为静态（固定在向阳最亮位，lit=1）。
struct Planet: View {
    let radius: CGFloat
    let duration: Double
    let delay: Double
    let size: CGFloat
    let tint: Color     // 向阳面亮色（行星本色）
    let shade: Color    // 背阴面暗色（朝外，渐暗）

    var motionActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor: TimeInterval = 0
    @State private var frozenPhase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let phase = phase(at: now)
            let angle = phase * 360
            // 明暗随相位起伏：正对蜂巢（phase 0）最亮 → 背对（phase 0.5）最暗
            let lit = (cos(2 * .pi * phase) + 1) / 2 // 0~1

            PlanetBody(size: size, tint: tint, shade: shade, lit: lit)
                .offset(y: -radius)
                .rotationEffect(.degrees(angle))
        }
        .onAppear { anchor = Date().timeIntervalSinceReferenceDate }
        .onChange(of: motionActive) { _, active in
            let now = Date().timeIntervalSinceReferenceDate
            if active {
                // 从冻结相位恢复，避免跳变
                anchor = now - (frozenPhase - delay / duration) * duration
            } else {
                frozenPhase = ((now - anchor) / duration + delay / duration).truncatingRemainder(dividingBy: 1)
            }
        }
    }

    private func phase(at now: TimeInterval) -> Double {
        if reduceMotion {
            return 0                       // 静态：固定向阳位（最亮）
        } else if motionActive {
            return ((now - anchor) / duration + delay / duration).truncatingRemainder(dividingBy: 1)
        } else {
            return frozenPhase              // 冻结在当前相位
        }
    }
}

/// 行星球体：受光面朝内，整体明暗/颜色深浅随 lit（0暗~1亮）变化
struct PlanetBody: View {
    let size: CGFloat
    let tint: Color
    let shade: Color
    let lit: Double

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: tint.opacity(0.28 + 0.72 * lit), location: 0.0),
                        .init(color: tint.opacity(0.14 + 0.42 * lit), location: 0.42),
                        .init(color: shade.opacity(0.10 + 0.36 * (1 - lit)), location: 0.78),
                        .init(color: shade.opacity(0.02 + 0.06 * (1 - lit)), location: 1.0),
                    ]),
                    center: UnitPoint(x: 0.5, y: 0.30), // 受光面朝内（指向蜂巢）
                    startRadius: 0,
                    endRadius: size
                )
            )
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.10 + 0.28 * lit), radius: 2.5)
    }
}

/// 主动问候气泡：打字机逐字 + 轮播，点击换一句（互动核心）
/// - 减弱动态效果：直接静态显示第一句，点击才换下一句，不逐字、不自动轮播（VoiceOver 友好）
/// - paused（录音中）：暂停自动轮播，避免打扰
struct ActiveGreeting: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = ""
    @State private var msgIndex = 0
    @State private var typeTask: Task<Void, Never>?

    /// 录音等「正在输入」时暂停自动轮播
    var paused: Bool = false

    /// P2-3：问候语提到「照片」时，置 true → 首页拍照入口呼吸 2 秒（每日首次）
    @Binding var photoGlow: Bool

    /// ④ 点击问候气泡 → 弹出「选择做什么」主题选择（而非换一句话）
    var onTapAction: (() -> Void)? = nil
    /// 每日首次限制：记录当天日期，同一天不再重复触发
    @AppStorage("hive.greet.photoGlowDay") private var glowDay = ""

    private var messages: [String] {
        let h = Calendar.current.component(.hour, from: Date())
        let greet: String
        switch h {
        case 5..<12: greet = String(localized: "早上好")
        case 12..<18: greet = String(localized: "下午好")
        case 18..<23: greet = String(localized: "晚上好")
        default: greet = String(localized: "夜深了")
        }
        return [
            String(localized: "\(greet)，今天想记点什么？"),
            String(localized: "把刚闪过的念头交给我吧"),
            String(localized: "有张照片、一段话想留住吗？"),
            String(localized: "我在听，随时可以存"),
            String(localized: "一句语音、一个地址，都能归档"),
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(HiveTheme.amber)
                .frame(width: 7, height: 7)
                .shadow(color: HiveTheme.amber.opacity(0.8), radius: 6)
            Text(displayed.isEmpty ? " " : displayed)
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(HiveTheme.holoTop)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.22), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture {
            if let onTapAction {
                onTapAction()
            } else if reduceMotion {
                showNextStatic()
            } else {
                restart()
            }
        }
        .onAppear {
            if reduceMotion {
                displayed = messages[0]
                msgIndex = 1
            } else {
                restart()
            }
        }
        .onDisappear { typeTask?.cancel() }
        .onChange(of: paused) { _, pausing in
            guard !reduceMotion else { return }
            if pausing {
                typeTask?.cancel()
            } else if displayed.isEmpty || typeTask == nil {
                restart()
            }
        }
    }

    /// P2-3：问候语提到「照片」时，给首页拍照入口一次琥珀呼吸（每日首次，减弱动效则跳过）
    private func maybeTriggerPhotoGlow(for message: String) {
        guard message.contains("照片") else { return }
        guard !reduceMotion else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        guard glowDay != today else { return }
        glowDay = today
        photoGlow = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            photoGlow = false
        }
    }

    private func showNextStatic() {
        displayed = messages[msgIndex]
        msgIndex = (msgIndex + 1) % messages.count
    }

    private func restart() {
        typeTask?.cancel()
        let full = messages[msgIndex]
        msgIndex = (msgIndex + 1) % messages.count
        maybeTriggerPhotoGlow(for: full)
        displayed = ""
        typeTask = Task { @MainActor in
            for ch in full {
                displayed.append(ch)
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)   // 4s 停留（原 3s，按清单节奏放缓）
            if !Task.isCancelled { restart() }
        }
    }
}
