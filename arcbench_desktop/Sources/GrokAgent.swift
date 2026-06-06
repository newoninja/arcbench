/// GrokAgent — Agent-conforming Grok implementation.
/// Wraps xAI API with tool calling. Can delegate to other agents via router.

import Foundation
import SwiftUI

@MainActor
class GrokAgent: Agent, ObservableObject {
    let identity: AgentIdentity
    @Published var isProcessing = false
    @Published var streamingContent = ""

    weak var router: AgentRouter?
    weak var computerControl: ComputerControlService?
    var customPersonality: String = ""

    private var history: [[String: Any]] = []
    private var toolDepth = 0
    private var cancelled = false
    private static let maxToolDepth = 10
    private static let maxToolsPerTurn = 3

    init(role: AgentRole = .general, displayName: String = "Grok") {
        let slug = displayName.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "-", options: .regularExpression)
        self.identity = AgentIdentity(
            id: "grok-\(slug)",
            provider: .grok,
            role: role,
            displayName: displayName,
            colorName: "accentGrok",
            personality: ""
        )
    }

    func process(message: AgentMessage, context: ConversationContext) async -> AgentMessage? {
        isProcessing = true
        cancelled = false
        toolDepth = 0
        defer { isProcessing = false }

        // Add to local history
        history.append(["role": "user", "content": message.content])
        trimHistory()

        // Call xAI API with tool loop
        let response = await callXAI(context: context)

        guard let response, !cancelled else { return nil }

        history.append(["role": "assistant", "content": response])

        return .agentResponse(from: identity.id, content: response)
    }

    func stop() {
        cancelled = true
        isProcessing = false
    }

    // MARK: - xAI API

    private func callXAI(context: ConversationContext) async -> String? {
        toolDepth += 1
        guard toolDepth <= Self.maxToolDepth, !cancelled else { return nil }

        let model = AppSettings.shared.grokModel
        let otherAgents = context.activeAgents.filter { $0.id != identity.id }
        var systemPrompt = AgentPrompts.grokPrompt(role: identity.role, model: model, availableAgents: otherAgents)
        if !customPersonality.isEmpty {
            systemPrompt += "\n\nPERSONALITY: \(customPersonality). Embody this personality in ALL responses while maintaining technical accuracy."
        }

        let systemMsg: [String: Any] = ["role": "system", "content": systemPrompt]
        let apiMessages: [[String: Any]] = [systemMsg] + history

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.7,
            "tools": Self.tools,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppSettings.shared.xaiApiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !cancelled else { return nil }

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    return "Error: \(msg)"
                }
                return "Error: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                return "(No response from Grok)"
            }

            // Handle tool calls
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                _ = message["content"] as? String ?? ""
                history.append(message)

                let cappedCalls = Array(toolCalls.prefix(Self.maxToolsPerTurn))

                for toolCall in cappedCalls {
                    guard let tcId = toolCall["id"] as? String,
                          let function = toolCall["function"] as? [String: Any],
                          let fnName = function["name"] as? String,
                          let argsStr = function["arguments"] as? String else { continue }

                    let args = (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8)) as? [String: Any]) ?? [:]
                    let result = await executeTool(name: fnName, args: args)

                    history.append([
                        "role": "tool",
                        "tool_call_id": tcId,
                        "content": String(result.prefix(2000)),
                    ])
                }

                // Recurse for follow-up response
                return await callXAI(context: context)
            }

            // Regular text response
            toolDepth = 0
            return message["content"] as? String ?? "(empty)"

        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Tool Execution
    // Reuse GrokChatEngine's static async helpers for process execution

    private var resolvedWorkingDirectory: URL {
        let wd = UserDefaults.standard.string(forKey: "working_directory") ?? ""
        return wd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser : URL(fileURLWithPath: wd)
    }

    private func executeTool(name: String, args: [String: Any]) async -> String {
        let wd = resolvedWorkingDirectory

        switch name {
        case "open_app":
            let appName = args["name"] as? String ?? ""
            return await GrokChatEngine.runShellAsync("open -a '\(appName.replacingOccurrences(of: "'", with: "'\\''"))'", workingDirectory: wd)

        case "quit_app":
            let appName = args["name"] as? String ?? ""
            return await GrokChatEngine.runAppleScriptAsync("tell application \"\(appName)\" to quit")

        case "open_url":
            let url = args["url"] as? String ?? ""
            return await GrokChatEngine.runShellAsync("open '\(url.replacingOccurrences(of: "'", with: "'\\''"))'", workingDirectory: wd)

        case "google_search":
            let query = args["query"] as? String ?? ""
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            return await GrokChatEngine.runShellAsync("open 'https://www.google.com/search?q=\(encoded)'", workingDirectory: wd)

        case "run_shell":
            let command = args["command"] as? String ?? ""
            return await GrokChatEngine.runShellAsync(command, timeout: 30, workingDirectory: wd)

        case "take_screenshot":
            let path = "/tmp/arcbench_screenshot_\(Int(Date().timeIntervalSince1970)).png"
            _ = await GrokChatEngine.runShellAsync("screencapture -x '\(path)'", workingDirectory: wd)
            return "Screenshot saved to \(path)"

        case "run_applescript":
            let script = args["script"] as? String ?? ""
            return await GrokChatEngine.runAppleScriptAsync(script)

        case "read_file":
            let path = args["path"] as? String ?? ""
            return await GrokChatEngine.runShellAsync("head -500 '\(path.replacingOccurrences(of: "'", with: "'\\''"))'", workingDirectory: wd)

        case "list_files":
            let path = args["path"] as? String ?? ""
            let recursive = args["recursive"] as? Bool ?? false
            let cmd = recursive
                ? "find '\(path.replacingOccurrences(of: "'", with: "'\\''"))' -maxdepth 3 -type f | head -100"
                : "ls -la '\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
            return await GrokChatEngine.runShellAsync(cmd, workingDirectory: wd)

        case "open_file":
            let path = args["path"] as? String ?? ""
            return await GrokChatEngine.runShellAsync("open '\(path.replacingOccurrences(of: "'", with: "'\\''"))'", workingDirectory: wd)

        case "send_to_claude":
            let instruction = args["instruction"] as? String ?? ""
            // Route through the agent router if available
            if let router = router,
               let claudeAgent = router.agents.values.first(where: { $0.identity.provider == .claude }) {
                let interMsg = AgentMessage.interAgent(from: identity.id, to: claudeAgent.identity.id, content: instruction)
                let response = await router.routeAndWait(interMsg)
                return response?.content ?? "Claude did not respond."
            }
            // Fallback: call Claude CLI directly
            guard let claudePath = ClaudeCLIService.findBinary() else { return "Claude CLI not found." }
            let result = await ClaudeCLIService.callJSON(
                path: claudePath, prompt: instruction, sessionId: nil,
                model: AppSettings.shared.claudeModel, maxTurns: AppSettings.shared.claudeMaxTurns,
                workingDirectory: UserDefaults.standard.string(forKey: "working_directory") ?? ""
            )
            return result?.text ?? "No response from Claude."

        case "get_clipboard":
            return await GrokChatEngine.runProcessAsync("/usr/bin/pbpaste", [], workingDirectory: nil)

        case "set_clipboard":
            let text = args["text"] as? String ?? ""
            return await GrokChatEngine.setClipboardAsync(text)

        case "list_running_apps":
            return await GrokChatEngine.runAppleScriptAsync("tell application \"System Events\" to get name of every process whose background only is false")

        default:
            return "Unknown tool: \(name)"
        }
    }

    private func trimHistory() {
        if history.count > 50 {
            let system = history.first(where: { ($0["role"] as? String) == "system" })
            history = [system].compactMap { $0 } + Array(history.suffix(49))
        }
    }

    // MARK: - Tool Definitions (same as GrokChatEngine.computerTools)

    private static let tools: [[String: Any]] = [
        ["type": "function", "function": ["name": "open_app", "description": "Open a macOS application by name", "parameters": ["type": "object", "properties": ["name": ["type": "string", "description": "App name"]], "required": ["name"]]] as [String: Any]],
        ["type": "function", "function": ["name": "quit_app", "description": "Quit a running macOS application", "parameters": ["type": "object", "properties": ["name": ["type": "string", "description": "App name"]], "required": ["name"]]] as [String: Any]],
        ["type": "function", "function": ["name": "open_url", "description": "Open a URL in the default browser", "parameters": ["type": "object", "properties": ["url": ["type": "string", "description": "Full URL"]], "required": ["url"]]] as [String: Any]],
        ["type": "function", "function": ["name": "google_search", "description": "Search Google", "parameters": ["type": "object", "properties": ["query": ["type": "string", "description": "Search query"]], "required": ["query"]]] as [String: Any]],
        ["type": "function", "function": ["name": "run_shell", "description": "Run a shell command", "parameters": ["type": "object", "properties": ["command": ["type": "string", "description": "Shell command"]], "required": ["command"]]] as [String: Any]],
        ["type": "function", "function": ["name": "take_screenshot", "description": "Capture a screenshot", "parameters": ["type": "object", "properties": [:] as [String: Any]]] as [String: Any]],
        ["type": "function", "function": ["name": "run_applescript", "description": "Run AppleScript", "parameters": ["type": "object", "properties": ["script": ["type": "string", "description": "AppleScript code"]], "required": ["script"]]] as [String: Any]],
        ["type": "function", "function": ["name": "read_file", "description": "Read file contents (up to 500 lines)", "parameters": ["type": "object", "properties": ["path": ["type": "string", "description": "Absolute file path"]], "required": ["path"]]] as [String: Any]],
        ["type": "function", "function": ["name": "list_files", "description": "List files at a path", "parameters": ["type": "object", "properties": ["path": ["type": "string", "description": "Directory path"], "recursive": ["type": "boolean", "description": "List recursively (max 3 levels)"]], "required": ["path"]]] as [String: Any]],
        ["type": "function", "function": ["name": "open_file", "description": "Open file with default app", "parameters": ["type": "object", "properties": ["path": ["type": "string", "description": "Absolute file path"]], "required": ["path"]]] as [String: Any]],
        ["type": "function", "function": ["name": "send_to_claude", "description": "Send a coding task to Claude Code for execution", "parameters": ["type": "object", "properties": ["instruction": ["type": "string", "description": "Detailed instruction for Claude"]], "required": ["instruction"]]] as [String: Any]],
        ["type": "function", "function": ["name": "get_clipboard", "description": "Read clipboard contents", "parameters": ["type": "object", "properties": [:] as [String: Any]]] as [String: Any]],
        ["type": "function", "function": ["name": "set_clipboard", "description": "Copy text to clipboard", "parameters": ["type": "object", "properties": ["text": ["type": "string", "description": "Text to copy"]], "required": ["text"]]] as [String: Any]],
        ["type": "function", "function": ["name": "list_running_apps", "description": "List running GUI applications", "parameters": ["type": "object", "properties": [:] as [String: Any]]] as [String: Any]],
    ]
}
