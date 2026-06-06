/// Main window — 3-column IDE layout: ActivityBar | Sidebar | Terminal/Chat main area.
/// Premium glassmorphism, neon accents, and micro-interactions throughout.

import SwiftUI

// MARK: - Activity Bar Panel Selection

enum SidebarPanel: String, CaseIterable {
    case sessions = "Sessions"
    case history  = "History"
    case files    = "Files"

    var icon: String {
        switch self {
        case .sessions: return "square.stack"
        case .history:  return "clock.arrow.circlepath"
        case .files:    return "folder"
        }
    }
}

// MARK: - Content View (3-column layout)

struct ContentView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var tailscale: TailscaleService

    @State private var selectedPanel: SidebarPanel = .sessions
    @State private var sidebarWidth: CGFloat = 260
    @State private var showSidebar = true
    @State private var showCommandPalette = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // 1. Activity Bar (44px icon strip)
                ActivityBar(selectedPanel: $selectedPanel, showSidebar: $showSidebar)

                if showSidebar {
                    // 2. Sidebar
                    SidebarContainer(selectedPanel: selectedPanel, sidebarWidth: $sidebarWidth)

                    // Divider with glow
                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(width: 1)
                        .shadow(color: Color.arcBlue.opacity(0.05), radius: 2, x: 1)
                }

                // 3. Main content
                VStack(spacing: 0) {
                    TopToolbar(showSettings: $showSettings)
                    Rectangle().fill(Color.borderSubtle).frame(height: 1)
                    if showSettings {
                        SettingsFullPage(isShowing: $showSettings)
                    } else {
                        MainContentArea()
                    }
                }
                .background(Color.bg)
            }

            // Error toast
            if connectionManager.errorVisible, let error = connectionManager.error {
                VStack {
                    ErrorToast(message: error) {
                        connectionManager.dismissError()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    Spacer()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: connectionManager.errorVisible)
            }

            // Command Palette overlay
            if showCommandPalette {
                CommandPaletteView(isPresented: $showCommandPalette)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Computer Control action overlay (centered HUD)
            ActionOverlay()
                .allowsHitTesting(false)

            // Recent actions strip (above input bar, right-aligned)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ActionHistoryStrip()
                }
                .padding(.bottom, 56)
                .padding(.leading, showSidebar ? sidebarWidth + 44 : 44)
            }
            .allowsHitTesting(false)
        }
        .background(
            LinearGradient(
                colors: [Color.bg, Color.bgSecondary],
                startPoint: .top, endPoint: .bottom
            )
        )
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showCommandPalette.toggle()
            }
        }
    }
}

// MARK: - Error Toast

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(.accentRed)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .padding(.trailing, 36)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgSecondary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentRed.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal, 20)
    }
}

// MARK: - Activity Bar (44px)

struct ActivityBar: View {
    @Binding var selectedPanel: SidebarPanel
    @Binding var showSidebar: Bool
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(SidebarPanel.allCases, id: \.self) { panel in
                    ActivityBarIcon(
                        icon: panel.icon,
                        isActive: showSidebar && selectedPanel == panel,
                        tooltip: panel.rawValue
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if selectedPanel == panel && showSidebar {
                                showSidebar = false
                            } else {
                                selectedPanel = panel
                                showSidebar = true
                            }
                        }
                    }
                }
            }
            .padding(.top, 14)

            Spacer()

            // Server status icon at bottom
            VStack(spacing: 4) {
                ActivityBarIcon(
                    icon: "server.rack",
                    isActive: false,
                    tint: serverManager.isRunning ? .accentGreen : .textTertiary,
                    tooltip: serverManager.isRunning ? "Stop Server" : "Start Server"
                ) {
                    if serverManager.isRunning { serverManager.stop() } else { serverManager.start() }
                }
            }
            .padding(.bottom, 14)
        }
        .frame(width: 44)
        .background(Color.bgSecondary.opacity(0.7))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.borderSubtle).frame(width: 1)
        }
    }
}

struct ActivityBarIcon: View {
    let icon: String
    let isActive: Bool
    var tint: Color? = nil
    var tooltip: String = ""
    let action: () -> Void
    @State private var isHovered = false

    private var iconColor: Color {
        if let tint { return tint }
        if isActive { return .arcBlue }
        return isHovered ? .textSecondary : .textTertiary
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Active indicator bar
                if isActive {
                    HStack {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.arcBlue)
                            .frame(width: 3, height: 18)
                            .shadow(color: .arcBlue.opacity(0.6), radius: 4)
                        Spacer()
                    }
                }

                // Icon with glow on active
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isActive ? Color.arcBlue.opacity(0.12) : (isHovered ? Color.bgTertiary : .clear))
                    )
                    .shadow(color: isActive ? .arcBlue.opacity(0.3) : .clear, radius: 8)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
            }
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovered = hovering }
        }
        .help(tooltip)
    }
}

// MARK: - Sidebar Container

struct SidebarContainer: View {
    let selectedPanel: SidebarPanel
    @Binding var sidebarWidth: CGFloat

    var body: some View {
        Group {
            switch selectedPanel {
            case .sessions: SessionsSidebar()
            case .history:  HistorySidebar()
            case .files:    FilesSidebar()
            }
        }
        .frame(width: sidebarWidth)
        .background(Color.bgSecondary.opacity(0.5))
    }
}

// MARK: - Sessions Sidebar

