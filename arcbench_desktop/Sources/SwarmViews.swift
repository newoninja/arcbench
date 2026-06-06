/// SwarmViews — Swarm multi-agent chat view and helpers.
/// SwarmChatView, SwarmMessageRow, SwarmChip + private helpers.

import SwiftUI

// MARK: - Swarm Chat View (Grok ↔ Claude multi-agent)

struct SwarmChatView: View {
    @Binding var attachedFiles: [AttachedFile]
    @ObservedObject var engine: SwarmEngine
    @EnvironmentObject var terminalManager: TerminalManager
    // engine.draftText lives on engine.draftText so it survives Settings toggle
    @State private var showSettings = false
    @State private var isDropping = false

    private var canSend: Bool {
        (!engine.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty) &&
        !engine.xaiKey.isEmpty &&
        (engine.useClaudeCLI || !engine.anthropicKey.isEmpty)
    }

    var body: some View {
        HStack(spacing: 0) {
            SwarmMetricsView(engine: engine)

            VStack(spacing: 0) {
                swarmPhaseBar

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if engine.events.isEmpty && !engine.isRunning {
                                swarmWelcome
                            }

                            ForEach(engine.events) { event in
                                if event.role == .user {
                                    UserRow(text: event.content, files: event.files)
                                        .id(event.id)
                                } else if event.role != .system && !event.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    IterationCard(event: event)
                                        .id(event.id)
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.95)),
                                            removal: .opacity
                                        ))
                                }
                            }

                            if engine.isStreaming && !engine.streamingContent.isEmpty {
                                StreamingPreviewCard(content: engine.streamingContent)
                                    .id("streaming-preview")
                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            }

                            if engine.isApproved {
                                SwarmApprovedCard(iteration: engine.iteration)
                            }

                            if let error = engine.lastError, !engine.isRunning {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.accentRed)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Error").font(ArcFont.label(.bold)).foregroundColor(.accentRed)
                                        Text(error).font(.system(size: 12)).foregroundColor(.textSecondary).lineLimit(3)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous)
                                        .fill(Color.accentRed.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous).stroke(Color.accentRed.opacity(0.25), lineWidth: 1))
                                )
                                .padding(.horizontal, ArcSpacing.xl)
                                .padding(.vertical, ArcSpacing.md)
                            }

                            if engine.isRunning && !engine.isApproved {
                                swarmThinkingIndicator
                            }

                            Color.clear.frame(height: 1).id("swarm-bottom")
                        }
                        .padding(.vertical, ArcSpacing.md)
                    }
                    .clipped()
                    .onChange(of: engine.events.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("swarm-bottom", anchor: .bottom) }
                    }
                    .onChange(of: engine.streamingContent) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("swarm-bottom", anchor: .bottom) }
                    }
                }

                swarmInputBar
                    .layoutPriority(1)

                SwarmStatusBanner(engine: engine)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
        }
        .background(Color.bg)
        .sheet(isPresented: $showSettings) { swarmSettingsSheet }
        .onAppear {
            if engine.anthropicKey.isEmpty {
                engine.anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
            }
        }
    }

    // MARK: - Phase Bar

    private var swarmPhaseBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: ArcSpacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(ArcFont.small(.semibold))
                    .foregroundColor(.accentOrange)
                Text(engine.isRunning ? "ITER \(engine.iteration)/\(engine.maxIterations)" : engine.isApproved ? "COMPLETE" : "IDLE")
                    .font(ArcFont.monoSmall(.bold))
                    .foregroundColor(engine.isApproved ? .accentGreen : engine.isRunning ? .accentOrange : .textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(engine.isRunning ? Color.accentOrange.opacity(0.1) : engine.isApproved ? Color.accentGreen.opacity(0.1) : Color.bgTertiary)
                    .overlay(Capsule().stroke(engine.isRunning ? Color.accentOrange.opacity(0.25) : engine.isApproved ? Color.accentGreen.opacity(0.25) : Color.borderSubtle, lineWidth: 1))
            )

            Spacer()

            HStack(spacing: ArcSpacing.xs) {
                phasePill("Grok", icon: "bolt.fill", active: engine.phase == .grokPlanning || engine.phase == .grokJudging, color: .accentGrok)
                Image(systemName: "arrow.right").font(ArcFont.xs).foregroundColor(.textTertiary)
                phasePill("Claude", icon: "circle.hexagongrid.fill", active: engine.phase == .claudeExecuting, color: .arcBlue)
                Image(systemName: "arrow.right").font(ArcFont.xs).foregroundColor(.textTertiary)
                phasePill("Review", icon: "checkmark.circle", active: engine.phase == .grokJudging, color: .accentPurple)
            }

            Spacer()

            HStack(spacing: ArcSpacing.lg) {
                tokenBadge(icon: "bolt.fill", count: engine.grokTokens, color: .accentGrok)
                tokenBadge(icon: "circle.hexagongrid.fill", count: engine.claudeTokens, color: .arcBlue)
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(ArcFont.caption).foregroundColor(.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.bgTertiary))
            }
            .buttonStyle(.plain)
            .padding(.leading, ArcSpacing.md)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, ArcSpacing.md)
        .background(Color.bgSecondary)
    }

    private func phasePill(_ label: String, icon: String, active: Bool, color: Color) -> some View {
        HStack(spacing: ArcSpacing.xs) {
            if active {
                StatusDot(color: color, size: 6, pulse: true)
            }
            Image(systemName: icon).font(.system(size: 8, weight: .semibold))
            Text(label).font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundColor(active ? color : .textTertiary)
        .padding(.horizontal, ArcSpacing.md)
        .padding(.vertical, ArcSpacing.xs)
        .background(
            Capsule().fill(active ? color.opacity(0.1) : Color.clear)
                .overlay(Capsule().stroke(active ? color.opacity(0.3) : Color.borderSubtle.opacity(0.5), lineWidth: 1))
        )
    }

    private func tokenBadge(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 7, weight: .bold)).foregroundColor(color.opacity(0.7))
            Text(count > 0 ? formatTokens(count) : "0").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(.textTertiary)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Welcome

    private var swarmWelcome: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            HStack(spacing: ArcSpacing.xxl) {
                VStack(spacing: ArcSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color.accentOrange.opacity(0.2), Color.accentOrange.opacity(0.03)], center: .center, startRadius: 0, endRadius: 28))
                            .frame(width: 56, height: 56)
                        GrokLogo(size: 28, color: .accentGrok)
                    }
                    Text("Grok").font(.system(size: 12, weight: .bold)).foregroundColor(.accentGrok)
                    Text("Boss").font(ArcFont.small).foregroundColor(.textTertiary)
                }

                VStack(spacing: ArcSpacing.xs) {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            Circle().fill(Color.textTertiary.opacity(0.3)).frame(width: 3, height: 3)
                        }
                    }
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textTertiary.opacity(0.5))
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            Circle().fill(Color.textTertiary.opacity(0.3)).frame(width: 3, height: 3)
                        }
                    }
                }

                VStack(spacing: ArcSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color.arcBlue.opacity(0.2), Color.arcBlue.opacity(0.03)], center: .center, startRadius: 0, endRadius: 28))
                            .frame(width: 56, height: 56)
                        ClaudeLogo(size: 24)
                    }
                    Text("Claude").font(.system(size: 12, weight: .bold)).foregroundColor(.arcBlue)
                    Text("Worker").font(ArcFont.small).foregroundColor(.textTertiary)
                }
            }

            VStack(spacing: ArcSpacing.md) {
                Text("Multi-Agent Swarm")
                    .font(ArcFont.headline)
                    .foregroundColor(.textPrimary)
                Text("Grok plans and reviews. Claude executes.\nThe loop runs until Grok approves the output.")
                    .font(ArcFont.label)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: ArcSpacing.md) {
                SwarmChip(text: "Write a landing page") { engine.draftText = "Write a complete, beautiful landing page for a SaaS product" }
                SwarmChip(text: "Code review") { engine.draftText = "Review the code in this project and suggest improvements" }
                SwarmChip(text: "Debug a problem") { engine.draftText = "Help me find and fix the most critical bug in this codebase" }
            }

            if !engine.useClaudeCLI && engine.anthropicKey.isEmpty {
                HStack(spacing: ArcSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").font(ArcFont.small).foregroundColor(.accentOrange)
                    Text("Set your Anthropic API key in Settings, or enable Claude Code CLI mode.")
                        .font(ArcFont.caption)
                        .foregroundColor(.accentOrange.opacity(0.8))
                }
                .padding(.top, ArcSpacing.xs)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Thinking Indicator

    private var swarmThinkingIndicator: some View {
        HStack(alignment: .center, spacing: 10) {
            let isGrok = engine.phase == .grokPlanning || engine.phase == .grokJudging
            let color: Color = isGrok ? .accentGrok : .arcBlue
            let label = engine.phase.rawValue

            ZStack {
                Circle().fill(color.opacity(0.1)).frame(width: 32, height: 32)
                if isGrok {
                    GrokLogo(size: 16, color: color)
                } else {
                    ClaudeLogo(size: 14)
                }
            }
            .breathingScale()

            HStack(spacing: ArcSpacing.md) {
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .opacity(0.4)
                            .scaleEffect(1.0)
                            .animation(
                                .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                                value: engine.isRunning
                            )
                    }
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, ArcSpacing.md)
            .background(
                Capsule().fill(color.opacity(0.06))
                    .overlay(Capsule().stroke(color.opacity(0.15), lineWidth: 1))
            )

            Spacer()
        }
        .padding(.horizontal, ArcSpacing.xl)
        .padding(.vertical, ArcSpacing.sm)
    }

    // MARK: - Input Bar

    private var swarmInputBar: some View {
        VStack(spacing: 0) {
            if !attachedFiles.isEmpty {
                AttachedFilesStrip(files: $attachedFiles)
            }
            HStack(spacing: 0) {
            TextField("Describe the task for the swarm...", text: $engine.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(ArcFont.label)
                .lineLimit(1...5)
                .foregroundColor(.textPrimary)
                .onSubmit { if canSend && !engine.isRunning { startSwarm() } }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            HStack(spacing: ArcSpacing.sm) {
                if engine.isRunning {
                    Text("esc")
                        .font(ArcFont.monoSmall(.medium))
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, ArcSpacing.sm)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: ArcRadius.sm).fill(Color.bgTertiary))
                }

                Button {
                    if engine.isRunning { engine.stop() }
                    else { startSwarm() }
                } label: {
                    ZStack {
                        if engine.isRunning {
                            RoundedRectangle(cornerRadius: 3).fill(Color.accentRed).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                                .foregroundColor(canSend ? .white : .textTertiary)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(
                            engine.isRunning ? Color.accentRed.opacity(0.2) :
                            canSend ? Color.accentOrange : Color.bgTertiary
                        )
                        .shadow(color: engine.isRunning ? Color.accentRed.opacity(0.3) : canSend ? Color.accentOrange.opacity(0.3) : .clear, radius: ArcShadow.md)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!engine.isRunning && !canSend)
            }
            .padding(.trailing, ArcSpacing.md)
        }
        }
        .background(
            RoundedRectangle(cornerRadius: ArcRadius.bar, style: .continuous)
                .fill(Color.bgTertiary.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: ArcRadius.bar, style: .continuous)
                        .stroke(engine.isRunning ? Color.accentOrange.opacity(0.3) : Color.borderMedium, lineWidth: 1)
                )
        )
        .shadow(color: engine.isRunning ? Color.accentOrange.opacity(0.08) : .clear, radius: ArcShadow.lg)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bg)
        .mentionAutocomplete(text: $engine.draftText)
    }

    private func startSwarm() {
        var t = engine.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !attachedFiles.isEmpty else { return }

        if let (targetMode, cleanedMsg) = TerminalManager.parseMention(t), targetMode != .swarm {
            let sentFiles = attachedFiles
            terminalManager.routeToBot(mode: targetMode, message: cleanedMsg, files: sentFiles)
            engine.draftText = ""
            withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
            return
        }

        let sentFiles = attachedFiles
        if !attachedFiles.isEmpty {
            let paths = attachedFiles.map { $0.url.path }
            let fileSection = paths.map { "  \($0)" }.joined(separator: "\n")
            t = t.isEmpty ? "Analyze these files:\n\(fileSection)" : "\(t)\n\nAttached files:\n\(fileSection)"
            withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
        }
        engine.start(task: t, files: sentFiles)
        engine.draftText = ""
    }

    // MARK: - Settings Sheet

    private var swarmSettingsSheet: some View {
        VStack(alignment: .leading, spacing: ArcSpacing.xxl) {
            SheetHeader(title: "Swarm Settings") { showSettings = false }

            VStack(alignment: .leading, spacing: ArcSpacing.sm) {
                Text("Anthropic API Key").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                SecureField("sk-ant-...", text: Binding(
                    get: { engine.anthropicKey },
                    set: { engine.anthropicKey = $0 }
                ))
                .textFieldStyle(.plain)
                .font(ArcFont.monoLabel)
                .foregroundColor(.textPrimary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: ArcRadius.md).fill(Color.bgTertiary).overlay(RoundedRectangle(cornerRadius: ArcRadius.md).stroke(Color.borderSubtle, lineWidth: 1)))
            }

            VStack(alignment: .leading, spacing: ArcSpacing.sm) {
                Text("Max Iterations").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                HStack {
                    Slider(value: Binding(
                        get: { Double(engine.maxIterations) },
                        set: { engine.maxIterations = Int($0) }
                    ), in: 2...8, step: 1)
                    Text("\(engine.maxIterations)").font(ArcFont.monoLabel(.bold)).foregroundColor(.accentOrange).frame(width: 30)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 280)
        .background(Color.bg)
    }
}

