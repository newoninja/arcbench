/// ArcBench Desktop — macOS IDE-style app for AI coding agent control.
/// Premium dark-only UI with glassmorphism, neon accents, and micro-interactions.

import SwiftUI

// MARK: - ArcBench Theme (single source of truth)

extension Color {
    // Backgrounds — deep dark gradient palette
    static let bg          = Color(nsColor: NSColor(red: 0.059, green: 0.059, blue: 0.078, alpha: 1))  // #0F0F14
    static let bgSecondary = Color(nsColor: NSColor(red: 0.067, green: 0.067, blue: 0.086, alpha: 1))  // #111116
    static let bgTertiary  = Color(nsColor: NSColor(red: 0.090, green: 0.090, blue: 0.110, alpha: 1))  // #17171C
    static let bgHover     = Color(nsColor: NSColor(red: 0.110, green: 0.110, blue: 0.135, alpha: 1))  // #1C1C22
    static let bgElevated  = Color(nsColor: NSColor(red: 0.130, green: 0.130, blue: 0.155, alpha: 1))  // #212128

    // Card / code block backgrounds
    static let cardBg = Color(nsColor: NSColor(red: 0.102, green: 0.102, blue: 0.137, alpha: 1))       // #1A1A23
    static let codeBg = Color(nsColor: NSColor(red: 0.075, green: 0.075, blue: 0.100, alpha: 1))       // #13131A

    // Borders
    static let borderSubtle = Color.white.opacity(0.06)
    static let borderMedium = Color.white.opacity(0.10)
    static let borderGlow   = Color(nsColor: NSColor(red: 0.0, green: 0.831, blue: 1.0, alpha: 0.15))  // arcBlue 15%

    // Text
    static let textPrimary   = Color(nsColor: NSColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 1))  // #E0E0E0
    static let textSecondary = Color(nsColor: NSColor(red: 0.627, green: 0.627, blue: 0.647, alpha: 1))  // #A0A0A5
    static let textTertiary  = Color(nsColor: NSColor(red: 0.420, green: 0.420, blue: 0.450, alpha: 1))  // #6B6B73

    // Accent colors — muted, cohesive palette
    static let arcBlue      = Color(nsColor: NSColor(red: 0.0, green: 0.710, blue: 0.878, alpha: 1))     // #00B5E0 — slightly muted cyan
    static let accentGreen  = Color(nsColor: NSColor(red: 0.345, green: 0.698, blue: 0.490, alpha: 1))   // #58B27D — muted sage
    static let accentRed    = Color(nsColor: NSColor(red: 0.820, green: 0.380, blue: 0.380, alpha: 1))   // #D16161 — muted red
    static let accentOrange = Color(nsColor: NSColor(red: 0.820, green: 0.620, blue: 0.310, alpha: 1))   // #D19E4F — muted amber
    static let accentPurple = Color(nsColor: NSColor(red: 0.545, green: 0.435, blue: 0.780, alpha: 1))   // #8B6FC7 — muted purple
    static let accentGrok   = Color(nsColor: NSColor(red: 0.780, green: 0.780, blue: 0.810, alpha: 1))   // #C7C7CF — cool silver (Grok's brand)
}

// MARK: - App Delegate

class ArcBenchAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.applicationIconImage = Self.makeAppIcon()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows where window.isVisible {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.backgroundColor = NSColor(red: 0.059, green: 0.059, blue: 0.078, alpha: 1)
                window.isMovableByWindowBackground = false
                window.toolbar = nil
                window.hasShadow = true
            }
        }
    }

    static func makeAppIcon() -> NSImage {
        let size: CGFloat = 512
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // Transparent background — no filled rectangle
        let arcBlue = NSColor(red: 0.0, green: 0.831, blue: 1.0, alpha: 1)

        // Subtle glow behind the symbol
        let glowRect = NSRect(x: 100, y: 160, width: 312, height: 192)
        let glow = NSBezierPath(ovalIn: glowRect)
        arcBlue.withAlphaComponent(0.12).setFill()
        glow.fill()

        // "<"
        let leftBracket = NSBezierPath()
        leftBracket.move(to: NSPoint(x: 230, y: 170))
        leftBracket.line(to: NSPoint(x: 140, y: 256))
        leftBracket.line(to: NSPoint(x: 230, y: 342))
        leftBracket.lineWidth = 36
        leftBracket.lineCapStyle = .round
        leftBracket.lineJoinStyle = .round
        arcBlue.setStroke()
        leftBracket.stroke()

        // "/"
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: 290, y: 155))
        slash.line(to: NSPoint(x: 222, y: 357))
        slash.lineWidth = 30
        slash.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.9).setStroke()
        slash.stroke()

        // ">"
        let rightBracket = NSBezierPath()
        rightBracket.move(to: NSPoint(x: 282, y: 170))
        rightBracket.line(to: NSPoint(x: 372, y: 256))
        rightBracket.line(to: NSPoint(x: 282, y: 342))
        rightBracket.lineWidth = 36
        rightBracket.lineCapStyle = .round
        rightBracket.lineJoinStyle = .round
        arcBlue.setStroke()
        rightBracket.stroke()

        image.unlockFocus()
        return image
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }
}

