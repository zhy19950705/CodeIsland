import SwiftUI

/// Lightweight symbol spinner for processing states where a full mascot would be visually noisy.
struct ProcessingSpinner: View {
    var tint: Color = Color(red: 0.79, green: 1.0, blue: 0.16)
    var fontSize: CGFloat = 11

    private let frames = ["·", "✢", "✳", "∗", "✻", "✽"]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.11)) { context in
            let frame = frame(for: context.date)
            Text(frames[frame])
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: fontSize + 6, height: fontSize + 4)
        }
    }

    private func frame(for date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate * 9).quotientAndRemainder(dividingBy: frames.count).remainder
    }
}

/// Tiny ASCII buddy used in idle or empty states to add more personality than a static number.
struct BuddyASCIIView: View {
    var tint: Color = .white.opacity(0.72)

    private let frames = [
        "(=^.^=)",
        "(=^o^=)",
        "(=^-^=)"
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * 2.2)
                .quotientAndRemainder(dividingBy: frames.count).remainder
            Text(frames[frame])
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }
}

/// Minimal neon cat accent rendered with Canvas so idle mode has a distinct visual signature.
struct NeonPixelCatView: View {
    var tint: Color = Color(red: 0.79, green: 1.0, blue: 0.16)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            Canvas { graphicsContext, size in
                let pulse = 0.62 + 0.38 * sin(context.date.timeIntervalSinceReferenceDate * 3.2)
                let glow = tint.opacity(0.3 + 0.25 * pulse)
                let fill = tint.opacity(0.75 + 0.2 * pulse)

                func pixel(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 2, _ height: CGFloat = 2) {
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    graphicsContext.fill(Path(rect), with: .color(fill))
                    graphicsContext.addFilter(.shadow(color: glow, radius: 2.4))
                    graphicsContext.fill(Path(rect), with: .color(glow))
                }

                _ = size
                pixel(4, 8, 10, 2)
                pixel(2, 10, 2, 6)
                pixel(14, 10, 2, 6)
                pixel(4, 16, 10, 2)
                pixel(6, 6, 2, 2)
                pixel(10, 6, 2, 2)
                pixel(6, 12, 2, 2)
                pixel(10, 12, 2, 2)
                pixel(0, 6, 2, 4)
                pixel(16, 6, 2, 4)
                pixel(16, 16, 4, 2)
            }
            .frame(width: 20, height: 20)
        }
    }
}
