/// MessageViews — Shared message display components.
/// UserRow, MessageFileChip, FlowLayout, ClaudeRow, and ClaudeSegment.

import SwiftUI

// ClaudeSegment is defined in PTYChatViewModel.swift

// MARK: - @Mention Highlighting

/// Cached regex for @mention matching — avoids recompilation on every call
private let mentionRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"@(grok|claude|swarm|shell)\b"#, options: .caseInsensitive)

/// Returns true if text contains an @mention (grok/claude/swarm/shell)
func textHasMention(_ text: String) -> Bool {
    guard let regex = mentionRegex else { return false }
    let nsText = text as NSString
    return regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) != nil
}

/// Renders text with @mentions highlighted as colored inline badges.
/// WARNING: The returned composite Text (built with +) is NOT safe with .textSelection(.enabled) on macOS.
/// Callers should avoid .textSelection on the result.
func highlightedMentionText(_ text: String, baseFont: Font = ArcFont.body, baseColor: Color = .white) -> Text {
    let mentionColors: [String: Color] = [
        "grok": .accentGrok, "claude": .arcBlue,
        "swarm": .accentOrange, "shell": .accentGreen,
    ]
    guard let regex = mentionRegex else {
        return Text(text).font(baseFont).foregroundColor(baseColor)
    }
    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    if matches.isEmpty {
        return Text(text).font(baseFont).foregroundColor(baseColor)
    }

    var result = Text("")
    var lastEnd = 0
    for match in matches {
        if match.range.location > lastEnd {
            let before = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            result = result + Text(before).font(baseFont).foregroundColor(baseColor)
        }
        let mention = nsText.substring(with: match.range)
        let tag = nsText.substring(with: match.range(at: 1)).lowercased()
        let color = mentionColors[tag] ?? .arcBlue
        result = result + Text(mention)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(color)
            .underline(true, color: color.opacity(0.5))
        lastEnd = match.range.location + match.range.length
    }
    if lastEnd < nsText.length {
        let remaining = nsText.substring(from: lastEnd)
        result = result + Text(remaining).font(baseFont).foregroundColor(baseColor)
    }
    return result
}

// MARK: - User Row (cyan bubble with glow)

struct UserRow: View {
    let text: String
    var files: [AttachedFile] = []
    @State private var isExpanded = false

    private var displayText: String {
        if let range = text.range(of: "\n\nAttached files:\n", options: .literal) {
            return String(text[text.startIndex..<range.lowerBound])
        }
        if text.hasPrefix("Analyze these files:\n") { return "" }
        return text
    }

    private var lineCount: Int { displayText.components(separatedBy: "\n").count }
    private var isLong: Bool { lineCount > 12 }

    var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text("You").font(ArcFont.caption(.semibold)).foregroundColor(.textTertiary)

                if !files.isEmpty {
                    FlowLayout(spacing: ArcSpacing.sm) {
                        ForEach(files) { file in
                            MessageFileChip(file: file)
                        }
                    }
                }

                if !displayText.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        if textHasMention(displayText) {
                            highlightedMentionText(displayText,
                                baseFont: isLong ? .system(size: 12, design: .monospaced) : ArcFont.body,
                                baseColor: .white)
                                .lineSpacing(3)
                                .lineLimit(isExpanded ? nil : (isLong ? 6 : nil))
                                .truncationMode(.tail)
                        } else {
                            Text(displayText)
                                .font(isLong ? .system(size: 12, design: .monospaced) : ArcFont.body)
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                                .lineLimit(isExpanded ? nil : (isLong ? 6 : nil))
                                .truncationMode(.tail)
                        }

                        if isLong {
                            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1).padding(.top, 8)
                            HStack(spacing: 6) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("\(lineCount) lines")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                            }.padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, ArcSpacing.xl).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: ArcRadius.bubble, style: .continuous)
                            .fill(ArcGradient.userBubble)
                    )
                    .shadow(color: Color.arcBlue.opacity(0.25), radius: ArcShadow.md, y: 2)
                    .onTapGesture { if isLong { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } } }
                }
            }
        }.padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.xs)
    }
}

// MARK: - Message File Chip (compact, no remove button)

struct MessageFileChip: View {
    let file: AttachedFile
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: ArcSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(file.iconColor.opacity(0.25))
                    .frame(width: 28, height: 28)
                Image(systemName: file.fileIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(file.iconColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !file.fileSize.isEmpty {
                    Text(file.fileSize)
                        .font(.system(size: 8.5))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, ArcSpacing.sm).padding(.vertical, ArcSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: ArcRadius.md, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.1))
        )
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHovered = h } }
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        .help(file.url.path)
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Claude Row (parsed segments + markdown)

