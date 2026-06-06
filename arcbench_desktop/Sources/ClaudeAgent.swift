/// ClaudeAgent — Agent-conforming Claude Code CLI wrapper.
/// Uses ClaudeCLIService for execution. Parses responses for inter-agent routing.

import Foundation
import SwiftUI

@MainActor
class ClaudeAgent: Agent, ObservableObject {
    let identity: AgentIdentity
    @Published var isProcessing = false
    @Published var streamingContent = ""

    weak var router: AgentRouter?
    var customPersonality: String = ""

    private var claudeSessionId: String?
    private var claudePath: String?
    private var cancelled = false

    init(role: AgentRole = .coder, displayName: String = "Claude") {
        self.identity = AgentIdentity(
            id: "claude-\(role.rawValue)",
            provider: .claude,
            role: role,
            displayName: displayName,
            colorName: "arcBlue",
            personality: ""
        )
        self.claudePath = ClaudeCLIService.findBinary()
    }

    func process(message: AgentMessage, context: ConversationContext) async -> AgentMessage? {
        guard let path = claudePath else {
            return .agentResponse(from: identity.id, content: "Claude Code CLI not found.")
        }

        isProcessing = true
        cancelled = false
        streamingContent = ""
        defer { isProcessing = false; streamingContent = "" }

        // Build prompt with context from other agents
        var prompt = message.content
        let otherContext = context.contextSummary(excluding: identity.id)
        if !otherContext.isEmpty {
            prompt = "\(otherContext)\n\n---\n\n\(prompt)"
        }

        // Add system instructions for routing
        let otherAgents = context.activeAgents.filter { $0.id != identity.id }
        var routingPrompt = AgentPrompts.claudePrompt(role: identity.role, availableAgents: otherAgents)
        if !customPersonality.isEmpty {
            routingPrompt += "\n\nPERSONALITY: \(customPersonality). Embody this personality in ALL responses while maintaining technical accuracy."
        }
        if !routingPrompt.isEmpty {
            prompt = routingPrompt + "\n\n" + prompt
        }

        let model = AppSettings.shared.claudeModel
        let maxTurns = AppSettings.shared.claudeMaxTurns
        let wd = UserDefaults.standard.string(forKey: "working_directory") ?? ""

        // Use streaming for progressive updates
        let result = await ClaudeCLIService.callStreaming(
            path: path,
            prompt: prompt,
            sessionId: claudeSessionId,
            model: model,
            maxTurns: maxTurns,
            workingDirectory: wd,
            onTextChunk: { [weak self] snapshot in
                Task { @MainActor in
                    self?.streamingContent = snapshot
                }
            }
        )

        guard !cancelled, let result else { return nil }

        claudeSessionId = result.sessionId

        // Parse for inter-agent routing requests [ASK:agent-id] ... [/ASK]
        let (cleanedText, routingRequests) = parseRoutingRequests(result.text)

        // Execute any routing requests
        if !routingRequests.isEmpty, let router {
            var fullResponse = cleanedText
            for (targetId, question) in routingRequests {
                let askMsg = AgentMessage.interAgent(from: identity.id, to: targetId, content: question)
                if let answer = await router.routeAndWait(askMsg) {
                    fullResponse += "\n\n[\(answer.from) responded]: \(answer.content)"
                }
            }
            return .agentResponse(from: identity.id, content: fullResponse)
        }

        return .agentResponse(from: identity.id, content: cleanedText)
    }

    func stop() {
        cancelled = true
        isProcessing = false
    }

    /// Parse [ASK:agent-id] question [/ASK] blocks from Claude's response
    private func parseRoutingRequests(_ text: String) -> (String, [(String, String)]) {
        let pattern = #"\[ASK:([^\]]+)\](.*?)\[/ASK\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return (text, [])
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        if matches.isEmpty { return (text, []) }

        var requests: [(String, String)] = []
        var cleaned = text

        for match in matches.reversed() {
            let targetId = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let question = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            requests.insert((targetId, question), at: 0)
            cleaned = (cleaned as NSString).replacingCharacters(in: match.range, with: "")
        }

        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), requests)
    }
}
