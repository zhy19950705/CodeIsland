import SwiftUI
import SuperIslandCore

// SessionRowChrome centralizes the list-row palette so compact and expanded rows
// share the same hierarchy, hover feedback, and selected-state treatment.
struct SessionRowChromeStyle {
    let accent: Color
    let fill: Color
    let border: Color
    let rail: Color
    let railOpacity: Double
    let title: Color
    let primaryText: Color
    let secondaryText: Color
    let symbolFill: Color
    let symbolBorder: Color
}

enum SessionRowChrome {
    static let reviewTint = Color(red: 0.32, green: 0.74, blue: 1.0)
    static let runningTint = Color(red: 0.3, green: 0.85, blue: 0.4)
    static let waitingTint = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let interruptedTint = Color(red: 1.0, green: 0.45, blue: 0.35)

    static func accent(
        status: AgentStatus,
        interrupted: Bool,
        needsCompletionReview: Bool
    ) -> Color {
        if needsCompletionReview {
            return reviewTint
        }
        if status == .idle && interrupted {
            return interruptedTint
        }
        switch status {
        case .processing, .running:
            return runningTint
        case .waitingApproval, .waitingQuestion:
            return waitingTint
        case .idle:
            return .white.opacity(0.82)
        }
    }

    static func style(
        status: AgentStatus,
        interrupted: Bool,
        isSelected: Bool,
        isHovered: Bool,
        needsCompletionReview: Bool
    ) -> SessionRowChromeStyle {
        let accentColor = accent(
            status: status,
            interrupted: interrupted,
            needsCompletionReview: needsCompletionReview
        )

        if isSelected {
            return SessionRowChromeStyle(
                accent: accentColor,
                fill: Color(red: 0.05, green: 0.13, blue: 0.16),
                border: accentColor.opacity(0.38),
                rail: accentColor,
                railOpacity: 0.92,
                title: .white.opacity(0.97),
                primaryText: .white.opacity(0.9),
                secondaryText: .white.opacity(0.7),
                symbolFill: Color.white.opacity(0.1),
                symbolBorder: accentColor.opacity(0.18)
            )
        }

        if needsCompletionReview {
            return SessionRowChromeStyle(
                accent: accentColor,
                fill: isHovered ? Color(red: 0.05, green: 0.1, blue: 0.12) : Color(red: 0.04, green: 0.08, blue: 0.1),
                border: accentColor.opacity(isHovered ? 0.3 : 0.22),
                rail: accentColor,
                railOpacity: isHovered ? 0.5 : 0.34,
                title: .white.opacity(isHovered ? 0.9 : 0.84),
                primaryText: .white.opacity(isHovered ? 0.78 : 0.72),
                secondaryText: .white.opacity(isHovered ? 0.66 : 0.58),
                symbolFill: Color.white.opacity(isHovered ? 0.08 : 0.05),
                symbolBorder: accentColor.opacity(isHovered ? 0.18 : 0.12)
            )
        }

        return SessionRowChromeStyle(
            accent: accentColor,
            fill: Color.white.opacity(isHovered ? 0.065 : 0.036),
            border: Color.white.opacity(isHovered ? 0.09 : 0.045),
            rail: accentColor,
            railOpacity: isHovered ? 0.22 : 0,
            title: accentColor.opacity(isHovered ? 0.98 : 0.9),
            primaryText: .white.opacity(isHovered ? 0.76 : 0.64),
            secondaryText: .white.opacity(isHovered ? 0.64 : 0.52),
            symbolFill: Color.white.opacity(isHovered ? 0.075 : 0.04),
            symbolBorder: Color.white.opacity(isHovered ? 0.1 : 0.05)
        )
    }
}

// Row press feedback stays transform-only so the list feels responsive without
// introducing layout churn or oversized scale animations in the notch surface.
struct SessionRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.992 : 1, anchor: .center)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(NotchAnimation.micro, value: configuration.isPressed)
    }
}
