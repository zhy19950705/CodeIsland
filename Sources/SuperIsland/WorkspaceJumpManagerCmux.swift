import AppKit
import Foundation
import SuperIslandCore

// cmux-specific jumping stays isolated so terminal workspace focus logic does not leak into generic app launching.
extension WorkspaceJumpManager {
    func openInCmux(_ workspaceURL: URL, session: SessionSnapshot) -> Bool {
        let workspaceReference = normalizedCmuxReference(session.cmuxWorkspaceRef)
            ?? normalizedCmuxReference(session.cmuxWorkspaceId)
        let surfaceReference = normalizedCmuxReference(session.cmuxSurfaceRef)
            ?? normalizedCmuxReference(session.cmuxSurfaceId)
        let paneReference = normalizedCmuxReference(session.cmuxPaneRef)

        if focusInCmuxViaCLI(
            workspaceReference: workspaceReference,
            surfaceReference: surfaceReference,
            paneReference: paneReference,
            socketPath: session.cmuxSocketPath
        ) {
            return true
        }

        if let executable = cliExecutable(for: .cmux),
           runProcess(executable: executable, arguments: [workspaceURL.path], environment: cmuxEnvironment(socketPath: session.cmuxSocketPath)) {
            return true
        }
        return openWithApplication(workspaceURL, target: .cmux)
    }

    // Try direct cmux focus commands first so terminal sessions reopen with the right pane selected.
    func focusInCmuxViaCLI(
        workspaceReference: String?,
        surfaceReference: String?,
        paneReference: String?,
        socketPath: String?
    ) -> Bool {
        guard let executable = cliExecutable(for: .cmux) else { return false }
        let environment = cmuxEnvironment(socketPath: socketPath)

        if let workspaceReference,
           let paneReference,
           runProcessAndWait(
               executable: executable,
               arguments: ["focus-pane", "--workspace", workspaceReference, "--pane", paneReference],
               environment: environment
           ) {
            triggerCmuxFlash(executable: executable, workspaceReference: workspaceReference, surfaceReference: surfaceReference, environment: environment)
            _ = activateApplication(target: .cmux)
            return true
        }

        if let surfaceReference,
           let focusTarget = cmuxFocusTarget(
               surfaceReference: surfaceReference,
               workspaceReference: workspaceReference,
               executable: executable,
               environment: environment
           ),
           runProcessAndWait(
               executable: executable,
               arguments: ["focus-pane", "--workspace", focusTarget.workspaceReference, "--pane", focusTarget.paneReference],
               environment: environment
           ) {
            triggerCmuxFlash(executable: executable, workspaceReference: focusTarget.workspaceReference, surfaceReference: surfaceReference, environment: environment)
            _ = activateApplication(target: .cmux)
            return true
        }

        if let workspaceReference,
           runProcessAndWait(
               executable: executable,
               arguments: ["select-workspace", "--workspace", workspaceReference],
               environment: environment
           ) {
            triggerCmuxFlash(executable: executable, workspaceReference: workspaceReference, surfaceReference: surfaceReference, environment: environment)
            _ = activateApplication(target: .cmux)
            return true
        }

        return false
    }

    func triggerCmuxFlash(executable: String, workspaceReference: String?, surfaceReference: String?, environment: [String: String]) {
        var arguments = ["trigger-flash"]
        if let workspaceReference {
            arguments.append(contentsOf: ["--workspace", workspaceReference])
        }
        if let surfaceReference {
            arguments.append(contentsOf: ["--surface", surfaceReference])
        }
        _ = runProcessAndWait(executable: executable, arguments: arguments, environment: environment)
    }

    func cmuxFocusTarget(
        surfaceReference: String,
        workspaceReference: String?,
        executable: String,
        environment: [String: String]
    ) -> (workspaceReference: String, paneReference: String)? {
        guard let snapshot = loadCmuxTreeSnapshot(
            workspaceReference: workspaceReference,
            executable: executable,
            environment: environment
        ) else {
            return nil
        }

        for window in snapshot.windows {
            for workspace in window.workspaces {
                for pane in workspace.panes where pane.surfaceRefs.contains(surfaceReference) || pane.selectedSurfaceRef == surfaceReference {
                    return (workspace.ref, pane.ref)
                }
            }
        }

        return nil
    }

    func loadCmuxTreeSnapshot(
        workspaceReference: String?,
        executable: String,
        environment: [String: String]
    ) -> CmuxTreeSnapshot? {
        var arguments = ["tree", "--json"]
        if let workspaceReference {
            arguments.append(contentsOf: ["--workspace", workspaceReference])
        } else {
            arguments.insert("--all", at: 1)
        }

        guard let output = captureProcessOutput(executable: executable, arguments: arguments, environment: environment),
              let data = output.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(CmuxTreeSnapshot.self, from: data)
    }

    func normalizedCmuxReference(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func cmuxEnvironment(socketPath: String?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let socketPath = socketPath?.trimmingCharacters(in: .whitespacesAndNewlines), !socketPath.isEmpty {
            environment["CMUX_SOCKET_PATH"] = socketPath
        }
        return environment
    }
}
