/// Manages the FastAPI backend server process lifecycle.
/// Uses shared TailscaleService instead of duplicate checks.

import Foundation
import SwiftUI

@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var logs: [String] = []
    @Published var pid: Int32?
    @Published var crashCount = 0

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var intentionalStop = false
    private static let maxAutoRestarts = 5

    /// Project root — uses env var or derives from known location
    private var projectRoot: String {
        if let envPath = ProcessInfo.processInfo.environment["ARCBENCH_PROJECT_ROOT"] {
            return envPath
        }
        // Walk up from executable to find gymclaw
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Desktop/Potential App/gymclaw",
            "\(home)/gymclaw",
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: "\(candidate)/backend/main.py") {
                return candidate
            }
        }
        return "\(home)/Desktop/Potential App/gymclaw"
    }

    private var venvPython: String { "\(projectRoot)/.venv/bin/python" }
    private var backendDir: String { "\(projectRoot)/backend" }

    func start() {
        guard !isRunning else { return }
        intentionalStop = false

        // Kill any stale process on port 8000 before starting
        killStaleProcess(port: 8000)

        // Start Tailscale polling
        TailscaleService.shared.startPolling()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: venvPython)
        proc.arguments = ["main.py"]
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDir)

        // Load environment from .env
        var env = ProcessInfo.processInfo.environment
        let envFile = "\(projectRoot)/.env"
        if let envContents = try? String(contentsOfFile: envFile, encoding: .utf8) {
            for line in envContents.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    env[String(parts[0])] = String(parts[1])
                }
            }
        }
        proc.environment = env

        outputPipe = Pipe()
        errorPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                Task { @MainActor in self?.appendLog(str) }
            }
        }

        errorPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                Task { @MainActor in self?.appendLog("[ERR] \(str)") }
            }
        }

        proc.terminationHandler = { [weak self] terminatedProc in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.pid = nil

                let exitCode = terminatedProc.terminationStatus
                if self.intentionalStop {
                    self.appendLog("[Server stopped]")
                } else if exitCode != 0 {
                    self.crashCount += 1
                    self.appendLog("[Server crashed — exit code \(exitCode), crash #\(self.crashCount)]")
                    if self.crashCount <= ServerManager.maxAutoRestarts {
                        self.appendLog("[Auto-restarting in 2s...]")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.start()
                        }
                    } else {
                        self.appendLog("[Too many crashes (\(self.crashCount)), not restarting. Use Start to retry.]")
                    }
                } else {
                    self.appendLog("[Server exited cleanly]")
                }
            }
        }

        do {
            try proc.run()
            process = proc
            pid = proc.processIdentifier
            isRunning = true
            appendLog("[Server started — PID \(proc.processIdentifier)]")
        } catch {
            appendLog("[Failed to start: \(error.localizedDescription)]")
        }
    }

    func stop() {
        intentionalStop = true
        crashCount = 0
        TailscaleService.shared.stopPolling()
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if proc.isRunning { proc.interrupt() }
        }
    }

    func openDashboard() {
        if let url = URL(string: "\(AppSettings.shared.serverURL)/docs") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Kill any process already listening on the given port
    private func killStaleProcess(port: Int) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else { return }
            for pidStr in output.components(separatedBy: "\n") {
                if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) {
                    kill(pid, SIGTERM)
                    appendLog("[Killed stale process on port \(port) — PID \(pid)]")
                }
            }
            usleep(500_000) // 0.5s for process to exit
        } catch {}
    }

    private func appendLog(_ text: String) {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        logs.append(contentsOf: lines)
        if logs.count > 500 { logs = Array(logs.suffix(500)) }
    }
}
