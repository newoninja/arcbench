/// Manages WebSocket connection and REST API calls to the local backend.
/// Includes exponential backoff reconnection and proper error surfacing.

import Foundation
import SwiftUI

@MainActor
class ConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var serverStatus: ServerStatusResponse?
    @Published var sessions: [SessionSummary] = []
    @Published var currentSessionId: String?
    @Published var messages: [ChatMessageModel] = []
    @Published var isStreaming = false
    @Published var error: String?
    @Published var errorVisible = false

    var sessionCount: Int { sessions.count }

    private var webSocketTask: URLSessionWebSocketTask?
    private let wsSession = URLSession(configuration: .default)
    private var baseURL: String { AppSettings.shared.serverURL }
    private var apiKey: String = ""
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = false

    // MARK: - Configuration

    func configure(apiKey: String) {
        self.apiKey = apiKey
    }

    func loadApiKeyFromEnv() {
        // Try multiple locations for .env
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["ARCBENCH_PROJECT_ROOT"].map { "\($0)/.env" },
            "\(home)/Desktop/Potential App/gymclaw/.env",
        ].compactMap { $0 }

        for envPath in candidates {
            guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("ARCBENCH_API_KEY=") {
                    apiKey = String(trimmed.dropFirst("ARCBENCH_API_KEY=".count))
                    return
                }
            }
        }
    }

    // MARK: - Error Display

    func showError(_ message: String) {
        error = message
        errorVisible = true
        // Auto-dismiss after 8 seconds
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if self.error == message {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.errorVisible = false
                }
            }
        }
    }

    func dismissError() {
        withAnimation(.easeOut(duration: 0.3)) {
            errorVisible = false
        }
    }

    // MARK: - REST

    private func request(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            throw NSError(domain: "ArcBench", code: http?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Unknown error"])
        }
        return data
    }

    func fetchStatus() async {
        do {
            let data = try await request("GET", path: "/status")
            serverStatus = try JSONDecoder().decode(ServerStatusResponse.self, from: data)
            isConnected = true
            error = nil
        } catch {
            isConnected = false
            // Don't show error on startup — backend is optional for local-only mode
        }
    }

    func fetchSessions() async {
        do {
            let data = try await request("GET", path: "/sessions")
            sessions = try JSONDecoder().decode([SessionSummary].self, from: data)
        } catch {
            // Silently fail — sessions are optional when backend is offline
            sessions = []
        }
    }

    func createSession(model: String? = nil) async -> String? {
        do {
            var body: [String: String] = [:]
            if let model { body["model"] = model }
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            let data = try await request("POST", path: "/sessions", body: jsonData)
            let session = try JSONDecoder().decode(SessionSummary.self, from: data)
            sessions.insert(session, at: 0)
            currentSessionId = session.id
            messages = []
            return session.id
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    func applyAll() async {
        guard let sid = currentSessionId else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
            _ = try await request("POST", path: "/sessions/\(sid)/apply", body: body)
            messages.append(ChatMessageModel(role: "system", content: "Changes applied and committed."))
        } catch {
            showError(error.localizedDescription)
        }
    }

    func rejectAll() async {
        guard let sid = currentSessionId else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
            _ = try await request("POST", path: "/sessions/\(sid)/reject", body: body)
            messages.append(ChatMessageModel(role: "system", content: "Changes rejected."))
        } catch {
            showError(error.localizedDescription)
        }
    }

    func undo() async {
        guard let sid = currentSessionId else { return }
        do {
            _ = try await request("POST", path: "/sessions/\(sid)/undo")
            messages.append(ChatMessageModel(role: "system", content: "Last commit undone."))
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - WebSocket with Reconnection

    func connectWebSocket() {
        shouldReconnect = true
        reconnectAttempt = 0
        doConnect()
    }

    func disconnectWebSocket() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func doConnect() {
        let wsURL = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        guard let url = URL(string: "\(wsURL)/ws") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        webSocketTask = wsSession.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempt = 0
        receiveMessage()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)) * 0.5, 30.0) // Max 30s
        let jitter = Double.random(in: 0...0.5)

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
            guard !Task.isCancelled, self.shouldReconnect else { return }
            self.doConnect()
        }
    }

    func sendPrompt(_ text: String) {
        guard let sid = currentSessionId else { return }
        messages.append(ChatMessageModel(role: "user", content: text))

        let payload: [String: Any] = [
            "type": "prompt",
            "session_id": sid,
            "content": text,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }

        isStreaming = true
        messages.append(ChatMessageModel(role: "assistant", content: ""))

        webSocketTask?.send(.string(jsonStr)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }

    func sendApply() {
        guard let sid = currentSessionId else { return }
        sendWsJson(["type": "apply", "session_id": sid])
    }

    func sendReject() {
        guard let sid = currentSessionId else { return }
        sendWsJson(["type": "reject", "session_id": sid])
    }

    func sendUndo() {
        guard let sid = currentSessionId else { return }
        sendWsJson(["type": "undo", "session_id": sid])
    }

    private func sendWsJson(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { _ in }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self?.handleWsMessage(text)
                    default:
                        break
                    }
                    self?.receiveMessage()
                case .failure(let error):
                    self?.isConnected = false
                    self?.showError("WebSocket: \(error.localizedDescription)")
                    self?.scheduleReconnect()
                }
            }
        }
    }

    private func handleWsMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "stream":
            let content = json["content"] as? String ?? ""
            if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                messages[lastIdx].content += content
            }

        case "complete":
            isStreaming = false

        case "ack":
            let action = json["action"] as? String ?? ""
            let files = json["files"] as? [String] ?? []
            messages.append(ChatMessageModel(
                role: "system",
                content: "\(action): \(files.joined(separator: ", "))"
            ))

        case "error":
            let msg = json["message"] as? String ?? "Unknown error"
            isStreaming = false
            showError(msg)

        default:
            break
        }
    }
}

// MARK: - Models

struct ServerStatusResponse: Codable {
    let status: String
    let version: String
    let hostname: String
    let repoPath: String
    let defaultModel: String
    let activeSessions: Int
    let uptimeSeconds: Double
    let cpuPercent: Double
    let memoryMb: Double

    enum CodingKeys: String, CodingKey {
        case status, version, hostname
        case repoPath = "repo_path"
        case defaultModel = "default_model"
        case activeSessions = "active_sessions"
        case uptimeSeconds = "uptime_seconds"
        case cpuPercent = "cpu_percent"
        case memoryMb = "memory_mb"
    }
}

struct SessionSummary: Codable, Identifiable {
    let id: String
    let createdAt: String
    let branch: String
    let model: String
    let messageCount: Int
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, branch, model, active
        case createdAt = "created_at"
        case messageCount = "message_count"
    }
}

struct ChatMessageModel: Identifiable {
    let id = UUID()
    let role: String
    var content: String
    let timestamp = Date()
}
