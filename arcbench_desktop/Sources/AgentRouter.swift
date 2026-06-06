/// AgentRouter — Central message bus for multi-agent conversations.
/// Routes user messages and inter-agent messages. Includes AgentChatView.

import Foundation
import SwiftUI

@MainActor
class AgentRouter: ObservableObject {
    @Published var context: ConversationContext
    @Published var agents: [String: any Agent] = [:]
    @Published var isAnyProcessing = false
    @Published var draftText = ""

    private var chainDepth = 0
    private static let maxChainDepth = 5

    init() {
        self.context = ConversationContext()
    }

    /// Register an agent
    func register(_ agent: any Agent) {
        agents[agent.identity.id] = agent
        context.activeAgents.append(agent.identity)
        // Wire up the router reference if the agent supports it
        if let grok = agent as? GrokAgent { grok.router = self }
        if let claude = agent as? ClaudeAgent { claude.router = self }
    }

    /// User sends a message
    func sendUserMessage(_ text: String, files: [AttachedFile] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        chainDepth = 0

        let filePaths = files.map { $0.url.path }
        var content = trimmed
        if !files.isEmpty {
            let fileSection = files.map { file -> String in
                let path = file.url.path
                let name = file.url.lastPathComponent
                if file.url.hasDirectoryPath {
                    let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                    let listing = items.prefix(50).joined(separator: "\n  ")
                    return "\(name)/ (path: \(path))\n  \(listing)"
                } else {
                    return "\(name) (path: \(path))"
                }
            }.joined(separator: "\n\n")
            content = trimmed.isEmpty ? "Review these files:\n\n\(fileSection)" : "\(trimmed)\n\n---\nAttached files (use filesystem paths with tools):\n\n\(fileSection)"
        }

        let userMsg = AgentMessage(id: UUID(), timestamp: Date(), from: "user", to: nil, content: content, messageRole: .user, attachedFilePaths: filePaths)
        context.append(userMsg)

        // Determine target agent(s) from @mention or broadcast to all
        let (targetIds, cleanedContent) = parseTargets(content)

        Task {
            isAnyProcessing = true
            // Process all targeted agents concurrently
            await withTaskGroup(of: Void.self) { group in
                for targetId in targetIds {
                    guard let targetAgent = agents[targetId] else { continue }
                    let placeholder = AgentMessage.agentResponse(from: targetId, content: "")
                    context.append(placeholder)

                    group.addTask { @MainActor in
                        let routedMsg = AgentMessage(id: UUID(), timestamp: Date(), from: "user", to: targetId, content: cleanedContent, messageRole: .user, attachedFilePaths: filePaths)
                        let response = await targetAgent.process(message: routedMsg, context: self.context)
                        if let response {
                            if let idx = self.context.messages.lastIndex(where: { $0.from == targetId && $0.messageRole == .assistant && $0.content.isEmpty }) {
                                self.context.messages[idx] = response
                            } else {
                                self.context.append(response)
                            }
                        } else {
                            self.context.messages.removeAll { $0.id == placeholder.id }
                        }
                    }
                }
            }
            isAnyProcessing = false
        }
    }

    /// Route an inter-agent message and wait for the response
    func routeAndWait(_ message: AgentMessage) async -> AgentMessage? {
        chainDepth += 1
        guard chainDepth <= Self.maxChainDepth else {
            return .agentResponse(from: "system", content: "(Chain depth limit reached)")
        }

        guard let targetId = message.to, let targetAgent = agents[targetId] else { return nil }

        context.append(message)

        let response = await targetAgent.process(message: message, context: context)
        if let response {
            context.append(response)
        }
        return response
    }

    /// Parse @mentions to determine target agent(s). No mention = broadcast to all.
    private func parseTargets(_ text: String) -> ([String], String) {
        let lower = text.lowercased()
        var matched: [String] = []
        var cleaned = text

        // Check for @mentions by display name (case-insensitive)
        for (id, agent) in agents {
            let name = agent.identity.displayName.lowercased()
            // Match @displayname or @provider-prefix
            let patterns = ["@\(name)", "@\(id.components(separatedBy: "-").first ?? id)"]
            for pattern in patterns {
                if lower.contains(pattern) {
                    if !matched.contains(id) { matched.append(id) }
                    cleaned = cleaned.replacingOccurrences(of: "(?i)\\s*\(NSRegularExpression.escapedPattern(for: pattern))\\s*", with: " ", options: .regularExpression)
                }
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        if matched.isEmpty {
            // No mention — broadcast to ALL agents
            return (Array(agents.keys), cleaned)
        }
        return (matched, cleaned)
    }
}

// MARK: - Agent Chat View (multi-agent conversation UI)

struct AgentChatView: View {
    @ObservedObject var router: AgentRouter
    @Binding var attachedFiles: [AttachedFile]
    @EnvironmentObject var terminalManager: TerminalManager
    @State private var showAgentCreator = false

    var body: some View {
        VStack(spacing: 0) {
            // Agent bar — shows active agents
            HStack(spacing: ArcSpacing.md) {
                ForEach(router.context.activeAgents) { agent in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(agent.color.opacity(0.15))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: agent.role.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(agent.color)
                            )
                        Text(agent.displayName)
                            .font(ArcFont.caption(.semibold))
                            .foregroundColor(agent.color)
                    }
                    .padding(.horizontal, ArcSpacing.md)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(agent.color.opacity(0.06)))
                }
                Button { showAgentCreator = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, ArcSpacing.sm)
            .background(Color.bgSecondary)

            Rectangle().fill(Color.borderSubtle).frame(height: 1)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(router.context.messages) { msg in
                            if msg.messageRole == .user {
                                UserRow(text: msg.content).padding(.vertical, ArcSpacing.xs)
                            } else if msg.messageRole == .tool {
                                ToolExecutionRow(toolName: msg.toolName ?? "tool", content: msg.content)
                                    .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.xs)
                            } else if msg.messageRole == .interAgent {
                                InterAgentRow(message: msg, agents: router.context.activeAgents)
                                    .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.xs)
                            } else {
                                AgentResponseRow(message: msg, agents: router.context.activeAgents, router: router)
                                    .padding(.vertical, ArcSpacing.xs)
                            }
                        }

