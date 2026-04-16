import SwiftUI

/// Overlay controls for adjusting notch width, offset, and virtual height in place.
struct NotchLiveEditOverlay: View {
    let screenID: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var dragStartOffset: CGFloat?
    @State private var store = NotchCustomizationStore.shared

    private let accent = Color(red: 0.79, green: 1.0, blue: 0.16)
    private let cancelAccent = Color(red: 1.0, green: 0.45, blue: 0.55)

    var body: some View {
        GeometryReader { proxy in
            let screenWidth = proxy.size.width
            let geometry = store.customization.geometry(for: screenID)
            let effectiveWidth = geometry.customWidth > 0 ? geometry.customWidth : NotchHardwareDetector.fallbackVirtualWidth(for: screenWidth)
            let effectiveHeight = visibleHeight(for: geometry)
            let clampedOffset = NotchHardwareDetector.clampedHorizontalOffset(
                storedOffset: geometry.horizontalOffset,
                runtimeWidth: effectiveWidth,
                screenFrame: CGRect(x: 0, y: 0, width: screenWidth, height: proxy.size.height)
            )
            let centerX = screenWidth / 2 + clampedOffset

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: effectiveWidth + 8, height: effectiveHeight + 8)
                    .shadow(color: accent.opacity(0.25), radius: 8)
                    .position(x: centerX, y: effectiveHeight / 2 + 4)

                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: effectiveWidth + 18, height: effectiveHeight + 14)
                    .position(x: centerX, y: effectiveHeight / 2 + 4)
                    .gesture(dragGesture())

                widthButton(symbol: "arrow.left", delta: -16)
                    .position(x: centerX - effectiveWidth / 2 - 28, y: effectiveHeight / 2 + 4)
                widthButton(symbol: "arrow.right", delta: 16)
                    .position(x: centerX + effectiveWidth / 2 + 28, y: effectiveHeight / 2 + 4)

                if store.customization.hardwareNotchMode == .forceVirtual {
                    heightButton(symbol: "arrow.down", delta: -4)
                        .position(x: centerX - 20, y: effectiveHeight + 16)
                    heightButton(symbol: "arrow.up", delta: 4)
                        .position(x: centerX + 20, y: effectiveHeight + 16)
                }

                Text(readout(width: effectiveWidth, height: effectiveHeight, offset: clampedOffset))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.62)))
                    .position(x: centerX, y: effectiveHeight + 44)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        actionButton(title: "预设", tint: accent) {
                            applyPresetWidth()
                        }
                        actionButton(title: "重置", tint: .white.opacity(0.9)) {
                            resetGeometry()
                        }
                        actionButton(title: "虚拟", tint: accent) {
                            toggleHardwareMode()
                        }
                    }

                    HStack(spacing: 12) {
                        actionButton(title: "保存", tint: accent, filled: true) {
                            onSave()
                        }
                        actionButton(title: "取消", tint: cancelAccent, filled: true) {
                            onCancel()
                        }
                    }
                }
                .position(x: centerX, y: effectiveHeight + 92)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    /// Physical notches keep their measured height, while virtual mode exposes a clamped editable height.
    private func visibleHeight(for geometry: ScreenNotchGeometry) -> CGFloat {
        if store.customization.hardwareNotchMode == .forceVirtual {
            return NotchHardwareDetector.clampedHeight(geometry.notchHeight)
        }
        return max(38, geometry.notchHeight)
    }

    /// Dragging moves the persisted offset directly so the main panel can live-preview the new position.
    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = store.customization.geometry(for: screenID).horizontalOffset
                }
                let start = dragStartOffset ?? 0
                store.updateGeometry(for: screenID) { geometry in
                    geometry.horizontalOffset = start + value.translation.width
                }
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    /// Width adjustments stay bounded so users cannot create an unusable island.
    private func widthButton(symbol: String, delta: CGFloat) -> some View {
        Button {
            store.updateGeometry(for: screenID) { geometry in
                let currentWidth = geometry.customWidth > 0 ? geometry.customWidth : 200
                geometry.customWidth = max(120, min(currentWidth + delta, 420))
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent))
        }
        .buttonStyle(.plain)
    }

    /// Height controls are only shown in virtual mode because physical notch height is hardware-defined.
    private func heightButton(symbol: String, delta: CGFloat) -> some View {
        Button {
            store.updateGeometry(for: screenID) { geometry in
                geometry.notchHeight = NotchHardwareDetector.clampedHeight(geometry.notchHeight + delta)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(accent))
        }
        .buttonStyle(.plain)
    }

    /// Shared pill button keeps the overlay compact and avoids duplicating control styling.
    private func actionButton(title: String, tint: Color, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(filled ? Color.black : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(filled ? tint : Color.black.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(filled ? 0 : 0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Revert to auto-detected width while also re-centering the island.
    private func applyPresetWidth() {
        store.updateGeometry(for: screenID) { geometry in
            geometry.customWidth = 0
            geometry.horizontalOffset = 0
        }
    }

    /// Full reset clears both width and virtual-height overrides for the active screen.
    private func resetGeometry() {
        store.updateGeometry(for: screenID) { geometry in
            geometry = .default
        }
    }

    /// Toggle persists both the shared setting and the richer customization payload.
    private func toggleHardwareMode() {
        let mode: HardwareNotchMode = store.customization.hardwareNotchMode == .auto ? .forceVirtual : .auto
        SettingsManager.shared.hardwareNotchMode = mode
        store.update { customization in
            customization.hardwareNotchMode = mode
        }
    }

    /// Monospaced metrics make live tuning precise without opening a separate settings sheet.
    private func readout(width: CGFloat, height: CGFloat, offset: CGFloat) -> String {
        let offsetValue = Int(offset.rounded())
        let offsetText = offsetValue > 0 ? "+\(offsetValue)" : "\(offsetValue)"
        return "宽 \(Int(width.rounded()))pt   高 \(Int(height.rounded()))pt   偏移 \(offsetText)pt"
    }
}