// MARK: - Swarm Message Row

struct SwarmMessageRow: View {
    let event: SwarmEvent

    private var isGrok: Bool { event.role == .grok }
    private var color: Color { isGrok ? .accentGrok : .arcBlue }
    private var roleLabel: String { isGrok ? "Grok" : "Claude" }
    private var phaseLabel: String {
        switch event.phase {
        case .grokPlanning: return "Planning"
        case .grokJudging: return "Reviewing"
        case .claudeExecuting: return "Executing"
        case .approved: return "Approved"
        case .error: return "Error"
        default: return ""
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 30, height: 30)
                    .shadow(color: color.opacity(0.15), radius: ArcShadow.sm)
                if isGrok {
                    GrokLogo(size: 16, color: color)
                } else {
                    ClaudeLogo(size: 14)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: ArcSpacing.xs) {
                HStack(spacing: ArcSpacing.sm) {
                    Text(roleLabel)
                        .font(ArcFont.caption(.bold))
                        .foregroundColor(color)
                    if !phaseLabel.isEmpty {
                        Text(phaseLabel)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(color.opacity(0.6))
                            .padding(.horizontal, ArcSpacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color.opacity(0.08)))
                    }
                    Text("Iter \(event.iteration)")
                        .font(ArcFont.monoXs)
                        .foregroundColor(.textTertiary)
                }

                WordTypewriter(text: event.content, color: color)
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, ArcSpacing.xl)
        .padding(.vertical, ArcSpacing.xs)
    }
}

// MARK: - Swarm Chip

struct SwarmChip: View {
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(ArcFont.caption(.medium))
                .foregroundColor(isHovered ? .accentOrange : .textSecondary)
                .padding(.horizontal, ArcSpacing.lg)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isHovered ? Color.accentOrange.opacity(0.08) : Color.bgTertiary.opacity(0.5))
                        .overlay(Capsule().stroke(isHovered ? Color.accentOrange.opacity(0.3) : Color.borderSubtle, lineWidth: 1))
                )
                .shadow(color: isHovered ? Color.accentOrange.opacity(0.15) : .clear, radius: ArcShadow.md)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovered = h } }
    }
}