struct SessionsSidebar: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var terminalManager: TerminalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Open Terminals
                    SidebarSectionHeader(title: "TERMINALS", menuContent: {
                        AnyView(Group {
                            Button { terminalManager.createTerminal(mode: .claude) } label: {
                                Label("Claude Code", systemImage: "circle.hexagongrid.fill")
                            }
                            Button { terminalManager.createTerminal(mode: .shell) } label: {
                                Label("Shell", systemImage: "terminal")
                            }
                            Button { terminalManager.createTerminal(mode: .swarm) } label: {
                                Label("Swarm", systemImage: "bolt.trianglebadge.exclamationmark")
                            }
                            Button { terminalManager.createTerminal(mode: .grok) } label: {
                                Label("Grok", systemImage: "globe.americas.fill")
                            }
                            Button { terminalManager.createTerminal(mode: .agents) } label: {
                                Label("Agents", systemImage: "person.3.fill")
                            }
                        })
                    })

                    if terminalManager.terminals.isEmpty {
                        SidebarEmptyHint(text: "No terminals open")
                    } else {
                        ForEach(terminalManager.terminals) { terminal in
                            TerminalRow(
                                terminal: terminal,
                                isSelected: terminal.id == terminalManager.activeTerminalId
                            )
                            .onTapGesture { terminalManager.selectTerminal(terminal.id) }
                        }
                    }

                    Rectangle().fill(Color.borderSubtle).frame(height: 1)
                        .padding(.horizontal, 12).padding(.vertical, ArcSpacing.md)

                    // MARK: Recent Sessions
                    SidebarSectionHeader(title: "RECENT")

                    if terminalManager.historyStore.sessions.isEmpty {
                        SidebarEmptyHint(text: "Closed sessions appear here")
                    } else {
                        ForEach(terminalManager.historyStore.sessions.prefix(10)) { history in
                            SessionCard(session: history)
                                .onTapGesture { terminalManager.restoreSession(history) }
                                .contextMenu {
                                    Button("Reopen") { terminalManager.restoreSession(history) }
                                    Button("Rename...") { /* TODO */ }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        withAnimation { terminalManager.historyStore.delete(history.id) }
                                    }
                                }
                        }
                    }
                }
            }
            .clipped()

            ServerInfoPanel()
        }
    }
}

// MARK: - History Sidebar

struct HistorySidebar: View {
    @EnvironmentObject var terminalManager: TerminalManager
    @State private var searchText = ""
    @State private var showClearConfirm = false
    @State private var filterMode: String? = nil

