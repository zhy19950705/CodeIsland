import SwiftUI

// Keep the first AI settings frame intentionally light so tab switches stay responsive even on slower Macs.
struct AIPageLoadingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("Loading AI settings…")
                .font(.system(size: 13, weight: .semibold))

            Text("Usage monitor and Codex account state will appear in a moment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}
