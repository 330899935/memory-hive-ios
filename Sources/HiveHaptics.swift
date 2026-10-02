import UIKit

/// 触觉反馈：记忆落袋 / 归巢的物理确认感
/// - light：存成功（轻震一下）
/// - success：归巢成功（更强的成功确认）
enum HiveHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
