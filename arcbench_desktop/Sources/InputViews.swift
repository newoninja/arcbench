/// InputViews — Input bar, file attachment previews, and @mention autocomplete.
/// Shared input components used across Claude, Shell, Grok, and Swarm modes.

import SwiftUI

// MARK: - Input Bar (glass + file attachments)

struct InputBar: View {
    @Binding var text: String
    @Binding var attachedFiles: [AttachedFile]
    @Binding var isDropping: Bool
    let onSend: () -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void
    let onInterrupt: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Attached files preview row
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ArcSpacing.md) {
                        ForEach(attachedFiles) { file in
                            AttachedFilePreview(file: file) {
                                withAnimation(ArcAnimation.quick) {
                                    attachedFiles.removeAll { $0.id == file.id }
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.6).combined(with: .opacity)
                            ))
                        }

                        // Clear all button
                        if attachedFiles.count > 1 {
                            Button {
                                withAnimation(ArcAnimation.medium) { attachedFiles.removeAll() }
                            } label: {
                                HStack(spacing: ArcSpacing.xs) {
                                    Image(systemName: "xmark").font(ArcFont.xs(.bold))
                                    Text("Clear all").font(ArcFont.small(.medium))
                                }
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, ArcSpacing.md)
                                .padding(.vertical, ArcSpacing.xs)
                                .background(Capsule().fill(Color.bgTertiary).overlay(Capsule().stroke(Color.borderSubtle, lineWidth: 1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, ArcSpacing.md)
                }
                .frame(height: 72)

                Rectangle().fill(Color.borderSubtle.opacity(0.5)).frame(height: 1).padding(.horizontal, 14)
            }

            // Main input row
            HStack(alignment: .center, spacing: ArcSpacing.md) {
                Button(action: { openFilePanel(attachedFiles: $attachedFiles) }) {
                    Image(systemName: "paperclip")
                        .font(ArcFont.label(.medium))
                        .foregroundColor(attachedFiles.isEmpty ? .textTertiary : .arcBlue)
                        .frame(width: 24, height: 24)
                        .background(attachedFiles.isEmpty ? Color.clear : Color.arcBlue.opacity(0.1))
                        .clipShape(Circle())
                }.buttonStyle(.plain).help("Attach file (\(attachedFiles.count) attached)")

                if text.hasPrefix("/") { Image(systemName: "command").font(.system(size: 12)).foregroundColor(.arcBlue) }

                TextField("Message or /command...", text: $text)
                    .textFieldStyle(.plain)
                    .font(ArcFont.body)
                    .foregroundColor(.textPrimary)
                    .focused($isFocused)
                    .onSubmit { let t = text.trimmingCharacters(in: .whitespacesAndNewlines); if t.isEmpty && attachedFiles.isEmpty { onEnter() } else { onSend() } }

                Button(action: onEscape) {
                    Text("esc").font(ArcFont.monoSmall(.medium)).foregroundColor(.textTertiary)
                        .padding(.horizontal, ArcSpacing.sm).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: ArcRadius.sm).fill(Color.bgTertiary))
                }.buttonStyle(.plain).help("Send Escape character to terminal")

                Button(action: onInterrupt) {
                    Image(systemName: "stop.fill").font(ArcFont.small).foregroundColor(.accentRed.opacity(0.7))
                        .frame(width: 24, height: 24).background(Circle().fill(Color.accentRed.opacity(0.1)))
                }.buttonStyle(.plain).help("Interrupt (Ctrl+C)")

                Button(action: { let t = text.trimmingCharacters(in: .whitespacesAndNewlines); if t.isEmpty && attachedFiles.isEmpty { onEnter() } else { onSend() } }) {
                    Image(systemName: "arrow.up").font(ArcFont.label(.bold))
                        .foregroundColor(hasContent ? .white : .arcBlue.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(hasContent ? Color.arcBlue : Color.arcBlue.opacity(0.12)).shadow(color: hasContent ? Color.arcBlue.opacity(0.4) : .clear, radius: ArcShadow.md))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: ArcRadius.bar, style: .continuous)
                .fill(Color.bgTertiary.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: ArcRadius.bar, style: .continuous)
                        .stroke(isDropping ? Color.arcBlue.opacity(0.6) : isFocused ? Color.arcBlue.opacity(0.4) : Color.borderMedium, lineWidth: isDropping ? 2 : 1)
                )
        )
        .shadow(color: isDropping ? Color.arcBlue.opacity(0.25) : isFocused ? Color.arcBlue.opacity(0.1) : .clear, radius: isDropping ? ArcShadow.xl : ArcShadow.lg)
        .padding(.horizontal, ArcSpacing.xl).padding(.vertical, 10).background(Color.bg)
        .mentionAutocomplete(text: $text)
        .slashCommandAutocomplete(text: $text)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFocused = true } }
    }

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty
    }
}

