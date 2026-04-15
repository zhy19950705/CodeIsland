import AppKit
import Foundation
import SuperIslandCore

// cmux-specific jumping stays isolated so terminal workspace focus logic does not leak into generic app launching.
extension WorkspaceJumpManager {
    func openInCmux(_ workspaceURL: URL, session: SessionSnapshot) -> Bool {
        let workspaceReference = normalizedCmuxReference(session.cmuxWorkspaceRef)
        let workspaceIdentifier = normalizedCmuxReference(session.cmuxWorkspaceId)
        let surfaceReference = normalizedCmuxReference(session.cmuxSurfaceRef)
        let surfaceIdentifier = normalizedCmuxReference(session.cmuxSurfaceId)
        let paneReference = normalizedCmuxReference(session.cmuxPaneRef)

        if focusInCmuxViaCLI(
            workspaceReference: workspaceReference,
            workspaceIdentifier: workspaceIdentifier,
            surfaceReference: surfaceReference,
            surfaceIdentifier: surfaceIdentifier,
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
        workspaceIdentifier: String?,
        surfaceReference: String?,
        surfaceIdentifier: String?,
        paneReference: String?,
        socketPath: String?
    ) -> Bool {
        guard let executable = cliExecutable(for: .cmux) else { return false }
        let environment = cmuxEnvironment(socketPath: socketPath)

        let focusTarget = cmuxFocusTarget(
            workspaceReference: workspaceReference,
            workspaceIdentifier: workspaceIdentifier,
            surfaceReference: surfaceReference,
            surfaceIdentifier: surfaceIdentifier,
            paneReference: paneReference,
            executable: executable,
            environment: environment
        )

        if let focusTarget,
           focusCmuxTarget(focusTarget, executable: executable, environment: environment) {
            triggerCmuxFlash(
                executable: executable,
                workspaceReference: focusTarget.workspaceReference ?? workspaceReference,
                surfaceReference: focusTarget.surfaceReference ?? surfaceReference,
                environment: environment
            )
            _ = activateApplication(target: .cmux)
            return true
        }

        return false
    }

    // Surface focus is the only cmux API that can reliably select the tab inside a pane.
    func focusCmuxTarget(
        _ target: CmuxFocusTarget,
        executable: String,
        environment: [String: String]
    ) -> Bool {
        if let workspaceIdentifier = target.workspaceIdentifier,
           let surfaceIdentifier = target.surfaceIdentifier,
           runCmuxRPC(
               executable: executable,
               method: "surface.focus",
               parameters: [
                   "workspace_id": workspaceIdentifier,
                   "surface_id": surfaceIdentifier,
               ],
               environment: environment
           ) {
            return true
        }

        if let workspaceIdentifier = target.workspaceIdentifier,
           let paneIdentifier = target.paneIdentifier,
           runCmuxRPC(
               executable: executable,
               method: "pane.focus",
               parameters: [
                   "workspace_id": workspaceIdentifier,
                   "pane_id": paneIdentifier,
               ],
               environment: environment
           ) {
            return true
        }

        if let workspaceSelector = cmuxWorkspaceSelector(
            workspaceReference: target.workspaceReference,
            workspaceIdentifier: target.workspaceIdentifier
        ),
           let paneReference = target.paneReference,
           runProcessAndWait(
               executable: executable,
               arguments: ["focus-pane", "--workspace", workspaceSelector, "--pane", paneReference],
               environment: environment
           ) {
            return true
        }

        if let workspaceSelector = cmuxWorkspaceSelector(
            workspaceReference: target.workspaceReference,
            workspaceIdentifier: target.workspaceIdentifier
        ),
           runProcessAndWait(
               executable: executable,
               arguments: ["select-workspace", "--workspace", workspaceSelector],
               environment: environment
           ) {
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

    // Resolve refs to IDs when possible so we can use cmux RPC surface focus instead of pane-only focus.
    func cmuxFocusTarget(
        workspaceReference: String?,
        workspaceIdentifier: String?,
        surfaceReference: String?,
        surfaceIdentifier: String?,
        paneReference: String?,
        executable: String,
        environment: [String: String]
    ) -> CmuxFocusTarget? {
        guard let snapshot = loadCmuxTreeSnapshot(
            workspaceReference: workspaceReference,
            workspaceIdentifier: workspaceIdentifier,
            executable: executable,
            environment: environment
        ) else {
            let fallbackTarget = CmuxFocusTarget(
                workspaceReference: workspaceReference,
                workspaceIdentifier: workspaceIdentifier,
                paneReference: paneReference,
                paneIdentifier: nil,
                surfaceReference: surfaceReference,
                surfaceIdentifier: surfaceIdentifier
            )
            return fallbackTarget.isEmpty ? nil : fallbackTarget
        }

        let scopedWorkspaces = snapshot.windows
            .flatMap(\.workspaces)
            .filter { workspace in
                if let workspaceIdentifier, workspace.id == workspaceIdentifier { return true }
                if let workspaceReference, workspace.ref == workspaceReference { return true }
                return workspaceIdentifier == nil && workspaceReference == nil
            }

        if let surfaceTarget = cmuxSurfaceFocusTarget(
            in: scopedWorkspaces,
            surfaceReference: surfaceReference,
            surfaceIdentifier: surfaceIdentifier
        ) {
            return surfaceTarget
        }

        if let paneTarget = cmuxPaneFocusTarget(in: scopedWorkspaces, paneReference: paneReference) {
            return paneTarget
        }

        let fallbackTarget = CmuxFocusTarget(
            workspaceReference: workspaceReference,
            workspaceIdentifier: workspaceIdentifier,
            paneReference: paneReference,
            paneIdentifier: nil,
            surfaceReference: surfaceReference,
            surfaceIdentifier: surfaceIdentifier
        )
        return fallbackTarget.isEmpty ? nil : fallbackTarget
    }

    // Search exact surface matches first so a pane with multiple tabs lands on the intended tab, not just the pane.
    func cmuxSurfaceFocusTarget(
        in workspaces: [CmuxWorkspace],
        surfaceReference: String?,
        surfaceIdentifier: String?
    ) -> CmuxFocusTarget? {
        for workspace in workspaces {
            for pane in workspace.panes {
                if let surfaceIdentifier,
                   let surface = pane.surfaces?.first(where: { $0.id == surfaceIdentifier }) {
                    return CmuxFocusTarget(
                        workspaceReference: workspace.ref,
                        workspaceIdentifier: workspace.id,
                        paneReference: pane.ref,
                        paneIdentifier: pane.id,
                        surfaceReference: surface.ref,
                        surfaceIdentifier: surface.id
                    )
                }
                if let surfaceReference,
                   let surface = pane.surfaces?.first(where: { $0.ref == surfaceReference }) {
                    return CmuxFocusTarget(
                        workspaceReference: workspace.ref,
                        workspaceIdentifier: workspace.id,
                        paneReference: pane.ref,
                        paneIdentifier: pane.id,
                        surfaceReference: surface.ref,
                        surfaceIdentifier: surface.id
                    )
                }
                if let surfaceReference,
                   pane.surfaceRefs.contains(surfaceReference) || pane.selectedSurfaceRef == surfaceReference {
                    return CmuxFocusTarget(
                        workspaceReference: workspace.ref,
                        workspaceIdentifier: workspace.id,
                        paneReference: pane.ref,
                        paneIdentifier: pane.id,
                        surfaceReference: surfaceReference,
                        surfaceIdentifier: pane.surfaces?.first(where: { $0.ref == surfaceReference })?.id
                    )
                }
            }
        }

        return nil
    }

    // Pane-only fallback still matters for older cmux payloads that do not expose per-surface IDs.
    func cmuxPaneFocusTarget(in workspaces: [CmuxWorkspace], paneReference: String?) -> CmuxFocusTarget? {
        guard let paneReference else { return nil }

        for workspace in workspaces {
            if let pane = workspace.panes.first(where: { $0.ref == paneReference }) {
                return CmuxFocusTarget(
                    workspaceReference: workspace.ref,
                    workspaceIdentifier: workspace.id,
                    paneReference: pane.ref,
                    paneIdentifier: pane.id,
                    surfaceReference: pane.selectedSurfaceRef,
                    surfaceIdentifier: pane.selectedSurfaceId
                )
            }
        }

        return nil
    }

    func loadCmuxTreeSnapshot(
        workspaceReference: String?,
        workspaceIdentifier: String?,
        executable: String,
        environment: [String: String]
    ) -> CmuxTreeSnapshot? {
        if let snapshot = loadCmuxTreeSnapshotViaRPC(
            workspaceReference: workspaceReference,
            workspaceIdentifier: workspaceIdentifier,
            executable: executable,
            environment: environment
        ) {
            return snapshot
        }

        var arguments = ["tree", "--json"]
        if let workspaceReference {
            arguments.append(contentsOf: ["--workspace", workspaceReference])
        } else if let workspaceIdentifier {
            arguments.append(contentsOf: ["--workspace", workspaceIdentifier])
        } else {
            arguments.insert("--all", at: 1)
        }

        guard let output = captureProcessOutput(executable: executable, arguments: arguments, environment: environment),
              let data = output.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(CmuxTreeSnapshot.self, from: data)
    }

    // Newer cmux builds expose full ID-rich topology through RPC, which is required for exact surface focus.
    func loadCmuxTreeSnapshotViaRPC(
        workspaceReference: String?,
        workspaceIdentifier: String?,
        executable: String,
        environment: [String: String]
    ) -> CmuxTreeSnapshot? {
        var parameters: [String: String] = [:]
        if let workspaceIdentifier {
            parameters["workspace_id"] = workspaceIdentifier
        } else if let workspaceReference {
            parameters["workspace_ref"] = workspaceReference
        }

        guard let output = captureCmuxRPCOutput(
            executable: executable,
            method: "system.tree",
            parameters: parameters,
            environment: environment
        ),
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

    // The CLI accepts both IDs and refs for workspace selectors, so prefer refs for readability and fall back to IDs.
    func cmuxWorkspaceSelector(workspaceReference: String?, workspaceIdentifier: String?) -> String? {
        workspaceReference ?? workspaceIdentifier
    }

    // RPC is the only cmux path that can focus a specific surface, so centralize the JSON encoding here.
    func runCmuxRPC(
        executable: String,
        method: String,
        parameters: [String: String],
        environment: [String: String]
    ) -> Bool {
        guard let json = cmuxRPCJSON(parameters) else { return false }
        return runProcessAndWait(
            executable: executable,
            arguments: ["rpc", method, json],
            environment: environment
        )
    }

    // Snapshot loading and focus routing share the same RPC transport, so keep output capture in one helper.
    func captureCmuxRPCOutput(
        executable: String,
        method: String,
        parameters: [String: String],
        environment: [String: String]
    ) -> String? {
        guard let json = cmuxRPCJSON(parameters) else { return nil }
        return captureProcessOutput(
            executable: executable,
            arguments: ["rpc", method, json],
            environment: environment
        )
    }

    // JSONSerialization keeps the payload stable across macOS releases without pulling in extra encoding models.
    func cmuxRPCJSON(_ parameters: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: parameters, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    func cmuxEnvironment(socketPath: String?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let socketPath = socketPath?.trimmingCharacters(in: .whitespacesAndNewlines), !socketPath.isEmpty {
            environment["CMUX_SOCKET_PATH"] = socketPath
        }
        return environment
    }
}
