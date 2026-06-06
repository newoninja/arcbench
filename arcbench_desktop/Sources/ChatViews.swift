/// Chat terminal views — tab bar, terminal routing, welcome card.
/// Orchestrator views only — components extracted to:
///   MessageViews, InputViews, ThinkingViews, DialogViews,
///   TypewriterView, SwarmViews, GrokViews, GrokChatEngine.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - TerminalView (entry point)

struct TerminalView: View {
    let session: TerminalSession
    @EnvironmentObject var terminalManager: TerminalManager
    @State private var attachedFiles: [AttachedFile] = []
    @State private var isDropping = false

    private var isActive: Bool { session.id == terminalManager.activeTerminalId }

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBar(session: session)
            Rectangle().fill(Color.borderSubtle).frame(height: 1)
            if session.mode == .swarm {
                SwarmChatView(attachedFiles: $attachedFiles, engine: terminalManager.swarmEngine(for: session)).id(session.id)
            } else if session.mode == .grok {
                GrokChatView(attachedFiles: $attachedFiles, engine: terminalManager.grokEngine(for: session)).id(session.id)
            } else if session.mode == .agents {
                AgentChatView(router: terminalManager.agentRouter(for: session), attachedFiles: $attachedFiles).id(session.id)
            } else {
                ChatTerminalView(session: session, viewModel: terminalManager.viewModel(for: session), attachedFiles: $attachedFiles).id(session.id)
            }
        }
        .overlay {
            if isDropping {
                DropOverlay(color: dropColor)
                    .padding(ArcSpacing.xxl)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropping) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        if !attachedFiles.contains(where: { $0.url == url }) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                attachedFiles.append(AttachedFile(url: url))
                            }
                        }
                    }
                }
            }
            return !providers.isEmpty
        }
    }

    private var dropColor: Color {
        switch session.mode {
        case .claude: return .arcBlue
        case .grok: return .accentGrok
        case .swarm: return .accentOrange
        case .shell: return .accentGreen
        case .agents: return .accentPurple
        }
    }
}

// MARK: - Tab Bar

struct TerminalTabBar: View {
    let session: TerminalSession
    @EnvironmentObject var terminalManager: TerminalManager
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(terminalManager.terminals) { t in
                        TerminalTab(terminal: t, isActive: t.id == terminalManager.activeTerminalId)
                    }
                }.padding(.horizontal, 1)
            }
            Spacer(minLength: 0)
            Menu {
                Button { terminalManager.createTerminal(mode: .claude) } label: { Label("Claude Code", systemImage: "circle.hexagongrid.fill") }
                Button { terminalManager.createTerminal(mode: .shell) } label: { Label("Shell", systemImage: "terminal") }
                Button { terminalManager.createTerminal(mode: .swarm) } label: { Label("Swarm", systemImage: "bolt.trianglebadge.exclamationmark") }
                Button { terminalManager.createTerminal(mode: .grok) } label: { Label("Grok", systemImage: "globe.americas.fill") }
                Button { terminalManager.createTerminal(mode: .agents) } label: { Label("Agents", systemImage: "person.3.fill") }
            } label: {
                Image(systemName: "plus").font(ArcFont.small(.semibold)).foregroundColor(.textTertiary)
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30).padding(.trailing, ArcSpacing.sm)
        }.frame(height: 36).background(Color.bgSecondary)
    }
}

struct TerminalTab: View {
    let terminal: TerminalSession
    let isActive: Bool
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @EnvironmentObject var terminalManager: TerminalManager