struct ClaudeRow: View {
    let text: String
    @State private var showThinking = false
    @State private var cachedSegments: [ClaudeSegment] = []
    @State private var cachedText: String = ""

    private var thinkingSegments: [ClaudeSegment] {
        cachedSegments.filter { if case .toolUse = $0 { return true }; if case .treeDetail = $0 { return true }; return false }
    }
    private var responseSegments: [ClaudeSegment] {
        cachedSegments.filter { if case .text = $0 { return true }; return false }
    }

    var body: some View {
        Group {
            if cachedSegments.isEmpty && cachedText.isEmpty {
                EmptyView()
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(ArcColor.avatarBg).frame(width: 30, height: 30)
                            .shadow(color: .arcBlue.opacity(0.12), radius: ArcShadow.sm)
                        ClaudeLogo(size: 16)
                    }.padding(.top, 2)

                    VStack(alignment: .leading, spacing: ArcSpacing.sm) {
                        Text("Claude").font(ArcFont.caption(.semibold)).foregroundColor(.textTertiary)
                        if !thinkingSegments.isEmpty {
                            ThinkingBubble(segments: thinkingSegments, isExpanded: $showThinking)
                        }
                        ForEach(responseSegments) { seg in
                            if case .text(let c) = seg { TypewriterText(fullText: c) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.xs)
            }
        }
        .onAppear { reparse() }
        .onChange(of: text) { _, _ in reparse() }
    }

    private func reparse() {
        cachedSegments = Self.parseSegments(text)
        cachedText = Self.cleanOutput(text)
    }

    // MARK: - Segment Parsing

    static func parseSegments(_ raw: String) -> [ClaudeSegment] {
        let cleaned = cleanOutput(raw)
        guard !cleaned.isEmpty else { return [] }
        let lines = cleaned.components(separatedBy: "\n")
        var segs: [ClaudeSegment] = []
        var textBuf: [String] = []
        var treeBuf: [String] = []

        func flushText() {
            let j = textBuf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !j.isEmpty { segs.append(.text(j)) }
            textBuf.removeAll()
        }
        func flushTree() {
            if !treeBuf.isEmpty { segs.append(.treeDetail(treeBuf.joined(separator: "\n"))); treeBuf.removeAll() }
        }

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let m = t.range(of: #"^Reading \d+ files?"#, options: .regularExpression) {
                flushText(); flushTree(); segs.append(.toolUse(icon: "doc.text", name: "Read", detail: String(t[m]))); continue
            }
            if t.hasPrefix("$") || t.hasPrefix("bash") || t.hasPrefix("Bash") {
                flushText(); flushTree(); segs.append(.toolUse(icon: "terminal", name: "Bash", detail: t)); continue
            }
            if t.hasPrefix("Writing to") || t.hasPrefix("Editing") || t.hasPrefix("Edit") || t.hasPrefix("Write") {
                flushText(); flushTree(); segs.append(.toolUse(icon: "pencil.line", name: "Edit", detail: t)); continue
            }
            if t.hasPrefix("Glob") || t.hasPrefix("Grep") || t.hasPrefix("Search") {
                flushText(); flushTree(); segs.append(.toolUse(icon: "magnifyingglass", name: "Search", detail: t)); continue
            }
            if t.hasPrefix("\u{2514}") || t.hasPrefix("\u{251C}") {
                if t.contains("Tip:") || t.contains("**/") { continue }
                flushText(); treeBuf.append(t); continue
            }
            flushTree(); textBuf.append(line)
        }
        flushTree(); flushText()
        return segs
    }

    // MARK: - Output Cleaning

