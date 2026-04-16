import SwiftUI

enum NotchAnimation {
    /// 展开面板：微弹，有少许回弹感
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// 收起面板：临界阻尼，无过冲（防止 NotchPanelShape 底边露出刘海）
    static let close = Animation.spring(response: 0.38, dampingFraction: 1.0)
    /// 通知弹出：快速弹跳，用于 completion/approval 自动展开
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.65)
    /// Surface 切换用更短的缓动，避免列表/详情来回时看起来像重新开关整个刘海。
    static let surfaceSwap = Animation.easeInOut(duration: 0.22)
    /// 微交互：hover 状态变化、按钮高亮等
    static let micro = Animation.easeOut(duration: 0.12)
    /// 会话行强调态保持轻量，避免列表滚动时引入过重的动画成本。
    static let rowEmphasis = Animation.easeOut(duration: 0.16)
}
