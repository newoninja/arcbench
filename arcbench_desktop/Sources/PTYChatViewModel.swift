import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    var responded = false
    var attachedFiles: [AttachedFile] = []
    enum Role { case user, claude }
}

// MARK: - Attached File Model

struct AttachedFile: Identifiable {
    let id = UUID()
    let url: URL
    let thumbnail: NSImage?
    let fileSize: String

    init(url: URL) {
        self.url = url
        // Generate thumbnail for images
        if url.isImage, let img = NSImage(contentsOf: url) {
            self.thumbnail = img
        } else {
            self.thumbnail = nil
        }
        // Compute human-readable file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let bytes = attrs[.size] as? Int64 {
            self.fileSize = AttachedFile.formatBytes(bytes)
        } else {
            self.fileSize = ""
        }
    }

    var displayName: String { url.lastPathComponent }

    var fileIcon: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "swift", "py", "js", "ts", "rs", "go", "java", "c", "cpp", "h", "rb", "kt":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return "curlybraces"
        case "md", "txt", "rtf", "log":
            return "doc.text"
        case "zip", "tar", "gz", "rar":
            return "doc.zipper"
        default:
            if url.hasDirectoryPath { return "folder.fill" }
            return "doc.fill"
        }
    }

    var iconColor: Color {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return .accentRed
        case "swift": return .accentOrange
        case "py": return .accentGreen
        case "js", "ts": return .yellow
        case "json", "yaml", "yml", "toml": return .accentPurple
        default:
            if url.hasDirectoryPath { return .arcBlue }
            if url.isImage { return .arcBlue }
            return .textTertiary
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }
}

extension URL {
    var isImage: Bool {
        ["png", "jpg", "jpeg", "heic", "gif", "webp", "bmp", "tiff", "ico", "svg"].contains(pathExtension.lowercased())
    }
}

// MARK: - File Drop Delegate

struct FileDropDelegate: DropDelegate {
    @Binding var attachedFiles: [AttachedFile]
    @Binding var isDropping: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isDropping = true }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isDropping = false }
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isDropping = false }
        let providers = info.itemProviders(for: [.fileURL])
        return handleDrop(providers: providers)
    }

    /// Shared drop handler — used by both DropDelegate and .onDrop(of:isTargeted:) closure
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    if !self.attachedFiles.contains(where: { $0.url == url }) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            self.attachedFiles.append(AttachedFile(url: url))
                        }
                    }
                }
            }
        }
        return true
    }
}

enum ClaudeSegment: Identifiable {
    case text(String)
    case toolUse(icon: String, name: String, detail: String)
    case treeDetail(String)
    var id: String {
        switch self {
        case .text(let s): return "txt-\(s.prefix(80))"
        case .toolUse(_, let n, let d): return "tool-\(n)-\(d.prefix(40))"
        case .treeDetail(let s): return "tree-\(s.prefix(80))"
        }
    }
}

/// Debug log to /tmp/arcbench_debug.log
func arcLog(_ msg: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
    let url = URL(fileURLWithPath: "/tmp/arcbench_debug.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)?.write(to: url)
    }
}

