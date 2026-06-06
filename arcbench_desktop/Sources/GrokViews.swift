/// GrokViews — Standalone Grok chat interface.
/// GrokChatView, GrokUserBubble, ToolExecutionRow, GrokQuickChip.

import SwiftUI

// MARK: - Grok Chat View

struct GrokChatView: View {
    @Binding var attachedFiles: [AttachedFile]
    @ObservedObject var engine: GrokChatEngine
    @EnvironmentObject var computerControl: ComputerControlService
    @EnvironmentObject var terminalManager: TerminalManager
    // engine.draftText lives on engine.draftText so it survives Settings toggle
    @State private var showSettings = false
    @State private var showClearConfirm = false
    @State private var isDropping = false

    private var canSend: Bool {
        (!engine.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty) && !engine.xaiKey.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                GrokLogo(size: 18)
                Text("Grok").font(ArcFont.body(.bold)).foregroundColor(.accentGrok)
                Spacer()
                if !engine.messages.isEmpty {
                    Button { showClearConfirm = true } label: {
                        Image(systemName: "trash").font(ArcFont.caption).foregroundColor(.textTertiary)
                            .frame(width: 28, height: 28).background(Circle().fill(Color.bgTertiary))
                    }.buttonStyle(.plain).help("Clear chat")
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(ArcFont.caption).foregroundColor(.textTertiary)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.bgTertiary))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, ArcSpacing.md).background(Color.bgSecondary)

            // Messages
            if engine.messages.isEmpty {
                ScrollView {
                    grokWelcome
                }
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(engine.messages) { msg in
                            if msg.role == "user" {
                                GrokUserBubble(message: msg).id(msg.id)
                            } else if msg.role == "claude" {
                                // Claude execution result (left-aligned, purple accent — distinct from user blue)
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle().fill(Color.accentPurple.opacity(0.08)).frame(width: 30, height: 30)
                                            .shadow(color: .accentPurple.opacity(0.15), radius: ArcShadow.md)
                                        ClaudeLogo(size: 16)
                                    }.padding(.top, 2)

                                    VStack(alignment: .leading, spacing: ArcSpacing.xs) {
                                        Text("Claude").font(ArcFont.caption(.semibold)).foregroundColor(.accentPurple)

                                        if msg.content.isEmpty && engine.isExecuting {
                                            HStack(spacing: ArcSpacing.sm) {
                                                ProgressView().scaleEffect(0.6)
                                                Text("Executing...").font(.system(size: 12)).foregroundColor(.textTertiary)
                                            }
                                            .padding(.horizontal, 14).padding(.vertical, ArcSpacing.lg)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(Color.cardBg)
                                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.borderSubtle, lineWidth: 1))
                                            )
                                        } else {
                                            WordTypewriter(text: msg.content, color: .accentPurple)
                                        }
                                    }
                                    .frame(maxWidth: 620, alignment: .leading)
                                    Spacer(minLength: 20)
                                }
                                .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.sm)
                                .id(msg.id)
                            } else if msg.role == "tool" {
                                ToolExecutionRow(toolName: msg.toolName ?? "tool", content: msg.content)
                                    .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.xs)
                                    .id(msg.id)
                            } else if !msg.content.isEmpty || (engine.isStreaming && msg.id == engine.messages.last(where: { $0.role == "assistant" })?.id) {
                                // Grok response (left-aligned) — skip empty stale assistant messages
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle().fill(Color.accentGrok.opacity(0.08)).frame(width: 30, height: 30)
                                            .shadow(color: .accentGrok.opacity(0.15), radius: ArcShadow.md)
                                        GrokLogo(size: 16)
                                    }.padding(.top, 2)

                                    VStack(alignment: .leading, spacing: ArcSpacing.xs) {
                                        Text("Grok").font(ArcFont.caption(.semibold)).foregroundColor(.textTertiary)

                                        if msg.content.isEmpty && engine.isStreaming && msg.id == engine.messages.last(where: { $0.role == "assistant" })?.id {
                                            GrokStreamingBar()
                                                .padding(.horizontal, 14).padding(.vertical, ArcSpacing.lg)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .fill(Color.cardBg)
                                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.borderSubtle, lineWidth: 1))
                                                )
                                        } else if msg.content == "Stopped." {
                                            HStack(spacing: 5) {
                                                Image(systemName: "stop.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.textTertiary)
                                                Text("Stopped")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.textTertiary)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(
                                                Capsule().fill(Color.bgTertiary)
                                                    .overlay(Capsule().stroke(Color.borderSubtle, lineWidth: 1))
                                            )
                                        } else if !msg.content.isEmpty {
                                            WordTypewriter(text: msg.content, color: .accentGrok)
                                        }
                                    }
                                    .frame(maxWidth: 620, alignment: .leading)
                                    Spacer(minLength: 20)
                                }
                                .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.sm)
                                .id(msg.id)
                            }
                        }

                        Color.clear.frame(height: 1).id("grok-bottom")
                    }.padding(.vertical, ArcSpacing.md)
                }
                .clipped()
                .onChange(of: engine.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("grok-bottom", anchor: .bottom) }
                }
                .onChange(of: engine.messages.last?.content ?? "") { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("grok-bottom", anchor: .bottom) }
                }
            }
            }

            // Input bar
            VStack(spacing: 0) {
                if !attachedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: ArcSpacing.sm) {
                            ForEach(attachedFiles) { file in
                                AttachedFilePreview(file: file) {
                                    withAnimation(ArcAnimation.medium) {
                                        attachedFiles.removeAll { $0.id == file.id }
                                    }
                                }
                            }
                            if attachedFiles.count > 1 {
                                Button {
                                    withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
                                } label: {
                                    Text("Clear all")
                                        .font(ArcFont.small(.medium))
                                        .foregroundColor(.textTertiary)
                                        .padding(.horizontal, ArcSpacing.md).padding(.vertical, ArcSpacing.xs)
                                        .background(Capsule().fill(Color.bgTertiary))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, ArcSpacing.xs)
                    }

                    Rectangle().fill(Color.borderSubtle.opacity(0.5)).frame(height: 1)
                        .padding(.horizontal, 14)
                }

                HStack(alignment: .center, spacing: ArcSpacing.md) {
                    Button(action: { openFilePanel(attachedFiles: $attachedFiles) }) {
                        Image(systemName: "paperclip")
                            .font(ArcFont.label(.medium))
                            .foregroundColor(attachedFiles.isEmpty ? .textTertiary : .accentGrok)
                            .frame(width: 24, height: 24)
                            .background(attachedFiles.isEmpty ? Color.clear : Color.accentGrok.opacity(0.1))
                            .clipShape(Circle())
                    }.buttonStyle(.plain).help("Attach file")

                    TextField("Message or /command...", text: $engine.draftText, axis: .vertical)
                        .textFieldStyle(.plain).font(ArcFont.body).lineLimit(1...5)
                        .foregroundColor(.textPrimary)
                        .onSubmit { if canSend && !engine.isStreaming { sendMessage() } }

                    Button {
                        if engine.isStreaming { engine.stop() } else { sendMessage() }
                    } label: {
                        Image(systemName: engine.isStreaming ? "square.fill" : "arrow.up")
                            .font(.system(size: engine.isStreaming ? 10 : 13, weight: .bold))
                            .foregroundColor(engine.isStreaming ? .accentRed : canSend ? .white : .textTertiary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(engine.isStreaming ? Color.accentRed.opacity(0.2) : canSend ? Color.accentGrok : Color.bgTertiary)
                                    .shadow(color: canSend ? Color.accentGrok.opacity(0.4) : .clear, radius: ArcShadow.md)
                            )
                    }
                    .buttonStyle(.plain).disabled(!engine.isStreaming && !canSend)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: ArcRadius.bubble, style: .continuous)
                    .fill(Color.cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: ArcRadius.bubble, style: .continuous)
                            .stroke(Color.borderSubtle, lineWidth: 1)
                    )
            )
            .padding(.horizontal, ArcSpacing.lg).padding(.vertical, ArcSpacing.md).background(Color.bg)
            .mentionAutocomplete(text: $engine.draftText)
        }
        .background(Color.bg)
        .sheet(isPresented: $showSettings) {
            VStack(alignment: .leading, spacing: ArcSpacing.xxl) {
                SheetHeader(title: "Grok Settings") { showSettings = false }
                VStack(alignment: .leading, spacing: ArcSpacing.sm) {
                    Text("xAI API Key").font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                    HStack(spacing: ArcSpacing.md) {
                        SecureField("xai-...", text: Binding(get: { engine.xaiKey }, set: { engine.xaiKey = $0 }))
                            .textFieldStyle(.plain).font(ArcFont.monoLabel).foregroundColor(.textPrimary)
                            .padding(10).background(RoundedRectangle(cornerRadius: ArcRadius.md).fill(Color.bgTertiary).overlay(RoundedRectangle(cornerRadius: ArcRadius.md).stroke(Color.borderSubtle, lineWidth: 1)))
                        if !engine.xaiKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.accentGreen).font(.system(size: 16))
                        }
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    Button { showSettings = false } label: {
                        Text("Done").font(ArcFont.label(.semibold)).foregroundColor(.white)
                            .padding(.horizontal, ArcSpacing.xxl).padding(.vertical, ArcSpacing.md)
                            .background(RoundedRectangle(cornerRadius: ArcRadius.md).fill(Color.arcBlue))
                    }.buttonStyle(.plain)
                }
            }.padding(24).frame(width: 400, height: 220).background(Color.bg)
        }
        .alert("Clear Chat", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { engine.clear() }
        } message: {
            Text("Are you sure you want to clear this conversation? This cannot be undone.")
        }
        .onAppear { engine.computerControl = computerControl }
        .onReceive(NotificationCenter.default.publisher(for: .grokRouteMessage)) { note in
            guard let msg = note.userInfo?["message"] as? String, !msg.isEmpty else { return }
            engine.send(msg, apiText: msg)
        }
    }

    private var grokWelcome: some View {
        VStack(spacing: ArcSpacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.accentOrange.opacity(0.2), Color.accentOrange.opacity(0.03)], center: .center, startRadius: 0, endRadius: 32))
                    .frame(width: 56, height: 56)
                GrokLogo(size: 28)
            }
            Text("Chat with Grok").font(ArcFont.title).foregroundColor(.textPrimary)
            Text("Grok can control your Mac — open apps, browse the web, run commands, and more.")
                .font(.system(size: 12)).foregroundColor(.textSecondary).multilineTextAlignment(.center)

            HStack(spacing: ArcSpacing.md) {
                GrokQuickChip(text: "Open Google") { engine.draftText = "Open Google in my browser" }
                GrokQuickChip(text: "Take a screenshot") { engine.draftText = "Take a screenshot of my screen" }
                GrokQuickChip(text: "What apps are running?") { engine.draftText = "List all running apps on my Mac" }
            }.padding(.top, ArcSpacing.xs)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendMessage() {
        let userText = engine.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty || !attachedFiles.isEmpty else { return }

        // Check for @mention routing
        if let (targetMode, cleanedMsg) = TerminalManager.parseMention(userText), targetMode != .grok {
            let sentFiles = attachedFiles
            terminalManager.routeToBot(mode: targetMode, message: cleanedMsg, files: sentFiles)
            engine.draftText = ""
            withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
            return
        }

        let sentFiles = attachedFiles
        var apiText = userText

        if !attachedFiles.isEmpty {
            var fileBlocks: [String] = []
            for file in attachedFiles {
                let name = file.url.lastPathComponent
                let path = file.url.path  // filesystem path, NOT file:// URL
                if file.url.hasDirectoryPath {
                    let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                    let listing = items.prefix(50).joined(separator: "\n  ")
                    fileBlocks.append("📁 \(name)/ (path: \(path))\n  \(listing)" + (items.count > 50 ? "\n  ... and \(items.count - 50) more" : ""))
                } else if let contents = try? String(contentsOf: file.url, encoding: .utf8) {
                    let trimmed = contents.count > 30_000 ? String(contents.prefix(30_000)) + "\n... (truncated)" : contents
                    fileBlocks.append("📄 \(name) (path: \(path))\n```\n\(trimmed)\n```")
                } else {
                    fileBlocks.append("📎 \(name) (path: \(path)) (\(file.fileSize)) — binary file")
                }
            }
            let fileSection = fileBlocks.joined(separator: "\n\n")
            let fileNames = attachedFiles.map { $0.url.lastPathComponent }.joined(separator: ", ")
            apiText = userText.isEmpty
                ? "Review these files: \(fileNames)\n\nIMPORTANT: Use the filesystem paths below (NOT file:// URLs) when calling tools.\n\n\(fileSection)"
                : "\(userText)\n\n---\nAttached files (use these filesystem paths with tools, NOT file:// URLs):\n\n\(fileSection)"
            withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
        }

        guard !apiText.isEmpty else { return }
        let display = userText.isEmpty && !sentFiles.isEmpty
            ? "Review these files"
            : userText
        engine.send(display, apiText: apiText, files: sentFiles)
        engine.draftText = ""
    }

}

