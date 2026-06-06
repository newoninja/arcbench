/// Shared app settings — persisted via UserDefaults.
/// Single source of truth for API keys, preferences, and configuration.

import Foundation
import SwiftUI

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - API Keys

    @AppStorage("xai_api_key") var xaiApiKey: String = ""
    @AppStorage("anthropic_api_key") var anthropicApiKey: String = ""

    // MARK: - Swarm / Grok

    @AppStorage("use_claude_cli") var useClaudeCLI: Bool = true
    @AppStorage("swarm_max_iterations") var swarmMaxIterations: Int = 10
    @AppStorage("grok_model") var grokModel: String = "grok-3"
    @AppStorage("claude_model") var claudeModel: String = "sonnet"
    @AppStorage("claude_max_turns") var claudeMaxTurns: Int = 3

    // MARK: - Server

    @AppStorage("server_url") var serverURL: String = "http://localhost:8000"
    @AppStorage("auto_start_server") var autoStartServer: Bool = false

    // MARK: - Working Directory

    @AppStorage("working_directory") var workingDirectory: String = ""

    var resolvedWorkingDirectory: URL {
        if workingDirectory.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: workingDirectory)
    }

    var workingDirectoryDisplay: String {
        if workingDirectory.isEmpty { return "~" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if workingDirectory.hasPrefix(home) {
            return "~" + workingDirectory.dropFirst(home.count)
        }
        return workingDirectory
    }

    // MARK: - Appearance

    @AppStorage("default_terminal_mode") var defaultTerminalMode: String = "claude"
    @AppStorage("font_size") var fontSize: Double = 13.0
    @AppStorage("show_thinking_bubbles") var showThinkingBubbles: Bool = true
    @AppStorage("typewriter_enabled") var typewriterEnabled: Bool = true

    // MARK: - Default key (set via environment)
    static let defaultXaiKey = ""

    func loadFromEnvIfNeeded() {
        if xaiApiKey.isEmpty {
            xaiApiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        }
        if anthropicApiKey.isEmpty {
            anthropicApiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        }
    }
}
