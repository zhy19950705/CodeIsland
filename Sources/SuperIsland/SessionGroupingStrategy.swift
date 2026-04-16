import Foundation
import SuperIslandCore

struct SessionGroupingSupport {
    let sessions: [String: SessionSnapshot]
    let sortIDs: ([String]) -> [String]
    let latestActivity: ([String]) -> Date
}

protocol SessionGroupingStrategy {
    func makeGroups(allIDs: [String], support: SessionGroupingSupport) -> [SessionListGroupPresentation]
}

enum SessionGroupingStrategies {
    static func strategy(for groupingMode: String) -> any SessionGroupingStrategy {
        switch groupingMode {
        case "project":
            ProjectSessionGroupingStrategy()
        case "status":
            StatusSessionGroupingStrategy()
        case "cli":
            CLISessionGroupingStrategy()
        default:
            AllSessionGroupingStrategy()
        }
    }
}

private struct ProjectSessionGroupingStrategy: SessionGroupingStrategy {
    func makeGroups(allIDs: [String], support: SessionGroupingSupport) -> [SessionListGroupPresentation] {
        var projectGroups: [String: [String]] = [:]
        for id in allIDs {
            let project = support.sessions[id]?.displayName ?? "Session"
            projectGroups[project, default: []].append(id)
        }

        let sortedProjects = projectGroups.keys.sorted { lhs, rhs in
            support.latestActivity(projectGroups[lhs] ?? []) > support.latestActivity(projectGroups[rhs] ?? [])
        }

        return sortedProjects.enumerated().map { index, project in
            let ids = support.sortIDs(projectGroups[project] ?? [])
            return SessionListGroupPresentation(
                id: "project-\(index)-\(project)",
                header: "\(project) (\(ids.count))",
                source: nil,
                ids: ids
            )
        }
    }
}

private struct StatusSessionGroupingStrategy: SessionGroupingStrategy {
    func makeGroups(allIDs: [String], support: SessionGroupingSupport) -> [SessionListGroupPresentation] {
        let l10n = AppText.shared
        let statusGroups: [(Set<AgentStatus>, String)] = [
            ([.running], l10n["status_running"]),
            ([.waitingApproval, .waitingQuestion], l10n["status_waiting"]),
            ([.processing], l10n["status_processing"]),
            ([.idle], l10n["status_idle"]),
        ]

        return statusGroups.enumerated().compactMap { index, item in
            let (statuses, label) = item
            let ids = support.sortIDs(allIDs.filter { id in
                guard let session = support.sessions[id] else { return false }
                return statuses.contains(session.status)
            })
            guard !ids.isEmpty else { return nil }
            return SessionListGroupPresentation(
                id: "status-\(index)-\(label)",
                header: "\(label) (\(ids.count))",
                source: nil,
                ids: ids
            )
        }
    }
}

private struct CLISessionGroupingStrategy: SessionGroupingStrategy {
    func makeGroups(allIDs: [String], support: SessionGroupingSupport) -> [SessionListGroupPresentation] {
        let cliOrder: [(source: String, name: String)] = [
            ("claude", "Claude"),
            ("codex", "Codex"),
            ("gemini", "Gemini"),
            ("cursor", "Cursor"),
            ("copilot", "Copilot"),
            ("qoder", "Qoder"),
            ("droid", "Factory"),
            ("codebuddy", "CodeBuddy"),
            ("opencode", "OpenCode"),
        ]

        var result: [SessionListGroupPresentation] = []
        var seen = Set<String>()

        for (index, cli) in cliOrder.enumerated() {
            let ids = support.sortIDs(allIDs.filter { id in
                support.sessions[id]?.source == cli.source
            })
            guard !ids.isEmpty else { continue }
            ids.forEach { seen.insert($0) }
            result.append(
                SessionListGroupPresentation(
                    id: "cli-\(index)-\(cli.source)",
                    header: "\(cli.name) (\(ids.count))",
                    source: cli.source,
                    ids: ids
                )
            )
        }

        let remaining = support.sortIDs(allIDs.filter { !seen.contains($0) })
        if !remaining.isEmpty {
            result.append(
                SessionListGroupPresentation(
                    id: "cli-other",
                    header: "\(AppText.shared["other"]) (\(remaining.count))",
                    source: nil,
                    ids: remaining
                )
            )
        }

        return result
    }
}

private struct AllSessionGroupingStrategy: SessionGroupingStrategy {
    func makeGroups(allIDs: [String], support: SessionGroupingSupport) -> [SessionListGroupPresentation] {
        [
            SessionListGroupPresentation(
                id: "all",
                header: "",
                source: nil,
                ids: support.sortIDs(allIDs)
            )
        ]
    }
}
