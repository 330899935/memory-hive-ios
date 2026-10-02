import SwiftUI

/// 通用「点开看解释」弹层 —— ⑯⑰⑫ 等「点标题看说明」共用
/// 视觉：图标 + 标题 + 大白话正文 + 「知道了」按钮
struct InfoSheet: View {
    let title: String
    let symbol: String
    let tint: Color
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 20, weight: .heavy))
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
                // 2026-09-19 引流指令书触点3：正文支持 Markdown 链接（排查兜底「下载 Mac 版」可点直达）
                // inlineOnlyPreservingWhitespace：不解析标题/块级语法，但保留 \n 换行原样
                Group {
                    if let attr = try? AttributedString(
                        markdown: text,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(attr)
                    } else {
                        Text(text)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textBody)
                .tint(HiveTheme.amber)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    dismiss()
                } label: {
                    Text("知道了")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HiveTheme.bgVoid)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(HiveTheme.amber)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(HiveTheme.bgVoid)
        .presentationDetents([.medium])
    }
}
