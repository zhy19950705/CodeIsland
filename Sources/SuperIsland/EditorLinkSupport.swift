import AppKit
import SwiftUI
import SuperIslandCore

/// Rendering surfaces pass session context through here so relative transcript links can resolve against the session workspace.
struct EditorLinkContext {
    let sessionId: String?
    let session: SessionSnapshot?

    static let empty = EditorLinkContext(sessionId: nil, session: nil)

    /// Relative file links should resolve against the tracked workspace instead of the app process cwd.
    var workingDirectory: String? { session?.cwd }
}

/// Local file targets keep the resolved path separate from any optional line hint.
struct EditorLocalTarget: Equatable {
    let filePath: String
    let line: Int?
}

/// Transcript and tool-result file links route through a code editor first so macOS does not hand them to Finder.
@MainActor
enum EditorLinkSupport {
    /// Web links should keep using the system browser, while file-like links route into the editor handoff path.
    static func open(url: URL, context: EditorLinkContext) -> OpenURLAction.Result {
        guard let localTarget = resolvedLocalTarget(from: url, workingDirectory: context.workingDirectory) else {
            return .systemAction(url)
        }
        return open(localTarget: localTarget, context: context) ? .handled : .discarded
    }

    /// Buttons in tool result cards reuse the same editor routing as markdown links so both surfaces behave identically.
    static func open(localTarget: EditorLocalTarget, context: EditorLinkContext) -> Bool {
        let fileURL = URL(fileURLWithPath: localTarget.filePath)
        let manager = WorkspaceJumpManager()

        for target in preferredTargets(manager: manager, session: context.session) where manager.isTargetAvailable(target) {
            if open(fileURL: fileURL, line: localTarget.line, using: target, manager: manager) {
                return true
            }
        }

        return manager.workspace.open(fileURL)
    }

    /// URL parsing stays permissive because transcript markdown can emit relative links, file URLs, or file URLs with line fragments.
    static func resolvedLocalTarget(from url: URL, workingDirectory: String?) -> EditorLocalTarget? {
        if let scheme = url.scheme?.lowercased(), !scheme.isEmpty, scheme != "file" {
            return nil
        }

        let rawPath = url.isFileURL ? url.path : strippedLinkPath(from: url.relativeString)
        let parsedPath = parsedPathAndLine(from: rawPath)
        guard let filePath = resolvedFilePath(from: parsedPath.path, workingDirectory: workingDirectory) else {
            return nil
        }

        return EditorLocalTarget(
            filePath: filePath,
            line: extractedLineNumber(from: url) ?? parsedPath.line
        )
    }

    /// Tool-result buttons already know the path string, so they can skip URL parsing and jump straight to resolution.
    static func resolvedLocalTarget(
        path: String,
        line: Int? = nil,
        workingDirectory: String?
    ) -> EditorLocalTarget? {
        let parsedPath = parsedPathAndLine(from: path)
        guard let filePath = resolvedFilePath(from: parsedPath.path, workingDirectory: workingDirectory) else {
            return nil
        }
        return EditorLocalTarget(
            filePath: filePath,
            line: normalizedLineNumber(line) ?? parsedPath.line
        )
    }

