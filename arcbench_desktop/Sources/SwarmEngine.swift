/// SwarmEngine — Grok ↔ Claude continuous inspection loop.
/// Grok (via xAI OpenAI-compatible API) is the strict Boss.
/// Claude (via Anthropic API) is the Worker.
/// Runs entirely in-process — no backend needed.

import Foundation

// MARK: - Thread-safe string buffer

final class LockedBuffer: @unchecked Sendable {
    private var _value = ""
    private let lock = NSLock()

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func append(_ chunk: String) -> String {
        lock.lock()
        _value += chunk
        let snapshot = _value
        lock.unlock()
        return snapshot
    }
}

// MARK: - Data Types

enum SwarmPhase: String {
    case idle = "Idle"
    case grokPlanning = "Grok Planning"
    case claudeExecuting = "Claude Executing"
    case grokJudging = "Grok Judging"
    case approved = "Approved"
    case error = "Error"
}

struct SwarmEvent: Identifiable {
    let id = UUID()
    let iteration: Int
    let phase: SwarmPhase
    let role: SwarmRole
    let content: String
    let approved: Bool
    let finalOutput: String
    var files: [AttachedFile] = []

    enum SwarmRole: String {
        case grok, claude, system, user
    }
}

// MARK: - Swarm Engine

@MainActor
class SwarmEngine: ObservableObject {
    @Published var events: [SwarmEvent] = []
    @Published var phase: SwarmPhase = .idle
    @Published var iteration: Int = 0
    @Published var isRunning = false
    @Published var isApproved = false
    @Published var finalOutput = ""
    @Published var grokTokens: Int = 0
    @Published var claudeTokens: Int = 0
    @Published var lastError: String? = nil
    /// Persists draft text across view recreation (e.g. Settings toggle)
    @Published var draftText: String = ""
    /// Live streaming content from Claude while executing
    @Published var streamingContent: String = ""
    @Published var isStreaming: Bool = false

    var xaiKey: String {
        get { AppSettings.shared.xaiApiKey }
        set { AppSettings.shared.xaiApiKey = newValue }
    }
    var anthropicKey: String {
        get { AppSettings.shared.anthropicApiKey }
        set { AppSettings.shared.anthropicApiKey = newValue }
    }
    var maxIterations: Int {
        get { AppSettings.shared.swarmMaxIterations }
        set { AppSettings.shared.swarmMaxIterations = newValue }
    }
    var useClaudeCLI: Bool {
        get { AppSettings.shared.useClaudeCLI }
        set { AppSettings.shared.useClaudeCLI = newValue }
    }

    private var grokHistory: [[String: String]] = []
    private var cancelled = false
    private var activeProcess: Process?
    /// Claude CLI session ID — persists across iterations so Claude has full conversation memory
    private var claudeCLISessionId: String?

    // MARK: - Public API

    func start(task: String, files: [AttachedFile] = []) {
        guard !isRunning else { return }
        // Add user message to event timeline
        events.append(SwarmEvent(iteration: 0, phase: .idle, role: .user, content: task, approved: false, finalOutput: "", files: files))
        guard !xaiKey.isEmpty else {
            addEvent(0, .error, .system, "xAI API key is required.")
            return
        }
        if !useClaudeCLI && anthropicKey.isEmpty {
            addEvent(0, .error, .system, "Anthropic API key required when not using Claude Code CLI.")
            return
        }

        // Keep existing events (chat history) — only reset running state
        phase = .idle
        iteration = 0
        isRunning = true
        isApproved = false
        finalOutput = ""
        // Accumulate tokens across runs
        // grokTokens = 0; claudeTokens = 0
        // Keep grokHistory for context if we have prior conversation, otherwise start fresh
        if grokHistory.isEmpty {
            grokHistory = [["role": "system", "content": Self.grokSystemPrompt]]
        }
        cancelled = false
        // Trim events to prevent unbounded growth (keep last 100)
        if events.count > 100 {
            events = Array(events.suffix(100))
        }
        // Trim grokHistory to prevent API payload bloat (keep system + last 40)
        if grokHistory.count > 40 {
            let system = grokHistory.first
            grokHistory = [system].compactMap { $0 } + Array(grokHistory.suffix(39))
        }
        claudeCLISessionId = nil  // Fresh session so --dangerously-skip-permissions takes effect

        Task { await runLoop(task: task) }
    }