// MARK: - @Mention Autocomplete Popup

struct MentionOption: Identifiable {
    let id = UUID()
    let tag: String       // "grok", "claude", "swarm", "shell"
    let label: String
    let icon: String
    let color: Color
    let description: String
}

struct MentionPopup: View {
    @Binding var text: String
    @Binding var isVisible: Bool
    @State private var selectedIndex = 0

    static let allOptions: [MentionOption] = [
        MentionOption(tag: "grok", label: "Grok", icon: "bolt.fill", color: .accentGrok,
                      description: "AI assistant with computer control"),
        MentionOption(tag: "claude", label: "Claude", icon: "circle.hexagongrid.fill", color: .arcBlue,
                      description: "Claude Code — coding agent"),
        MentionOption(tag: "swarm", label: "Swarm", icon: "bolt.trianglebadge.exclamationmark", color: .accentOrange,
                      description: "Grok + Claude multi-agent loop"),
        MentionOption(tag: "shell", label: "Shell", icon: "terminal", color: .accentGreen,
                      description: "Direct terminal access"),
    ]

    private var filteredOptions: [MentionOption] {
        let query = extractMentionQuery(from: text).lowercased()
        if query.isEmpty { return Self.allOptions }
        return Self.allOptions.filter { $0.tag.hasPrefix(query) || $0.label.lowercased().hasPrefix(query) }
    }

    private func extractMentionQuery(from text: String) -> String {
        guard let atIndex = text.lastIndex(of: "@") else { return "" }
        let after = String(text[text.index(after: atIndex)...])
        if after.contains(" ") || after.contains("\n") { return "" }
        return after
    }

    var body: some View {
        if isVisible && !filteredOptions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(filteredOptions.enumerated()), id: \.element.id) { index, option in
                    Button {
                        completeMention(option)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(option.color)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(option.color.opacity(0.12))
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(option.tag)")
                                    .font(ArcFont.label(.semibold))
                                    .foregroundColor(.textPrimary)
                                Text(option.description)
                                    .font(ArcFont.small)
                                    .foregroundColor(.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: ArcRadius.md, style: .continuous)
                                .fill(index == selectedIndex ? Color.bgHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < filteredOptions.count - 1 {
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, ArcSpacing.md)
                    }
                }
            }
            .padding(ArcSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous)
                    .stroke(Color.borderMedium, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: -4)
            .frame(width: 290)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95, anchor: .bottom)),
                removal: .opacity
            ))
            .onChange(of: text) { _, _ in
                selectedIndex = 0
            }
            .onKeyPress(.upArrow) {
                if !filteredOptions.isEmpty {
                    selectedIndex = (selectedIndex - 1 + filteredOptions.count) % filteredOptions.count
                }
                return .handled
            }
            .onKeyPress(.downArrow) {
                if !filteredOptions.isEmpty {
                    selectedIndex = (selectedIndex + 1) % filteredOptions.count
                }
                return .handled
            }
            .onKeyPress(.tab) {
                if !filteredOptions.isEmpty {
                    completeMention(filteredOptions[selectedIndex])
                }
                return .handled
            }
            .onKeyPress(.return) {
                if !filteredOptions.isEmpty {
                    completeMention(filteredOptions[selectedIndex])
                    return .handled
                }
                return .ignored
            }
        }
    }

    private func completeMention(_ option: MentionOption) {
        if let atIndex = text.lastIndex(of: "@") {
            text = String(text[..<atIndex]) + "@\(option.tag) "
        } else {
            text = "@\(option.tag) "
        }
        withAnimation(.easeOut(duration: 0.15)) { isVisible = false }
    }
}

/// View modifier that watches a text binding and shows/hides the mention popup.
struct MentionPopupModifier: ViewModifier {
    @Binding var text: String
    @State private var showMention = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            // Popup floats above input in a natural stack
            if showMention {
                HStack {
                    MentionPopup(text: $text, isVisible: $showMention)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            content
        }
        .onChange(of: text) { _, newVal in
            let shouldShow = shouldShowMentionPopup(newVal)
            if shouldShow != showMention {
                withAnimation(ArcAnimation.quick) {
                    showMention = shouldShow
                }
            }
        }
    }

    private func shouldShowMentionPopup(_ text: String) -> Bool {
        guard let atIndex = text.lastIndex(of: "@") else { return false }
        let after = String(text[text.index(after: atIndex)...])
        if after.contains(" ") || after.contains("\n") { return false }
        if atIndex != text.startIndex {
            let before = text[text.index(before: atIndex)]
            if !before.isWhitespace && before != "\n" { return false }
        }
        return after.count < 10
    }
}

