/// ClaudeCLIService — Single source of truth for calling Claude Code CLI.
/// Extracted from PTYChatViewModel, SwarmEngine, and GrokChatEngine.

import Foundation

enum ClaudeCLIService {

    struct Result {
        let text: String
        let sessionId: String?
    }

    /// Find the claude binary on the system
    static func findBinary() -> String? {
        let home = NSHomeDirectory()
        let searchPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.nvm/versions/node/default/bin/claude",
        ]
        if let found = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }
        // Fallback: try `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Call Claude CLI with JSON output mode (single response, no streaming)
    static func callJSON(
        path: String,
        prompt: String,
        sessionId: String?,
        model: String,
        maxTurns: Int,
        workingDirectory: String,
        timeout: TimeInterval = 120
    ) async -> Result? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                var args = ["-p", prompt, "--output-format", "json", "--dangerously-skip-permissions", "--model", model, "--max-turns", "\(maxTurns)"]
                if let sid = sessionId { args += ["--resume", sid] }
                proc.arguments = args

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                env["NO_COLOR"] = "1"
                env.removeValue(forKey: "COLORTERM")
                proc.environment = env
                proc.currentDirectoryURL = workingDirectory.isEmpty
                    ? FileManager.default.homeDirectoryForCurrentUser
                    : URL(fileURLWithPath: workingDirectory)

                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardOutput = stdout
                proc.standardError = stderr

                // Drain stderr to prevent pipe buffer deadlock
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    _ = handle.availableData
                }

                // Timeout protection
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if proc.isRunning { proc.terminate() }
                }

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    stderr.fileHandleForReading.readabilityHandler = nil

                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                    if proc.terminationStatus != 0 && data.isEmpty {
                        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(returning: Result(text: "Error: \(errStr.isEmpty ? "exit code \(proc.terminationStatus)" : errStr)", sessionId: sessionId))
                        return
                    }

                    guard !data.isEmpty,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if text.isEmpty {
                            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No output"
                            continuation.resume(returning: Result(text: "Error: \(errStr)", sessionId: sessionId))
                        } else {
                            continuation.resume(returning: Result(text: text, sessionId: sessionId))
                        }
                        return
                    }

                    let resultText = json["result"] as? String ?? ""
                    let sid = json["session_id"] as? String ?? sessionId

                    continuation.resume(returning: resultText.isEmpty
                        ? Result(text: "(empty result)", sessionId: sid)
                        : Result(text: resultText, sessionId: sid))
                } catch {
                    continuation.resume(returning: Result(text: "Error: \(error.localizedDescription)", sessionId: sessionId))
                }
            }
        }
    }

    /// Call Claude CLI with stream-json output mode (progressive updates via callback)
    static func callStreaming(
        path: String,
        prompt: String,
        sessionId: String?,
        model: String,
        maxTurns: Int,
        workingDirectory: String,
        timeout: TimeInterval = 300,
        onTextChunk: @escaping @Sendable (String) -> Void
    ) async -> Result? {
        // Use LockedBuffer from SwarmEngine (already exists in codebase)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                var args = [
                    "-p", prompt,
                    "--output-format", "stream-json",
                    "--verbose",
                    "--dangerously-skip-permissions",
                    "--max-turns", "\(maxTurns)",
                    "--model", model,
                ]
                if let sid = sessionId { args += ["--resume", sid] }
                proc.arguments = args

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                env["NO_COLOR"] = "1"
                proc.environment = env
                proc.currentDirectoryURL = workingDirectory.isEmpty
                    ? FileManager.default.homeDirectoryForCurrentUser
                    : URL(fileURLWithPath: workingDirectory)

                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardOutput = stdout
                proc.standardError = stderr

                stderr.fileHandleForReading.readabilityHandler = { handle in
                    _ = handle.availableData
                }

                let buffer = LockedBuffer()
                let lineLock = NSLock()
                var partialLine = ""
                var latestText = ""
                var detectedSessionId: String? = nil

                stdout.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    buffer.append(chunk)

                    // Handle partial lines split across chunks
                    lineLock.lock()
                    let combined = partialLine + chunk
                    var lines = combined.components(separatedBy: "\n")
                    // Last element is either empty (if chunk ended with \n) or a partial line
                    partialLine = lines.removeLast()
                    lineLock.unlock()

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              let lineData = trimmed.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        // assistant events contain full message snapshots, not deltas — replace, don't append
                        if type == "assistant",
                           let message = event["message"] as? [String: Any],
                           let contentBlocks = message["content"] as? [[String: Any]] {
                            var fullText = ""
                            for block in contentBlocks {
                                if block["type"] as? String == "text",
                                   let text = block["text"] as? String {
                                    fullText += text
                                }
                            }
                            if !fullText.isEmpty {
                                lineLock.lock()
                                latestText = fullText
                                lineLock.unlock()
                                onTextChunk(fullText)
                            }
                        }
                        if type == "result", let sid = event["session_id"] as? String {
                            detectedSessionId = sid
                        }
                    }
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if proc.isRunning { proc.terminate() }
                }

                do {
                    try proc.run()
                    proc.waitUntilExit()

                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    let remaining = stdout.fileHandleForReading.readDataToEndOfFile()
                    if let chunk = String(data: remaining, encoding: .utf8), !chunk.isEmpty {
                        buffer.append(chunk)
                    }

                    let allOutput = buffer.value
                    lineLock.lock()
                    var finalResult = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
                    lineLock.unlock()

                    for line in allOutput.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              let lineData = trimmed.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = event["type"] as? String else { continue }
                        if type == "result" {
                            if let r = event["result"] as? String, !r.isEmpty { finalResult = r }
                            if let s = event["session_id"] as? String { detectedSessionId = s }
                        }
                        if type == "assistant" && finalResult.isEmpty,
                           let message = event["message"] as? [String: Any],
                           let contentBlocks = message["content"] as? [[String: Any]] {
                            // assistant events are full snapshots — use last one, don't accumulate
                            var snapshot = ""
                            for block in contentBlocks {
                                if block["type"] as? String == "text",
                                   let text = block["text"] as? String {
                                    snapshot += text
                                }
                            }
                            if !snapshot.isEmpty { finalResult = snapshot }
                        }
                    }

                    let sid = detectedSessionId ?? sessionId
                    continuation.resume(returning: finalResult.isEmpty ? nil : Result(text: finalResult, sessionId: sid))
                } catch {
                    continuation.resume(returning: Result(text: "Error: \(error.localizedDescription)", sessionId: sessionId))
                }
            }
        }
    }
}
