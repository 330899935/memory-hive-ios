import SwiftUI

/// 触角详情页 —— 发卡 / 权限 / 熔断 / 吊销
/// 视觉语言：审计四件套 + 星球头像（按 agent.type 映射品牌色）
/// 命脉「连」第二腿：熔断/解熔断 + 吊销/删除，全部接真实后端动作
struct 触角详情页: View {
    let agent: HiveAgent
    @EnvironmentObject private var config: HiveConfig

    @State private var busy = false
    @State private var statusText = ""

    /// P1-4：权限页双层——默认用户层人话，点开「技术详情」折叠保留原始权限码
    @State private var showTechDetail = false

    // 确认弹窗
    @State private var confirmAction: ConfirmAction?

    enum ConfirmAction: Identifiable {
        case fuse
        case unfuse
        case revoke
        case delete

        var id: String {
            switch self {
            case .fuse: return "fuse"
            case .unfuse: return "unfuse"
            case .revoke: return "revoke"
            case .delete: return "delete"
            }
        }
    }

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    identityCard
                    issueCard
                    permissionCard
                    fuseCard
                    actionButtons
                    statusFooter
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            StitchAccent().allowsHitTesting(false)
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(confirmButtonLabel, role: .destructive) {
                let action = confirmAction
                confirmAction = nil
                Task { await perform(action) }
            }
            Button("取消", role: .cancel) {
                confirmAction = nil
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEMORY HIVE · 触角详情")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(HiveTheme.amber)
            Text("触角详情")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(HiveTheme.textTitle)
        }
    }

    // MARK: - 身份卡
    private var identityCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [agent.avatarColor, agent.avatarColor.opacity(0.45)],
                            center: .center, startRadius: 2, endRadius: 28
                        )
                    )
                    .frame(width: 56, height: 56)
                Circle()
                    .stroke(agent.avatarColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.displayName.isEmpty || agent.displayName == "?" ? agent.agentId : agent.displayName)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(HiveTheme.textTitle)
                Text("触角 · \(agent.typeLabel)")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textSecondary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(agent.statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: agent.statusColor.opacity(0.8), radius: 4)
                    Text(agent.statusLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(agent.statusColor)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    // MARK: - 发卡信息
    private var issueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "发卡信息"))
            fieldRow(String(localized: "名字（ID）"), value: agent.agentId, copy: false)
            fieldRow(String(localized: "钥匙"), value: "••••••••••••", copy: false)
            Text("注册于 \(shortDate(agent.registeredAt)) · 钥匙发卡时只显示一次")
                .font(.system(size: 11))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func shortDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso.isEmpty ? "—" : iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(HiveTheme.textStrong)
    }

    private func fieldRow(_ label: String, value: String, copy: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(HiveTheme.textCaption)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(HiveTheme.textStrong)
        }
    }

    // MARK: - 权限（用户层人话 + 工程层折叠）
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "这个触角能干什么"))

            // 用户层（默认）：人话，非技术朋友能复述
            if agent.allowedActions.isEmpty {
                permRow(symbol: "minus.circle.fill", color: HiveTheme.textMuted, text: String(localized: "没有额外授权"))
            } else {
                ForEach(agent.allowedActions, id: \.self) { a in
                    permRow(symbol: "checkmark.circle.fill", color: HiveTheme.green, text: ActionPhrase.allow(a))
                }
            }
            ForEach(agent.deniedActions, id: \.self) { a in
                permRow(symbol: "xmark.circle.fill", color: HiveTheme.red, text: ActionPhrase.deny(a))
            }
            permRow(symbol: "lock.fill", color: HiveTheme.purple, text: String(localized: "读不到你的隐私区（个人 · 财务 · 关系 · 私事）"))

            // 工程层（折叠）：原始权限码
            Button {
                showTechDetail.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("技术详情")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: showTechDetail ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(HiveTheme.textMuted)
            }
            .buttonStyle(.plain)

            if showTechDetail {
                fieldRow("allowed_actions", value: agent.allowedActions.isEmpty ? "—" : agent.allowedActions.joined(separator: ", "), copy: false)
                fieldRow("denied_actions", value: agent.deniedActions.isEmpty ? "—" : agent.deniedActions.joined(separator: ", "), copy: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .holoCard()
    }

    private func permRow(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textSecondary)
        }
    }

    // MARK: - 熔断
    private var fuseCard: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(HiveTheme.red)
                .frame(width: 3)
                .cornerRadius(1.5)
            VStack(alignment: .leading, spacing: 4) {
                Text("一键熔断")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(HiveTheme.textStrong)
                Text(agent.status == "fused" ? String(localized: "已熔断 · 点开关解除") : String(localized: "锁定单个触角 · 不影响其他"))
                    .font(.system(size: 11))
                    .foregroundStyle(HiveTheme.textCaption)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { agent.status == "fused" },
                set: { newValue in
                    confirmAction = newValue ? .fuse : .unfuse
                }
            ))
            .labelsHidden()
            .tint(HiveTheme.red)
            .disabled(busy)
        }
        .padding(16)
        .holoCard()
    }

    // MARK: - 底部按钮
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                confirmAction = .revoke
            } label: {
                Text("吊销")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HiveTheme.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(HiveTheme.holoTop)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(HiveTheme.amber.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(busy || agent.status == "revoked")

            Button {
                confirmAction = .delete
            } label: {
                Text("删除")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(HiveTheme.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private var statusFooter: some View {
        Group {
            if busy {
                HStack(spacing: 8) {
                    ProgressView().tint(HiveTheme.amber)
                    Text("处理中...")
                        .font(.system(size: 12))
                        .foregroundStyle(HiveTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            } else if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - 确认弹窗文案
    private var confirmTitle: String {
        switch confirmAction {
        case .fuse: return String(localized: "熔断这个触角？")
        case .unfuse: return String(localized: "解除熔断？")
        case .revoke: return String(localized: "吊销这个触角？")
        case .delete: return String(localized: "彻底删除这个触角？")
        case nil: return ""
        }
    }

    private var confirmButtonLabel: String {
        switch confirmAction {
        case .fuse: return String(localized: "熔断")
        case .unfuse: return String(localized: "解除熔断")
        case .revoke: return String(localized: "吊销")
        case .delete: return String(localized: "删除")
        case nil: return ""
        }
    }

    private var confirmMessage: String {
        switch confirmAction {
        case .fuse: return String(localized: "熔断后该触角立即停止工作，任务会转移到备用触角（若有）。")
        case .unfuse: return String(localized: "解除后该触角恢复在线。")
        case .revoke: return String(localized: "吊销后令牌失效，记录保留（可查），主触角不可吊销。")
        case .delete: return String(localized: "删除会彻底移除记录，不可恢复。")
        case nil: return ""
        }
    }

    // MARK: - 动作
    @MainActor
    private func perform(_ action: ConfirmAction?) async {
        guard let action else { return }
        busy = true
        statusText = ""
        let result: HiveAgentService.ActionResult
        switch action {
        case .fuse:
            result = await HiveAgentService.fuseAgent(agentId: agent.agentId, reason: "手机版手动熔断", config: config)
        case .unfuse:
            result = await HiveAgentService.unfuseAgent(agentId: agent.agentId, config: config)
        case .revoke:
            result = await HiveAgentService.revokeAgent(agentId: agent.agentId, config: config)
        case .delete:
            result = await HiveAgentService.deleteAgent(agentId: agent.agentId, config: config)
        }
        busy = false
        switch result {
        case .ok(let msg):
            statusText = msg
            HiveHaptics.success()
        case .offline:
            statusText = String(localized: "连不上家，稍后再试")
        case .notReady:
            statusText = String(localized: "先去设置页填「家地址 + 密钥」")
        case .failed(let msg):
            statusText = msg
        }
    }
}

// MARK: - 权限码 → 人话翻译（P1-4 用户层）
/// 把后端的工程权限码翻译成用户能复述的话。未知码回退到原文，绝不吞掉信息。
enum ActionPhrase {
    static func allow(_ code: String) -> String {
        switch code {
        case "ingest": return String(localized: "能存东西进来（把记忆写进你的巢）")
        case "nest": return String(localized: "能筑巢（归集你的记忆）")
        case "approve": return String(localized: "能确认归档")
        case "gatekeeper": return String(localized: "能当守门员")
        case "config": return String(localized: "能改配置")
        case "read": return String(localized: "能读公开记忆")
        default: return code
        }
    }

    static func deny(_ code: String) -> String {
        switch code {
        case "ingest": return String(localized: "不能存东西进来")
        case "nest": return String(localized: "不能动你的巢")
        case "approve": return String(localized: "不能改你的规则")
        case "gatekeeper": return String(localized: "不能当守门员")
        case "config": return String(localized: "不能碰你的配置")
        case "read": return String(localized: "读不到公开记忆")
        default: return String(localized: "不能执行 \(code)")
        }
    }
}

// MARK: - 橙色品牌色（补充到主题外）
extension HiveTheme {
    static let orange = Color(red: 0.878, green: 0.482, blue: 0.310) // #E07B4F Claude 橙
}

#Preview {
    触角详情页(agent: HiveAgent(agentId: "claude_main", displayName: "Claude", type: "mcp", level: "C", status: "active", registeredAt: "2026-08-16T00:00:00Z", role: "", note: "", allowedActions: ["ingest"], deniedActions: ["nest", "approve"]))
        .environmentObject(HiveConfig())
}
