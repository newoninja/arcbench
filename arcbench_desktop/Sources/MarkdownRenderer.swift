import SwiftUI

struct TypewriterText: View {
    let fullText: String
    @State private var displayedCount: Int = 0
    @State private var timer: Timer?
    @State private var lastFullText: String = ""
    @State private var isComplete: Bool = false
    private var shownText: String { isComplete ? fullText : String(fullText.prefix(max(displayedCount, 0))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Self.parseMarkdown(shownText).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text): Text(mkAttr(text)).font(.system(size: level == 1 ? 18 : level == 2 ? 16 : 14, weight: .bold)).foregroundColor(.textPrimary)
                case .codeBlock(let lang, let code):
                    CodeBlockView(lang: lang, code: code, accentColor: .arcBlue)
                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 8) { ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Circle().fill(Color.arcBlue.opacity(0.7)).frame(width: 5, height: 5).offset(y: 1); Text(mkAttr(item)).font(.system(size: 13.5)).foregroundColor(.textPrimary).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
                    } }.padding(.leading, 4)
                case .numberedList(let items):
                    VStack(alignment: .leading, spacing: 8) { ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(idx+1).").font(.system(size: 12.5, weight: .semibold, design: .monospaced)).foregroundColor(Color.arcBlue.opacity(0.7)).frame(width: 20, alignment: .trailing); Text(mkAttr(item)).font(.system(size: 13.5)).foregroundColor(.textPrimary).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
                    } }.padding(.leading, 2)
                case .paragraph(let text): Text(mkAttr(text)).font(.system(size: 13.5)).foregroundColor(.textPrimary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
            }

            if isComplete && !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CopyMessageButton(text: fullText)
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: 600, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.cardBg).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.borderSubtle, lineWidth: 1)))
        .onAppear { startTyping() }
        .onChange(of: fullText) { _, newVal in if newVal != lastFullText { startTyping() } }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func mkAttr(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    enum MdBlock { case heading(level: Int, text: String); case codeBlock(language: String, code: String); case bulletList(items: [String]); case numberedList(items: [String]); case paragraph(text: String) }

    static func parseMarkdown(_ text: String) -> [MdBlock] {
        let lines = text.components(separatedBy: "\n"); var blocks: [MdBlock] = []; var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { i += 1; continue }
            if t.hasPrefix("```") { let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces); var cl: [String] = []; i += 1; while i < lines.count { if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { i += 1; break }; cl.append(lines[i]); i += 1 }; blocks.append(.codeBlock(language: lang, code: cl.joined(separator: "\n"))); continue }
            if t.hasPrefix("#") { let lv = t.prefix(while: { $0 == "#" }).count; if lv <= 3 && t.count > lv && t[t.index(t.startIndex, offsetBy: lv)] == " " { blocks.append(.heading(level: lv, text: String(t.dropFirst(lv+1)))); i += 1; continue } }
            if t.hasPrefix("- ") || t.hasPrefix("* ") { var items: [String] = []; while i < lines.count { let bl = lines[i].trimmingCharacters(in: .whitespaces); if bl.hasPrefix("- ") { items.append(String(bl.dropFirst(2))) } else if bl.hasPrefix("* ") { items.append(String(bl.dropFirst(2))) } else if bl.isEmpty { break } else if !items.isEmpty { items[items.count-1] += " " + bl }; i += 1 }; blocks.append(.bulletList(items: items)); continue }
            if let _ = t.range(of: #"^\d+\.\s"#, options: .regularExpression) { var items: [String] = []; while i < lines.count { let nl = lines[i].trimmingCharacters(in: .whitespaces); if let r = nl.range(of: #"^\d+\.\s"#, options: .regularExpression) { items.append(String(nl[r.upperBound...])) } else if nl.isEmpty { break } else if !items.isEmpty { items[items.count-1] += " " + nl }; i += 1 }; blocks.append(.numberedList(items: items)); continue }
            var pl: [String] = []; while i < lines.count { let pt = lines[i].trimmingCharacters(in: .whitespaces); if pt.isEmpty || pt.hasPrefix("```") || pt.hasPrefix("#") || pt.hasPrefix("- ") || pt.hasPrefix("* ") || pt.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { break }; pl.append(pt); i += 1 }
            if !pl.isEmpty { blocks.append(.paragraph(text: pl.joined(separator: " "))) }
        }; return blocks
    }

    private func startTyping() {
        lastFullText = fullText; timer?.invalidate()
        let target = fullText.count; if displayedCount >= target { displayedCount = target; isComplete = true; return }
        isComplete = false; let remaining = target - displayedCount; let cpt = max(1, remaining / 30)
        timer = Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { t in
            let total = fullText.count; if displayedCount < total { displayedCount = min(displayedCount + cpt, total) } else { isComplete = true; t.invalidate() }
        }
    }
}