// MARK: - Tool Execution Row (animated pill for tool calls)

struct ToolExecutionRow: View {
    let toolName: String
    let content: String
    @State private var appeared = false

    private var icon: String {
        switch toolName {
        case "open_app": return "app.badge"
        case "quit_app": return "xmark.app"
        case "open_url", "google_search": return "globe"
        case "run_shell": return "terminal"
        case "take_screenshot": return "camera.viewfinder"
        case "run_applescript": return "applescript"
        case "open_file": return "doc"
        case "send_to_claude": return "circle.hexagongrid.fill"
        case "get_clipboard", "set_clipboard": return "doc.on.clipboard"
        case "list_running_apps": return "macwindow.on.rectangle"
        case "read_file": return "doc.text"
        case "list_files": return "folder"
        case "stop": return "stop.circle.fill"
        default: return "gear"
        }
    }

    private var color: Color {
        switch toolName {
        case "open_app", "quit_app": return .arcBlue
        case "open_url", "google_search": return .accentGreen
        case "run_shell": return .accentGreen
        case "send_to_claude": return .arcBlue
        case "take_screenshot": return .accentPurple
        case "stop": return .textTertiary
        case "read_file", "list_files": return .accentPurple
        default: return .accentOrange
        }
    }

    private var isExecuting: Bool { content.hasSuffix("…") }