    private var filteredSessions: [SessionHistory] {
        var all = terminalManager.historyStore.sessions
        if let mode = filterMode {
            all = all.filter { $0.mode == mode }
        }
        if !searchText.isEmpty {
            all = all.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.preview.localizedCaseInsensitiveContains(searchText)
            }
        }
        return all
    }

    private var grouped: [(String, [SessionHistory])] {
        let cal = Calendar.current
        var today: [SessionHistory] = []
        var yesterday: [SessionHistory] = []
        var thisWeek: [SessionHistory] = []
        var older: [SessionHistory] = []

        for s in filteredSessions {
            if cal.isDateInToday(s.closedAt) { today.append(s) }
            else if cal.isDateInYesterday(s.closedAt) { yesterday.append(s) }
            else if cal.isDate(s.closedAt, equalTo: Date(), toGranularity: .weekOfYear) { thisWeek.append(s) }
            else { older.append(s) }
        }

        var result: [(String, [SessionHistory])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        if !older.isEmpty { result.append(("Older", older)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("HISTORY")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.textTertiary)
                Spacer()
                if !terminalManager.historyStore.sessions.isEmpty {
                    Text("\(filteredSessions.count)")
                        .font(ArcFont.monoXs)
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.bgTertiary))

                    Button { showClearConfirm = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.bgTertiary.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .help("Clear all history")
                    .alert("Clear History", isPresented: $showClearConfirm) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear All", role: .destructive) {
                            withAnimation { terminalManager.historyStore.clearAll() }
                        }
                    } message: {
                        Text("Delete all \(terminalManager.historyStore.sessions.count) saved sessions? This can't be undone.")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, ArcSpacing.md)

            // Search
            HStack(spacing: ArcSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(ArcFont.caption)
                    .foregroundColor(.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, ArcSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: ArcRadius.md, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: ArcRadius.md, style: .continuous).stroke(Color.borderSubtle, lineWidth: 1))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, ArcSpacing.sm)

            // Mode filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ArcSpacing.xs) {
                    HistoryFilterChip(label: "All", isActive: filterMode == nil) {
                        withAnimation(ArcAnimation.quick) { filterMode = nil }
                    }
                    HistoryFilterChip(label: "Claude", icon: "circle.hexagongrid.fill", color: .arcBlue, isActive: filterMode == "claude") {
                        withAnimation(ArcAnimation.quick) { filterMode = filterMode == "claude" ? nil : "claude" }
                    }
                    HistoryFilterChip(label: "Shell", icon: "terminal", color: .accentGreen, isActive: filterMode == "shell") {
                        withAnimation(ArcAnimation.quick) { filterMode = filterMode == "shell" ? nil : "shell" }
                    }
                    HistoryFilterChip(label: "Swarm", icon: "bolt.trianglebadge.exclamationmark", color: .accentOrange, isActive: filterMode == "swarm") {
                        withAnimation(ArcAnimation.quick) { filterMode = filterMode == "swarm" ? nil : "swarm" }
                    }
                    HistoryFilterChip(label: "Grok", icon: "bolt.fill", color: .accentGrok, isActive: filterMode == "grok") {
                        withAnimation(ArcAnimation.quick) { filterMode = filterMode == "grok" ? nil : "grok" }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, ArcSpacing.md)

            if filteredSessions.isEmpty {
                VStack(spacing: ArcSpacing.md) {
                    Image(systemName: searchText.isEmpty && filterMode == nil ? "clock.arrow.circlepath" : "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(Color.textTertiary.opacity(0.4))
                    Text(searchText.isEmpty && filterMode == nil ? "No session history" : "No matching sessions")
                        .font(ArcFont.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped, id: \.0) { label, sessions in
                            HStack(spacing: ArcSpacing.sm) {
                                Text(label)
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.textTertiary)
                                    .tracking(0.5)
                                Rectangle().fill(Color.borderSubtle).frame(height: 1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, ArcSpacing.sm)

                            ForEach(sessions) { session in
                                SessionCard(session: session)
                                    .onTapGesture {
                                        terminalManager.restoreSession(session)
                                    }
                                    .contextMenu {
                                        Button("Reopen") { terminalManager.restoreSession(session) }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            withAnimation { terminalManager.historyStore.delete(session.id) }
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.bottom, ArcSpacing.md)
                }
                .clipped()
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Session Card (shared between SessionsSidebar and HistorySidebar)

struct SessionCard: View {
    let session: SessionHistory
    @State private var isHovered = false

    private var modeColor: Color {
        switch session.mode {
        case "claude": return .arcBlue
        case "swarm": return .accentOrange
        case "grok": return .accentGrok
        case "shell": return .accentGreen
        default: return .textTertiary
        }
    }

    private var modeIcon: String {
        switch session.mode {
        case "claude": return "circle.hexagongrid.fill"
        case "swarm": return "bolt.trianglebadge.exclamationmark"
        case "grok": return "globe.americas.fill"
        case "shell": return "terminal"
        default: return "terminal"
        }
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(session.closedAt)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: session.closedAt)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Mode icon — Claude gets the real logo, others get SF Symbols
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(modeColor.opacity(0.1))
                    .frame(width: 32, height: 32)
                if session.mode == "claude" {
                    ClaudeLogo(size: 18)
                } else {
                    Image(systemName: modeIcon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(modeColor)
                }
            }

            // Title + preview
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text(session.smartTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(timeAgo)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }

                if session.preview != "Empty session" {
                    Text(session.preview)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: ArcRadius.md, style: .continuous)
                .fill(isHovered ? Color.bgHover : .clear)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isHovered ? modeColor : .clear)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, ArcSpacing.xs)
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
        .contentShape(Rectangle())
    }
}

// MARK: - History Filter Chip

private struct HistoryFilterChip: View {
    let label: String
    var icon: String? = nil
    var color: Color = .textSecondary
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isActive ? color : .textTertiary)
                }
                Text(label)
                    .font(.system(size: 9.5, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? color : .textTertiary)
            }
            .padding(.horizontal, ArcSpacing.md)
            .padding(.vertical, ArcSpacing.xs)
            .background(
                Capsule()
                    .fill(isActive ? color.opacity(0.1) : Color.bgTertiary.opacity(0.4))
                    .overlay(Capsule().stroke(isActive ? color.opacity(0.3) : Color.borderSubtle, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar Empty Hint

private struct SidebarEmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(ArcFont.caption)
            .foregroundColor(.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}

struct SidebarSectionHeader: View {
    let title: String
    var menuContent: (() -> AnyView)? = nil
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Color.textTertiary)
            Spacer()

            if let menuContent {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.bgTertiary.opacity(0.5)))
                    .overlay {
                        Menu {
                            menuContent()
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }
            } else if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.bgTertiary.opacity(0.5)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

struct TerminalRow: View {
    let terminal: TerminalSession
    let isSelected: Bool
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showCloseConfirm = false
    @EnvironmentObject var terminalManager: TerminalManager

    private var modeColor: Color {
        switch terminal.mode {
        case .claude: return .arcBlue
        case .shell: return .accentGreen
        case .swarm: return .accentOrange
        case .grok: return .accentGrok
        case .agents: return .accentPurple
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon — dropdown menu to change (wrapped to prevent borderlessButton expansion)
            TerminalIcon(session: terminal, size: 16, activeColor: isSelected ? modeColor : .textTertiary)
                .frame(width: 20, height: 20)
                .overlay {
                    Menu {
                        Button { terminalManager.setTerminalIcon(terminal.id, icon: "") } label: {
                            Label("Default", systemImage: terminal.mode.icon)
                        }
                        Divider()
                        ForEach(terminalIconOptions, id: \.symbol) { opt in
                            if !opt.symbol.isEmpty {
                                Button {
                                    terminalManager.setTerminalIcon(terminal.id, icon: opt.symbol)
                                } label: {
                                    Label(opt.name, systemImage: opt.symbol)
                                }
                            }
                        }
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

            // Name — double-click to rename, pencil on hover
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Name", text: $renameText)
                        .onSubmit {
                            let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !t.isEmpty { terminalManager.renameTerminal(terminal.id, to: t) }
                            isRenaming = false
                        }
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.textPrimary)
                } else {
                    HStack(spacing: 4) {
                        Text(terminal.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .monospaced))
                            .foregroundColor(isSelected ? Color.textPrimary : Color.textSecondary)
                            .lineLimit(1)
                        if isHovered {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color.textTertiary)
                                .transition(.opacity)
                        }
                    }
                    .onTapGesture(count: 2) {
                        renameText = terminal.title
                        isRenaming = true
                    }
                    .onTapGesture(count: 1) {
                        terminalManager.selectTerminal(terminal.id)
                    }
                }
                Text(terminal.mode.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(modeColor.opacity(0.6))
            }

            Spacer()

            StatusDot(color: modeColor, size: 5, pulse: isSelected)
                .opacity(isSelected ? 1 : 0.4)

            if isHovered {
                Button {
                    showCloseConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.bgTertiary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.arcBlue.opacity(0.08) : (isHovered ? Color.bgHover : .clear))
                .padding(.horizontal, 8)
        )
        .neonUnderline(.arcBlue, active: isSelected, width: 1.5)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Close", role: .destructive) { showCloseConfirm = true }
        }
        .alert("Close Terminal", isPresented: $showCloseConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Close", role: .destructive) { terminalManager.closeTerminal(terminal.id) }
        } message: {
            Text("Are you sure you want to close \"\(terminal.title)\"? Any unsaved work will be lost.")
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "message")
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Color.arcBlue : Color.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.branch)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(isSelected ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)
                Text("\(session.messageCount) messages")
                    .font(.system(size: 11))
                    .foregroundColor(Color.textTertiary)
            }

            Spacer()

            if session.active {
                StatusDot(color: .accentGreen, size: 6, pulse: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.arcBlue.opacity(0.08) : (isHovered ? Color.bgHover : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - Files Sidebar

struct FilesSidebar: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var fileTree: [FileNode] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "EXPLORER")

            if let repoPath = connectionManager.serverStatus?.repoPath {
                Text(URL(fileURLWithPath: repoPath).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(fileTree) { node in
                        FileNodeRow(node: node, depth: 0)
                    }
                }
                .padding(.horizontal, 8)
            }
            .clipped()

            Spacer()
        }
        .onAppear { loadFileTree() }
    }

    private func loadFileTree() {
        guard let repoPath = connectionManager.serverStatus?.repoPath else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: repoPath) else { return }

        fileTree = contents
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .map { name in
                let fullPath = (repoPath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                return FileNode(name: name, path: fullPath, isDirectory: isDir.boolValue)
            }
    }
}

struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
}

struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    @State private var isExpanded = false
    @State private var children: [FileNode] = []
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.textTertiary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                    .font(.system(size: 12))
                    .foregroundColor(node.isDirectory ? Color.accentOrange.opacity(0.8) : Color.textTertiary)
                    .frame(width: 16)

                Text(node.name)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.leading, CGFloat(depth) * 16 + 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.bgHover.opacity(0.5) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering in isHovered = hovering }
            .onTapGesture {
                if node.isDirectory {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                    if isExpanded && children.isEmpty { loadChildren() }
                }
            }

            if isExpanded {
                ForEach(children) { child in
                    FileNodeRow(node: child, depth: depth + 1)
                }
            }
        }
    }

    private func loadChildren() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: node.path) else { return }
        children = contents
            .filter { !$0.hasPrefix(".") }
            .sorted { a, b in
                let aPath = (node.path as NSString).appendingPathComponent(a)
                let bPath = (node.path as NSString).appendingPathComponent(b)
                let aDir = fm.isDirectory(at: aPath)
                let bDir = fm.isDirectory(at: bPath)
                if aDir != bDir { return aDir }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            .map { name in
                let fullPath = (node.path as NSString).appendingPathComponent(name)
                return FileNode(name: name, path: fullPath, isDirectory: fm.isDirectory(at: fullPath))
            }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts": return "curlybraces"
        case "json": return "doc.badge.gearshape"
        case "md", "txt": return "doc.text"
        case "yaml", "yml": return "list.bullet.rectangle"
        case "sh": return "terminal"
        default: return "doc"
        }
    }
}

extension FileManager {
    func isDirectory(at path: String) -> Bool {
        var isDir: ObjCBool = false
        fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }
}

// MARK: - Settings Sidebar

