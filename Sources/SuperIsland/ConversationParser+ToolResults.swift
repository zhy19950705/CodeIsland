import Foundation

/// Shared tool-result parsing keeps Claude and Codex transcript rendering aligned.
extension ConversationParser {
    func parseStructuredToolResult(
        toolName: String,
        payload: [String: Any],
        isError: Bool
    ) -> ToolResultData {
        if toolName.hasPrefix("mcp__") {
            let trimmed = String(toolName.dropFirst(5))
            let parts = trimmed.split(separator: "_", maxSplits: 1)
            return .mcp(
                MCPResult(
                    serverName: parts.first.map(String.init) ?? "mcp",
                    toolName: parts.dropFirst().first.map(String.init) ?? trimmed,
                    rawResult: payload
                )
            )
        }

        switch toolName {
        case "Read":
            return .read(
                ReadResult(
                    filePath: nestedString(payload, "file", "filePath") ?? payload["filePath"] as? String ?? "",
                    content: nestedString(payload, "file", "content") ?? payload["content"] as? String ?? "",
                    startLine: nestedInt(payload, "file", "startLine") ?? payload["startLine"] as? Int ?? 1,
                    totalLines: nestedInt(payload, "file", "totalLines") ?? payload["totalLines"] as? Int ?? 0
                )
            )
        case "Edit":
            return .edit(
                EditResult(
                    filePath: payload["filePath"] as? String ?? "",
                    oldString: payload["oldString"] as? String ?? "",
                    newString: payload["newString"] as? String ?? "",
                    replaceAll: payload["replaceAll"] as? Bool ?? false,
                    userModified: payload["userModified"] as? Bool ?? false,
                    structuredPatch: patchHunks(payload["structuredPatch"] as? [[String: Any]])
                )
            )
        case "Write":
            let writeType = (payload["type"] as? String) == "overwrite" ? WriteResult.WriteType.overwrite : .create
            return .write(
                WriteResult(
                    type: writeType,
                    filePath: payload["filePath"] as? String ?? "",
                    content: payload["content"] as? String ?? "",
                    structuredPatch: patchHunks(payload["structuredPatch"] as? [[String: Any]])
                )
            )
        case "Bash":
            return .bash(
                BashResult(
                    stdout: payload["stdout"] as? String ?? "",
                    stderr: payload["stderr"] as? String ?? "",
                    interrupted: payload["interrupted"] as? Bool ?? isError,
                    returnCodeInterpretation: payload["returnCodeInterpretation"] as? String,
                    backgroundTaskId: payload["backgroundTaskId"] as? String
                )
            )
        case "Grep":
            return .grep(
                GrepResult(
                    mode: GrepResult.Mode(rawValue: payload["mode"] as? String ?? "") ?? .filesWithMatches,
                    filenames: payload["filenames"] as? [String] ?? [],
                    content: payload["content"] as? String,
                    numFiles: payload["numFiles"] as? Int ?? 0
                )
            )
        case "Glob":
            return .glob(
                GlobResult(
                    filenames: payload["filenames"] as? [String] ?? [],
                    numFiles: payload["numFiles"] as? Int ?? 0,
                    truncated: payload["truncated"] as? Bool ?? false
                )
            )
        case "Task":
            return .task(
                TaskResult(
                    agentId: payload["agentId"] as? String ?? "",
                    status: payload["status"] as? String ?? "completed",
                    content: payload["content"] as? String ?? payload["result"] as? String ?? "",
                    totalDurationMs: payload["totalDurationMs"] as? Int,
                    totalToolUseCount: payload["totalToolUseCount"] as? Int
                )
            )
        case "WebFetch":
            return .webFetch(
                WebFetchResult(
                    url: payload["url"] as? String ?? "",
                    code: payload["code"] as? Int ?? 0,
                    codeText: payload["codeText"] as? String ?? "",
                    bytes: payload["bytes"] as? Int ?? 0,
                    durationMs: payload["durationMs"] as? Int ?? 0,
                    result: payload["result"] as? String ?? ""
                )
            )
        case "WebSearch":
            let results = (payload["results"] as? [[String: Any]] ?? []).map {
                SearchResultItem(
                    title: $0["title"] as? String ?? "",
                    url: $0["url"] as? String ?? "",
                    snippet: $0["snippet"] as? String ?? ""
                )
            }
            return .webSearch(
                WebSearchResult(
                    query: payload["query"] as? String ?? "",
                    durationSeconds: payload["durationSeconds"] as? Double ?? 0,
                    results: results
                )
            )
        case "AskUserQuestion":
            let questions = (payload["questions"] as? [[String: Any]] ?? []).map { question in
                QuestionItem(
                    question: question["question"] as? String ?? "",
                    header: question["header"] as? String,
                    options: (question["options"] as? [[String: Any]] ?? []).map {
                        QuestionOption(label: $0["label"] as? String ?? "", description: $0["description"] as? String)
                    }
                )
            }
            return .askUserQuestion(
                AskUserQuestionResult(
                    questions: questions,
                    answers: payload["answers"] as? [String: String] ?? [:]
                )
            )
        case "BashOutput":
            return .bashOutput(
                BashOutputResult(
                    shellId: payload["shellId"] as? String ?? "",
                    status: payload["status"] as? String ?? "",
                    stdout: payload["stdout"] as? String ?? "",
                    stderr: payload["stderr"] as? String ?? "",
                    exitCode: payload["exitCode"] as? Int,
                    command: payload["command"] as? String
                )
            )
        case "KillShell":
            return .killShell(
                KillShellResult(
                    shellId: payload["shellId"] as? String ?? "",
                    message: payload["message"] as? String ?? ""
                )
            )
        case "ExitPlanMode":
            return .exitPlanMode(
                ExitPlanModeResult(
                    filePath: payload["filePath"] as? String,
                    plan: payload["plan"] as? String,
                    isAgent: payload["isAgent"] as? Bool ?? false
                )
            )
        default:
            let rawContent = payload["content"] as? String ?? payload["stdout"] as? String ?? payload["result"] as? String
            return .generic(GenericResult(rawContent: rawContent, rawData: payload))
        }
    }

