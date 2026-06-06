/// GrokChatEngine — ObservableObject managing Grok ↔ Claude chat flow.
/// Handles xAI API calls, tool execution, and Claude CLI piping.

import SwiftUI
import Foundation

// MARK: - Grok Chat Message

struct GrokChatMessage: Identifiable {
    let id = UUID()
    let role: String  // "user", "assistant", "claude", "tool"
    var content: String
    var attachedFiles: [AttachedFile] = []
    var toolName: String? = nil  // for tool-use display
}

// MARK: - Grok Chat Engine

@MainActor
class GrokChatEngine: ObservableObject {
    @Published var messages: [GrokChatMessage] = []
    @Published var isStreaming = false
    @Published var isExecuting = false
    @Published var error: String?
    /// Persists draft text across view recreation (e.g. Settings toggle)
    @Published var draftText: String = ""

    var xaiKey: String {
        get { AppSettings.shared.xaiApiKey }
        set { AppSettings.shared.xaiApiKey = newValue }
    }
    /// When true, Grok's response is auto-sent to Claude CLI for execution
    var autoExecute: Bool {
        get { AppSettings.shared.useClaudeCLI }
    }
    private var history: [[String: Any]] = []
    private var cancelled = false
    private var claudeSessionId: String?
    private var claudeProcess: Process?
    private var activeShellCount = 0
    private static let maxConcurrentShells = 3
    private static let shellTimeout: TimeInterval = 30

    /// Reference to ComputerControlService for animations (injected from view)
    weak var computerControl: ComputerControlService?