struct SettingsSidebar: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var tailscale: TailscaleService
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "SETTINGS")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // API Keys
                    SettingsGroup(title: "API Keys") {
                        SettingsSecureField(label: "xAI (Grok)", placeholder: "xai-...", text: $settings.xaiApiKey)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsSecureField(label: "Anthropic", placeholder: "sk-ant-...", text: $settings.anthropicApiKey)
                    }

                    // Claude / Swarm
                    SettingsGroup(title: "Claude & Swarm") {
                        SettingsToggle(label: "Use Claude Code CLI", subtitle: "Uses Max plan instead of API", isOn: $settings.useClaudeCLI)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsModelPicker(label: "Claude Model", selection: $settings.claudeModel, options: [
                            ("sonnet", "Sonnet (fast)"),
                            ("opus", "Opus (best)"),
                            ("haiku", "Haiku (fastest)"),
                        ])
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsStepper(label: "Max Turns", value: $settings.claudeMaxTurns, range: 1...20)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        GrokModelPicker(selection: $settings.grokModel)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsStepper(label: "Max Iterations", value: $settings.swarmMaxIterations, range: 1...50)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        ModelSaveButton()
                    }

                    // Appearance
                    SettingsGroup(title: "Appearance") {
                        SettingsToggle(label: "Typewriter Effect", subtitle: "Word-by-word text reveal", isOn: $settings.typewriterEnabled)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsToggle(label: "Thinking Bubbles", subtitle: "Show tool activity in chat", isOn: $settings.showThinkingBubbles)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        HStack {
                            Text("Font Size")
                                .font(.system(size: 12)).foregroundColor(.textSecondary)
                            Spacer()
                            Text("\(Int(settings.fontSize))pt")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(.textTertiary)
                            Stepper("", value: $settings.fontSize, in: 10...20, step: 1)
                                .labelsHidden()
                                .scaleEffect(0.8)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                    }

                    // Connection
                    SettingsGroup(title: "Connection") {
                        SettingsLinkField(label: "Server URL", text: $settings.serverURL)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        if let status = connectionManager.serverStatus {
                            SettingsRow(label: "Hostname", value: status.hostname)
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "Model", value: status.defaultModel)
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        }
                        SettingsRow(label: "Tailscale", value: tailscale.statusText)
                    }

                    // Server
                    SettingsGroup(title: "Server") {
                        HStack {
                            Text("Status")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 6) {
                                StatusDot(
                                    color: serverManager.isRunning ? .accentGreen : .accentRed,
                                    size: 6,
                                    pulse: serverManager.isRunning
                                )
                                Text(serverManager.isRunning ? "Running" : "Stopped")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(serverManager.isRunning ? .accentGreen : .accentRed)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        if let pid = serverManager.pid {
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "PID", value: "\(pid)")
                        }
                        if let status = connectionManager.serverStatus {
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "Uptime", value: formatUptime(status.uptimeSeconds))
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "CPU", value: String(format: "%.1f%%", status.cpuPercent))
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "Memory", value: String(format: "%.0f MB", status.memoryMb))
                        }
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        HStack {
                            Spacer()
                            Button {
                                if serverManager.isRunning { serverManager.stop() } else { serverManager.start() }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: serverManager.isRunning ? "stop.fill" : "play.fill")
                                        .font(.system(size: 10))
                                    Text(serverManager.isRunning ? "Stop" : "Start")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(serverManager.isRunning ? Color.accentGreen : Color.accentRed)
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }

                    // About
                    SettingsGroup(title: "About") {
                        SettingsRow(label: "Version", value: "0.3.0")
                        SettingsRow(label: "Platform", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    }
                }
                .padding(16)
            }
            .clipped()

            Spacer()
        }
    }

    private func formatUptime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let hrs = mins / 60
        if hrs > 0 { return "\(hrs)h \(mins % 60)m" }
        return "\(mins)m"
    }
}

// MARK: - Settings Full Page

struct SettingsFullPage: View {
    @Binding var isShowing: Bool
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var tailscale: TailscaleService
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Two-column grid layout
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], alignment: .leading, spacing: 20) {

                    // API Keys
                    SettingsGroup(title: "API Keys") {
                        SettingsSecureField(label: "xAI (Grok)", placeholder: "xai-...", text: $settings.xaiApiKey)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsSecureField(label: "Anthropic", placeholder: "sk-ant-...", text: $settings.anthropicApiKey)
                    }

                    // Claude & Swarm
                    SettingsGroup(title: "Claude & Swarm") {
                        SettingsToggle(label: "Use Claude Code CLI", subtitle: "Uses Max plan instead of API", isOn: $settings.useClaudeCLI)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsModelPicker(label: "Claude Model", selection: $settings.claudeModel, options: [
                            ("sonnet", "Sonnet (fast)"),
                            ("opus", "Opus (best)"),
                            ("haiku", "Haiku (fastest)"),
                        ])
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsStepper(label: "Max Turns", value: $settings.claudeMaxTurns, range: 1...20)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        GrokModelPicker(selection: $settings.grokModel)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsStepper(label: "Max Iterations", value: $settings.swarmMaxIterations, range: 1...50)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        ModelSaveButton()
                    }

                    // Appearance
                    SettingsGroup(title: "Appearance") {
                        SettingsToggle(label: "Typewriter Effect", subtitle: "Word-by-word text reveal", isOn: $settings.typewriterEnabled)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        SettingsToggle(label: "Thinking Bubbles", subtitle: "Show tool activity in chat", isOn: $settings.showThinkingBubbles)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        HStack {
                            Text("Font Size")
                                .font(.system(size: 12)).foregroundColor(.textSecondary)
                            Spacer()
                            Text("\(Int(settings.fontSize))pt")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(.textTertiary)
                            Stepper("", value: $settings.fontSize, in: 10...20, step: 1)
                                .labelsHidden()
                                .scaleEffect(0.8)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                    }

                    // Connection
                    SettingsGroup(title: "Connection") {
                        SettingsLinkField(label: "Server URL", text: $settings.serverURL)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        if let status = connectionManager.serverStatus {
                            SettingsRow(label: "Hostname", value: status.hostname)
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "Model", value: status.defaultModel)
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        }
                        SettingsRow(label: "Tailscale", value: tailscale.statusText)
                    }

                    // Server
                    SettingsGroup(title: "Server") {
                        HStack {
                            Text("Status")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 6) {
                                StatusDot(
                                    color: serverManager.isRunning ? .accentGreen : .accentRed,
                                    size: 6,
                                    pulse: serverManager.isRunning
                                )
                                Text(serverManager.isRunning ? "Running" : "Stopped")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(serverManager.isRunning ? .accentGreen : .accentRed)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        if let pid = serverManager.pid {
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "PID", value: "\(pid)")
                        }
                        if let status = connectionManager.serverStatus {
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "Uptime", value: formatUptime(status.uptimeSeconds))
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "CPU", value: String(format: "%.1f%%", status.cpuPercent))
                            Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                            SettingsRow(label: "Memory", value: String(format: "%.0f MB", status.memoryMb))
                        }
                        Rectangle().fill(Color.borderSubtle).frame(height: 1).padding(.horizontal, 10)
                        HStack {
                            Spacer()
                            Button {
                                if serverManager.isRunning { serverManager.stop() } else { serverManager.start() }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: serverManager.isRunning ? "stop.fill" : "play.fill")
                                        .font(.system(size: 10))
                                    Text(serverManager.isRunning ? "Stop" : "Start")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(serverManager.isRunning ? Color.accentGreen : Color.accentRed)
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }

                    // About
                    SettingsGroup(title: "About") {
                        SettingsRow(label: "Version", value: "0.3.0")
                        SettingsRow(label: "Platform", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
    }

    private func formatUptime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let hrs = mins / 60
        if hrs > 0 { return "\(hrs)h \(mins % 60)m" }
        return "\(mins)m"
    }
}