extension View {
    func mentionAutocomplete(text: Binding<String>) -> some View {
        modifier(MentionPopupModifier(text: text))
    }
}

// MARK: - Slash Command Autocomplete

struct SlashCommand: Identifiable {
    let id = UUID()
    let command: String      // e.g. "help"
    let label: String        // e.g. "/help"
    let icon: String
    let color: Color
    let description: String
    let category: String     // "Popular", "Tools", "Config"
}

struct SlashCommandPopup: View {
    @Binding var text: String
    @Binding var isVisible: Bool
    @State private var selectedIndex = 0

    static let allCommands: [SlashCommand] = [
        // Popular
        SlashCommand(command: "help", label: "/help", icon: "questionmark.circle", color: .arcBlue, description: "Show available commands", category: "Popular"),
        SlashCommand(command: "clear", label: "/clear", icon: "trash", color: .accentRed, description: "Clear conversation history", category: "Popular"),
        SlashCommand(command: "status", label: "/status", icon: "info.circle", color: .accentGreen, description: "Show session status & usage", category: "Popular"),
        SlashCommand(command: "compact", label: "/compact", icon: "arrow.down.right.and.arrow.up.left", color: .accentOrange, description: "Compact conversation context", category: "Popular"),
        SlashCommand(command: "model", label: "/model", icon: "cpu", color: .accentPurple, description: "Show or change the AI model", category: "Popular"),

        // Tools
        SlashCommand(command: "terminal-setup", label: "/terminal-setup", icon: "terminal", color: .accentGreen, description: "Configure terminal integration", category: "Tools"),
        SlashCommand(command: "init", label: "/init", icon: "doc.badge.plus", color: .arcBlue, description: "Initialize CLAUDE.md for project", category: "Tools"),
        SlashCommand(command: "review", label: "/review", icon: "eye", color: .accentOrange, description: "Review code changes", category: "Tools"),
        SlashCommand(command: "pr-comments", label: "/pr-comments", icon: "text.bubble", color: .accentGrok, description: "Address PR review comments", category: "Tools"),

        // Config
        SlashCommand(command: "effort", label: "/effort", icon: "gauge.with.dots.needle.67percent", color: .accentPurple, description: "Set reasoning effort level", category: "Config"),
        SlashCommand(command: "memory", label: "/memory", icon: "brain", color: .arcBlue, description: "Manage project memory", category: "Config"),
        SlashCommand(command: "permissions", label: "/permissions", icon: "lock.shield", color: .accentOrange, description: "View allowed/denied tools", category: "Config"),
        SlashCommand(command: "cost", label: "/cost", icon: "dollarsign.circle", color: .accentGreen, description: "Show session cost breakdown", category: "Config"),
        SlashCommand(command: "doctor", label: "/doctor", icon: "stethoscope", color: .accentRed, description: "Check installation health", category: "Config"),
        SlashCommand(command: "logout", label: "/logout", icon: "rectangle.portrait.and.arrow.right", color: .textTertiary, description: "Sign out of current session", category: "Config"),
    ]

    private var query: String {
        guard text.hasPrefix("/") else { return "" }
        let q = String(text.dropFirst()).lowercased()
        return q.contains(" ") ? "" : q  // stop filtering after a space
    }

    private var filteredCommands: [SlashCommand] {
        if query.isEmpty { return Self.allCommands }
        return Self.allCommands.filter {
            $0.command.hasPrefix(query) || $0.label.hasPrefix("/\(query)")
        }
    }

    private var groupedCommands: [(String, [SlashCommand])] {
        let cmds = filteredCommands
        var groups: [(String, [SlashCommand])] = []
        var seen = Set<String>()
        for cmd in cmds {
            if !seen.contains(cmd.category) {
                seen.insert(cmd.category)
                groups.append((cmd.category, cmds.filter { $0.category == cmd.category }))
            }
        }
        return groups
    }