    private var accent: Color {
        switch terminal.mode {
        case .claude: return .arcBlue
        case .shell: return .accentGreen
        case .swarm: return .accentOrange
        case .grok: return .accentGrok
        case .agents: return .accentPurple
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            TerminalIcon(session: terminal, size: 14, activeColor: isActive ? accent : .textTertiary)

            if isRenaming {
                TextField("Name", text: Binding(
                    get: { renameText },
                    set: { renameText = String($0.prefix(30)) }
                ), onCommit: {
                    let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { terminalManager.renameTerminal(terminal.id, to: t) }
                    isRenaming = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: 120)
            } else {
                Text(terminal.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .textPrimary : .textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            }

            if isHovered || isActive {
                Button { terminalManager.closeTerminal(terminal.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(isHovered ? .textSecondary : .textTertiary)
                        .frame(width: 16, height: 16).background(Circle().fill(isHovered ? Color.bgTertiary : .clear))
                }.buttonStyle(.plain)
            } else { Spacer().frame(width: 16) }
        }
        .padding(.horizontal, 14).frame(height: 36)
        .background(Group { if isActive { Color.bg } else if isHovered { Color.bgTertiary.opacity(0.4) } else { Color.clear } })
        .overlay(alignment: .bottom) {
            if isActive { Capsule().fill(accent).frame(height: 2).shadow(color: accent.opacity(0.6), radius: ArcShadow.sm, y: 1).padding(.horizontal, ArcSpacing.xs) }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Color.borderSubtle.opacity(0.5)).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { terminalManager.selectTerminal(terminal.id) }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Rename") { renameText = terminal.title; isRenaming = true }
            Menu("Change Icon") {
                ForEach(terminalIconOptions, id: \.symbol) { opt in
                    Button {
                        terminalManager.setTerminalIcon(terminal.id, icon: opt.symbol)
                    } label: {
                        if opt.symbol.isEmpty {
                            Label("Default", systemImage: terminal.mode.icon)
                        } else {
                            Label(opt.name, systemImage: opt.symbol)
                        }
                    }
                }
            }
            Divider()
            Button("Close", role: .destructive) { terminalManager.closeTerminal(terminal.id) }
        }
    }
}

// MARK: - Chat Terminal View

struct ChatTerminalView: View {
    let session: TerminalSession
    @ObservedObject var viewModel: PTYChatViewModel
    @Binding var attachedFiles: [AttachedFile]
    // viewModel.draftText lives on viewModel.draftText so it survives Settings toggle
    @State private var isDropping = false
    @EnvironmentObject var terminalManager: TerminalManager

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if viewModel.mode == .claude {
                                WelcomeCard { viewModel.send($0) }.padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.lg)
                            }
                            ForEach(viewModel.messages) { msg in
                                if msg.role == .user {
                                    UserRow(text: msg.text, files: msg.attachedFiles).id(msg.id).padding(.vertical, ArcSpacing.xs)
                                } else {
                                    let isLast = msg.id == viewModel.messages.last?.id
                                    if (viewModel.pendingPrompt != nil || viewModel.pendingPermission != nil) && isLast {
                                        EmptyView().id(msg.id)
                                    } else {
                                        ClaudeRow(text: msg.text).id(msg.id)
                                    }
                                }
                            }

                            if viewModel.trustedConfirmation && !viewModel.userHasSentMessage {
                                TrustedBanner().padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.sm)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            if let prompt = viewModel.pendingPrompt {
                                if case .trust(let folder) = prompt {
                                    TrustCard(folder: folder) { a in
                                        withAnimation(ArcAnimation.medium) { viewModel.trustFolder(a) }
                                    }
                                    .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.md)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }

                            if let ctx = viewModel.pendingPermission {
                                PermissionCard(context: ctx) { a in
                                    withAnimation(ArcAnimation.medium) { viewModel.respondPermission(yes: a) }
                                }
                                .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.md)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            if viewModel.isThinking && viewModel.pendingPermission == nil && viewModel.pendingPrompt == nil {
                                ThinkingIndicator().padding(.vertical, ArcSpacing.xs)
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(.vertical, ArcSpacing.md)
                    }
                    .clipped()
                    .onChange(of: viewModel.messages.count) { _, _ in scroll(proxy) }
                    .onChange(of: viewModel.messages.last?.text ?? "") { _, _ in scroll(proxy) }
                }

                Rectangle().fill(Color.borderSubtle).frame(height: 1)
                    .layoutPriority(1)