// MARK: - App Entry Point

@main
struct ArcBenchApp: App {
    @NSApplicationDelegateAdaptor(ArcBenchAppDelegate.self) var appDelegate
    @StateObject private var serverManager = ServerManager()
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var terminalManager = TerminalManager()
    @StateObject private var tailscale = TailscaleService.shared
    @StateObject private var computerControl = ComputerControlService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
                .environmentObject(connectionManager)
                .environmentObject(terminalManager)
                .environmentObject(tailscale)
                .environmentObject(computerControl)
                .frame(minWidth: 960, minHeight: 640)
                .background(
                    LinearGradient(
                        colors: [Color.bg, Color.bgSecondary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onAppear {
                    NSLog("🔴🔴🔴 [ArcBench] APP LAUNCHED — debug build v2")
                    connectionManager.loadApiKeyFromEnv()
                    Task {
                        await connectionManager.fetchStatus()
                        if connectionManager.isConnected {
                            connectionManager.connectWebSocket()
                            await connectionManager.fetchSessions()
                        }
                    }
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Terminal") {
                    terminalManager.createTerminal()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Command Palette") {
                    NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        // System tray
        MenuBarExtra {
            ArcBenchMenuBarView()
                .environmentObject(serverManager)
                .environmentObject(connectionManager)
                .environmentObject(terminalManager)
                .environmentObject(tailscale)
                .environmentObject(computerControl)
        } label: {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - MenuBarExtra View

struct ArcBenchMenuBarView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var tailscale: TailscaleService

    private var allGood: Bool {
        serverManager.isRunning && tailscale.isConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.arcBlue.opacity(0.12))
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.arcBlue.opacity(0.2), lineWidth: 1)
                            )
                        ArcBenchLogo(size: 20, color: Color.arcBlue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ArcBench")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.textPrimary)
                        Text("v0.3.0")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.bgTertiary))
                    }
                    Spacer()
                    StatusDot(color: allGood ? .accentGreen : .accentOrange, size: 8, pulse: allGood)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }

            // Accent line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.arcBlue.opacity(0.5), Color.arcBlue.opacity(0.05)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Status list
            VStack(spacing: 3) {
                MenuBarStatusPill(icon: "server.rack", label: "Backend",
                    status: serverManager.isRunning ? "Live" : "Off",
                    color: serverManager.isRunning ? .accentGreen : .accentRed)
                MenuBarStatusPill(icon: "network", label: "Tailscale",
                    status: tailscale.isConnected ? "Connected" : "Down",
                    color: tailscale.isConnected ? .accentGreen : .textTertiary)
                MenuBarStatusPill(icon: "terminal", label: "Terminals",
                    status: "\(terminalManager.terminals.count)", color: .arcBlue)
                MenuBarStatusPill(icon: "bubble.left.and.bubble.right", label: "Sessions",
                    status: "\(connectionManager.sessions.count)", color: .accentPurple)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)

            // Actions
            VStack(spacing: 2) {
                MenuBarActionRow(icon: "plus.rectangle", label: "New Terminal") {
                    terminalManager.createTerminal()
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuBarActionRow(icon: "arrow.clockwise", label: "Restart Backend") {
                    serverManager.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { serverManager.start() }
                }
                MenuBarActionRow(icon: "doc.text.magnifyingglass", label: "Open API Docs") {
                    serverManager.openDashboard()
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)

            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)

            VStack(spacing: 2) {
                MenuBarActionRow(
                    icon: serverManager.isRunning ? "stop.circle" : "play.circle",
                    label: serverManager.isRunning ? "Stop Server" : "Start Server"
                ) {
                    if serverManager.isRunning { serverManager.stop() } else { serverManager.start() }
                }
                MenuBarActionRow(icon: "xmark.circle", label: "Quit ArcBench") {
                    serverManager.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .background(Color.bg)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleCommandPalette = Notification.Name("toggleCommandPalette")
    static let sendInterrupt = Notification.Name("sendInterrupt")
    static let grokRouteMessage = Notification.Name("grokRouteMessage")
}

// MARK: - MenuBar Helper Views

struct MenuBarStatusPill: View {
    let icon: String
    let label: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color.textSecondary)
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(status)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(color.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.borderSubtle, lineWidth: 1)
                )
        )
    }
}

struct MenuBarActionRow: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? Color.arcBlue : Color.textTertiary)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(isHovered ? Color.textPrimary : Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.bgHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
