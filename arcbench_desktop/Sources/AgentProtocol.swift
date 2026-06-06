/// AgentProtocol — Core types for the multi-agent system.
/// AgentIdentity, AgentRole, AgentMessage, ConversationContext, Agent protocol.

import Foundation
import SwiftUI

// MARK: - Agent Identity

enum AgentProvider: String, Codable {
    case grok    // xAI API
    case claude  // Claude CLI
}

enum AgentRole: String, Codable, CaseIterable {
    case coder       // writes/edits code (Claude default)
    case reviewer    // reviews code output
    case planner     // breaks tasks into steps
    case researcher  // gathers info, reads files, searches
    case general     // general-purpose assistant

    var label: String {
        switch self {
        case .coder: return "Coder"
        case .reviewer: return "Reviewer"
        case .planner: return "Planner"
        case .researcher: return "Researcher"
        case .general: return "General"
        }
    }

    var icon: String {
        switch self {
        case .coder: return "chevron.left.forwardslash.chevron.right"
        case .reviewer: return "eye"
        case .planner: return "list.bullet.rectangle"
        case .researcher: return "magnifyingglass"
        case .general: return "sparkles"
        }
    }
}

enum PersonalityPreset: String, CaseIterable {
    case professional = "Professional"
    case casual = "Casual & Friendly"
    case sarcastic = "Sarcastic Senior Dev"
    case pirate = "Pirate Captain"
    case zen = "Zen Master"
    case hype = "Hype Beast"
    case noir = "Film Noir Detective"
    case custom = "Custom"

    var prompt: String {
        switch self {
        case .professional: return "You are professional, precise, and thorough. No fluff."
        case .casual: return "You're chill, friendly, and use casual language. Drop in humor when appropriate."
        case .sarcastic: return "You're a brilliant but sarcastic senior engineer. You help, but with dry wit and mild roasting of bad code."
        case .pirate: return "You speak like a pirate captain. Technical accuracy is still paramount, but every response has nautical flair. 'Arr' and 'matey' are mandatory."
        case .zen: return "You are calm, philosophical, and speak in measured wisdom. You relate coding concepts to nature and mindfulness."
        case .hype: return "You're INCREDIBLY enthusiastic about EVERYTHING. Every piece of code is AMAZING. Liberal use of caps and exclamation marks. You gas up the user constantly."
        case .noir: return "You narrate everything like a 1940s detective novel. The code is the case. Bugs are suspects. You're world-weary but determined."
        case .custom: return ""
        }
    }
}

struct AgentIdentity: Hashable, Codable, Identifiable {
    let id: String           // "grok-general", "claude-coder"
    let provider: AgentProvider
    let role: AgentRole
    let displayName: String
    let colorName: String    // maps to Color extension names
    var personality: String   // e.g. "Sarcastic but brilliant senior engineer" or custom persona

    var color: Color {
        switch colorName {
        case "arcBlue": return .arcBlue
        case "accentGrok": return .accentGrok
        case "accentOrange": return .accentOrange
        case "accentPurple": return .accentPurple
        case "accentGreen": return .accentGreen
        default: return .arcBlue
        }
    }
}

// MARK: - Agent Message

struct AgentMessage: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let from: String           // agent ID or "user"
    let to: String?            // target agent ID, nil = broadcast/response
    var content: String
    let messageRole: MessageRole
    var attachedFilePaths: [String] = []
    var toolName: String?
    var isStreaming: Bool = false

    enum MessageRole: String, Codable {
        case user
        case assistant
        case tool
        case system
        case interAgent  // agent-to-agent
    }

    static func == (lhs: AgentMessage, rhs: AgentMessage) -> Bool {
        lhs.id == rhs.id
    }

    static func userMessage(_ text: String, files: [String] = []) -> AgentMessage {
        AgentMessage(id: UUID(), timestamp: Date(), from: "user", to: nil, content: text, messageRole: .user, attachedFilePaths: files)
    }

    static func agentResponse(from agentId: String, content: String) -> AgentMessage {
        AgentMessage(id: UUID(), timestamp: Date(), from: agentId, to: nil, content: content, messageRole: .assistant)
    }

    static func toolResult(from agentId: String, tool: String, content: String) -> AgentMessage {
        AgentMessage(id: UUID(), timestamp: Date(), from: agentId, to: nil, content: content, messageRole: .tool, toolName: tool)
    }

    static func interAgent(from: String, to: String, content: String) -> AgentMessage {
        AgentMessage(id: UUID(), timestamp: Date(), from: from, to: to, content: content, messageRole: .interAgent)
    }
}

// MARK: - Conversation Context

@MainActor
class ConversationContext: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var activeAgents: [AgentIdentity] = []

    /// Get recent history relevant to a specific agent
    func recentHistory(for agentId: String, maxMessages: Int = 40) -> [AgentMessage] {
        let relevant = messages.filter { msg in
            msg.from == "user" ||
            msg.from == agentId ||
            msg.to == agentId ||
            (msg.to == nil && msg.messageRole == .assistant)
        }
        return Array(relevant.suffix(maxMessages))
    }

    /// Brief summary of what other agents have contributed
    func contextSummary(excluding agentId: String) -> String {
        let otherAgentMsgs = messages.filter { $0.from != agentId && $0.from != "user" && $0.messageRole == .assistant }
        if otherAgentMsgs.isEmpty { return "" }
        let summaries = otherAgentMsgs.suffix(5).map { msg in
            let preview = String(msg.content.prefix(200))
            return "[\(msg.from)]: \(preview)"
        }
        return "Context from other agents:\n" + summaries.joined(separator: "\n")
    }

    func append(_ message: AgentMessage) {
        messages.append(message)
        if messages.count > 200 {
            messages = Array(messages.suffix(200))
        }
    }

    /// Update the last message from a specific agent (for streaming)
    func updateLastMessage(from agentId: String, content: String) {
        if let idx = messages.indices.reversed().first(where: { messages[$0].from == agentId && messages[$0].messageRole == .assistant }) {
            messages[idx].content = content
        }
    }
}

// MARK: - Agent Protocol

@MainActor
protocol Agent: AnyObject, ObservableObject {
    var identity: AgentIdentity { get }
    var isProcessing: Bool { get set }
    var streamingContent: String { get set }

    /// Process a message and return the response
    func process(message: AgentMessage, context: ConversationContext) async -> AgentMessage?

    /// Stop current processing
    func stop()
}