@MainActor
class PTYChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isWaiting = false
    @Published var isThinking = false
    /// Persists draft text across view recreation (e.g. Settings toggle)
    @Published var draftText: String = ""
    @Published var pendingPrompt: PromptType? = nil
    @Published var pendingPermission: String? = nil
    @Published var trustedConfirmation = false
    @Published var userHasSentMessage = false
    enum PromptType { case trust(folder: String) }

    /// PTY backend — only used for shell/grok modes
    private(set) var backend: PTYTerminalBackend?
    private var debounceTask: Task<Void, Never>?
    private var rawBuffer = ""
    private var outputCharCount = 0
    private var ansiCarryover = ""
    /// Buffer for accumulating output before flushing to @Published messages
    private var pendingOutput = ""
    private var flushTimer: Timer?

    /// Claude JSON mode — session state (public for persistence)
    private(set) var claudeSessionId: String?
    var claudeSessionIdPublic: String? { claudeSessionId }

    func restoreClaudeSessionId(_ id: String) {
        claudeSessionId = id
    }
    private var claudeTask: Task<Void, Never>?
    private var claudePath: String?

    let mode: TerminalMode
    weak var terminalManager: TerminalManager?
    var sessionId: UUID?  // set by TerminalManager for auto-save

    init(mode: TerminalMode) {
        self.mode = mode
        if mode == .claude {
            // Claude mode: use `claude -p --output-format json` (no PTY)
            claudePath = Self.findClaudeBinary()
            // Show ready state immediately
            isWaiting = false
            isThinking = false
        } else {
            // Shell/Grok modes: use PTY as before
            backend = PTYTerminalBackend(mode: mode)
            backend?.onOutput = { [weak self] data in Task { @MainActor in self?.handlePTYOutput(data) } }
        }
    }

    // MARK: - Auto-save

    private var autoSaveTask: Task<Void, Never>?

    /// Debounced auto-save — persists messages to disk after a short delay
    func triggerAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled, let self = self,
                  let sid = self.sessionId,
                  let manager = self.terminalManager,
                  let session = manager.terminals.first(where: { $0.id == sid }) else { return }
            manager.historyStore.autoSave(session: session, messages: self.messages, claudeSessionId: self.claudeSessionId)
        }
    }

    // MARK: - Public API

    func send(_ text: String, files: [AttachedFile] = []) {
        guard !text.isEmpty else { return }
        NSLog("🔴 [ArcBench] send() called — mode=%@ text=%@", mode.rawValue, String(text.prefix(40)))
        arcLog("[ArcBench] PTYChatViewModel.send() — mode=\(mode.rawValue) text=\(text.prefix(40))")
        userHasSentMessage = true
        pendingPrompt = nil
        pendingPermission = nil
        messages.append(ChatMessage(role: .user, text: text, attachedFiles: files))
        triggerAutoSave()

        if mode == .claude {
            arcLog("[ArcBench] → routing to sendToClaude")
            sendToClaude(text)
        } else {
            arcLog("[ArcBench] → routing to PTY backend (mode=\(mode.rawValue))")
            messages.append(ChatMessage(role: .claude, text: ""))
            isWaiting = true; isThinking = true; outputCharCount = 0
            backend?.write(text + "\r")
        }
    }

    func sendRaw(_ text: String) {
        guard mode != .claude else { return } // No raw mode for JSON backend
        pendingPrompt = nil; pendingPermission = nil; isWaiting = true
        if messages.last?.role == .claude, let last = messages.indices.last {
            if !messages[last].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append(ChatMessage(role: .claude, text: ""))
            }
        } else { messages.append(ChatMessage(role: .claude, text: "")) }
        backend?.write(text)
    }

    func interrupt() {
        let wasActive = isThinking || isWaiting
        if mode == .claude {
            // For JSON mode, cancel the running task
            claudeTask?.cancel()
            claudeTask = nil
        }
        // Send Ctrl+C to PTY
        backend?.write("\u{03}")

        if wasActive {
            isThinking = false
            isWaiting = false
            flushPendingOutput()
            // Append stopped indicator to the last claude message
            if let lastIdx = messages.indices.last, messages[lastIdx].role == .claude {
                let existing = messages[lastIdx].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if existing.isEmpty {
                    messages[lastIdx].text = "⏹ Stopped by user."
                } else {
                    messages[lastIdx].text += "\n\n⏹ Stopped by user."
                }
            } else {
                messages.append(ChatMessage(role: .claude, text: "⏹ Stopped by user."))
            }
            triggerAutoSave()
        }
    }

    func trustFolder(_ accept: Bool) {
        let folder = extractPath(from: rawBuffer)
        pendingPrompt = nil
        if accept {
            trustedConfirmation = true
            terminalManager?.trustedFolders.insert(folder)
            terminalManager?.trustedFolders.insert("*")
        }
        rawBuffer = ""; isWaiting = false; isThinking = false
        backend?.write(accept ? "\r" : "\u{1B}")
    }

    func respondPermission(yes: Bool) {
        pendingPermission = nil
        if let lastIdx = messages.indices.last, messages[lastIdx].role == .claude {
            messages[lastIdx].text = ""
        }
        messages.append(ChatMessage(role: .claude, text: ""))
        isWaiting = true; isThinking = true; outputCharCount = 0
        backend?.write(yes ? "\r" : "2\r")
    }

    func terminate() {
        claudeTask?.cancel()
        backend?.terminate()
        backend = nil
    }

    /// Reset Claude session so the next message uses the new model from settings
    func applyModelChange() {
        guard mode == .claude else { return }
        claudeTask?.cancel()
        claudeSessionId = nil  // new session will use updated model
    }

    deinit { debounceTask?.cancel(); claudeTask?.cancel(); backend?.terminate() }
    func resize(rows: UInt16, cols: UInt16) { backend?.resize(rows: rows, cols: cols) }

    // MARK: - Claude JSON Mode (no PTY, clean structured output)

    private func sendToClaude(_ text: String) {
        // Re-check claude path each time in case it was installed after app launch
        if claudePath == nil {
            claudePath = Self.findClaudeBinary()
        }
        guard let path = claudePath else {
            let home = NSHomeDirectory()
            let searched = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.local/bin/claude"]
                .map { FileManager.default.fileExists(atPath: $0) ? "  ✓ \($0)" : "  ✗ \($0)" }
                .joined(separator: "\n")
            messages.append(ChatMessage(role: .claude, text: "Claude Code CLI was not found on this system.\n\n\(searched)\n\nTo install, run:\nnpm install -g @anthropic-ai/claude-code"))
            return
        }

        arcLog("[ArcBench] sendToClaude called — path: \(path), prompt: \(text.prefix(60))")

        messages.append(ChatMessage(role: .claude, text: ""))
        isWaiting = true
        isThinking = true

        let model = AppSettings.shared.claudeModel
        let maxTurns = AppSettings.shared.claudeMaxTurns
        let wd = UserDefaults.standard.string(forKey: "working_directory") ?? ""
        arcLog("[ArcBench] model=\(model) maxTurns=\(maxTurns) wd=\(wd) sessionId=\(claudeSessionId ?? "nil")")

        claudeTask = Task {
            let result = await Self.callClaudeJSON(
                path: path,
                prompt: text,
                sessionId: claudeSessionId,
                model: model,
                maxTurns: maxTurns,
                workingDirectory: wd
            )
            arcLog("[ArcBench] callClaudeJSON returned — result: \(result?.text.prefix(100) ?? "nil")")

            guard !Task.isCancelled else { return }

            if let result = result {
                claudeSessionId = result.sessionId
                if let lastIdx = messages.indices.last, messages[lastIdx].role == .claude {
                    messages[lastIdx].text = result.text
                }
            } else {
                if let lastIdx = messages.indices.last, messages[lastIdx].role == .claude {
                    messages[lastIdx].text = "(No response from Claude)"
                }
            }

            isWaiting = false
            isThinking = false
            triggerAutoSave()
        }
    }

    private struct ClaudeResult {
        let text: String
        let sessionId: String?
    }

    private static func callClaudeJSON(path: String, prompt: String, sessionId: String?, model: String, maxTurns: Int, workingDirectory: String) async -> ClaudeResult? {
        arcLog("[ArcBench] callClaudeJSON starting — path=\(path) model=\(model)")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                var args = ["-p", prompt, "--output-format", "json", "--dangerously-skip-permissions", "--model", model, "--max-turns", "\(maxTurns)"]
                if let sid = sessionId {
                    args += ["--resume", sid]
                }
                proc.arguments = args
                arcLog("[ArcBench] args: \(args)")

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                env["NO_COLOR"] = "1"
                env.removeValue(forKey: "COLORTERM")
                proc.environment = env
                proc.currentDirectoryURL = workingDirectory.isEmpty ? FileManager.default.homeDirectoryForCurrentUser : URL(fileURLWithPath: workingDirectory)

                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardInput = FileHandle.nullDevice  // Prevent SIGTTIN suspension
                proc.standardOutput = stdout
                proc.standardError = stderr

                // Kill after 120s to prevent zombie hangs
                DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                    if proc.isRunning { proc.terminate() }
                }

                // Read pipes on separate threads to prevent buffer deadlock
                // (readabilityHandler + waitUntilExit causes hangs on macOS)
                let stdoutBox = UnsafeMutablePointer<Data>.allocate(capacity: 1)
                let stderrBox = UnsafeMutablePointer<Data>.allocate(capacity: 1)
                stdoutBox.initialize(to: Data())
                stderrBox.initialize(to: Data())
                let stdoutSema = DispatchSemaphore(value: 0)
                let stderrSema = DispatchSemaphore(value: 0)

                do {
                    try proc.run()
                    arcLog("[ArcBench] Process launched (PID \(proc.processIdentifier)), waiting for exit...")

                    // Drain both pipes concurrently
                    DispatchQueue.global(qos: .userInitiated).async {
                        stdoutBox.pointee = stdout.fileHandleForReading.readDataToEndOfFile()
                        stdoutSema.signal()
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        stderrBox.pointee = stderr.fileHandleForReading.readDataToEndOfFile()
                        stderrSema.signal()
                    }

                    proc.waitUntilExit()
                    stdoutSema.wait()
                    stderrSema.wait()

                    let data = stdoutBox.pointee
                    let errData = stderrBox.pointee
                    stdoutBox.deinitialize(count: 1); stdoutBox.deallocate()
                    stderrBox.deinitialize(count: 1); stderrBox.deallocate()

                    arcLog("[ArcBench] Process exited — status=\(proc.terminationStatus) stdout=\(data.count)B stderr=\(errData.count)B")
                    if let rawOut = String(data: data, encoding: .utf8) {
                        arcLog("[ArcBench] stdout: \(rawOut.prefix(300))")
                    }

                    // If process was killed or errored
                    if proc.terminationStatus != 0 && data.isEmpty {
                        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let msg = errStr.isEmpty ? "Claude CLI exited with code \(proc.terminationStatus)" : errStr
                        continuation.resume(returning: ClaudeResult(text: "Error: \(msg)", sessionId: sessionId))
                        return
                    }

                    guard !data.isEmpty,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        // Fall back to raw text output
                        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if text.isEmpty {
                            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No output"
                            continuation.resume(returning: ClaudeResult(text: "Error: \(errStr)", sessionId: sessionId))
                        } else {
                            continuation.resume(returning: ClaudeResult(text: text, sessionId: sessionId))
                        }
                        return
                    }

                    let resultText = json["result"] as? String ?? ""
                    let sid = json["session_id"] as? String ?? sessionId

                    continuation.resume(returning: resultText.isEmpty
                        ? ClaudeResult(text: "(Claude returned empty result)", sessionId: sid)
                        : ClaudeResult(text: resultText, sessionId: sid))
                } catch {
                    continuation.resume(returning: ClaudeResult(text: "Error: \(error.localizedDescription)", sessionId: sessionId))
                }
            }
        }
    }

    private static func findClaudeBinary() -> String? {
        let home = NSHomeDirectory()  // Always works, unlike env["HOME"]
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
        // Try `which` as fallback
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

    // MARK: - PTY Output Handling (shell/grok modes only)

    func handlePTYOutput(_ data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else { return }
        let combined = ansiCarryover + raw
        ansiCarryover = ""
        let (stripped, leftover) = Self.stripANSI(combined)
        ansiCarryover = leftover
        var cleaned = stripped.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: #" {3,}"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if !userHasSentMessage {
            rawBuffer += cleaned
            if pendingPrompt == nil && (rawBuffer.contains("trust this") || rawBuffer.contains("I trust")) {
                let folder = extractPath(from: rawBuffer)
                if let tm = terminalManager, tm.trustedFolders.contains(folder) || tm.trustedFolders.contains("*") {
                    trustFolder(true); return
                }
                pendingPrompt = .trust(folder: folder); isThinking = false; isWaiting = false
            }
            return
        }

        let meaningful = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaningful.isEmpty else { return }
        if meaningful.count > 3 { outputCharCount += meaningful.count; if outputCharCount > 10 { isThinking = false } }

        // Buffer output and flush at ~15fps to avoid hammering SwiftUI
        pendingOutput += cleaned
        if flushTimer == nil {
            flushTimer = Timer.scheduledTimer(withTimeInterval: 0.066, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.flushPendingOutput() }
            }
        }

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled {
                self.flushPendingOutput() // flush any remaining
                self.isWaiting = false; self.isThinking = false
                self.triggerAutoSave()
            }
        }
    }

    private func flushPendingOutput() {
        flushTimer?.invalidate()
        flushTimer = nil
        guard !pendingOutput.isEmpty else { return }
        let chunk = pendingOutput
        pendingOutput = ""

        if let lastIdx = messages.indices.last, messages[lastIdx].role == .claude {
            let existing = messages[lastIdx].text
            let ct = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ct.isEmpty {
                if ct.count > 20 && existing.hasSuffix(ct) { /* duplicate, skip */ }
                else if ct.count > 50 && existing.contains(ct) { /* duplicate, skip */ }
                else { messages[lastIdx].text += chunk }
            }
        } else {
            messages.append(ChatMessage(role: .claude, text: chunk))
        }
    }

    private func extractPermissionContext(from text: String) -> String {
        let lines = text.components(separatedBy: "\n"); var ctx: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Do you want to proceed") { break }
            if !t.isEmpty { ctx.append(t) }
        }
        let r = ctx.suffix(5).joined(separator: "\n")
        return r.isEmpty ? "Claude wants to perform an action." : r
    }

    private func extractPath(from text: String) -> String {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("/") && t.count > 3 && !t.contains(" ") { return t }
        }
        return "this folder"
    }

    // MARK: - ANSI Stripper (kept for shell/grok PTY modes)

    static func stripANSI(_ raw: String) -> (String, String) {
        var result = ""
        var i = raw.startIndex

        while i < raw.endIndex {
            let ch = raw[i]

            if ch == "\u{1B}" {
                let remaining = raw[i...]
                let next = raw.index(after: i)
                guard next < raw.endIndex else { return (result, String(remaining)) }

                if raw[next] == "[" {
                    var j = raw.index(after: next)
                    var paramStr = ""
                    var foundEnd = false
                    var terminator: Character = " "
                    while j < raw.endIndex {
                        let c = raw[j]
                        if (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || c == "@" || c == "`" {
                            foundEnd = true; terminator = c; break
                        }
                        if !(c >= "0" && c <= "9") && c != ";" && c != "?" && c != " " && c != ">" && c != "!" {
                            foundEnd = true; terminator = c; break
                        }
                        paramStr.append(c)
                        j = raw.index(after: j)
                    }
                    if !foundEnd { return (result, String(remaining)) }
                    if terminator == "C" {
                        let n = min(Int(paramStr) ?? 1, 4)
                        result += String(repeating: " ", count: n)
                    } else if terminator == "B" {
                        let n = min(Int(paramStr) ?? 1, 3)
                        result += String(repeating: "\n", count: n)
                    }
                    i = raw.index(after: j); continue

                } else if raw[next] == "]" {
                    var j = raw.index(after: next)
                    var foundEnd = false
                    while j < raw.endIndex {
                        if raw[j] == "\u{07}" { i = raw.index(after: j); foundEnd = true; break }
                        if raw[j] == "\u{1B}" {
                            let jn = raw.index(after: j)
                            if jn < raw.endIndex && raw[jn] == "\\" { i = raw.index(after: jn); foundEnd = true; break }
                        }
                        j = raw.index(after: j)
                    }
                    if !foundEnd { return (result, String(remaining)) }
                    continue
                } else if raw[next] == "(" || raw[next] == ")" {
                    let afterNext = raw.index(after: next)
                    if afterNext < raw.endIndex { i = raw.index(after: afterNext) } else { return (result, String(remaining)) }
                    continue
                } else {
                    i = raw.index(after: next); continue
                }
            }

            if ch == "\u{07}" || ch == "\u{0E}" || ch == "\u{0F}" { i = raw.index(after: i); continue }
            if ch == "\u{08}" { if !result.isEmpty { result.removeLast() }; i = raw.index(after: i); continue }


            // Strip box-drawing / decorative unicode
            let scalar = ch.unicodeScalars.first?.value ?? 0
            if (scalar >= 0x2500 && scalar <= 0x259F) || (scalar >= 0x25A0 && scalar <= 0x25FF) ||
               (scalar >= 0xE000 && scalar <= 0xF8FF) || (scalar >= 0x2800 && scalar <= 0x28FF) {
                i = raw.index(after: i); continue
            }

            result.append(ch)
            i = raw.index(after: i)
        }
        return (result, "")
    }
}
