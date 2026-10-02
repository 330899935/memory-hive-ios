import SwiftUI

/// 蜂巢专属粒子点阵图标（设计规范 v3 第六节「图标系统」）
/// 触角=三角点阵 · 存=竖排三点 · 问=竖排四点 · 家=聚拢五点（漏斗） · 首页=六边形点阵 · 设置=齿轮点阵
/// 用归一化坐标 + 半径描述，自适应尺寸；点阵即图标，发光即选中（暗夜琥珀语义）。
/// 2026-09-11：外脑 #3「底部图标自绘蜂巢专属视觉」，替换通用 SF Symbols。
/// 2026-09-18：新增 `.inbox`（家/收件箱）—— 家页接进 tab 导航后需要一个与首页六边形明显区分的图标。

/// 单个粒子点：归一化坐标（0-1）+ 半径（相对 1 的比值）
struct ParticleDot {
    let x: CGFloat
    let y: CGFloat
    let r: CGFloat
}

enum HiveTabGlyph {
    case home      // 首页 · 蜂巢本体 → 六边形点阵
    case save      // 存 → 竖排三点
    case ask       // 问 → 竖排四点
    case inbox     // 家 · 收件箱 → 聚拢五点（念头从上方两点收进底部一点）
    case antenna   // 触角 → 三角点阵（顶点在上）
    case settings  // 设置 → 齿轮点阵（外圈 6 点 + 中心 1 点）

    var dots: [ParticleDot] {
        switch self {
        case .save: // 竖排三点（上小 / 中大 / 下小，SVG 定稿比例）
            return [
                ParticleDot(x: 0.5, y: 0.20, r: 0.10),
                ParticleDot(x: 0.5, y: 0.50, r: 0.12),
                ParticleDot(x: 0.5, y: 0.80, r: 0.09),
            ]
        case .ask: // 竖排四点（间距拉大防视觉合并，与「存」三点区分）
            return [
                ParticleDot(x: 0.5, y: 0.08, r: 0.085),
                ParticleDot(x: 0.5, y: 0.36, r: 0.10),
                ParticleDot(x: 0.5, y: 0.64, r: 0.10),
                ParticleDot(x: 0.5, y: 0.92, r: 0.085),
            ]
        case .inbox: // 聚拢五点：上两点（投进来的）→ 中两点（收拢）→ 底一点（落到家）
            // 与首页六边形（6 点环）、触角三角（上 1 下 2）形状与朝向都不同，小尺寸下可区分
            return [
                ParticleDot(x: 0.26, y: 0.16, r: 0.085),
                ParticleDot(x: 0.74, y: 0.16, r: 0.085),
                ParticleDot(x: 0.36, y: 0.50, r: 0.085),
                ParticleDot(x: 0.64, y: 0.50, r: 0.085),
                ParticleDot(x: 0.50, y: 0.86, r: 0.105),
            ]
        case .antenna: // 三角点阵（顶点在上，底边两点）
            return [
                ParticleDot(x: 0.50, y: 0.16, r: 0.13),
                ParticleDot(x: 0.24, y: 0.72, r: 0.10),
                ParticleDot(x: 0.76, y: 0.72, r: 0.10),
            ]
        case .home: // 六边形点阵（蜂巢格：顶 / 左上 / 右上 / 左下 / 右下 / 底，居中均衡）
            return [
                ParticleDot(x: 0.50, y: 0.14, r: 0.085),
                ParticleDot(x: 0.24, y: 0.38, r: 0.085),
                ParticleDot(x: 0.76, y: 0.38, r: 0.085),
                ParticleDot(x: 0.24, y: 0.62, r: 0.085),
                ParticleDot(x: 0.76, y: 0.62, r: 0.085),
                ParticleDot(x: 0.50, y: 0.86, r: 0.085),
            ]
        case .settings: // 齿轮点阵：外圈 8 齿（45° 均匀）+ 中心点，与首页 6 点六边形明显区分
            let cx: CGFloat = 0.5, cy: CGFloat = 0.5
            let radius: CGFloat = 0.30
            var dots = [ParticleDot(x: cx, y: cy, r: 0.06)]
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                dots.append(ParticleDot(x: cx + radius * sin(angle), y: cy - radius * cos(angle), r: 0.065))
            }
            return dots
        }
    }
}

/// 粒子点阵图标：把一组归一化圆点画成图标，选中态用琥珀 + 发光，未选中态灰。
struct ParticleIcon: View {
    let glyph: HiveTabGlyph
    let color: Color

    private let size: CGFloat = 24

    var body: some View {
        ZStack {
            ForEach(Array(glyph.dots.enumerated()), id: \.offset) { _, dot in
                Circle()
                    .fill(color)
                    .frame(width: dot.r * 2 * size, height: dot.r * 2 * size)
                    .position(x: dot.x * size, y: dot.y * size)
                    .shadow(color: color.opacity(0.6), radius: dot.r * size * 1.4)
            }
        }
        .frame(width: size, height: size)
    }
}
