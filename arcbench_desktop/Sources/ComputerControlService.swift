/// ComputerControlService — Calls backend /computer/* endpoints and drives the action overlay.

import Foundation
import SwiftUI

// MARK: - Action Types

enum ComputerAction: Equatable {
    case openApp(String)
    case quitApp(String)
    case activateApp(String)
    case launchBrowser
    case navigateURL(String)
    case browserClick(String)
    case browserType(String)
    case screenshot
    case mouseMove(Int, Int)
    case mouseClick(Int, Int)
    case keyboardType(String)
    case hotkey([String])
    case shell(String)
    case clipboard
    case openFile(String)
    case openURL(String)
    case applescript

    var label: String {
        switch self {
        case .openApp(let name):       return "Opening \(name)"
        case .quitApp(let name):       return "Closing \(name)"
        case .activateApp(let name):   return "Switching to \(name)"
        case .launchBrowser:           return "Launching Browser"
        case .navigateURL(let url):    return "Navigating to \(shortenURL(url))"
        case .browserClick(let sel):   return "Clicking \(sel)"
        case .browserType(let text):   return "Typing \(String(text.prefix(20)))…"
        case .screenshot:              return "Capturing Screen"
        case .mouseMove(let x, let y): return "Moving to (\(x), \(y))"
        case .mouseClick(let x, let y):return "Clicking (\(x), \(y))"
        case .keyboardType(let text):  return "Typing \(String(text.prefix(20)))…"
        case .hotkey(let keys):        return "Pressing \(keys.joined(separator: "+"))"
        case .shell(let cmd):          return "Running \(String(cmd.prefix(30)))…"
        case .clipboard:               return "Clipboard"
        case .openFile(let path):      return "Opening \(URL(fileURLWithPath: path).lastPathComponent)"
        case .openURL(let url):        return "Opening \(shortenURL(url))"
        case .applescript:             return "Running AppleScript"
        }
    }

    var icon: String {
        switch self {
        case .openApp:       return "app.badge"
        case .quitApp:       return "xmark.app"
        case .activateApp:   return "macwindow"
        case .launchBrowser: return "globe"
        case .navigateURL:   return "safari"
        case .browserClick:  return "cursorarrow.click.2"
        case .browserType:   return "keyboard"
        case .screenshot:    return "camera.viewfinder"
        case .mouseMove:     return "cursorarrow.motionlines"
        case .mouseClick:    return "cursorarrow.click"
        case .keyboardType:  return "keyboard"
        case .hotkey:        return "command"
        case .shell:         return "terminal"
        case .clipboard:     return "doc.on.clipboard"
        case .openFile:      return "doc"
        case .openURL:       return "link"
        case .applescript:   return "applescript"
        }
    }

    var color: Color {
        switch self {
        case .openApp, .activateApp:     return .arcBlue
        case .quitApp:                   return .accentRed
        case .launchBrowser, .navigateURL, .openURL: return .accentGreen
        case .browserClick, .mouseClick: return .accentOrange
        case .browserType, .keyboardType, .hotkey: return .accentPurple
        case .screenshot:                return .arcBlue
        case .mouseMove:                 return .textSecondary
        case .shell:                     return .accentGreen
        case .clipboard:                 return .textSecondary
        case .openFile:                  return .accentOrange
        case .applescript:               return .accentPurple
        }
    }
}

private func shortenURL(_ url: String) -> String {
    if let host = URL(string: url)?.host { return host }
    return String(url.prefix(30))
}

// MARK: - Active Action State

struct ActiveAction: Identifiable, Equatable {
    let id = UUID()
    let action: ComputerAction
    var phase: ActionPhase = .appearing

    static func == (lhs: ActiveAction, rhs: ActiveAction) -> Bool {
        lhs.id == rhs.id
    }
}

enum ActionPhase {
    case appearing, running, success, failure
}

// MARK: - Service

@MainActor
class ComputerControlService: ObservableObject {
    @Published var activeAction: ActiveAction?
    @Published var recentActions: [ActiveAction] = []

    private var baseURL: String { AppSettings.shared.serverURL }
    private var dismissTask: Task<Void, Never>?

    // MARK: - Generic request helper

    private func post(_ path: String, body: [String: Any] = [:]) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/computer\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Request failed"
            throw NSError(domain: "ComputerControl", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func get(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/computer\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Show action overlay

    private func showAction(_ action: ComputerAction) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            activeAction = ActiveAction(action: action, phase: .running)
        }
    }

    private func completeAction(success: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeAction?.phase = success ? .success : .failure
        }
        if var completed = activeAction {
            completed.phase = success ? .success : .failure
            recentActions.insert(completed, at: 0)
            if recentActions.count > 10 { recentActions.removeLast() }
        }
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                activeAction = nil
            }
        }
    }

    // MARK: - Public API

    func openApp(_ name: String) async {
        showAction(.openApp(name))
        do {
            _ = try await post("/app/open", body: ["name": name])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func quitApp(_ name: String) async {
        showAction(.quitApp(name))
        do {
            _ = try await post("/app/quit", body: ["name": name])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func activateApp(_ name: String) async {
        showAction(.activateApp(name))
        do {
            _ = try await post("/app/activate", body: ["name": name])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func launchBrowser(headless: Bool = false) async {
        showAction(.launchBrowser)
        do {
            _ = try await post("/browser/launch", body: ["headless": headless])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func navigateURL(tabId: String, url: String) async {
        showAction(.navigateURL(url))
        do {
            _ = try await post("/browser/navigate", body: ["tab_id": tabId, "url": url])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func takeScreenshot() async {
        showAction(.screenshot)
        do {
            _ = try await post("/screenshot")
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func runShell(_ command: String) async {
        showAction(.shell(command))
        do {
            _ = try await post("/shell", body: ["command": command])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func openURL(_ url: String) async {
        showAction(.openURL(url))
        do {
            _ = try await post("/open/url", body: ["url": url])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func openFile(_ path: String) async {
        showAction(.openFile(path))
        do {
            _ = try await post("/open/file", body: ["path": path])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }

    func runAppleScript(_ script: String) async {
        showAction(.applescript)
        do {
            _ = try await post("/applescript", body: ["script": script])
            completeAction(success: true)
        } catch {
            completeAction(success: false)
        }
    }
}