                InputBar(text: $viewModel.draftText,
                    attachedFiles: $attachedFiles,
                    isDropping: $isDropping,
                    onSend: {
                        let t = viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let hasFiles = !attachedFiles.isEmpty
                        guard !t.isEmpty || hasFiles else { return }

                        if let (targetMode, cleanedMsg) = TerminalManager.parseMention(t),
                           targetMode != session.mode {
                            let sentFiles = attachedFiles
                            terminalManager.routeToBot(mode: targetMode, message: cleanedMsg, files: sentFiles)
                            viewModel.draftText = ""
                            withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
                            return
                        }

                        var message = t
                        if hasFiles {
                            let paths = attachedFiles.map { $0.url.path }
                            let fileSection = paths.map { "  \($0)" }.joined(separator: "\n")
                            if message.isEmpty {
                                message = "Analyze these files:\n\(fileSection)"
                            } else {
                                message += "\n\nAttached files:\n\(fileSection)"
                            }
                        }

                        let sentFiles = attachedFiles
                        arcLog("[ArcBench] InputBar onSend → viewModel.send() mode=\(viewModel.mode.rawValue) session.mode=\(session.mode.rawValue)")
                        viewModel.send(message, files: sentFiles)
                        viewModel.draftText = ""
                        withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
                    },
                    onEnter: { viewModel.sendRaw("\r") },
                    onEscape: { viewModel.sendRaw("\u{1B}") },
                    onInterrupt: { viewModel.interrupt() }
                )
                .layoutPriority(1)
            }

        }
        .background(Color.bg)
        .onAppear { viewModel.terminalManager = terminalManager }
        .onReceive(NotificationCenter.default.publisher(for: .sendInterrupt)) { _ in viewModel.interrupt() }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    let onSend: (String) -> Void

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Burning the midnight oil"
        }
    }

    private var userName: String { NSFullUserName().components(separatedBy: " ").first ?? NSUserName() }

    private var subtitle: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Ready to build something great today."
        case 12..<17: return "Let's keep the momentum going."
        case 17..<22: return "What are we working on tonight?"
        default: return "Late night coding session? I'm here for it."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ArcSpacing.xl) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color.arcBlue.opacity(0.15), Color.arcBlue.opacity(0.03)], center: .center, startRadius: 0, endRadius: 32)).frame(width: 56, height: 56)
                    ClaudeLogo(size: 26)
                }
                VStack(spacing: ArcSpacing.sm) {
                    Text("\(greeting), \(userName)").font(.system(size: 19, weight: .bold)).foregroundColor(.textPrimary)
                    Text(subtitle).font(ArcFont.label).foregroundColor(.textSecondary)
                }
            }.padding(.top, 32).padding(.bottom, ArcSpacing.xxl)

            HStack(spacing: ArcSpacing.md) {
                WelcomeChip(icon: "folder", text: "Browse files", help: "List files in the current directory") { onSend("List the files and folders in the current directory") }
                WelcomeChip(icon: "hammer", text: "Fix a bug", help: "Find and fix bugs in your project") { onSend("Help me find and fix a bug in this project") }
                WelcomeChip(icon: "sparkles", text: "Build something", help: "Explore what to build or improve") { onSend("What can we build or improve in this project?") }
            }.padding(.bottom, ArcSpacing.xxl)

            Text("Type a message or use /help for commands").font(ArcFont.caption).foregroundColor(Color.textTertiary.opacity(0.6)).padding(.bottom, ArcSpacing.xl)
        }.frame(maxWidth: .infinity)
    }
}

struct WelcomeChip: View {
    let icon: String; let text: String; var help: String = ""; let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(ArcFont.small(.medium)).foregroundColor(isHovered ? .arcBlue : .arcBlue.opacity(0.7))
                Text(text).font(ArcFont.caption(.medium)).foregroundColor(isHovered ? .textPrimary : .textSecondary)
            }.padding(.horizontal, ArcSpacing.lg).padding(.vertical, 7)
            .background(Capsule().fill(isHovered ? Color.arcBlue.opacity(0.10) : Color.bgTertiary.opacity(0.5)).overlay(Capsule().stroke(isHovered ? Color.arcBlue.opacity(0.3) : Color.borderSubtle, lineWidth: 1)))
            .shadow(color: isHovered ? Color.arcBlue.opacity(0.15) : .clear, radius: ArcShadow.md).contentShape(Capsule())
        }.buttonStyle(.plain).onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovered = h } }
        .help(help.isEmpty ? text : help)
    }
}
