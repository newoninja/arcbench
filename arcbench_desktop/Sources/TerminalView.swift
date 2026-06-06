/// Terminal interface — premium chat-style UI for Claude Code and Shell sessions.
/// Uses extracted PTYTerminalBackend, PTYChatViewModel, and MarkdownRenderer.
/// View-only code — logic is in PTYChatViewModel, rendering in MarkdownRenderer.

import SwiftUI
import Foundation

// MARK: - Claude Logo (PNG from bundle)

struct ClaudeLogo: View {
    var size: CGFloat = 20
    private static let cachedImage: NSImage? = {
        if let url = Bundle.main.url(forResource: "claudelogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
        let paths = [
            execURL?.appendingPathComponent("ArcBenchDesktop_ArcBenchDesktop.bundle/claudelogo.png"),
            execURL?.appendingPathComponent("claudelogo.png"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/Potential App/gymclaw/arcbench_desktop/Sources/Resources/claudelogo.png"),
        ].compactMap { $0 }
        for p in paths { if let img = NSImage(contentsOf: p) { return img } }
        return nil
    }()
    var body: some View {
        if let nsImage = Self.cachedImage {
            Image(nsImage: nsImage).resizable().interpolation(.high).antialiased(true).aspectRatio(contentMode: .fit).frame(width: size, height: size)
        } else {
            Image(systemName: "circle.hexagongrid.fill").font(.system(size: size * 0.7)).foregroundColor(.arcBlue)
        }
    }
}

struct ArcBenchLogo: View {
    var size: CGFloat = 20; var color: Color = .arcBlue
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height, s = max(w * 0.09, 1.5)
            var l = Path(); l.move(to: CGPoint(x: w*0.42, y: h*0.22)); l.addLine(to: CGPoint(x: w*0.18, y: h*0.50)); l.addLine(to: CGPoint(x: w*0.42, y: h*0.78))
            ctx.stroke(l, with: .color(color), style: StrokeStyle(lineWidth: s, lineCap: .round, lineJoin: .round))
            var sl = Path(); sl.move(to: CGPoint(x: w*0.58, y: h*0.20)); sl.addLine(to: CGPoint(x: w*0.42, y: h*0.80))
            ctx.stroke(sl, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: s*0.85, lineCap: .round))
            var r = Path(); r.move(to: CGPoint(x: w*0.58, y: h*0.22)); r.addLine(to: CGPoint(x: w*0.82, y: h*0.50)); r.addLine(to: CGPoint(x: w*0.58, y: h*0.78))
            ctx.stroke(r, with: .color(color), style: StrokeStyle(lineWidth: s, lineCap: .round, lineJoin: .round))
        }.frame(width: size, height: size)
    }
}

// MARK: - Grok Logo (PNG from bundle)

struct GrokLogo: View {
    var size: CGFloat = 20
    var color: Color = .white  // tint color (applied via .colorMultiply or template)

    private static let cachedImage: NSImage? = {
        if let url = Bundle.main.url(forResource: "groklogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
        let paths = [
            execURL?.appendingPathComponent("ArcBenchDesktop_ArcBenchDesktop.bundle/groklogo.png"),
            execURL?.appendingPathComponent("groklogo.png"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/Potential App/gymclaw/arcbench_desktop/Sources/Resources/groklogo.png"),
        ].compactMap { $0 }
        for p in paths { if let img = NSImage(contentsOf: p) { return img } }
        return nil
    }()

    var body: some View {
        if let nsImage = Self.cachedImage {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            // Fallback SF Symbol
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Terminal Icon (smart: uses logo for claude/grok, SF Symbol for custom/default)

struct TerminalIcon: View {
    let session: TerminalSession
    var size: CGFloat = 14
    var activeColor: Color? = nil

    var body: some View {
        if !session.customIcon.isEmpty {
            // Custom icon override
            Image(systemName: session.customIcon)
                .font(.system(size: size * 0.75, weight: .medium))
                .foregroundColor(activeColor ?? modeColor)
        } else {
            // Default: use proper logos for Claude/Grok, SF Symbols for others
            switch session.mode {
            case .claude:
                ClaudeLogo(size: size)
            case .grok:
                GrokLogo(size: size, color: activeColor ?? .accentOrange)
            case .swarm:
                Image(systemName: "bolt.trianglebadge.exclamationmark")
                    .font(.system(size: size * 0.75, weight: .medium))
                    .foregroundColor(activeColor ?? .accentOrange)
            case .shell:
                Image(systemName: "terminal")
                    .font(.system(size: size * 0.75, weight: .medium))
                    .foregroundColor(activeColor ?? .accentGreen)
            case .agents:
                Image(systemName: "person.3.fill")
                    .font(.system(size: size * 0.75, weight: .medium))
                    .foregroundColor(activeColor ?? .accentPurple)
            }
        }
    }

    private var modeColor: Color {
        switch session.mode {
        case .claude: return .arcBlue
        case .shell: return .accentGreen
        case .swarm: return .accentOrange
        case .grok: return .accentGrok
        case .agents: return .accentPurple
        }
    }
}

// All terminal view code has been moved to ChatViews.swift
