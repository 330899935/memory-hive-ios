import SwiftUI

/// 规划页 —— 蜂巢「自主」第②步第三刀：独立规划/待办页
/// 借电脑大脑（/api/plan）产出「今日重点 + 待办清单 + 当前主线」，独立入口展示。
struct 规划页: View {
    @EnvironmentObject private var config: HiveConfig
    @State private var state: HivePlanService.PlanOutcome = .notReady
    @State private var plan: HivePlan?
    /// 14 条修复第 13 条：加加载态，首帧不再“白屏等”，让用户知道正在盘、不是卡死。
    @State private var loading = false

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            StitchAccent().allowsHitTesting(false)
        }
        .task {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEMORY HIVE · 规划")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(HiveTheme.amber)
            Text("规划")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(HiveTheme.textTitle)
            Text("蜂巢替你盘今天")
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textCaption)
        }
    }

    @MainActor
    private func load() async {
        loading = true
        state = await HivePlanService.plan(config: config)
        if case .ok(let p) = state { plan = p }
        loading = false
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().tint(HiveTheme.amber)
                Text("蜂巢正在盘…")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            switch state {
            case .ok(let p):
                if !p.focus.isEmpty {
                    focusCard(p.focus)
                }
                todosCard(p.todos)
                if !p.mainline.isEmpty {
                    mainlineCard(p.mainline)
                }
                refreshButton
            case .empty:
                quietCard(String(localized: "蜂巢还没记下待办"), symbol: "hexagon")
                refreshButton
            case .noKey:
                quietCard(String(localized: "大脑还没配钥匙，去设置里接上，我才能替你规划"), symbol: "key")
            case .offline:
                quietCard(String(localized: "连不上家，先存手机，回家我再看"), symbol: "wifi.slash")
            case .notReady:
                quietCard(String(localized: "先到设置里填好家地址和密钥"), symbol: "house")
            case .failed(let msg):
                quietCard(String(localized: "规划生成失败：\(msg)"), symbol: "exclamationmark.triangle")
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await load() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                Text("重新盘一遍")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(HiveTheme.amber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.5), lineWidth: 1))
            .background(HiveTheme.holoTop)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func focusCard(_ focus: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.amber)
                Text("今日重点")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HiveTheme.amber)
            }
            Text(focus)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func todosCard(_ todos: [HiveTodo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.green)
                Text("还没做完")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HiveTheme.green)
            }
            if todos.isEmpty {
                Text("今天没有明确的待办，想到什么随手记，蜂巢替你接着。")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(todos.enumerated()), id: \.element.id) { idx, todo in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(HiveTheme.amber)
                            .frame(width: 22, height: 22)
                            .background(HiveTheme.amber.opacity(0.15))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(todo.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(HiveTheme.textStrong)
                            if !todo.detail.isEmpty {
                                Text(todo.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(HiveTheme.textBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func mainlineCard(_ mainline: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.cyan)
                Text(HiveWarehouses.displayName(String(localized: "当前主线")))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HiveTheme.cyan)
            }
            Text(mainline)
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func quietCard(_ msg: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(HiveTheme.amber.opacity(0.5))
            Text(msg)
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textCaption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .holoCard()
    }
}

#Preview {
    规划页()
        .environmentObject(HiveConfig())
}
