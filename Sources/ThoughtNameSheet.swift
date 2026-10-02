import SwiftUI

/// 记忆改名弹层 —— 详情页「改名 / 写摘要」入口打开（ThoughtDetailSheet 复用本层，不另造）
/// 2026-09-18（任务 B）：拍照/选图/录音后**不再必弹**本层，落库即走，
/// 名字/摘要/分仓交给后台 /api/understand 自动补；本层只作人工改名/补摘要的兜底与覆盖入口。
struct ThoughtNameSheet: View {
    let thought: PendingThought
    @EnvironmentObject private var store: ThoughtStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var summary: String
    @FocusState private var nameFocused: Bool
    @FocusState private var summaryFocused: Bool

    /// 预填现有名称/摘要（改名场景：不该让用户从空白重打）
    init(thought: PendingThought) {
        self.thought = thought
        _name = State(initialValue: thought.name)
        _summary = State(initialValue: thought.summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("名称与摘要")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(HiveTheme.textTitle)
            Text("起个好记的名字，日后搜索更容易找到它")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)

            VStack(alignment: .leading, spacing: 6) {
                Text("名称")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HiveTheme.textStrong)
                TextField("如：和老铁的合影", text: $name)
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.textStrong)
                    .focused($nameFocused)
                    .submitLabel(.next)
                    .onSubmit { summaryFocused = true }
                    .padding(12)
                    .background(HiveTheme.holoTop)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("摘要（可选）")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HiveTheme.textStrong)
                TextField("一句话记下这段记忆讲什么", text: $summary, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.textStrong)
                    .focused($summaryFocused)
                    .submitLabel(.done)
                    .onSubmit { summaryFocused = false }
                    .lineLimit(2...4)
                    .padding(12)
                    .background(HiveTheme.holoTop)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    store.setNameSummary(thought, name: name, summary: summary)
                    HiveHaptics.light()
                    dismiss()
                } label: {
                    Text("保存")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HiveTheme.bgVoid)
                        .padding(.horizontal, 22)
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
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.height(380)])
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    nameFocused = false
                    summaryFocused = false
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.amber)
            }
        }
    }
}