    // Pre-compiled regexes for cleanOutput — avoids recompilation on every call
    // Note: \u{1B} and \u{08} must use non-raw strings so Swift resolves the unicode escapes
    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{1B}\\[[\\d;]*[A-Za-z]")
    private static let numSeqRegex = try! NSRegularExpression(pattern: #"^\d+(?:;\d+)*m"#, options: .anchorsMatchLines)
    private static let blockCharsRegex = try! NSRegularExpression(pattern: "[█▓▒░▕▏▎▍▌▋▊▐▀▄▛▜▝▘▙▚▞▟]+")
    private static let backspaceRegex = try! NSRegularExpression(pattern: ".\u{08}")
    private static let thoughtRegex = try! NSRegularExpression(pattern: #"(?:T|t)?h?o?ught\s+for\s+\d+s?\)?"#)
    private static let thoughtRegex2 = try! NSRegularExpression(pattern: #"^\(?[Tt]hought\s+for\s+\d+m?\d*s?\)?"#, options: .anchorsMatchLines)
    private static let bulletRegex = try! NSRegularExpression(pattern: #"^[●○◉◎⏺•◐◑◒◓]\s*"#, options: .anchorsMatchLines)

    static func cleanOutput(_ raw: String) -> String {
        // Strip complete ANSI escape sequences first (ESC[...letter)
        let range = NSRange(raw.startIndex..., in: raw)
        var s = ansiRegex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
        s = s.replacingOccurrences(of: "\u{1B}", with: "")
        let sRange = NSRange(s.startIndex..., in: s)
        s = numSeqRegex.stringByReplacingMatches(in: s, range: sRange, withTemplate: "")
        let sRange2 = NSRange(s.startIndex..., in: s)
        s = blockCharsRegex.stringByReplacingMatches(in: s, range: sRange2, withTemplate: "")
        let sRange3 = NSRange(s.startIndex..., in: s)
        s = backspaceRegex.stringByReplacingMatches(in: s, range: sRange3, withTemplate: "")

        let lines = s.components(separatedBy: "\n")
        var cleaned: [String] = []
        var lastWasBlank = false
        let skipExact: Set<String> = [">","❯",")","●","$","%","#","Allow","Deny","Allow once","Allow always","Always allow","(thinking)","thinking","Accessing workspace:","Security guide"]

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if skipExact.contains(t) { continue }
            if t.hasPrefix("esc to") || t.hasPrefix("Esc to") || t.contains("esc to interrupt") { continue }
            if t.contains("ctrl+o") || t.contains("ctrl+e") { continue }
            if t.contains("ctrl+c") && t.count < 40 { continue }
            if t.contains("Esc to cancel") || t.contains("Tab to amend") || t.contains("/effort") || t.contains("for shortcuts") || t.contains("? for help") { continue }
            if t.hasPrefix("*") && (t.contains("...") || t.contains("\u{2026}")) { continue }
            if t.hasPrefix("\u{23FA}") { let x = String(t.dropFirst()).trimmingCharacters(in: .whitespaces); if !x.isEmpty { cleaned.append(x); lastWasBlank = false }; continue }
            let stars: Set<Character> = ["\u{2722}","\u{2726}","\u{2727}","\u{2728}","\u{2729}","\u{272A}","\u{2730}","\u{2731}","\u{2732}","\u{2733}","\u{2734}","\u{2735}","\u{2736}","\u{273B}","\u{25CF}","\u{25CB}","\u{25C9}","\u{25CE}","\u{25D0}","\u{25D1}","\u{23F9}","\u{23F8}","\u{25B6}","\u{25C0}","\u{00B7}","\u{2022}","\u{2219}","\u{25AA}","\u{25AB}","\u{2218}","\u{2217}","\u{2023}","\u{204E}"]
            if let f = t.first, stars.contains(f) { if t.count == 1 || t.contains("...") || t.contains("\u{2026}") { continue } }
            // Catch spinner/status lines (e.g. "✻ Propagating...", "Compiling...", etc.)
            let spinnerWords = ["Propagating","Compiling","Loading","Initializing","Starting","Connecting","Syncing","Bundling","Resolving","Fetching"]
            if spinnerWords.contains(where: { t.contains($0) }) && t.count < 80 { continue }
            if t.count < 30 && t.first.map({ "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".contains($0) }) == true { continue }
            if (t.hasPrefix("+") || t.hasPrefix("-")) && (t.hasSuffix("...") || t.hasSuffix("\u{2026}")) && t.count < 60 { continue }
            if (t.hasSuffix("...") || t.hasSuffix("\u{2026}")) && !t.contains(" ") && t.count < 30 { continue }
            if t.hasPrefix("❯") { continue }
            if t.contains("Native installation exists") || t.contains("not in your PATH") { continue }
            if t.hasPrefix("echo 'export PATH") || t.hasPrefix("echo \"export PATH") { continue }
            if t.contains("enabled \u{00B7}") || (t.contains("Chrome") && t.contains("enabled")) || t.contains("/chrome") || t.hasPrefix("Infusing") { continue }
            if t.hasPrefix("\u{25D0}") || t.hasPrefix("\u{25D1}") { continue }
            if ["medium","compact","extended","normal"].contains(t.lowercased()) { continue }
            if t.contains("Claude Code v") { continue }
            if t.contains("Opus") && t.contains("Claude") && t.count < 50 { continue }
            if t.hasPrefix("Quick safety check") || t.contains("able to read, edit, and execute") || t.contains("Enter to confirm") { continue }
            if t.contains("Do you want to proceed?") { continue }
            if t.hasPrefix("1.") && (t.contains("Yes") || t.contains("Allow")) { continue }
            if t.hasPrefix("2.") && (t.contains("No") || t.contains("Deny")) { continue }
            if t.hasPrefix("3.") && t.contains("Always") { continue }
            if t.contains("I trust this") || t.contains("trust this folder") || t.contains("Don't trust") { continue }
            if t.contains("wants to") && t.contains(":") && t.count < 80 {
                if t.lowercased().contains("wants to run") || t.lowercased().contains("wants to read") || t.lowercased().contains("wants to edit") || t.lowercased().contains("wants to write") || t.lowercased().contains("wants to execute") { continue }
            }
            if t.hasPrefix("(thinking") { continue }
            // Catch "Thought for Xs)" and mangled fragments
            let tRange = NSRange(t.startIndex..., in: t)
            if thoughtRegex.firstMatch(in: t, range: tRange) != nil && t.count < 40 { continue }
            if thoughtRegex2.firstMatch(in: t, range: tRange) != nil { continue }
            if t.contains("Thought for") || t.contains("hought for") || t.contains("ought for") { continue }
            if t.contains("Sprouting") || t.contains("Germinating") || t.contains("Blooming") || t.contains("Budding") { continue }
            if t.contains("Tip:") || t.contains("/terminal-setup") || t.contains("Plugin updated") || t.contains("/reload-plugins") { continue }
            if t.contains("plugin") && t.contains("apply") { continue }
            if t.contains("Share Claude Code") || t.contains("/passes") || t.contains("extra usage") { continue }
            if (t.hasPrefix("ading") && t.contains("file")) || (t.hasPrefix("iting") && t.contains("file")) || t.hasPrefix("arching") { continue }
            if t.contains("rl+o to expand") || (t.contains("to expand)") && t.count < 40) || t.contains("ctrl+o") || t.contains("rl+o") { continue }
            if t.contains("Cogitated for") || t.contains("Philosophising") || t.contains("Meandering") || t.contains("Ruminating") || t.contains("Pondering") { continue }
            if t.count <= 3 && t.allSatisfy({ $0.isNumber || $0 == " " }) && !t.isEmpty { continue }
            if t.hasPrefix("↑") || t.hasPrefix("↓") { continue }
            if t.hasPrefix("/**") || t.hasPrefix("**/") || t.hasPrefix("\"**/") || t.hasPrefix("\"**\\") { continue }
            if t.count < 20 && t.contains("**") && t.contains("*") { continue }
            if t.contains("You've used") && t.contains("session") { continue }
            if t.contains("/upgrade") || (t.contains("resets") && t.contains("am") && t.count < 100) || t.contains("keep using Cla") { continue }
            if t.hasPrefix("**") && t.count < 15 { continue }

            let db = bulletRegex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
            if !t.isEmpty && t.count <= 2 && !(t.allSatisfy(\.isLetter) || t.allSatisfy(\.isNumber)) { continue }
            if !t.isEmpty && t.allSatisfy({ "\u{2500}\u{2501}\u{2502}\u{2503}\u{250C}\u{2510}\u{2514}\u{2518}\u{251C}\u{2524}\u{252C}\u{2534}\u{253C}\u{2550}\u{2551}\u{2594}\u{2581}\u{2588}\u{2593}\u{2592}\u{2591}\u{25CF}\u{25CB}\u{25C9}\u{25CE}\u{2022}\u{00B7}".contains($0) || $0 == " " }) { continue }
            if t.count > 5 && t.allSatisfy({ "-=\u{2500}\u{2501}\u{2550}".contains($0) }) { continue }

            if t.isEmpty || db.isEmpty {
                if !lastWasBlank && !cleaned.isEmpty { cleaned.append("") }
                lastWasBlank = true; continue
            }
            lastWasBlank = false; cleaned.append(db)
        }

        while cleaned.last?.isEmpty == true { cleaned.removeLast() }
        while cleaned.first?.isEmpty == true { cleaned.removeFirst() }
        return cleaned.joined(separator: "\n")
    }
}
