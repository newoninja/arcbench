/// Unified Tailscale status service — shared across ServerManager and ConnectionManager.
/// Runs process checks off the main thread to avoid blocking UI.

import Foundation

@MainActor
class TailscaleService: ObservableObject {
    static let shared = TailscaleService()

    @Published var isConnected = false
    @Published var isInstalled = true
    @Published var ipAddress = ""
    @Published var hostname = ""

    var statusText: String {
        if !isInstalled { return "Not installed" }
        return isConnected ? (hostname.isEmpty ? ipAddress : hostname) : "Not connected"
    }

    private var pollTimer: Timer?

    func startPolling(interval: TimeInterval = 30) {
        check()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in TailscaleService.shared.check() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func check() {
        Task.detached {
            let result = await Self.detectTailscale()
            await MainActor.run { [result] in
                Self.shared.isConnected = result.connected
                Self.shared.isInstalled = result.installed
                Self.shared.ipAddress = result.ip
                Self.shared.hostname = result.hostname
            }
        }
    }

    private static func detectTailscale() async -> (connected: Bool, installed: Bool, ip: String, hostname: String) {
        // Check if tailscale CLI exists
        let which = runProcess(args: ["which", "tailscale"])
        guard !which.isEmpty else { return (false, false, "", "") }

        // Try tailscale CLI for IP
        let ip = runProcess(args: ["tailscale", "ip", "-4"])
        guard !ip.isEmpty else { return (false, true, "", "") }

        // Try to get hostname
        let status = runProcess(args: ["tailscale", "status", "--self", "--json"])
        var hostname = ""
        if let data = status.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let self_ = json["Self"] as? [String: Any],
           let dns = self_["DNSName"] as? String {
            hostname = dns.hasSuffix(".") ? String(dns.dropLast()) : dns
        }

        return (true, true, ip, hostname)
    }

    private static func runProcess(args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard proc.terminationStatus == 0 else { return "" }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