// MARK: - Settings Input Components

struct SettingsSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 10)
            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.textPrimary)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)

                if !text.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentGreen)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 2)
    }
}

struct SettingsToggle: View {
    let label: String
    var subtitle: String = ""
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(isOn ? .accentGreen : .accentRed)
                .scaleEffect(0.7)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.textTertiary)
                .tracking(1.0)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bgTertiary.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct SettingsTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Spacer()
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct SettingsLinkField: View {
    let label: String
    @Binding var text: String
    @State private var isEditing = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Spacer()
            if isEditing {
                TextField("", text: $text, onCommit: { isEditing = false })
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
            } else {
                Button {
                    if let url = URL(string: text) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.arcBlue)
                        .underline()
                }
                .buttonStyle(.plain)
                .onLongPressGesture(minimumDuration: 0.5) {
                    isEditing = true
                }
                .contextMenu {
                    Button("Edit URL") { isEditing = true }
                    Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct GrokModelPicker: View {
    @Binding var selection: String

    private let models: [(value: String, display: String)] = [
        ("grok-4.20-beta-0309-reasoning", "Grok 4.20 (reasoning)"),
        ("grok-4.20-beta-0309-non-reasoning", "Grok 4.20 (fast)"),
        ("grok-4-1-fast-reasoning", "Grok 4.1 Fast (reasoning)"),
        ("grok-4-1-fast-non-reasoning", "Grok 4.1 Fast"),
        ("grok-4-fast-reasoning", "Grok 4 Fast (reasoning)"),
        ("grok-4-fast-non-reasoning", "Grok 4 Fast"),
        ("grok-4-0709", "Grok 4 (0709)"),
        ("grok-3", "Grok 3"),
        ("grok-3-mini", "Grok 3 Mini"),
        ("grok-code-fast-1", "Grok Code Fast"),
    ]

    var body: some View {
        HStack {
            Text("Grok Model")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(models, id: \.value) { model in
                    Text(model.display).tag(model.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 170)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

struct SettingsStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.textTertiary)
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

struct SettingsModelPicker: View {
    let label: String
    @Binding var selection: String
    let options: [(value: String, display: String)]

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options, id: \.value) { opt in
                    Text(opt.display).tag(opt.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 140)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

// MARK: - Model Save Button

struct ModelSaveButton: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject var terminalManager: TerminalManager
    @State private var saved = false

    private var claudeLabel: String {
        switch settings.claudeModel {
        case "opus": return "Opus"
        case "haiku": return "Haiku"
        default: return "Sonnet"
        }
    }

    var body: some View {
        HStack {
            Spacer()
            Button {
                // Reset Claude sessions so the next message uses the new model
                for session in terminalManager.terminals where session.mode == .claude {
                    terminalManager.viewModel(for: session).applyModelChange()
                }

                withAnimation(.easeInOut(duration: 0.2)) { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.2)) { saved = false }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: saved ? "checkmark" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                    Text(saved ? "Saved" : "Save & Apply")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(saved ? Color.accentGreen : Color.arcBlue)
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Server Info Panel

struct ServerInfoPanel: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.borderSubtle).frame(height: 1)

            // Collapsed: just the status dot + label, tap to expand
            Button {
                withAnimation(ArcAnimation.quick) { isExpanded.toggle() }
            } label: {
                HStack(spacing: ArcSpacing.sm) {
                    StatusDot(
                        color: serverManager.isRunning ? .accentGreen : .accentRed,
                        size: 6,
                        pulse: serverManager.isRunning
                    )
                    Text(serverManager.isRunning ? "Server Online" : "Server Offline")
                        .font(ArcFont.caption(.medium))
                        .foregroundColor(serverManager.isRunning ? .textSecondary : .textTertiary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: ArcSpacing.xs) {
                    if let status = connectionManager.serverStatus {
                        Text(status.repoPath)
                            .font(ArcFont.monoSmall)
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let lastLog = serverManager.logs.last {
                        Text(lastLog)
                            .font(ArcFont.monoSmall)
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

// MARK: - Top Toolbar (glassmorphism)

struct TopToolbar: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        HStack(spacing: 10) {
            // Active terminal mode indicator
            if !showSettings, let active = terminalManager.activeTerminal {
                HStack(spacing: 6) {
                    if active.mode == .claude {
                        ClaudeLogo(size: 14)
                    } else if active.mode == .grok {
                        GrokLogo(size: 14)
                    } else {
                        Image(systemName: active.mode.icon)
                            .font(.system(size: 12))
                            .foregroundColor(active.mode == .shell ? .accentGreen : .accentOrange)
                    }
                    Text(active.title)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                }
            }

            if showSettings {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.arcBlue)
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                }
            }

            Spacer()

            if !showSettings {
                // Working directory
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Open"
                    panel.message = "Choose a working directory"
                    if !AppSettings.shared.workingDirectory.isEmpty {
                        panel.directoryURL = AppSettings.shared.resolvedWorkingDirectory
                    }
                    if panel.runModal() == .OK, let url = panel.url {
                        AppSettings.shared.workingDirectory = url.path
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentOrange)
                        Text(AppSettings.shared.workingDirectoryDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: 160, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.bgTertiary)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.borderSubtle, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .help("Open working directory")

                ToolbarDivider()

                ToolbarPillButton(label: "New Terminal", icon: "plus", color: .arcBlue) {
                    terminalManager.createTerminal(mode: .claude)
                }

                ToolbarDivider()

                // Dynamic connection status
                ConnectionStatusPill()

                ToolbarDivider()

                // Interrupt
                ToolbarPillButton(label: "Interrupt", icon: "stop.fill", color: .accentRed) {
                    NotificationCenter.default.post(name: .sendInterrupt, object: nil)
                }

                ToolbarDivider()
            }

            // Settings button
            ToolbarPillButton(
                label: showSettings ? "Close Settings" : "Settings",
                icon: "gearshape",
                color: showSettings ? .textTertiary : .textSecondary
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSettings.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bgSecondary.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)
        }
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(width: 1, height: 18)
    }
}

struct ToolbarPillButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isHovered ? color : Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHovered ? color.opacity(0.12) : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(isHovered ? color.opacity(0.3) : Color.borderSubtle, lineWidth: 1)
                    )
            )
            .shadow(color: isHovered ? color.opacity(0.2) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovered = hovering }
        }
        .help(label)
    }
}

// MARK: - Connection Status Pill

struct ConnectionStatusPill: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    private var statusColor: Color {
        if connectionManager.isStreaming { return .accentOrange }
        if connectionManager.isConnected { return .accentGreen }
        return .accentRed
    }

    private var statusLabel: String {
        if connectionManager.isStreaming { return "Thinking..." }
        if connectionManager.isConnected { return "Connected" }
        return "Offline"
    }

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: statusColor, size: 6, pulse: connectionManager.isStreaming)
            Text(statusLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(statusColor.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.08))
                .overlay(Capsule().stroke(statusColor.opacity(0.2), lineWidth: 1))
        )
    }
}