    var body: some View {
        HStack(spacing: ArcSpacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 24, height: 24)
                if isExecuting {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(color.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(appeared ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: appeared)
                }
                Image(systemName: icon)
                    .font(ArcFont.small(.semibold))
                    .foregroundColor(color)
            }

            Text(content)
                .font(ArcFont.monoCaption)
                .foregroundColor(.textSecondary)
                .lineLimit(2)

            if !isExecuting {
                Image(systemName: "checkmark")
                    .font(ArcFont.xs(.bold))
                    .foregroundColor(.accentGreen)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, ArcSpacing.lg)
        .padding(.vertical, ArcSpacing.sm)
        .background(
            Capsule()
                .fill(color.opacity(0.06))
                .overlay(Capsule().stroke(color.opacity(0.12), lineWidth: 0.5))
        )
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

// MARK: - Grok User Bubble (with file chips)

struct GrokUserBubble: View {
    let message: GrokChatMessage

    var body: some View {
        VStack(alignment: .trailing, spacing: ArcSpacing.xs) {
            if !message.attachedFiles.isEmpty {
                HStack {
                    Spacer(minLength: 60)
                    FlowLayout(spacing: ArcSpacing.xs) {
                        ForEach(message.attachedFiles) { file in
                            MessageFileChip(file: file)
                        }
                    }
                }
                .padding(.horizontal, ArcSpacing.xl)
            }

            if !message.content.isEmpty {
                HStack {
                    Spacer(minLength: 60)
                    Group {
                        if textHasMention(message.content) {
                            highlightedMentionText(message.content, baseFont: ArcFont.body, baseColor: .white)
                                .lineSpacing(3)
                        } else {
                            Text(message.content).font(ArcFont.body).foregroundColor(.white)
                                .textSelection(.enabled).lineSpacing(3)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: ArcRadius.bubble, style: .continuous)
                            .fill(ArcGradient.userBubble)
                    )
                    .shadow(color: Color.arcBlue.opacity(0.25), radius: ArcShadow.md, y: 2)
                }
                .padding(.horizontal, ArcSpacing.xl)
            }
        }
        .padding(.vertical, ArcSpacing.xs)
    }
}

// MARK: - Grok Streaming Bar (replaces 3 dots)

struct GrokStreamingBar: View {
    @State private var animate = false

    private let barHeights: [CGFloat] = [10, 16, 8, 14, 12]
    private let durations: [Double] = [0.5, 0.4, 0.6, 0.35, 0.55]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentGrok.opacity(animate ? 0.7 : 0.2))
                    .frame(width: 3.5, height: animate ? barHeights[i] : 3.5)
                    .animation(
                        .easeInOut(duration: durations[i])
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                        value: animate
                    )
            }
        }
        .frame(width: 34, height: 20, alignment: .center)
        .onAppear { animate = true }
    }
}

// MARK: - Grok Quick Chip

struct GrokQuickChip: View {
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(ArcFont.caption(.medium))
                .foregroundColor(isHovered ? .accentOrange : .textSecondary)
                .padding(.horizontal, ArcSpacing.lg).padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isHovered ? Color.accentOrange.opacity(0.10) : Color.bgTertiary.opacity(0.5))
                        .overlay(Capsule().stroke(isHovered ? Color.accentOrange.opacity(0.3) : Color.borderSubtle, lineWidth: 1))
                )
                .shadow(color: isHovered ? Color.accentOrange.opacity(0.15) : .clear, radius: ArcShadow.md)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovered = h } }
    }
}