                        Color.clear.frame(height: 1).id("agent-bottom")
                    }.padding(.vertical, ArcSpacing.md)
                }
                .clipped()
                .onChange(of: router.context.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("agent-bottom", anchor: .bottom) }
                }
            }

            // Input bar
            VStack(spacing: 0) {
                if !attachedFiles.isEmpty {
                    AttachedFilesStrip(files: $attachedFiles)
                }
                HStack(alignment: .center, spacing: ArcSpacing.md) {
                    Button(action: { openFilePanel(attachedFiles: $attachedFiles) }) {
                        Image(systemName: "paperclip")
                            .font(ArcFont.label(.medium))
                            .foregroundColor(.textTertiary)
                            .frame(width: 24, height: 24)
                    }.buttonStyle(.plain)

                    TextField("Message agents... (@grok, @claude)", text: $router.draftText, axis: .vertical)
                        .textFieldStyle(.plain).font(ArcFont.body).lineLimit(1...5)
                        .foregroundColor(.textPrimary)
                        .onSubmit { send() }

                    Button(action: send) {
                        Image(systemName: router.isAnyProcessing ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(router.isAnyProcessing ? .accentRed : canSend ? .white : .textTertiary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(router.isAnyProcessing ? Color.accentRed.opacity(0.2) : canSend ? Color.arcBlue : Color.bgTertiary))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: ArcRadius.bar, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: ArcRadius.bar, style: .continuous).stroke(Color.borderMedium, lineWidth: 1))
            )
            .padding(.horizontal, ArcSpacing.lg).padding(.vertical, ArcSpacing.md).background(Color.bg)
            .mentionAutocomplete(text: $router.draftText)
        }
        .background(Color.bg)
        .sheet(isPresented: $showAgentCreator) {
            AgentCreatorSheet(router: router, isPresented: $showAgentCreator)
        }
    }

    private var canSend: Bool {
        !router.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty
    }

    private func send() {
        if router.isAnyProcessing {
            for agent in router.agents.values { agent.stop() }
            return
        }
        let text = router.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedFiles.isEmpty else { return }
        router.sendUserMessage(text, files: attachedFiles)
        router.draftText = ""
        withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
    }
}

// MARK: - Agent Response Row

struct AgentResponseRow: View {
    let message: AgentMessage
    let agents: [AgentIdentity]
    let router: AgentRouter

    private var agent: AgentIdentity? {
        agents.first(where: { $0.id == message.from })
    }

    private var accentColor: Color { agent?.color ?? .arcBlue }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Agent avatar
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.10))
                    .frame(width: 26, height: 26)
                if agent?.provider == .claude {
                    ClaudeLogo(size: 13)
                } else if agent?.provider == .grok {
                    GrokLogo(size: 13)
                } else {
                    Image(systemName: agent?.role.icon ?? "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor)
                }
            }.padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent?.displayName ?? message.from)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)

                if message.content.isEmpty {
                    if let agentObj = router.agents[message.from], !agentObj.streamingContent.isEmpty {
                        WordTypewriter(text: agentObj.streamingContent, color: accentColor)
                    } else {
                        GrokStreamingBar()
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.cardBg)
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.borderSubtle, lineWidth: 0.5))
                            )
                    }
                } else {
                    WordTypewriter(text: message.content, color: accentColor)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, ArcSpacing.lg).padding(.vertical, 3)
    }
}

// MARK: - Inter-Agent Message Row

struct InterAgentRow: View {
    let message: AgentMessage
    let agents: [AgentIdentity]

    private var fromAgent: AgentIdentity? { agents.first(where: { $0.id == message.from }) }
    private var toAgent: AgentIdentity? { agents.first(where: { $0.id == message.to }) }