    /// Relative file links should expand against the session cwd, while absolute paths and tildes stay intact.
    static func resolvedFilePath(from rawPath: String, workingDirectory: String?) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded).standardizedFileURL.path
        }
        if decoded.hasPrefix("~/") || decoded == "~" {
            let expanded = (decoded as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let baseURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return baseURL.appendingPathComponent(decoded).standardizedFileURL.path
    }

    /// Fragment parsing supports common editor link styles like `#L12`, `#12`, and `#L12-L18`.
    static func extractedLineNumber(from url: URL) -> Int? {
        if let fragmentLine = extractedLineNumber(fromFragment: url.fragment) {
            return fragmentLine
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        for key in ["line", "lines", "startLine", "start_line"] {
            if let value = queryItems.first(where: { $0.name == key })?.value,
               let line = normalizedLineNumber(Int(value)) {
                return line
            }
        }

        return nil
    }

    /// File-target preference intentionally skips native agents like Codex because they cannot open arbitrary local files.
    static func preferredTargets(
        manager: WorkspaceJumpManager,
        session: SessionSnapshot?
    ) -> [WorkspaceJumpManager.JumpTarget] {
        let hostPreferredTargets = session
            .map(manager.editorFallbackChain(for:))
            .map(vsCodeCompatibleTargets(from:))
            ?? []

        let fallbackTargets: [WorkspaceJumpManager.JumpTarget] = [
            .visualStudioCode,
            .visualStudioCodeInsiders,
            .vscodium,
            .cursor,
            .trae,
            .qoder,
            .codeBuddy,
            .factory,
            .windsurf,
            .finder,
        ]

        return deduplicatedTargets(
            (hostPreferredTargets + fallbackTargets).filter(isFileOpenTarget(_:))
        )
    }

    /// CLI-first launch mirrors `code <path>` semantics and avoids Finder receiving unsupported file URLs from transcript links.
    private static func open(
        fileURL: URL,
        line: Int?,
        using target: WorkspaceJumpManager.JumpTarget,
        manager: WorkspaceJumpManager
    ) -> Bool {
        switch target {
        case .cursor,
             .trae,
             .qoder,
             .codeBuddy,
             .factory,
             .windsurf,
             .visualStudioCode,
             .visualStudioCodeInsiders,
             .vscodium:
            if let executable = manager.cliExecutable(for: target),
               manager.runProcess(executable: executable, arguments: codeEditorArguments(for: fileURL, line: line)) {
                return true
            }
            return manager.openWithApplication(fileURL, target: target)
        case .finder:
            manager.workspace.activateFileViewerSelecting([fileURL])
            return true
        default:
            return false
        }
    }

    /// `--goto` preserves line anchors when the transcript emitted a GitHub-style `#Lxx` fragment.
    private static func codeEditorArguments(for fileURL: URL, line: Int?) -> [String] {
        guard let line = normalizedLineNumber(line) else {
            return ["--reuse-window", fileURL.path]
        }
        return ["--reuse-window", "--goto", "\(fileURL.path):\(line)"]
    }

    /// Relative markdown links arrive as raw strings, so query and fragment stripping is done with lightweight string slicing.
    private static func strippedLinkPath(from rawLink: String) -> String {
        let endIndex = rawLink.firstIndex(where: { $0 == "#" || $0 == "?" }) ?? rawLink.endIndex
        return String(rawLink[..<endIndex])
    }

    /// File-link opening follows `code` semantics, so VS Code variants are preferred ahead of non-VSCode editors.
    private static func vsCodeCompatibleTargets(
        from targets: [WorkspaceJumpManager.JumpTarget]
    ) -> [WorkspaceJumpManager.JumpTarget] {
        let preferredOrder: [WorkspaceJumpManager.JumpTarget] = [
            .visualStudioCode,
            .visualStudioCodeInsiders,
            .vscodium,
        ]

        let remainingTargets = targets.filter { !preferredOrder.contains($0) }
        return preferredOrder + remainingTargets
    }

    /// Transcript markdown often emits `path:line` instead of a fragment, so suffix parsing happens before filesystem resolution.
    private static func parsedPathAndLine(from rawPath: String) -> (path: String, line: Int?) {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastColonIndex = trimmed.lastIndex(of: ":") else {
            return (trimmed, nil)
        }

        let trailing = trimmed[trimmed.index(after: lastColonIndex)...]
        guard let trailingValue = Int(trailing),
              trailingValue > 0 else {
            return (trimmed, nil)
        }

        let withoutTrailing = String(trimmed[..<lastColonIndex])
        if let secondColonIndex = withoutTrailing.lastIndex(of: ":") {
            let possibleColumn = withoutTrailing[withoutTrailing.index(after: secondColonIndex)...]
            if let lineValue = Int(possibleColumn),
               lineValue > 0 {
                let linePath = String(withoutTrailing[..<secondColonIndex])
                _ = trailingValue
                return (linePath, lineValue)
            }
        }

        return (withoutTrailing, trailingValue)
    }

    /// The fragment parser only accepts positive integers so malformed links do not trigger accidental editor jumps.
    private static func extractedLineNumber(fromFragment fragment: String?) -> Int? {
        guard let fragment else { return nil }
        let digits = fragment.drop { !$0.isNumber }.prefix { $0.isNumber }
        return normalizedLineNumber(Int(String(digits)))
    }

    /// Normalization keeps invalid zero or negative lines from being forwarded to CLI arguments.
    private static func normalizedLineNumber(_ line: Int?) -> Int? {
        guard let line, line > 0 else { return nil }
        return line
    }

    /// File links should stay inside code editors or Finder; terminal and agent deep links are not suitable for file opens.
    private static func isFileOpenTarget(_ target: WorkspaceJumpManager.JumpTarget) -> Bool {
        switch target {
        case .cursor,
             .trae,
             .qoder,
             .codeBuddy,
             .factory,
             .windsurf,
             .visualStudioCode,
             .visualStudioCodeInsiders,
             .vscodium,
             .finder:
            return true
        default:
            return false
        }
    }

    /// Deduplication keeps the preferred-target chain stable even when host inference and generic fallbacks overlap.
    private static func deduplicatedTargets(
        _ targets: [WorkspaceJumpManager.JumpTarget]
    ) -> [WorkspaceJumpManager.JumpTarget] {
        var seen = Set<String>()
        var result: [WorkspaceJumpManager.JumpTarget] = []

        for target in targets {
            if seen.insert(target.title).inserted {
                result.append(target)
            }
        }

        return result
    }
}

/// Tool-result cards reuse this button wrapper so file titles open like transcript markdown links.
struct EditorFileLinkButton<Label: View>: View {
    let filePath: String
    let line: Int?
    let linkContext: EditorLinkContext
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let localTarget = EditorLinkSupport.resolvedLocalTarget(
            path: filePath,
            line: line,
            workingDirectory: linkContext.workingDirectory
        ) {
            Button {
                _ = EditorLinkSupport.open(localTarget: localTarget, context: linkContext)
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .help(helpText(for: localTarget))
        } else {
            label()
        }
    }

    /// Tooltip text exposes the exact resolved target path, which helps when the rendered filename is truncated.
    private func helpText(for localTarget: EditorLocalTarget) -> String {
        if let line = localTarget.line {
            return "\(localTarget.filePath):\(line)"
        }
        return localTarget.filePath
    }
}
