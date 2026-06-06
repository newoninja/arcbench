/// Manages terminal session lifecycle with proper PTY cleanup.

import Foundation
import SwiftUI

// MARK: - Session History (persisted to disk)

struct SavedMessage: Codable {
    let role: String // "user" or "claude"
    let text: String
}

struct SessionHistory: Identifiable, Codable {
    let id: UUID
    let title: String
    let mode: String
    let createdAt: Date
    let closedAt: Date
    let messages: [SavedMessage]
    let messageCount: Int
    var claudeSessionId: String?
    var isOpen: Bool?  // true = still open (live auto-save), nil/false = closed

    var preview: String {
        // First user message as preview
        let raw = messages.first(where: { $0.role == "user" })?.text ?? ""
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Empty session" }
        return String(cleaned.prefix(120))
    }

    /// Smart title: use first user message if the title is generic (e.g. "Claude Code 1")
    var smartTitle: String {
        let generic = title.range(of: #"^(Claude Code|Grok|Swarm|Shell|Agents)\s*\d*$"#, options: .regularExpression) != nil
        if !generic { return title }
        let firstMsg = messages.first(where: { $0.role == "user" })?.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if firstMsg.isEmpty { return title }
        return String(firstMsg.prefix(50))
    }
}

@MainActor
class SessionHistoryStore: ObservableObject {
    @Published var sessions: [SessionHistory] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ArcBench", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("session_history.json")
        load()
    }

    func save(session: TerminalSession, messages: [ChatMessage], claudeSessionId: String? = nil, isOpen: Bool = false) {
        let saved = messages.map { SavedMessage(role: $0.role == .user ? "user" : "claude", text: $0.text) }
        // Skip empty sessions
        guard !saved.isEmpty, saved.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        let history = SessionHistory(
            id: session.id,
            title: session.title,
            mode: session.mode.rawValue,
            createdAt: session.createdAt,
            closedAt: Date(),
            messages: saved,
            messageCount: saved.filter { $0.role == "user" }.count,
            claudeSessionId: claudeSessionId,
            isOpen: isOpen
        )
        // Update existing entry if same session was saved before, otherwise insert
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = history
        } else {
            sessions.insert(history, at: 0)
        }
        // Keep last 50
        if sessions.count > 50 { sessions = Array(sessions.prefix(50)) }
        persist()
    }

    /// Auto-save a live session (called after each message)
    func autoSave(session: TerminalSession, messages: [ChatMessage], claudeSessionId: String? = nil) {
        save(session: session, messages: messages, claudeSessionId: claudeSessionId, isOpen: true)
    }

    /// Mark a session as closed (no longer live)
    func markClosed(_ id: UUID) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx] = SessionHistory(
                id: sessions[idx].id,
                title: sessions[idx].title,
                mode: sessions[idx].mode,
                createdAt: sessions[idx].createdAt,
                closedAt: Date(),
                messages: sessions[idx].messages,
                messageCount: sessions[idx].messageCount,
                claudeSessionId: sessions[idx].claudeSessionId,
                isOpen: false
            )
            persist()
        }
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        sessions.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SessionHistory].self, from: data) else { return }
        sessions = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum TerminalMode: String, CaseIterable {
    case claude = "claude"
    case shell  = "shell"
    case swarm  = "swarm"
    case grok   = "grok"
    case agents = "agents"

    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .shell:  return "Shell"
        case .swarm:  return "Swarm"
        case .grok:   return "Grok"
        case .agents: return "Agents"
        }
    }

    var icon: String {
        switch self {
        case .claude: return "circle.hexagongrid.fill"
        case .shell:  return "terminal"
        case .swarm:  return "bolt.trianglebadge.exclamationmark"
        case .grok:   return "globe.americas.fill"
        case .agents: return "person.3.fill"
        }
    }
}

/// Available custom icons for terminal sessions
let terminalIconOptions: [(name: String, symbol: String)] = [
    ("Default", ""),
    ("Terminal", "terminal"),
    ("Code", "chevron.left.forwardslash.chevron.right"),
    ("Bug", "ladybug"),
    ("Rocket", "paperplane.fill"),
    ("Star", "star.fill"),
    ("Bolt", "bolt.fill"),
    ("Brain", "brain.head.profile"),
    ("Globe", "globe"),
    ("Hammer", "hammer.fill"),
    ("Flask", "flask.fill"),
    ("Gear", "gearshape.fill"),
    ("Book", "book.fill"),
    ("Shield", "shield.fill"),
    ("Wand", "wand.and.stars"),
    ("Cube", "cube.fill"),
    ("Leaf", "leaf.fill"),
    ("Fire", "flame.fill"),
    ("Eye", "eye.fill"),
    ("Heart", "heart.fill"),
]

struct TerminalSession: Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    var mode: TerminalMode
    /// Custom icon override — empty string means use the default mode icon/logo
    var customIcon: String

    init(title: String, mode: TerminalMode = .shell, customIcon: String = "") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.mode = mode
        self.customIcon = customIcon
    }

    init(id: UUID, title: String, createdAt: Date, mode: TerminalMode, customIcon: String = "") {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.mode = mode
        self.customIcon = customIcon
    }
}

