import Foundation

// Structured hook response encoding avoids hand-written JSON strings and keeps response shapes consistent.
enum HookResponsePayload {
    static func permissionAllow(toolName: String? = nil, persistRule: Bool = false) -> Data {
        let updatedPermissions: [HookUpdatedPermission]?
        if persistRule, let toolName {
            updatedPermissions = [
                HookUpdatedPermission(
                    type: "addRules",
                    rules: [HookPermissionRule(toolName: toolName, ruleContent: "*")],
                    behavior: "allow",
                    destination: "session"
                ),
            ]
        } else {
            updatedPermissions = nil
        }

        return encode(
            HookResponseEnvelope(
                hookSpecificOutput: HookSpecificOutput(
                    hookEventName: "PermissionRequest",
                    decision: HookDecision(
                        behavior: "allow",
                        updatedPermissions: updatedPermissions,
                        updatedInput: nil
                    ),
                    answer: nil
                )
            )
        )
    }

    static func permissionAllow(answerKey: String, answer: String) -> Data {
        encode(
            HookResponseEnvelope(
                hookSpecificOutput: HookSpecificOutput(
                    hookEventName: "PermissionRequest",
                    decision: HookDecision(
                        behavior: "allow",
                        updatedPermissions: nil,
                        updatedInput: HookUpdatedInput(answers: [answerKey: answer])
                    ),
                    answer: nil
                )
            )
        )
    }

    static func permissionDeny() -> Data {
        encode(
            HookResponseEnvelope(
                hookSpecificOutput: HookSpecificOutput(
                    hookEventName: "PermissionRequest",
                    decision: HookDecision(
                        behavior: "deny",
                        updatedPermissions: nil,
                        updatedInput: nil
                    ),
                    answer: nil
                )
            )
        )
    }

    static func notificationAnswer(_ answer: String) -> Data {
        encode(
            HookResponseEnvelope(
                hookSpecificOutput: HookSpecificOutput(
                    hookEventName: "Notification",
                    decision: nil,
                    answer: answer
                )
            )
        )
    }

    static func notificationAck() -> Data {
        encode(
            HookResponseEnvelope(
                hookSpecificOutput: HookSpecificOutput(
                    hookEventName: "Notification",
                    decision: nil,
                    answer: nil
                )
            )
        )
    }

    private static func encode(_ envelope: HookResponseEnvelope) -> Data {
        let encoder = JSONEncoder()
        return (try? encoder.encode(envelope)) ?? Data("{}".utf8)
    }
}

private struct HookResponseEnvelope: Encodable {
    let hookSpecificOutput: HookSpecificOutput
}

private struct HookSpecificOutput: Encodable {
    let hookEventName: String
    let decision: HookDecision?
    let answer: String?
}

private struct HookDecision: Encodable {
    let behavior: String
    let updatedPermissions: [HookUpdatedPermission]?
    let updatedInput: HookUpdatedInput?
}

private struct HookUpdatedPermission: Encodable {
    let type: String
    let rules: [HookPermissionRule]
    let behavior: String
    let destination: String
}

private struct HookPermissionRule: Encodable {
    let toolName: String
    let ruleContent: String
}

private struct HookUpdatedInput: Encodable {
    let answers: [String: String]
}