    func send(_ displayText: String, apiText: String, files: [AttachedFile] = []) {
        guard !apiText.isEmpty, !isStreaming, !isExecuting else { return }
        cancelled = false
        toolDepth = 0

        messages.append(GrokChatMessage(role: "user", content: displayText, attachedFiles: files))

        // Check for @mentions anywhere in the text to route to a specific model
        let lower = apiText.lowercased()
        let mentionsGrok = lower.contains("@grok")
        let mentionsClaude = lower.contains("@claude")

        // Strip the @mention from the text (wherever it appears)
        let cleanedText: String
        if mentionsGrok {
            cleanedText = apiText.replacingOccurrences(of: "(?i)\\s*@grok\\s*", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        } else if mentionsClaude {
            cleanedText = apiText.replacingOccurrences(of: "(?i)\\s*@claude\\s*", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        } else {
            cleanedText = apiText
        }

        if mentionsGrok {
            // Send directly to Grok only — no Claude execution
            messages.append(GrokChatMessage(role: "assistant", content: ""))
            isStreaming = true
            history.append(["role": "user", "content": cleanedText])
            Task { await callGrokOnly(cleanedText) }
        } else if mentionsClaude {
            // Send directly to Claude only — skip Grok
            Task { await executeWithClaude(instruction: cleanedText) }
        } else {
            // Default flow: Grok responds with tools (can invoke Claude via send_to_claude tool if needed)
            messages.append(GrokChatMessage(role: "assistant", content: ""))
            isStreaming = true
            history.append(["role": "user", "content": cleanedText])
            Task { await callGrokOnly(cleanedText) }
        }
    }

    func stop() {
        let wasActive = isStreaming || isExecuting
        cancelled = true
        isStreaming = false
        isExecuting = false
        toolDepth = 0
        claudeProcess?.terminate()
        claudeProcess = nil

        if wasActive {
            if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant", messages[lastIdx].content.isEmpty {
                messages[lastIdx].content = "Stopped."
            } else {
                messages.append(GrokChatMessage(role: "tool", content: "Stopped by user.", toolName: "stop"))
            }
        }
    }

    func clear() {
        messages.removeAll()
        history.removeAll()
        error = nil
        claudeSessionId = nil
        toolDepth = 0
    }

    // MARK: - Tool Definitions (OpenAI function calling format)

    private static let computerTools: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "open_app",
                "description": "Open a macOS application by name (e.g. Safari, Chrome, Finder, Terminal, Xcode, Notes, Mail, Messages, Spotify, Slack, Discord, VS Code)",
                "parameters": [
                    "type": "object",
                    "properties": ["name": ["type": "string", "description": "App name exactly as it appears in /Applications"]],
                    "required": ["name"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "quit_app",
                "description": "Quit/close a running macOS application",
                "parameters": [
                    "type": "object",
                    "properties": ["name": ["type": "string", "description": "App name to quit"]],
                    "required": ["name"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "open_url",
                "description": "Open a URL in the user's default web browser. Use this to navigate to websites, Google searches, etc.",
                "parameters": [
                    "type": "object",
                    "properties": ["url": ["type": "string", "description": "Full URL including https://"]],
                    "required": ["url"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "google_search",
                "description": "Open Google in the browser and search for something",
                "parameters": [
                    "type": "object",
                    "properties": ["query": ["type": "string", "description": "Search query"]],
                    "required": ["query"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "run_shell",
                "description": "Run a shell command on macOS and return its output",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "command": ["type": "string", "description": "Shell command to execute"],
                    ],
                    "required": ["command"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "take_screenshot",
                "description": "Capture a screenshot of the entire screen",
                "parameters": ["type": "object", "properties": [:] as [String: Any]],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "run_applescript",
                "description": "Run an AppleScript to control macOS apps, system settings, dialogs, notifications, etc. Very powerful for automation.",
                "parameters": [
                    "type": "object",
                    "properties": ["script": ["type": "string", "description": "AppleScript code"]],
                    "required": ["script"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "read_file",
                "description": "Read the contents of a file and return them as text. Use this to inspect source code, config files, logs, etc. Returns up to 500 lines.",
                "parameters": [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Absolute file path"]],
                    "required": ["path"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "list_files",
                "description": "List files and directories at a path. Returns names, sizes, and types. Use this to explore project structure before reading files.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Directory path to list"],
                        "recursive": ["type": "boolean", "description": "If true, list recursively (max 3 levels deep)"],
                    ],
                    "required": ["path"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "open_file",
                "description": "Open a file with its default application (e.g. images in Preview, PDFs in Preview). Do NOT use this to read source code — use read_file instead.",
                "parameters": [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Absolute file path"]],
                    "required": ["path"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "send_to_claude",
                "description": "Send a coding task to Claude Code CLI for execution. Claude has full filesystem access and can create/edit files, run commands, and build projects. Use this for coding tasks, file manipulation, git operations, etc.",
                "parameters": [
                    "type": "object",
                    "properties": ["instruction": ["type": "string", "description": "Detailed instruction for Claude Code to execute"]],
                    "required": ["instruction"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "get_clipboard",
                "description": "Read the current clipboard contents",
                "parameters": ["type": "object", "properties": [:] as [String: Any]],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "set_clipboard",
                "description": "Copy text to the clipboard",
                "parameters": [
                    "type": "object",
                    "properties": ["text": ["type": "string", "description": "Text to copy"]],
                    "required": ["text"],
                ],
            ] as [String: Any],
        ],
        [
            "type": "function",
            "function": [
                "name": "list_running_apps",
                "description": "List all currently running GUI applications",
                "parameters": ["type": "object", "properties": [:] as [String: Any]],
            ] as [String: Any],
        ],
    ]

    // MARK: - Helpers

    private var resolvedWorkingDirectory: URL {
        let wd = UserDefaults.standard.string(forKey: "working_directory") ?? ""
        return wd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser : URL(fileURLWithPath: wd)
    }

    /// Keep the system message + last 49 entries to cap memory usage.
    private func trimHistory() {
        guard history.count > 50 else { return }
        // If the first entry is a system message, preserve it
        if let role = history.first?["role"] as? String, role == "system" {
            history = [history[0]] + Array(history.suffix(49))
        } else {
            history = Array(history.suffix(50))
        }
    }

    // MARK: - Grok API Call with Tool Calling

    /// Maximum number of tool-call round-trips before forcing a text response
    private static let maxToolDepth = 8
    private var toolDepth = 0

    private func callGrok() async {
        // Guard against infinite tool-call recursion
        toolDepth += 1
        guard toolDepth <= Self.maxToolDepth else {
            if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                messages[lastIdx].content = "(Stopped: too many tool calls in a row)"
            }
            toolDepth = 0
            isStreaming = false
            return
        }
        trimHistory()
        let currentModel = AppSettings.shared.grokModel
        let systemMsg: [String: Any] = ["role": "system", "content":
            "You are Grok, an AI assistant built by xAI. You are running model '\(currentModel)'. You are embedded in ArcBench, a desktop control app on macOS. " +
            "You have FULL CONTROL of the user's computer through your tools. " +
            "\n\nWhen the user asks you to do something on their computer, USE YOUR TOOLS to do it directly. " +
            "DO NOT just describe how to do it — actually DO it by calling the appropriate tool. " +
            "\n\nExamples:" +
            "\n- 'open google' → call open_url with https://www.google.com" +
            "\n- 'search for cats' → call google_search with 'cats'" +
            "\n- 'open Safari' → call open_app with 'Safari'" +
            "\n- 'create a new project' → call send_to_claude with the instruction" +
            "\n- 'what apps are running' → call list_running_apps" +
            "\n- 'show a notification' → call run_applescript" +
            "\n\nIMPORTANT RULES:" +
            "\n- Do NOT call open_app before google_search or open_url — those tools open the browser automatically." +
            "\n- Do NOT use multiple tools when one tool does the job. e.g. 'open chrome and search X' → just call google_search." +
            "\n- Be proactive and action-oriented. After executing tools, briefly confirm what you did. The user is on macOS."
        ]

        let apiMessages: [[String: Any]] = [systemMsg] + history

        // Non-streaming request for tool calling support
        let body: [String: Any] = [
            "model": AppSettings.shared.grokModel,
            "messages": apiMessages,
            "temperature": 0.7,
            "tools": Self.computerTools,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            error = "Failed to encode request"; isStreaming = false; return
        }

        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(xaiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !cancelled else { isStreaming = false; return }

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    error = msg
                    if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                        messages[lastIdx].content = "Error: \(msg)"
                    }
                }
                isStreaming = false
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                    messages[lastIdx].content = "(Grok returned no response)"
                }
                isStreaming = false
                return
            }

            let finishReason = choices.first?["finish_reason"] as? String

            // Check for tool calls
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                let content = message["content"] as? String ?? ""
                if !content.isEmpty {
                    if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                        messages[lastIdx].content = content
                    }
                }

                // Add assistant message with tool_calls to history
                history.append(message)

                // Cap tool calls per turn to prevent system overload
                let cappedCalls = Array(toolCalls.prefix(3))
                if toolCalls.count > 3 {
                    messages.append(GrokChatMessage(role: "tool", content: "Capped at 3 tool calls (requested \(toolCalls.count))", toolName: "system"))
                }

                // Execute each tool call
                for toolCall in cappedCalls {
                    guard let tcId = toolCall["id"] as? String,
                          let function = toolCall["function"] as? [String: Any],
                          let fnName = function["name"] as? String,
                          let argsStr = function["arguments"] as? String else { continue }

                    let args = (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8)) as? [String: Any]) ?? [:]

                    // Show tool execution in UI
                    messages.append(GrokChatMessage(role: "tool", content: "Executing: \(fnName)…", toolName: fnName))

                    // Execute the tool
                    let result = await executeTool(name: fnName, args: args)

                    // Update UI with result
                    if let lastIdx = messages.indices.last, messages[lastIdx].toolName == fnName {
                        let shortResult = String(result.prefix(500))
                        messages[lastIdx].content = shortResult.isEmpty ? "Done" : shortResult
                    }

                    // Add tool result to history
                    history.append([
                        "role": "tool",
                        "tool_call_id": tcId,
                        "content": String(result.prefix(2000)),
                    ])
                }

                // Remove stale empty assistant message before recursing
                if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" && messages[lastIdx].content.isEmpty {
                    messages.remove(at: lastIdx)
                }
                // Call Grok again to get a follow-up response after tool execution
                messages.append(GrokChatMessage(role: "assistant", content: ""))
                await callGrok()
                return
            }

            // Regular text response (no tool calls) — reset depth counter
            toolDepth = 0
            let content = message["content"] as? String ?? "(empty)"
            if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                messages[lastIdx].content = content
            }
            history.append(["role": "assistant", "content": content])
            isStreaming = false

            // If Grok didn't use tools but autoExecute is on, pipe to Claude
            if autoExecute && !cancelled && finishReason == "stop" && content.count > 20 {
                // Only auto-execute if the response looks like an instruction (not a tool result summary)
                let lc = content.lowercased()
                let isInstruction = !lc.contains("opened") && !lc.contains("done") && !lc.contains("executed")
                if isInstruction {
                    await executeWithClaude(instruction: content)
                }
            }
        } catch {
            toolDepth = 0
            if !cancelled {
                self.error = error.localizedDescription
                if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                    messages[lastIdx].content = "Error: \(error.localizedDescription)"
                }
            }
            isStreaming = false
        }
    }

    // MARK: - Grok Only (direct conversation, no Claude)

    private static let maxToolDepthConversational = 12

    private func callGrokOnly(_ text: String) async {
        // Guard against infinite tool-call recursion — tighter limit for conversational mode
        toolDepth += 1
        guard toolDepth <= Self.maxToolDepthConversational else {
            if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                messages[lastIdx].content = "(Stopped: too many tool calls — ask me to try a different approach)"
            }
            toolDepth = 0
            isStreaming = false
            return
        }
        trimHistory()
        let currentModel = AppSettings.shared.grokModel
        let systemMsg: [String: Any] = ["role": "system", "content":
            "You are Grok, an AI assistant built by xAI. You are running model '\(currentModel)'. The user is talking to you directly. " +
            "Respond conversationally. Be helpful, direct, and concise. " +
            "You have tools for computer control if the user asks you to do something on their Mac. " +
            "\n\nIMPORTANT RULES:" +
            "\n- Do NOT call open_app before google_search or open_url — those tools open the browser automatically." +
            "\n- Use the MINIMUM number of tool calls needed. Prefer 1-2 calls max." +
            "\n- If a tool call returns an error (file not found, command failed, etc.), do NOT retry with variations. Tell the user what happened and ask for clarification." +
            "\n- For code reviews, large codebase analysis, or complex multi-step coding tasks, use send_to_claude — Claude Code has full filesystem access and can read entire projects efficiently." +
            "\n- You CAN use read_file and list_files to explore files yourself for quick questions." +
            "\n- NEVER run more than 3 tool calls in a single response."
        ]

        let apiMessages: [[String: Any]] = [systemMsg] + history

        let body: [String: Any] = [
            "model": AppSettings.shared.grokModel,
            "messages": apiMessages,
            "temperature": 0.7,
            "tools": Self.computerTools,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            error = "Failed to encode request"; isStreaming = false; return
        }

        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(xaiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !cancelled else { isStreaming = false; return }

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    error = msg
                    if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                        messages[lastIdx].content = "Error: \(msg)"
                    }
                }
                isStreaming = false
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                    messages[lastIdx].content = "(Grok returned no response)"
                }
                isStreaming = false
                return
            }

            // Handle tool calls same as callGrok
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                let content = message["content"] as? String ?? ""
                if !content.isEmpty {
                    if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                        messages[lastIdx].content = content
                    }
                }
                history.append(message)

                let cappedCalls = Array(toolCalls.prefix(3))
                if toolCalls.count > 3 {
                    messages.append(GrokChatMessage(role: "tool", content: "Capped at 3 tool calls (requested \(toolCalls.count))", toolName: "system"))
                }

                for toolCall in cappedCalls {
                    guard let tcId = toolCall["id"] as? String,
                          let function = toolCall["function"] as? [String: Any],
                          let fnName = function["name"] as? String,
                          let argsStr = function["arguments"] as? String else { continue }

                    let args = (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8)) as? [String: Any]) ?? [:]
                    messages.append(GrokChatMessage(role: "tool", content: "Executing: \(fnName)…", toolName: fnName))
                    let result = await executeTool(name: fnName, args: args)
                    if let lastIdx = messages.indices.last, messages[lastIdx].toolName == fnName {
                        let shortResult = String(result.prefix(500))
                        messages[lastIdx].content = shortResult.isEmpty ? "Done" : shortResult
                    }
                    history.append([
                        "role": "tool",
                        "tool_call_id": tcId,
                        "content": String(result.prefix(2000)),
                    ])
                }

                // Remove stale empty assistant message before recursing
                if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" && messages[lastIdx].content.isEmpty {
                    messages.remove(at: lastIdx)
                }
                messages.append(GrokChatMessage(role: "assistant", content: ""))
                await callGrokOnly(text)
                return
            }

            // Regular text response — NO auto-execute to Claude — reset depth counter
            toolDepth = 0
            let content = message["content"] as? String ?? "(empty)"
            if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                messages[lastIdx].content = content
            }
            history.append(["role": "assistant", "content": content])
            isStreaming = false
        } catch {
            toolDepth = 0
            if !cancelled {
                self.error = error.localizedDescription
                if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                    messages[lastIdx].content = "Error: \(error.localizedDescription)"
                }
            }
            isStreaming = false
        }
    }

    // MARK: - Tool Execution (runs locally on macOS — no backend needed)

    private func executeTool(name: String, args: [String: Any]) async -> String {
        let wd = resolvedWorkingDirectory

        switch name {
        case "open_app":
            let appName = args["name"] as? String ?? ""
            await computerControl?.openApp(appName)
            let result = await Self.runShellAsync("open -a '\(appName.replacingOccurrences(of: "'", with: "'\\''"))'", workingDirectory: wd)
            return result.isEmpty ? "Opened \(appName)" : "Error: \(result)"

        case "quit_app":
            let appName = args["name"] as? String ?? ""
            await computerControl?.quitApp(appName)
            let script = "tell application \"\(appName)\" to quit"
            return await Self.runAppleScriptAsync(script)

        case "open_url":
            let url = args["url"] as? String ?? ""
            await computerControl?.openURL(url)
            let result = await Self.runShellAsync("open '\(url.replacingOccurrences(of: "'", with: "'\\''"))'", workingDirectory: wd)
            return result.isEmpty ? "Opened \(url)" : "Error: \(result)"

        case "google_search":
            let query = args["query"] as? String ?? ""
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = "https://www.google.com/search?q=\(encoded)"
            await computerControl?.openURL(url)
            let result = await Self.runShellAsync("open '\(url)'", workingDirectory: wd)
            return result.isEmpty ? "Searched Google for '\(query)'" : "Error: \(result)"

        case "run_shell":
            let command = args["command"] as? String ?? ""
            guard activeShellCount < Self.maxConcurrentShells else {
                return "Skipped — too many commands running (\(activeShellCount)/\(Self.maxConcurrentShells)). Wait for current commands to finish."
            }
            activeShellCount += 1
            defer { activeShellCount -= 1 }
            await computerControl?.runShell(command)
            return await Self.runShellAsync(command, timeout: Self.shellTimeout, workingDirectory: wd)

        case "take_screenshot":
            await computerControl?.takeScreenshot()
            let path = "/tmp/arcbench_screenshot_\(Int(Date().timeIntervalSince1970)).png"
            _ = await Self.runShellAsync("screencapture -x '\(path)'", workingDirectory: wd)
            return "Screenshot saved to \(path)"

        case "run_applescript":
            let script = args["script"] as? String ?? ""
            await computerControl?.runAppleScript(script)
            return await Self.runAppleScriptAsync(script)

        case "read_file":
            let path = args["path"] as? String ?? ""
            let fullPath = path.hasPrefix("/") ? path : wd.appendingPathComponent(path).path
            do {
                let content = try String(contentsOfFile: fullPath, encoding: .utf8)
                let lines = content.components(separatedBy: "\n")
                if lines.count > 500 {
                    return lines.prefix(500).joined(separator: "\n") + "\n\n... (\(lines.count - 500) more lines truncated)"
                }
                return content.isEmpty ? "(empty file)" : content
            } catch {
                return "Error reading \(path): \(error.localizedDescription)"
            }

        case "list_files":
            let path = args["path"] as? String ?? ""
            let recursive = args["recursive"] as? Bool ?? false
            let escaped = path.hasPrefix("/") ? path.replacingOccurrences(of: "'", with: "'\\''") : wd.appendingPathComponent(path).path.replacingOccurrences(of: "'", with: "'\\''")
            if recursive {
                let result = await Self.runShellAsync("find '\(escaped)' -maxdepth 3 -not -path '*/.*' | head -200", workingDirectory: wd)
                return result.isEmpty ? "No files found at \(path)" : result
            } else {
                let result = await Self.runShellAsync("ls -la '\(escaped)'", workingDirectory: wd)
                return result.isEmpty ? "No files found at \(path)" : result
            }

        case "open_file":
            let path = args["path"] as? String ?? ""
            await computerControl?.openFile(path)
            let result = await Self.runShellAsync("open '\(path.replacingOccurrences(of: "'", with: "'\\''"))'", workingDirectory: wd)
            return result.isEmpty ? "Opened \(path)" : "Error: \(result)"

        case "send_to_claude":
            let instruction = args["instruction"] as? String ?? ""
            messages.append(GrokChatMessage(role: "claude", content: ""))
            isExecuting = true
            await executeWithClaude(instruction: instruction)
            isExecuting = false
            if let lastMsg = messages.last, lastMsg.role == "claude" {
                return String(lastMsg.content.prefix(2000))
            }
            return "Claude executed the instruction."

        case "get_clipboard":
            let result = await Self.runProcessAsync("/usr/bin/pbpaste", [])
            return result.isEmpty ? "(clipboard is empty)" : String(result.prefix(2000))

        case "set_clipboard":
            let text = args["text"] as? String ?? ""
            return await Self.setClipboardAsync(text)

        case "list_running_apps":
            return await Self.runAppleScriptAsync("tell application \"System Events\" to get name of every process whose background only is false")

        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Async Process Helpers (off main thread)

    nonisolated static func runProcessAsync(_ executable: String, _ arguments: [String], workingDirectory: URL? = nil) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = arguments
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                if let wd = workingDirectory { proc.currentDirectoryURL = wd }
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }

    nonisolated static func runShellAsync(_ command: String, timeout: TimeInterval = 60, workingDirectory: URL? = nil) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-c", command]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                proc.currentDirectoryURL = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
                do {
                    try proc.run()
                    let deadline = DispatchTime.now() + timeout
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if proc.isRunning { proc.terminate() }
                    }
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(returning: output.isEmpty ? "Command timed out after \(Int(timeout))s" : output + "\n(timed out)")
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }

    nonisolated static func runAppleScriptAsync(_ script: String) async -> String {
        await runProcessAsync("/usr/bin/osascript", ["-e", script])
    }

    nonisolated static func setClipboardAsync(_ text: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
                let pipe = Pipe()
                proc.standardInput = pipe
                do {
                    try proc.run()
                    pipe.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
                    pipe.fileHandleForWriting.closeFile()
                    proc.waitUntilExit()
                    continuation.resume(returning: "Copied to clipboard")
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Claude CLI Execution

    func executeWithClaude(instruction: String) async {
        // Prevent concurrent execution
        guard !isExecuting else { return }

        // Find claude binary
        let env = ProcessInfo.processInfo.environment
        let searchPaths = [
            "/usr/local/bin/claude", "/opt/homebrew/bin/claude",
            "\(env["HOME"] ?? "")/.npm-global/bin/claude",
            "\(env["HOME"] ?? "")/.local/bin/claude",
        ]
        guard let claudePath = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }

        // Add a "Claude executing" message
        messages.append(GrokChatMessage(role: "claude", content: ""))
        isExecuting = true

        let currentSessionId = claudeSessionId
        let maxTurns = AppSettings.shared.claudeMaxTurns
        let model = AppSettings.shared.claudeModel
        let wd = resolvedWorkingDirectory

        // Build process on main thread so we can store the reference
        let proc = Process()
        claudeProcess = proc
        proc.executableURL = URL(fileURLWithPath: claudePath)
        var args = [
            "-p", instruction,
            "--output-format", "stream-json",
            "--verbose",
            "--dangerously-skip-permissions",
            "--max-turns", "\(maxTurns)",
            "--model", model,
        ]
        if let sid = currentSessionId {
            args += ["--resume", sid]
        }
        proc.arguments = args

        var procEnv = ProcessInfo.processInfo.environment
        procEnv["TERM"] = "dumb"
        procEnv["NO_COLOR"] = "1"
        proc.environment = procEnv
        proc.currentDirectoryURL = wd

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        // Drain stderr to prevent pipe buffer deadlock
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData  // discard but keep draining
        }

        // Stream JSONL output and update the claude message progressively
        let buffer = LockedBuffer()
        let textBuffer = LockedBuffer()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            buffer.append(chunk)
            for line in chunk.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let lineData = trimmed.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = event["type"] as? String else { continue }

                if type == "assistant",
                   let message = event["message"] as? [String: Any],
                   let contentBlocks = message["content"] as? [[String: Any]] {
                    for block in contentBlocks {
                        if block["type"] as? String == "text",
                           let text = block["text"] as? String {
                            let snapshot = textBuffer.append(text)
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                if let lastIdx = self.messages.indices.last,
                                   self.messages[lastIdx].role == "claude" {
                                    self.messages[lastIdx].content = snapshot
                                }
                            }
                        }
                    }
                }
            }
        }

        // Run the process and wait on a background thread
        let result: (text: String, sessionId: String?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try proc.run()
                    proc.waitUntilExit()

                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    let remaining = stdout.fileHandleForReading.readDataToEndOfFile()
                    if let chunk = String(data: remaining, encoding: .utf8), !chunk.isEmpty {
                        buffer.append(chunk)
                    }

                    // Parse all JSONL to find result
                    let allOutput = buffer.value
                    var finalResult = textBuffer.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    var sid: String? = nil

                    for line in allOutput.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              let lineData = trimmed.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = event["type"] as? String else { continue }
                        if type == "result" {
                            if let r = event["result"] as? String, !r.isEmpty { finalResult = r }
                            if let s = event["session_id"] as? String { sid = s }
                        }
                        if type == "assistant" && finalResult.isEmpty,
                           let message = event["message"] as? [String: Any],
                           let contentBlocks = message["content"] as? [[String: Any]] {
                            for block in contentBlocks {
                                if block["type"] as? String == "text",
                                   let text = block["text"] as? String {
                                    finalResult += text
                                }
                            }
                        }
                    }

                    continuation.resume(returning: (finalResult, sid))
                } catch {
                    continuation.resume(returning: ("(Claude CLI failed: \(error.localizedDescription))", nil))
                }
            }
        }

        claudeProcess = nil

        if let sid = result.sessionId {
            claudeSessionId = sid
        }

        if let lastIdx = messages.indices.last, messages[lastIdx].role == "claude" {
            messages[lastIdx].content = result.text.isEmpty ? "(No output)" : result.text
        }
        isExecuting = false
    }
}