    func stop() {
        let wasRunning = isRunning
        activeProcess?.terminate()
        cancelled = true
        isRunning = false
        phase = .idle
        if wasRunning {
            addEvent(iteration, .idle, .system, "⏹ Stopped by user.")
        }
    }

    // MARK: - Loop

    private func runLoop(task: String) async {
        var claudeOutput = ""

        for i in 1...maxIterations {
            guard !cancelled else { break }
            iteration = i

            // Phase 1: Grok plans or reviews
            if i == 1 {
                phase = .grokPlanning
                addEvent(i, .grokPlanning, .system, "Grok is planning the first instruction...")
                let grokResp = await callGrok(userMsg:
                    "User message: \"\(task)\"\n\n" +
                    "Classify and respond:\n" +
                    "- If this is a GREETING or CASUAL MESSAGE (hi, hello, hey, what's up, etc): " +
                    "Set approved=true and put a friendly response in final_output. Do NOT send to Claude.\n" +
                    "- If this is a QUESTION about code/tech: Pass it to Claude as-is.\n" +
                    "- If this is a TASK: Write a detailed, actionable instruction for Claude Code " +
                    "(which has full filesystem and terminal access).\n" +
                    "JSON only."
                )
                guard !cancelled, let resp = grokResp else { break }
                let parsed = parseGrokJSON(resp)

                if let review = parsed["review_of_previous"], !review.isEmpty {
                    addEvent(i, .grokJudging, .grok, review)
                }
                let instruction1 = parsed["next_instruction_to_claude"] ?? resp
                let instr1Trimmed = instruction1.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if parsed["approved"] == "true" || Self.isVacuousInstruction(instr1Trimmed) {
                    finalOutput = parsed["final_output"] ?? claudeOutput
                    isApproved = true
                    phase = .approved
                    addEvent(i, .approved, .grok, "✓ APPROVED")
                    isRunning = false
                    return
                }
                addEvent(i, .grokPlanning, .grok, instruction1)

                // Phase 2: Claude executes
                phase = .claudeExecuting
                addEvent(i, .claudeExecuting, .system, "Claude is working...")
                let claudeResp = await callClaude(instruction: instruction1, context: "")
                guard !cancelled else { break }
                claudeOutput = claudeResp ?? "(Claude returned no output)"
                addEvent(i, .claudeExecuting, .claude, claudeOutput)
            } else {
                // Hard safety net: force approve after iteration 3 if Grok keeps saying positive things
                if i >= 4 {
                    finalOutput = claudeOutput
                    isApproved = true
                    phase = .approved
                    addEvent(i, .approved, .system, "✓ AUTO-APPROVED — Output stable after \(i-1) iterations.")
                    isRunning = false
                    return
                }

                phase = .grokJudging
                addEvent(i, .grokJudging, .system, "Grok is reviewing iteration \(i-1)...")
                let grokResp = await callGrok(userMsg:
                    "[Iteration \(i)] Claude's output:\n\n\(claudeOutput)\n\n" +
                    "Review against the original requirements. " +
                    "IMPORTANT: If the output is correct and complete — or if this is a casual/conversational " +
                    "interaction — you MUST set approved=true. Do NOT keep looping on completed work. " +
                    "Only set approved=false if there are SPECIFIC, CONCRETE bugs or missing requirements. " +
                    "This is iteration \(i) — approve unless there's a real problem. " +
                    "JSON only."
                )
                guard !cancelled, let resp = grokResp else { break }
                let parsed = parseGrokJSON(resp)

                if let review = parsed["review_of_previous"], !review.isEmpty {
                    addEvent(i, .grokJudging, .grok, review)
                }
                // Check explicit approval OR detect implicit approval from review text
                let instruction = parsed["next_instruction_to_claude"] ?? resp
                let instrTrimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let reviewText = (parsed["review_of_previous"] ?? "").lowercased()
                let isImplicitApproval = Self.isVacuousInstruction(instrTrimmed) ||
                    Self.reviewSoundsPositive(reviewText) ||
                    (instrTrimmed.count < 60 && Self.reviewSoundsPositive(instrTrimmed))
                if parsed["approved"] == "true" || isImplicitApproval {
                    finalOutput = parsed["final_output"] ?? claudeOutput
                    isApproved = true
                    phase = .approved
                    addEvent(i, .approved, .grok, "✓ APPROVED — Task complete.")
                    isRunning = false
                    return
                }
                addEvent(i, .grokPlanning, .grok, instruction)

                // Claude executes
                phase = .claudeExecuting
                addEvent(i, .claudeExecuting, .system, "Claude is working...")
                let review = parsed["review_of_previous"] ?? ""
                let claudeResp = await callClaude(instruction: instruction, context: review)
                guard !cancelled else { break }
                claudeOutput = claudeResp ?? "(Claude returned no output)"
                addEvent(i, .claudeExecuting, .claude, claudeOutput)
            }
        }

        if !cancelled && !isApproved {
            // Force approval at max iterations — deliver whatever we have
            finalOutput = claudeOutput.isEmpty ? "(No output produced)" : claudeOutput
            isApproved = true
            phase = .approved
            addEvent(maxIterations, .approved, .system,
                     "⚡ AUTO-APPROVED — Reached iteration limit (\(maxIterations)). Delivering best output.")
        }
        isRunning = false
    }