@MainActor
class TerminalManager: ObservableObject {
    @Published var terminals: [TerminalSession] = []
    @Published var activeTerminalId: UUID?
    /// Shared trust state — once any terminal trusts a folder, all terminals auto-accept
    @Published var trustedFolders: Set<String> = []

    /// Session history store for persisting closed sessions
    let historyStore = SessionHistoryStore()

    /// Track active PTY ViewModels for proper cleanup on close
    private var viewModels: [UUID: PTYChatViewModel] = [:]
    /// Track SwarmEngine instances so they survive tab switches
    private var swarmEngines: [UUID: SwarmEngine] = [:]
    /// Track GrokChatEngine instances so they survive tab switches
    private var grokEngines: [UUID: GrokChatEngine] = [:]
    /// Track AgentRouter instances so they survive tab switches
    private var agentRouters: [UUID: AgentRouter] = [:]

    // MARK: - @mention Routing

    /// Parses `@grok`, `@claude`, `@swarm`, `@shell` anywhere in a message.
    /// Returns (targetMode, cleanedMessage) or nil if no mention found.
    static func parseMention(_ text: String) -> (TerminalMode, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Check for @mentions anywhere in the text
        let mentions: [(String, TerminalMode)] = [
            ("@grok", .grok),
            ("@claude", .claude),
            ("@swarm", .swarm),
            ("@shell", .shell),
            ("@agents", .agents),
        ]
        for (tag, mode) in mentions {
            if let range = lower.range(of: tag) {
                // Make sure it's a word boundary (not part of an email like user@claude.com)
                let afterEnd = range.upperBound
                if afterEnd < lower.endIndex {
                    let nextChar = lower[afterEnd]
                    if nextChar.isLetter || nextChar.isNumber { continue }
                }
                // Strip the @mention from the text
                let cleaned = trimmed.replacingOccurrences(
                    of: "\\s*\(tag)\\s*", with: " ", options: [.regularExpression, .caseInsensitive]
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return (mode, cleaned.isEmpty ? trimmed : cleaned)
            }
        }
        return nil
    }

    /// Routes a message to a specific bot mode. Creates or reuses a terminal of that mode.
    /// Returns the target terminal's ID.
    @discardableResult
    func routeToBot(mode: TerminalMode, message: String, files: [AttachedFile] = []) -> UUID {
        // Find an existing terminal of this mode, or create one
        let target: TerminalSession
        if let existing = terminals.first(where: { $0.mode == mode }) {
            target = existing
        } else {
            let modeCount = terminals.filter { $0.mode == mode }.count + 1
            let label = "\(mode.label) \(modeCount)"
            let session = TerminalSession(title: label, mode: mode)
            terminals.append(session)
            target = session
        }
        activeTerminalId = target.id

        // Send the message to the appropriate engine
        switch mode {
        case .grok:
            let engine = grokEngine(for: target)
            engine.send(message, apiText: message, files: files)
        case .swarm:
            let engine = swarmEngine(for: target)
            if !engine.isRunning {
                engine.start(task: message, files: files)
            }
        case .claude, .shell:
            let vm = viewModel(for: target)
            vm.send(message, files: files)
        case .agents:
            let router = agentRouter(for: target)
            router.sendUserMessage(message, files: files)
        }

        return target.id
    }

    func createTerminal(title: String? = nil, mode: TerminalMode = .shell) {
        let modeCount = terminals.filter { $0.mode == mode }.count + 1
        let label = title ?? "\(mode.label) \(modeCount)"
        let session = TerminalSession(title: label, mode: mode)
        terminals.append(session)
        activeTerminalId = session.id
    }

    func closeTerminal(_ id: UUID) {
        // Final save + mark as closed
        if let session = terminals.first(where: { $0.id == id }) {
            if let vm = viewModels[id] {
                historyStore.save(session: session, messages: vm.messages, claudeSessionId: vm.claudeSessionIdPublic)
            } else if let grokEngine = grokEngines[id] {
                // Convert GrokChatMessages to ChatMessages for history
                let converted = grokEngine.messages.compactMap { msg -> ChatMessage? in
                    guard msg.role == "user" || msg.role == "assistant" else { return nil }
                    return ChatMessage(role: msg.role == "user" ? .user : .claude, text: msg.content)
                }
                if !converted.isEmpty { historyStore.save(session: session, messages: converted) }
            } else if let swarmEngine = swarmEngines[id] {
                // Convert SwarmEvents to ChatMessages for history
                let converted = swarmEngine.events.compactMap { event -> ChatMessage? in
                    guard event.role == .user || event.role == .grok || event.role == .claude else { return nil }
                    return ChatMessage(role: event.role == .user ? .user : .claude, text: event.content)
                }
                if !converted.isEmpty { historyStore.save(session: session, messages: converted) }
            }
        }
        historyStore.markClosed(id)

        viewModels[id]?.terminate()
        viewModels.removeValue(forKey: id)
        swarmEngines[id]?.stop()
        swarmEngines.removeValue(forKey: id)
        grokEngines[id]?.stop()
        grokEngines.removeValue(forKey: id)
        agentRouters.removeValue(forKey: id)

        if let idx = terminals.firstIndex(where: { $0.id == id }) {
            terminals.remove(at: idx)
            if activeTerminalId == id {
                // Select nearest neighbor (prefer right, then left, then nil)
                if idx < terminals.count {
                    activeTerminalId = terminals[idx].id
                } else if !terminals.isEmpty {
                    activeTerminalId = terminals[terminals.count - 1].id
                } else {
                    activeTerminalId = nil
                }
            }
        }
    }

    func switchMode(_ id: UUID, to newMode: TerminalMode) {
        guard let idx = terminals.firstIndex(where: { $0.id == id }) else { return }

        // Terminate existing PTY
        viewModels[id]?.terminate()
        viewModels.removeValue(forKey: id)

        terminals.remove(at: idx)
        let modeCount = terminals.filter { $0.mode == newMode }.count + 1
        let newSession = TerminalSession(title: "\(newMode.label) \(modeCount)", mode: newMode)
        terminals.insert(newSession, at: idx)
        activeTerminalId = newSession.id
    }

    func selectTerminal(_ id: UUID) {
        activeTerminalId = id
    }

    func renameTerminal(_ id: UUID, to newTitle: String) {
        guard let idx = terminals.firstIndex(where: { $0.id == id }) else { return }
        terminals[idx].title = newTitle
    }

    func setTerminalIcon(_ id: UUID, icon: String) {
        guard let idx = terminals.firstIndex(where: { $0.id == id }) else { return }
        terminals[idx].customIcon = icon
    }

    var activeTerminal: TerminalSession? {
        terminals.first(where: { $0.id == activeTerminalId })
    }

    // MARK: - ViewModel Registry

    /// Get or create a ViewModel for a session — persists across tab switches
    func viewModel(for session: TerminalSession) -> PTYChatViewModel {
        if let existing = viewModels[session.id] { return existing }
        let vm = PTYChatViewModel(mode: session.mode)
        vm.terminalManager = self
        vm.sessionId = session.id
        viewModels[session.id] = vm
        return vm
    }

    /// Get or create a SwarmEngine for a session — persists across tab switches
    func swarmEngine(for session: TerminalSession) -> SwarmEngine {
        if let existing = swarmEngines[session.id] { return existing }
        let engine = SwarmEngine()
        swarmEngines[session.id] = engine
        return engine
    }

    /// Get or create a GrokChatEngine for a session — persists across tab switches
    func grokEngine(for session: TerminalSession) -> GrokChatEngine {
        if let existing = grokEngines[session.id] { return existing }
        let engine = GrokChatEngine()
        grokEngines[session.id] = engine
        return engine
    }

    /// Get or create an AgentRouter for a session — persists across tab switches
    func agentRouter(for session: TerminalSession) -> AgentRouter {
        if let existing = agentRouters[session.id] { return existing }
        let router = AgentRouter()
        let grok = GrokAgent(role: .general, displayName: "Grok")
        let claude = ClaudeAgent(role: .coder, displayName: "Claude")
        router.register(grok)
        router.register(claude)
        agentRouters[session.id] = router
        return router
    }

    func registerViewModel(_ vm: PTYChatViewModel, for id: UUID) {
        viewModels[id] = vm
    }

    func unregisterViewModel(for id: UUID) {
        viewModels.removeValue(forKey: id)
    }

    // MARK: - Restore from History

    /// Reopens a saved session — if already open, just switch to it; otherwise create a new tab
    func restoreSession(_ history: SessionHistory) {
        // If a tab with this history's exact ID is already open, just switch to it
        if let existing = terminals.first(where: { $0.id == history.id }) {
            activeTerminalId = existing.id
            return
        }

        let mode = TerminalMode(rawValue: history.mode) ?? .claude
        // Reuse the original history ID so closing updates the same entry instead of creating a duplicate
        let session = TerminalSession(id: history.id, title: history.title, createdAt: history.createdAt, mode: mode)

        // Pre-populate the ViewModel BEFORE appending the session,
        // so viewModel(for:) finds it when the view renders.
        let vm = PTYChatViewModel(mode: mode)
        vm.terminalManager = self
        vm.sessionId = session.id
        if let csid = history.claudeSessionId {
            vm.restoreClaudeSessionId(csid)
        }
        for msg in history.messages {
            vm.messages.append(ChatMessage(role: msg.role == "user" ? .user : .claude, text: msg.text))
        }
        vm.userHasSentMessage = true
        vm.isWaiting = false
        vm.isThinking = false
        viewModels[session.id] = vm

        // Now trigger the view update — the VM is already registered
        terminals.append(session)
        activeTerminalId = session.id
    }
}
