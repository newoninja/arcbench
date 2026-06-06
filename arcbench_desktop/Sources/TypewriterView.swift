/// TypewriterView — Word-by-word text reveal with Markdown-aware rendering.
/// Used by SwarmViews and GrokViews for message content display.

import SwiftUI

// MARK: - Word-by-Word Typewriter (Markdown-aware)

struct WordTypewriter: View {
    let text: String
    let color: Color
    @State private var visibleChars: Int = 0
    @State private var timer: Timer?
    @State private var lastText: String = ""
    @State private var isComplete: Bool = false

    private var shownText: String {
        isComplete ? text : String(text.prefix(max(visibleChars, 0)))
    }

    var body: some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(Self.parseMarkdown(shownText).enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }

                if isComplete && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    CopyMessageButton(text: text)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 600, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous)
                    .fill(color.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArcRadius.lg, style: .continuous)
                            .stroke(color.opacity(0.12), lineWidth: 1)
                    )
            )
            .opacity(visibleChars == 0 && !text.isEmpty ? 0.3 : 1)
            .animation(.easeOut(duration: 0.15), value: visibleChars)
            .onAppear { startRevealing() }
            .onChange(of: text) { _, newVal in
                if newVal != lastText { startRevealing() }
            }
            .onDisappear { timer?.invalidate(); timer = nil }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MdBlock) -> some View {
        switch block {
        case .heading(let level, let txt):
            Text(mkAttr(txt))
                .font(ArcFont.heading(level))
                .foregroundColor(color)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 4 : 2)

        case .codeBlock(let lang, let code):
            codeBlockView(lang: lang, code: code)

        case .bulletList(let items):
            bulletListView(items: items)

        case .numberedList(let items):
            numberedListView(items: items)

        case .horizontalRule:
            Rectangle()
                .fill(color.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .paragraph(let txt):
            Text(mkAttr(txt))
                .font(ArcFont.label)
                .foregroundColor(.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func codeBlockView(lang: String, code: String) -> some View {
        CodeBlockView(lang: lang, code: code, accentColor: color)
    }

    private func bulletListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(color.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .offset(y: 1)
                    Text(mkAttr(item))
                        .font(ArcFont.label)
                        .foregroundColor(.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func numberedListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(idx + 1).")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(color.opacity(0.6))
                        .frame(width: 18, alignment: .trailing)
                    Text(mkAttr(item))
                        .font(ArcFont.label)
                        .foregroundColor(.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 2)
    }

    private func mkAttr(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    enum MdBlock {
        case heading(level: Int, text: String)
        case codeBlock(language: String, code: String)
        case bulletList(items: [String])
        case numberedList(items: [String])
        case horizontalRule
        case paragraph(text: String)
    }

    static func parseMarkdown(_ text: String) -> [MdBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MdBlock] = []
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { i += 1; continue }

            // Horizontal rule
            if t == "---" || t == "***" || t == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Code block
            if t.hasPrefix("```") {
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var cl: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { i += 1; break }
                    cl.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang, code: cl.joined(separator: "\n")))
                continue
            }

            // Heading
            if t.hasPrefix("#") {
                let lv = t.prefix(while: { $0 == "#" }).count
                if lv <= 3 && t.count > lv && t[t.index(t.startIndex, offsetBy: lv)] == " " {
                    blocks.append(.heading(level: lv, text: String(t.dropFirst(lv + 1))))
                    i += 1
                    continue
                }
            }

            // Bullet list
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let bl = lines[i].trimmingCharacters(in: .whitespaces)
                    if bl.hasPrefix("- ") { items.append(String(bl.dropFirst(2))) }
                    else if bl.hasPrefix("* ") { items.append(String(bl.dropFirst(2))) }
                    else if bl.isEmpty { break }
                    else if !items.isEmpty { items[items.count - 1] += " " + bl }
                    i += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Numbered list
            if let _ = t.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let nl = lines[i].trimmingCharacters(in: .whitespaces)
                    if let r = nl.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        items.append(String(nl[r.upperBound...]))
                    } else if nl.isEmpty { break }
                    else if !items.isEmpty { items[items.count - 1] += " " + nl }
                    i += 1
                }
                blocks.append(.numberedList(items: items))
                continue
            }

            // Paragraph — collect contiguous lines
            var pl: [String] = []
            while i < lines.count {
                let pt = lines[i].trimmingCharacters(in: .whitespaces)
                if pt.isEmpty || pt.hasPrefix("```") || pt.hasPrefix("#") || pt.hasPrefix("- ") || pt.hasPrefix("* ") || pt == "---" || pt == "***" || pt == "___" || pt.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { break }
                pl.append(pt)
                i += 1
            }
            if !pl.isEmpty { blocks.append(.paragraph(text: pl.joined(separator: " "))) }
        }
        return blocks
    }

    private func startRevealing() {
        lastText = text
        timer?.invalidate()
        let totalChars = text.count
        if totalChars == 0 { return }

        isComplete = false
        let charsPerTick = max(1, totalChars / 40)
        let interval: TimeInterval = totalChars > 200 ? 0.015 : 0.03

        visibleChars = 0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            if visibleChars < totalChars {
                visibleChars = min(visibleChars + charsPerTick, totalChars)
            } else {
                isComplete = true
                t.invalidate()
            }
        }
    }
}

// MARK: - Copy Message Button

struct CopyMessageButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack {
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(copied ? .accentGreen : .textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(copied ? Color.accentGreen.opacity(0.1) : Color.bgTertiary.opacity(0.6))
                        .overlay(Capsule().stroke(copied ? Color.accentGreen.opacity(0.3) : Color.borderSubtle.opacity(0.5), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// TypewriterText is defined in MarkdownRenderer.swift

// MARK: - Shared Code Block View (used by both TypewriterText and WordTypewriter)

struct CodeBlockView: View {
    let lang: String
    let code: String
    var accentColor: Color = .arcBlue
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !lang.isEmpty {
                Text(lang)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(accentColor.opacity(0.85))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, lang.isEmpty ? 8 : 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.codeBg)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(accentColor.opacity(0.08), lineWidth: 1))
        )
        .overlay(alignment: .topTrailing) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                    if copied {
                        Text("Copied").font(.system(size: 9, weight: .medium))
                    }
                }
                .foregroundColor(copied ? .accentGreen : .textTertiary)
                .padding(.horizontal, copied ? 8 : 6)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgTertiary.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .padding(5)
        }
    }
}
