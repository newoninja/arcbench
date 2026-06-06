import Foundation

class PTYTerminalBackend {
    let masterFd: Int32
    let slaveFd: Int32
    let process: Process
    var onOutput: ((Data) -> Void)?
    private var readSource: DispatchSourceRead?

    init?(mode: TerminalMode, modelOverride: String? = nil) {
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return nil }
        self.masterFd = master
        self.slaveFd = slave
        let flags = fcntl(master, F_GETFL)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        var winSize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &winSize)
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        if mode == .claude {
            env["TERM"] = "dumb"; env["NO_COLOR"] = "1"; env.removeValue(forKey: "COLORTERM")
        } else {
            env["TERM"] = "xterm-256color"; env["COLORTERM"] = "truecolor"
        }
        let proc = Process()
        switch mode {
        case .claude:
            let model = modelOverride ?? "sonnet"
            let paths = ["/usr/local/bin/claude","/opt/homebrew/bin/claude","\(env["HOME"] ?? "")/.npm-global/bin/claude","\(env["HOME"] ?? "")/.local/bin/claude"]
            if let p = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                proc.executableURL = URL(fileURLWithPath: p); proc.arguments = ["--model", model]
            } else { proc.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh"); proc.arguments = ["-l", "-c", "claude --model \(model)"] }
        case .shell:
            proc.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh"); proc.arguments = ["--login"]
        case .swarm:
            proc.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh"); proc.arguments = ["--login"]
        case .grok:
            proc.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh"); proc.arguments = ["--login"]
        case .agents:
            proc.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh"); proc.arguments = ["--login"]
        }
        proc.environment = env
        let wd = UserDefaults.standard.string(forKey: "working_directory") ?? ""
        proc.currentDirectoryURL = wd.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
            : URL(fileURLWithPath: wd)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardInput = slaveHandle; proc.standardOutput = slaveHandle; proc.standardError = slaveHandle
        self.process = proc
        do { try proc.run() } catch { Darwin.close(master); Darwin.close(slave); return nil }
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .global(qos: .userInteractive))
        // Coalesce rapid PTY reads — buffer data and flush at ~30fps max
        var pendingData = Data()
        var flushScheduled = false
        let flushLock = NSLock()
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(self.masterFd, &buf, buf.count)
            guard n > 0 else { return }
            flushLock.lock()
            pendingData.append(contentsOf: buf[0..<n])
            if !flushScheduled {
                flushScheduled = true
                flushLock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.033) { [weak self] in
                    flushLock.lock()
                    let chunk = pendingData
                    pendingData = Data()
                    flushScheduled = false
                    flushLock.unlock()
                    if !chunk.isEmpty { self?.onOutput?(chunk) }
                }
            } else {
                flushLock.unlock()
            }
        }
        source.setCancelHandler { [master] in Darwin.close(master) }
        source.resume()
        self.readSource = source
    }
    func resize(rows: UInt16, cols: UInt16) { var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0); _ = ioctl(masterFd, TIOCSWINSZ, &ws) }
    func write(_ data: Data) { data.withUnsafeBytes { if let b = $0.baseAddress { Darwin.write(masterFd, b, data.count) } } }
    func write(_ s: String) { if let d = s.data(using: .utf8) { write(d) } }
    private var terminated = false
    func terminate() {
        guard !terminated else { return }
        terminated = true
        readSource?.cancel()
        readSource = nil
        if process.isRunning { process.terminate() }
        Darwin.close(slaveFd)
    }
    deinit { terminate() }
}
