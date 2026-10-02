import SwiftUI

/// 使用说明书 —— 设置页整合说明书（真机清单 ㉖）
/// 竖排功能表，每项一个名称，点一下展开大白话说明（学其他 app 的「设置+说明书」合一）
struct HiveManualSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [ManualSection] = [
        ManualSection(symbol: "link", tint: HiveTheme.green,
                      title: String(localized: "家连接"),
                      oneLine: String(localized: "手机连上电脑里的蜂巢"),
                      detail: String(localized: "手机和电脑上的蜂巢连起来，你的念头才能存进电脑里的「家」。在设置页扫电脑蜂巢的二维码（扫不到就手输局域网地址，如 192.168.x.x:8768），再输电脑上显示的 6 位配对码，就接上了。")),
        ManualSection(symbol: "house.and.flag", tint: HiveTheme.amber,
                      title: String(localized: "远程回家"),
                      oneLine: String(localized: "出门也能投喂回家 · 不存云端"),
                      detail: String(localized: "出门在外也能把记忆投喂回家。家里电脑开着 → 直接送回家；电脑关了 → 先存手机，回家开机自动送回家。全程不存云端，记忆始终在你自己的电脑里。")),
        ManualSection(symbol: "lock.shield", tint: HiveTheme.purple,
                      title: String(localized: "隐私区"),
                      oneLine: String(localized: "四个加密仓库，锁死你的敏感记忆"),
                      detail: String(localized: "个人、财务、关系、私事，四个加密仓库。存进来的敏感信息自动锁死加密，连你信任的 AI 触角都读不到，只有你在电脑端解锁后才能看。")),
        ManualSection(symbol: "bolt.slash", tint: HiveTheme.red,
                      title: String(localized: "熔断"),
                      oneLine: String(localized: "一键掐断某个触角"),
                      detail: String(localized: "一键掐断某个触角的投稿通道。断开后它送不进东西，需要时随时恢复，不影响其他触角。适合临时停用某个 AI 时用。")),
        ManualSection(symbol: "checkmark.seal", tint: HiveTheme.green,
                      title: String(localized: "自动备份"),
                      oneLine: String(localized: "每天快照 · 误删能找回"),
                      detail: String(localized: "每天自动把你的记忆完整快照一份，存 10 份在电脑里，误删了随时能找回。")),
        ManualSection(symbol: "hexagon", tint: HiveTheme.amber,
                      title: String(localized: "关于"),
                      oneLine: String(localized: "记忆蜂巢 · 手机版"),
                      detail: String(localized: "记忆蜂巢手机版，是电脑蜂巢的延伸，不是替身。帮你在外面也能随手接住念头、送回家。永不上云。")),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(sections) { s in
                    sectionCard(s)
                }
            }
            .padding(20)
        }
        .background(HiveTheme.bgVoid)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("蜂巢说明书")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(HiveTheme.textTitle)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(HiveTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            Text("每个功能是什么、怎么用，点一下看明白")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .padding(.bottom, 4)
    }

    private func sectionCard(_ s: ManualSection) -> some View {
        DisclosureGroup {
            Text(s.detail)
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 6)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: s.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(s.tint)
                    .frame(width: 26, height: 26)
                    .background(s.tint.opacity(0.14))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(HiveTheme.textStrong)
                    Text(s.oneLine)
                        .font(.system(size: 11))
                        .foregroundStyle(HiveTheme.textCaption)
                }
            }
            .padding(.vertical, 4)
        }
        .tint(HiveTheme.amber)
        .padding(16)
        .background(HiveTheme.holoTop)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HiveTheme.amber.opacity(0.18), lineWidth: 1))
    }
}

private struct ManualSection: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    let oneLine: String
    let detail: String
}