// MARK: - Main Content Area

struct MainContentArea: View {
    @EnvironmentObject var terminalManager: TerminalManager

    var body: some View {
        ZStack {
            if terminalManager.terminals.isEmpty {
                WelcomeView()
            }

            // Keep ALL terminal views alive — hide inactive ones so state is preserved.
            // Active terminal gets zIndex(1) so it's on top for drag-and-drop
            // (macOS drop targets use z-order, not allowsHitTesting).
            ForEach(terminalManager.terminals) { terminal in
                let active = terminal.id == terminalManager.activeTerminalId
                TerminalView(session: terminal)
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(active)
                    .zIndex(active ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var terminalManager: TerminalManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.arcBlue.opacity(0.04))
                    .frame(width: 100, height: 100)
                    .breathingScale(min: 0.95, max: 1.05, duration: 3.0)
                Circle()
                    .fill(Color.arcBlue.opacity(0.08))
                    .frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.arcBlue.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .shadow(color: .arcBlue.opacity(0.3), radius: 12)
                ArcBenchLogo(size: 32, color: Color.arcBlue)
            }

            VStack(spacing: 10) {
                Text("ArcBench")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color.textPrimary)
                Text("Open a terminal or select a session to get started")
                    .font(.system(size: 14))
                    .foregroundColor(Color.textTertiary)
            }

            HStack(spacing: 12) {
                WelcomeButton(label: "Claude Code", color: .arcBlue, icon: { ClaudeLogo(size: 14) }) {
                    terminalManager.createTerminal(mode: .claude)
                }
                WelcomeButton(label: "Shell", icon: "terminal", color: .accentGreen) {
                    terminalManager.createTerminal(mode: .shell)
                }
                WelcomeButton(label: "Swarm", icon: "bolt.trianglebadge.exclamationmark", color: .accentOrange) {
                    terminalManager.createTerminal(mode: .swarm)
                }
                WelcomeButton(label: "Grok", color: .accentGrok, icon: { GrokLogo(size: 14) }) {
                    terminalManager.createTerminal(mode: .grok)
                }
                WelcomeButton(label: "Agents", icon: "person.3.fill", color: .accentPurple) {
                    terminalManager.createTerminal(mode: .agents)
                }
            }

            HStack(spacing: 8) {
                KeyboardHint(keys: ["⌘", "T"])
                Text("New Terminal")
                    .font(.system(size: 12))
                    .foregroundColor(Color.textTertiary)

                Spacer().frame(width: 16)

                KeyboardHint(keys: ["⌘", "K"])
                Text("Command Palette")
                    .font(.system(size: 12))
                    .foregroundColor(Color.textTertiary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
    }
}

struct WelcomeButton<Icon: View>: View {
    let label: String
    let color: Color
    let icon: Icon
    let action: () -> Void
    @State private var isHovered = false

    init(label: String, color: Color, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.label = label
        self.color = color
        self.icon = icon()
        self.action = action
    }

    /// Convenience for SF Symbol icons
    init(label: String, icon: String, color: Color, action: @escaping () -> Void) where Icon == Image {
        self.label = label
        self.color = color
        self.icon = Image(systemName: icon)
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? color : color.opacity(0.85))
                    .shadow(color: isHovered ? color.opacity(0.4) : color.opacity(0.2), radius: isHovered ? 12 : 6)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isHovered = hovering }
        }
    }
}