    var body: some View {
        HStack(spacing: ArcSpacing.sm) {
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)

            Text(fromAgent?.displayName ?? message.from)
                .font(ArcFont.caption(.semibold))
                .foregroundColor(fromAgent?.color ?? .textTertiary)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.textTertiary)

            Text(toAgent?.displayName ?? (message.to ?? "?"))
                .font(ArcFont.caption(.semibold))
                .foregroundColor(toAgent?.color ?? .textTertiary)

            Text(String(message.content.prefix(100)))
                .font(ArcFont.small)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, ArcSpacing.lg).padding(.vertical, 6)
        .background(
            Capsule().fill(Color.bgTertiary.opacity(0.5))
                .overlay(Capsule().stroke(Color.borderSubtle, lineWidth: 0.5))
        )
    }
}

// MARK: - Agent Creator Sheet

struct AgentCreatorSheet: View {
    @ObservedObject var router: AgentRouter
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var selectedProvider: AgentProvider = .grok
    @State private var selectedRole: AgentRole = .general
    @State private var selectedPreset: PersonalityPreset = .professional
    @State private var customPersonality = ""
    @State private var keywords = ""
    @State private var isGenerating = false

    private var personality: String {
        if selectedPreset == .custom {
            return customPersonality
        }
        return selectedPreset.prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Create Agent").font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.textTertiary)
                }.buttonStyle(.plain)
            }

            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                TextField("e.g. Code Reviewer, Research Bot", text: $name)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.textPrimary)
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.bgTertiary).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderSubtle)))
            }

            // Provider
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                    Picker("", selection: $selectedProvider) {
                        Text("Grok (xAI)").tag(AgentProvider.grok)
                        Text("Claude (CLI)").tag(AgentProvider.claude)
                    }.pickerStyle(.segmented).frame(width: 200)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Role").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                    Picker("", selection: $selectedRole) {
                        ForEach(AgentRole.allCases, id: \.self) { role in
                            Label(role.label, systemImage: role.icon).tag(role)
                        }
                    }.frame(width: 150)
                }
            }

            // Personality preset
            VStack(alignment: .leading, spacing: 6) {
                Text("Personality").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(PersonalityPreset.allCases, id: \.self) { preset in
                        Button {
                            selectedPreset = preset
                        } label: {
                            Text(preset.rawValue)
                                .font(.system(size: 11, weight: selectedPreset == preset ? .bold : .medium))
                                .foregroundColor(selectedPreset == preset ? .white : .textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedPreset == preset ? Color.arcBlue : Color.bgTertiary)
                                )
                        }.buttonStyle(.plain)
                    }
                }
            }

            // Custom personality / AI generate
            if selectedPreset == .custom {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Custom Personality").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                        Spacer()
                        // AI generate from keywords
                        HStack(spacing: 4) {
                            TextField("keywords...", text: $keywords)
                                .textFieldStyle(.plain).font(.system(size: 11)).foregroundColor(.textPrimary)
                                .frame(width: 120)
                                .padding(4).background(RoundedRectangle(cornerRadius: 4).fill(Color.bgTertiary))
                            Button {
                                generatePersonality()
                            } label: {
                                HStack(spacing: 3) {
                                    if isGenerating {
                                        ProgressView().scaleEffect(0.5)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text("Generate")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.arcBlue)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.arcBlue.opacity(0.1)))
                            }.buttonStyle(.plain).disabled(keywords.isEmpty || isGenerating)
                        }
                    }
                    TextEditor(text: $customPersonality)
                        .font(.system(size: 12)).foregroundColor(.textPrimary)
                        .frame(height: 60)
                        .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Color.bgTertiary).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderSubtle)))
                }
            }

            Spacer()

            // Create button
            HStack {
                Spacer()
                Button {
                    createAgent()
                    isPresented = false
                } label: {
                    Text("Create Agent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(name.isEmpty ? Color.bgTertiary : Color.arcBlue))
                }.buttonStyle(.plain).disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 460)
        .background(Color.bg)
    }

    private func createAgent() {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }

        let personality = self.personality

        if selectedProvider == .grok {
            let agent = GrokAgent(role: selectedRole, displayName: displayName)
            agent.customPersonality = personality
            router.register(agent)
        } else {
            let agent = ClaudeAgent(role: selectedRole, displayName: displayName)
            agent.customPersonality = personality
            router.register(agent)
        }
    }

    private func generatePersonality() {
        let kw = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        isGenerating = true

        // Use Grok API to generate a personality based on keywords
        Task {
            let prompt = "Generate a short (2-3 sentence) AI agent personality description based on these keywords: \(kw). Make it fun and distinctive. Output ONLY the personality description, nothing else."

            let body: [String: Any] = [
                "model": AppSettings.shared.grokModel,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.9,
                "max_tokens": 150,
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                isGenerating = false
                return
            }

            var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(AppSettings.shared.xaiApiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = jsonData
            request.timeoutInterval = 30

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    customPersonality = content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {}

            isGenerating = false
        }
    }
}
