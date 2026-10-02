import SwiftUI

/// 骨架占位页：统一「页标题 + 副标题 + 空状态」
struct PlaceholderPage: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(HiveTheme.amber)
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(HiveTheme.textTitle)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(HiveTheme.textCaption)
                    .multilineTextAlignment(.center)
            }
            .holoCard()
            .padding(24)
        }
    }
}

#Preview {
    ContentView()
}