struct KeyboardHint: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bgTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.borderMedium, lineWidth: 1)
                            )
                    )
            }
        }
    }
}

// MARK: - Command Palette (⌘K)

struct PaletteCommand: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let shortcut: String?
    let action: () -> Void
}

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var terminalManager: TerminalManager
    @EnvironmentObject var computerControl: ComputerControlService

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var commands: [PaletteCommand] {
        [
            PaletteCommand(icon: "plus", label: "New Claude Code Terminal", shortcut: "⌘T") {
                terminalManager.createTerminal(mode: .claude)
            },
            PaletteCommand(icon: "terminal", label: "New Shell Terminal", shortcut: nil) {
                terminalManager.createTerminal(mode: .shell)
            },
            PaletteCommand(icon: "bolt.trianglebadge.exclamationmark", label: "New Swarm Terminal", shortcut: nil) {
                terminalManager.createTerminal(mode: .swarm)
            },
            PaletteCommand(icon: "globe.americas.fill", label: "New Grok Chat", shortcut: nil) {
                terminalManager.createTerminal(mode: .grok)
            },
            PaletteCommand(icon: "person.3.fill", label: "New Agents Chat", shortcut: nil) {
                terminalManager.createTerminal(mode: .agents)
            },
            PaletteCommand(icon: "plus.rectangle", label: "New Session", shortcut: nil) {
                Task { await connectionManager.createSession() }
            },
            PaletteCommand(
                icon: serverManager.isRunning ? "stop.circle" : "play.circle",
                label: serverManager.isRunning ? "Stop Server" : "Start Server",
                shortcut: nil
            ) {
                if serverManager.isRunning { serverManager.stop() } else { serverManager.start() }
            },
            PaletteCommand(icon: "checkmark", label: "Apply Changes", shortcut: nil) {
                Task { await connectionManager.applyAll() }
            },
            PaletteCommand(icon: "xmark", label: "Reject Changes", shortcut: nil) {
                Task { await connectionManager.rejectAll() }
            },
            PaletteCommand(icon: "arrow.uturn.backward", label: "Undo Last Commit", shortcut: nil) {
                Task { await connectionManager.undo() }
            },
            PaletteCommand(icon: "globe", label: "Open Dashboard", shortcut: nil) {
                serverManager.openDashboard()
            },
            PaletteCommand(icon: "wifi.slash", label: "Disconnect", shortcut: nil) {
                connectionManager.disconnectWebSocket()
            },
            // Computer Control
            PaletteCommand(icon: "app.badge", label: "Open Safari", shortcut: nil) {
                Task { await computerControl.openApp("Safari") }
            },
            PaletteCommand(icon: "app.badge", label: "Open Finder", shortcut: nil) {
                Task { await computerControl.openApp("Finder") }
            },
            PaletteCommand(icon: "app.badge", label: "Open Terminal", shortcut: nil) {
                Task { await computerControl.openApp("Terminal") }
            },
            PaletteCommand(icon: "app.badge", label: "Open Xcode", shortcut: nil) {
                Task { await computerControl.openApp("Xcode") }
            },
            PaletteCommand(icon: "app.badge", label: "Open VS Code", shortcut: nil) {
                Task { await computerControl.openApp("Visual Studio Code") }
            },
            PaletteCommand(icon: "globe", label: "Launch Browser (Playwright)", shortcut: nil) {
                Task { await computerControl.launchBrowser() }
            },
            PaletteCommand(icon: "camera.viewfinder", label: "Take Screenshot", shortcut: nil) {
                Task { await computerControl.takeScreenshot() }
            },
            PaletteCommand(icon: "link", label: "Open Google", shortcut: nil) {
                Task { await computerControl.openURL("https://www.google.com") }
            },
        ]
    }

    private var filteredCommands: [PaletteCommand] {
        if searchText.isEmpty { return commands }
        let query = searchText.lowercased()
        return commands.filter { $0.label.lowercased().contains(query) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(Color.textTertiary)

                    TextField("Type a command...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundColor(Color.textPrimary)
                        .focused($isSearchFocused)
                        .onSubmit { executeSelected() }

                    KeyboardHint(keys: ["esc"])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Rectangle().fill(Color.borderSubtle).frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, cmd in
                                CommandRow(command: cmd, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture { cmd.action(); dismiss() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }

                if filteredCommands.isEmpty {
                    Text("No matching commands")
                        .font(.system(size: 13))
                        .foregroundColor(Color.textTertiary)
                        .padding(.vertical, 20)
                }
            }
            .frame(width: 480)
            .glassMorphism(cornerRadius: 14, stroke: .arcBlue, strokeOpacity: 0.2)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .shadow(color: .arcBlue.opacity(0.1), radius: 20)
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { isSearchFocused = true; selectedIndex = 0 }
        .onChange(of: searchText) { _, _ in selectedIndex = 0 }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredCommands.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func executeSelected() {
        guard !filteredCommands.isEmpty else { return }
        filteredCommands[min(selectedIndex, filteredCommands.count - 1)].action()
        dismiss()
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isPresented = false }
    }
}

struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? Color.arcBlue : Color.textTertiary)
                .frame(width: 20)

            Text(command.label)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? Color.textPrimary : Color.textSecondary)

            Spacer()

            if let shortcut = command.shortcut {
                KeyboardHint(keys: [String(shortcut.prefix(1)), String(shortcut.suffix(1))])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.arcBlue.opacity(0.12) : (isHovered ? Color.bgHover : .clear))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
    }
}