    var body: some View {
        if isVisible && !filteredCommands.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groupedCommands.enumerated()), id: \.offset) { gi, group in
                            if gi > 0 {
                                Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 4)
                            }
                            Text(group.0.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

                            ForEach(group.1) { cmd in
                                let idx = flatIndex(for: cmd)
                                Button { completeCommand(cmd) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: cmd.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(cmd.color)
                                            .frame(width: 24, height: 24)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(cmd.color.opacity(0.12))
                                            )

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(cmd.label)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.textPrimary)
                                            Text(cmd.description)
                                                .font(.system(size: 10.5))
                                                .foregroundColor(.textTertiary)
                                                .lineLimit(1)
                                        }
                                        Spacer()

                                        if idx == selectedIndex {
                                            Text("enter")
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(.textTertiary)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.bgTertiary))
                                        }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: ArcRadius.md, style: .continuous)
                                            .fill(idx == selectedIndex ? Color.bgHover : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(cmd.command)
                            }
                        }
                    }.padding(ArcSpacing.xs)
                }
                .frame(maxHeight: 320)
                .onChange(of: selectedIndex) { _, _ in
                    if selectedIndex < filteredCommands.count {
                        proxy.scrollTo(filteredCommands[selectedIndex].command, anchor: .center)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous)
                    .stroke(Color.borderMedium, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: -4)
            .frame(width: 320)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95, anchor: .bottom)),
                removal: .opacity
            ))
            .onChange(of: text) { _, _ in
                selectedIndex = 0
            }
            .onKeyPress(.upArrow) {
                if !filteredCommands.isEmpty {
                    selectedIndex = (selectedIndex - 1 + filteredCommands.count) % filteredCommands.count
                }
                return .handled
            }
            .onKeyPress(.downArrow) {
                if !filteredCommands.isEmpty {
                    selectedIndex = (selectedIndex + 1) % filteredCommands.count
                }
                return .handled
            }
            .onKeyPress(.tab) {
                if !filteredCommands.isEmpty {
                    completeCommand(filteredCommands[selectedIndex])
                }
                return .handled
            }
            .onKeyPress(.return) {
                if !filteredCommands.isEmpty {
                    completeCommand(filteredCommands[selectedIndex])
                    return .handled
                }
                return .ignored
            }
        }
    }

    private func flatIndex(for cmd: SlashCommand) -> Int {
        filteredCommands.firstIndex(where: { $0.command == cmd.command }) ?? 0
    }

    private func completeCommand(_ cmd: SlashCommand) {
        text = "/\(cmd.command) "
        withAnimation(.easeOut(duration: 0.15)) { isVisible = false }
    }
}

/// View modifier that watches text and shows/hides slash command popup
struct SlashCommandModifier: ViewModifier {
    @Binding var text: String
    @State private var showSlash = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if showSlash {
                HStack {
                    SlashCommandPopup(text: $text, isVisible: $showSlash)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            content
        }
        .onChange(of: text) { _, newVal in
            let shouldShow = shouldShowSlashPopup(newVal)
            if shouldShow != showSlash {
                withAnimation(ArcAnimation.quick) { showSlash = shouldShow }
            }
        }
    }

    private func shouldShowSlashPopup(_ text: String) -> Bool {
        guard text.hasPrefix("/") else { return false }
        let after = String(text.dropFirst())
        // Hide once user has typed a space (command is complete)
        if after.contains(" ") || after.contains("\n") { return false }
        return after.count < 20
    }
}

extension View {
    func slashCommandAutocomplete(text: Binding<String>) -> some View {
        modifier(SlashCommandModifier(text: text))
    }
}

// MARK: - Attached File Preview

struct AttachedFilePreview: View {
    let file: AttachedFile
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: ArcSpacing.md) {
            // Thumbnail or icon
            if let thumb = file.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: ArcRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArcRadius.sm)
                            .stroke(Color.borderSubtle, lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: ArcRadius.sm)
                        .fill(file.iconColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: file.fileIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(file.iconColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(ArcFont.caption(.medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.fileSize.isEmpty {
                    Text(file.fileSize)
                        .font(.system(size: 9.5))
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: 100, alignment: .leading)
        }
        .padding(ArcSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.bgHover : Color.bgTertiary.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isHovered ? Color.arcBlue.opacity(0.3) : Color.borderSubtle, lineWidth: 1)
                )
        )
        .shadow(color: isHovered ? Color.arcBlue.opacity(0.1) : .clear, radius: ArcShadow.sm)
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.textTertiary)
                    .background(Circle().fill(Color.bg).frame(width: 12, height: 12))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .opacity(isHovered ? 1 : 0.6)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovered = h } }
    }
}

// MARK: - Attached Files Strip (shared across all terminal types)

struct AttachedFilesStrip: View {
    @Binding var files: [AttachedFile]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ArcSpacing.sm) {
                ForEach(files) { file in
                    AttachedFilePreview(file: file) {
                        withAnimation(ArcAnimation.medium) {
                            files.removeAll { $0.id == file.id }
                        }
                    }
                }
                if files.count > 1 {
                    Button {
                        withAnimation(ArcAnimation.medium) { files.removeAll() }
                    } label: {
                        Text("Clear all")
                            .font(ArcFont.small(.medium))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, ArcSpacing.md).padding(.vertical, ArcSpacing.xs)
                            .background(Capsule().fill(Color.bgTertiary))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, ArcSpacing.lg).padding(.vertical, ArcSpacing.sm)
        }
    }
}