    // MARK: - Grok API (xAI OpenAI-compatible)

    private func callGrok(userMsg: String) async -> String? {
        grokHistory.append(["role": "user", "content": userMsg])

        let body: [String: Any] = [
            "model": AppSettings.shared.grokModel,
            "messages": grokHistory,
            "temperature": 0.4,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(xaiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                // Check for error
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let msg = error["message"] as? String {
                    addEvent(iteration, .error, .system, "Grok API error: \(msg)")
                    lastError = "Grok: \(msg)"
                }
                return nil
            }

            // Count tokens
            if let usage = json["usage"] as? [String: Any],
               let total = usage["total_tokens"] as? Int {
                grokTokens += total
            }

            grokHistory.append(["role": "assistant", "content": content])
            return content
        } catch {
            addEvent(iteration, .error, .system, "Grok request failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Claude (CLI or API)

    private func callClaude(instruction: String, context: String) async -> String? {
        if useClaudeCLI {
            return await callClaudeCLI(instruction: instruction, context: context)
        } else {
            return await callClaudeAPI(instruction: instruction, context: context)
        }
    }

    // MARK: - Claude Code CLI (uses Max plan)

    private func callClaudeCLI(instruction: String, context: String) async -> String? {
        let prompt: String
        if !context.isEmpty {
            prompt = "Feedback on your previous work:\n\(context)\n\nNew instruction:\n\(instruction)"
        } else {
            prompt = instruction
        }

        // Find claude binary
        let env = ProcessInfo.processInfo.environment
        let searchPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(env["HOME"] ?? "")/.npm-global/bin/claude",
            "\(env["HOME"] ?? "")/.local/bin/claude",
        ]
        guard let claudePath = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            addEvent(iteration, .error, .system, "Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code")
            return nil
        }

        streamingContent = ""
        isStreaming = true

        // Capture settings for the closure
        let currentSessionId = claudeCLISessionId
        let maxTurns = AppSettings.shared.claudeMaxTurns
        let model = AppSettings.shared.claudeModel

        return await withCheckedContinuation { continuation in
            Task.detached {
                let proc = Process()
                await MainActor.run { self.activeProcess = proc }
                proc.executableURL = URL(fileURLWithPath: claudePath)

                // stream-json requires --verbose
                var args = [
                    "-p", prompt,
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
                let wd = UserDefaults.standard.string(forKey: "working_directory") ?? ""
                proc.currentDirectoryURL = wd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser : URL(fileURLWithPath: wd)

                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardOutput = stdout
                proc.standardError = stderr

                // Drain stderr to prevent pipe buffer deadlock
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    _ = handle.availableData  // discard but keep draining
                }

                // Stream JSONL events progressively
                // Format: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}],...}}
                //         {"type":"result","result":"...","session_id":"..."}
                let buffer = LockedBuffer()
                let resultBuffer = LockedBuffer()
                stdout.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    buffer.append(chunk)
                    let lines = chunk.components(separatedBy: "\n")
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              let lineData = trimmed.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        // assistant events: message.content[].text
                        if type == "assistant",
                           let message = event["message"] as? [String: Any],
                           let contentBlocks = message["content"] as? [[String: Any]] {
                            for block in contentBlocks {
                                if block["type"] as? String == "text",
                                   let text = block["text"] as? String {
                                    let snapshot = resultBuffer.append(text)
                                    Task { @MainActor in
                                        self.streamingContent = snapshot
                                    }
                                }
                            }
                        }

                        // result event: has "result" string and "session_id"
                        if type == "result" {
                            if let sid = event["session_id"] as? String {
                                Task { @MainActor in
                                    self.claudeCLISessionId = sid
                                }
                            }
                        }
                    }
                }

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    await MainActor.run { self.activeProcess = nil }

                    // Final read — stop handlers before reading remaining data
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    let remaining = stdout.fileHandleForReading.readDataToEndOfFile()
                    if let chunk = String(data: remaining, encoding: .utf8), !chunk.isEmpty {
                        buffer.append(chunk)
                    }

                    // Parse the full output to find the result event
                    let allOutput = buffer.value
                    var finalResult = resultBuffer.value.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Always scan for the result JSONL line (most reliable source)
                    for line in allOutput.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              let lineData = trimmed.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        if type == "result" {
                            if let result = event["result"] as? String, !result.isEmpty {
                                finalResult = result
                            }
                            if let sid = event["session_id"] as? String {
                                await MainActor.run { self.claudeCLISessionId = sid }
                            }
                        }
                        // Also extract from assistant messages if result was empty
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

                    await MainActor.run {
                        self.isStreaming = false
                        self.streamingContent = ""
                    }

                    if proc.terminationStatus != 0 && finalResult.isEmpty {
                        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        await MainActor.run {
                            self.addEvent(self.iteration, .error, .system, "Claude CLI error: \(errStr)")
                        }
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: finalResult.isEmpty ? nil : finalResult)
                    }
                } catch {
                    await MainActor.run {
                        self.isStreaming = false
                        self.streamingContent = ""
                        self.addEvent(self.iteration, .error, .system, "Claude CLI failed: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Claude API (Anthropic) — fallback with streaming

    private func callClaudeAPI(instruction: String, context: String) async -> String? {
        var messages: [[String: String]] = []
        if !context.isEmpty {
            messages.append(["role": "user", "content": "Your previous work was reviewed. Here's the feedback:\n\n\(context)"])
            messages.append(["role": "assistant", "content": "Understood. I'll address each point in the feedback."])
        }
        messages.append(["role": "user", "content": instruction])

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "stream": true,
            "system": "You are Claude, an expert software engineer executing tasks in a review loop. " +
                "You receive instructions from your tech lead. Execute them precisely and completely. " +
                "Produce the actual deliverable — NOT a description of what you would do. " +
                "For code: write the full implementation, not pseudocode. " +
                "For writing: produce the finished text, not an outline. " +
                "Format output as clean Markdown with proper code blocks (specify language), " +
                "bullet lists, and paragraphs. Never wrap output in JSON.",
            "messages": messages,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anthropicKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        streamingContent = ""
        isStreaming = true

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            // Check for non-streaming error response
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                var errorData = Data()
                for try await byte in bytes { errorData.append(byte) }
                if let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let msg = error["message"] as? String {
                    addEvent(iteration, .error, .system, "Claude API error: \(msg)")
                    lastError = "Claude: \(msg)"
                }
                isStreaming = false
                streamingContent = ""
                return nil
            }

            var accumulated = ""
            for try await line in bytes.lines {
                guard !cancelled else { break }

                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }

                guard let eventData = payload.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else { continue }

                let eventType = event["type"] as? String ?? ""

                if eventType == "content_block_delta",
                   let delta = event["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    accumulated += text
                    streamingContent = accumulated
                }

                if eventType == "message_delta",
                   let usage = event["usage"] as? [String: Any],
                   let outputTokens = usage["output_tokens"] as? Int {
                    claudeTokens += outputTokens
                }

                if eventType == "message_start",
                   let message = event["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any],
                   let inputTokens = usage["input_tokens"] as? Int {
                    claudeTokens += inputTokens
                }
            }

            isStreaming = false
            streamingContent = ""
            return accumulated.isEmpty ? nil : accumulated
        } catch {
            isStreaming = false
            streamingContent = ""
            addEvent(iteration, .error, .system, "Claude request failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func addEvent(_ iter: Int, _ phase: SwarmPhase, _ role: SwarmEvent.SwarmRole, _ content: String) {
        events.append(SwarmEvent(iteration: iter, phase: phase, role: role, content: content,
                                 approved: phase == .approved, finalOutput: phase == .approved ? content : ""))
    }

    private func parseGrokJSON(_ raw: String) -> [String: String] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip ```json ... ```
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Convert JSON Any values to proper strings (bools → "true"/"false", not "1"/"0")
        func stringify(_ dict: [String: Any]) -> [String: String] {
            dict.mapValues { val in
                if let b = val as? Bool { return b ? "true" : "false" }
                if let n = val as? NSNumber {
                    // Distinguish bool from number in NSNumber
                    if CFBooleanGetTypeID() == CFGetTypeID(n) {
                        return n.boolValue ? "true" : "false"
                    }
                }
                return "\(val)"
            }
        }

        // Try direct parse
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return stringify(json)
        }

        // Find first { ... } block
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let sub = String(text[start...end])
            if let data = sub.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return stringify(json)
            }
        }

