import SwiftUI
import UIKit

@main
struct 记忆蜂巢App: App {
    init() {
        // 底部角标换琥珀色（黑金主题同色系，替代默认正红）
        UITabBarItem.appearance().badgeColor = UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1.0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
