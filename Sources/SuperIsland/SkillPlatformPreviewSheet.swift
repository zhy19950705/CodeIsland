import AppKit
import SwiftUI

// The preview sheet stays separate from the row components so the large marketplace/list file does not keep growing.
struct SkillPreviewSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let document: SkillPreviewDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(document.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !document.metadata.isEmpty {
                FlowMetadataView(items: document.metadata)
            }

            if let sourceURL = document.sourceURL {
                Button("Open Source") {
                    NSWorkspace.shared.open(sourceURL)
                }
                .buttonStyle(.bordered)
            }

            SkillMarkdownPreview(
                markdown: document.body,
                bodyHTML: document.bodyHTML,
                theme: SkillMarkdownTheme(colorScheme: colorScheme)
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

struct FlowMetadataView: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
            }
        }
    }
}