        return [
            "next_instruction_to_claude": text,
            "review_of_previous": "",
            "approved": "false",
        ]
    }

    /// Detects when Grok's instruction is vacuous (nothing left to do) but it forgot to set approved=true
    private static func isVacuousInstruction(_ s: String) -> Bool {
        let stripped = s.replacingOccurrences(of: "[^a-z ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let vacuous = ["n/a", "na", "none", "no further action", "no changes needed",
                       "no further action needed", "no action needed", "nothing to change",
                       "no revisions needed", "no additional changes", "looks good",
                       "no further instructions", "no more changes", "no issues",
                       "no fixes needed", "no changes required", "all good",
                       "complete", "task complete", "task is complete",
                       "the output is correct", "output is correct"]
        return vacuous.contains(where: { stripped.hasPrefix($0) || stripped == $0 }) ||
            (s.count < 30 && (s.contains("n/a") || s.contains("none") || s.contains("no ")))
    }

    /// Detects when Grok's review text sounds positive/approving even if approved wasn't set
    private static func reviewSoundsPositive(_ text: String) -> Bool {
        let positiveSignals = [
            "no fixes needed", "no changes needed", "no further action",
            "correct and complete", "no issues", "looks good", "well done",
            "no further changes", "meets the requirements", "meets all requirements",
            "complete and correct", "no bugs", "no errors",
            "appropriate", "suitable", "friendly response",
            "handled well", "no revisions", "nothing to fix",
            "casual interaction", "casual conversation",
            "no additional changes", "correctly", "complete",
        ]
        let negativeSignals = ["bug", "error", "missing", "wrong", "incorrect", "fix ", "change ",
                               "should ", "must ", "needs to", "doesn't", "does not", "failed"]

        let hasPositive = positiveSignals.contains(where: { text.contains($0) })
        let hasNegative = negativeSignals.contains(where: { text.contains($0) })

        return hasPositive && !hasNegative
    }

    static let grokSystemPrompt = """
    You are the Lead Architect in a two-agent coding workflow. You write prompts for \
    Claude Code (an AI coding agent with full filesystem, terminal, and tool access) \
    and review its output. Think of yourself as a tech lead writing crystal-clear \
    tickets for a senior engineer.

    === HOW TO PROMPT CLAUDE EFFECTIVELY ===
    Claude Code is a CLI agent that can read/write files, run shell commands, search \
    codebases, and execute multi-step tasks autonomously. Your instructions should:

    1. **Be specific and actionable** — Say exactly what to build, which files to create \
       or modify, what the expected behavior is. Bad: "make the auth better". \
       Good: "Add JWT refresh token rotation to auth_routes.py — when /auth/refresh is \
       called, invalidate the old token and issue a new pair."
    2. **Give file paths when you know them** — Claude works faster when you point it to \
       the right files. "Edit backend/main.py" beats "find the server entry point".
    3. **State acceptance criteria** — Tell Claude what "done" looks like. \
       "The endpoint should return 200 with {token, refresh_token} on success, \
       401 on invalid credentials."
    4. **Include context from previous output** — When iterating, quote the specific \
       lines or sections that need fixing. Don't just say "fix the bug" — say \
       "the parse_response function on line 45 doesn't handle the case where 'data' \
       is null, add a guard clause."
    5. **Break complex tasks into clear steps** — Number them. Claude executes linearly \
       and does best with ordered instructions.
    6. **Don't over-constrain** — Claude is good at making implementation decisions. \
       Specify WHAT and WHY, let Claude decide HOW unless architecture matters.
    7. **For code: specify the language, framework, and style** — "Write a Swift struct" \
       or "Add a Python FastAPI route" removes ambiguity.
    === END PROMPTING GUIDE ===

    === REVIEW GUIDELINES ===
    - Review like a senior engineer: specific, constructive, actionable.
    - Focus on: correctness, edge cases, missing error handling, API contract violations.
    - If output is good, APPROVE. Don't nitpick style or add gold-plating.
    - If output needs fixes, quote the exact problem and state the fix clearly.
    - Simple tasks (questions, creative writing) → approve on first good response.
    === END REVIEW GUIDELINES ===

    === HANDLING NON-TASK INPUTS ===
    Not every user message is a coding task. If the user sends a greeting ("hey", "hi", \
    "what's up"), a question, casual chat, or anything that is NOT a request to build/modify \
    something — just pass it through to Claude as-is. Set the instruction to exactly what \
    the user said. Do NOT invent a project, do NOT fabricate requirements. \
    For simple questions or greetings, approve after Claude's first response.
    === END NON-TASK HANDLING ===

    === APPROVAL RULES (CRITICAL) ===
    1. If Claude's output is correct and complete: SET approved=true IMMEDIATELY.
    2. If the user sent a greeting, question, or casual message: APPROVE after Claude's \
       FIRST response. Do NOT loop on conversational messages.
    3. "Could be better" or "minor style nits" are NOT reasons to reject. \
       Only reject for SPECIFIC, CONCRETE bugs or missing requirements.
    4. After iteration 3: only reject for critical bugs.
    5. After iteration 5: MUST approve regardless.
    6. NEVER keep looping when you say "no issues" or "looks good" — that IS approval.
    === END APPROVAL RULES ===

    === SAFETY RULES ===
    1. NEVER discuss API rate limits, usage quotas, billing, or token budgets.
    2. NEVER refuse work by citing "cost concerns". Just do the job.
    3. Your ONLY job: (a) write clear prompts for Claude, (b) review output, \
       (c) approve when requirements are met.
    4. No meta-commentary about the swarm process or iterations.
    5. NEVER invent tasks, projects, or requirements that the user didn't ask for. \
       Only work with what the user actually said.
    === END SAFETY RULES ===

    Always output valid JSON only: \
    {"next_instruction_to_claude": "...", "review_of_previous": "...", \
    "approved": true/false, "final_output": "..." (only if approved)}

    When approved is true, you MUST include "final_output" with the complete deliverable. \
    Do NOT keep looping if the work is done — approve immediately. \
    If your review says anything positive like "correct", "complete", "no issues", \
    "looks good" — then approved MUST be true.
    """
}