    /// Codex function outputs are often encoded as JSON strings; decode them before hitting the shared parser.
    func parseStructuredCodexResult(
        toolName: String,
        payload: [String: Any],
        input: [String: String]
    ) -> ToolResultData? {
        var mergedPayload = jsonObject(from: payload["output"])
            ?? jsonObject(from: payload["result"])
            ?? jsonObject(from: payload["content"])
            ?? [:]

        if toolName == "Bash", mergedPayload.isEmpty, let rawOutput = payload["output"] as? String {
            mergedPayload["stdout"] = rawOutput
        }

        // Merge scalar call arguments so views still have file paths and diff text when outputs are sparse.
        for (key, value) in input where mergedPayload[key] == nil {
            mergedPayload[key] = value
        }
        if mergedPayload["filePath"] == nil {
            mergedPayload["filePath"] = input["file_path"] ?? input["path"]
        }
        if mergedPayload["oldString"] == nil {
            mergedPayload["oldString"] = input["old_string"]
        }
        if mergedPayload["newString"] == nil {
            mergedPayload["newString"] = input["new_string"]
        }
        if mergedPayload["replaceAll"] == nil, let rawReplaceAll = input["replace_all"] ?? input["replaceAll"] {
            mergedPayload["replaceAll"] = rawReplaceAll == "true"
        }

        guard !mergedPayload.isEmpty else { return nil }
        return parseStructuredToolResult(toolName: toolName, payload: mergedPayload, isError: false)
    }

    /// JSON decoding stays intentionally permissive because transcript payloads can be mixed strings or dictionaries.
    func jsonObject(from rawValue: Any?) -> [String: Any]? {
        if let object = rawValue as? [String: Any] {
            return object
        }
        guard let string = rawValue as? String,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    func patchHunks(_ raw: [[String: Any]]?) -> [PatchHunk]? {
        let hunks = (raw ?? []).compactMap { patch -> PatchHunk? in
            guard let oldStart = patch["oldStart"] as? Int,
                  let oldLines = patch["oldLines"] as? Int,
                  let newStart = patch["newStart"] as? Int,
                  let newLines = patch["newLines"] as? Int,
                  let lines = patch["lines"] as? [String] else {
                return nil
            }
            return PatchHunk(oldStart: oldStart, oldLines: oldLines, newStart: newStart, newLines: newLines, lines: lines)
        }
        return hunks.isEmpty ? nil : hunks
    }

    func nestedString(_ payload: [String: Any], _ objectKey: String, _ valueKey: String) -> String? {
        (payload[objectKey] as? [String: Any])?[valueKey] as? String
    }

    func nestedInt(_ payload: [String: Any], _ objectKey: String, _ valueKey: String) -> Int? {
        (payload[objectKey] as? [String: Any])?[valueKey] as? Int
    }
}
