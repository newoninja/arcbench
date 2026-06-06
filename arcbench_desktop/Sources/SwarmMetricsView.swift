/// SwarmMetricsView — Compact left-panel metrics: Phase, Iterations, Tokens, System.
/// Clean horizontal bars with subtle color accents.

import SwiftUI

// MARK: - Metrics Panel (left sidebar)

struct SwarmMetricsView: View {
    @ObservedObject var engine: SwarmEngine
    @State private var cpuUsage: Double = 0
    @State private var memoryUsage: Double = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase Badge (top)
            HStack(spacing: 8) {
                StatusDot(color: phaseColor, size: 7, pulse: engine.isRunning)
                Text(engine.phase.rawValue)
                    .font(ArcFont.monoSmall(.bold))
                    .foregroundColor(phaseColor)
                    .lineLimit(1)
                Spacer()
                if engine.isRunning {
                    Text("ITER \(engine.iteration)")
                        .font(ArcFont.monoSmall(.heavy))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(phaseColor.opacity(0.04))

            Rectangle().fill(Color.borderSubtle).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {

                    // Iteration Progress
                    MetricSection(title: "PROGRESS") {
                        MetricBar(
                            label: "Iterations",
                            value: Double(engine.iteration),
                            total: Double(engine.maxIterations),
                            text: "\(engine.iteration) / \(engine.maxIterations)",
                            color: iterationColor
                        )
                        if engine.iteration >= engine.maxIterations - 2 && engine.isRunning {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8)).foregroundColor(.accentRed)
                                Text("Near limit")
                                    .font(ArcFont.xs(.semibold)).foregroundColor(.accentRed)
                            }
                        }
                    }

                    // Tokens
                    MetricSection(title: "TOKENS") {
                        TokenRow(icon: "bolt.fill", label: "Grok", count: engine.grokTokens, color: .accentGrok)
                        TokenRow(icon: "circle.hexagongrid.fill", label: "Claude", count: engine.claudeTokens, color: .arcBlue)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1)
                        TokenRow(icon: "sum", label: "Total", count: engine.grokTokens + engine.claudeTokens, color: .textSecondary)
                    }

                    // System
                    MetricSection(title: "SYSTEM") {
                        MetricBar(
                            label: "CPU",
                            value: cpuUsage,
                            total: 100,
                            text: String(format: "%.0f%%", cpuUsage),
                            color: cpuUsage > 80 ? .accentRed : cpuUsage > 50 ? .accentOrange : .accentGreen
                        )
                        MetricBar(
                            label: "Memory",
                            value: memoryUsage,
                            total: 100,
                            text: String(format: "%.0f%%", memoryUsage),
                            color: memoryUsage > 80 ? .accentRed : memoryUsage > 50 ? .accentOrange : .arcBlue
                        )
                    }
                }
                .padding(14)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 180)
        .background(Color.bgSecondary)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.borderSubtle).frame(width: 1)
        }
        .onAppear { startMonitoring() }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - Helpers

    private var iterationColor: Color {
        if engine.isApproved { return .accentGreen }
        let ratio = Double(engine.iteration) / Double(engine.maxIterations)
        if ratio > 0.75 { return .accentRed }
        if ratio > 0.5 { return .accentOrange }
        return .arcBlue
    }

    private var phaseColor: Color {
        switch engine.phase {
        case .idle: return .textTertiary
        case .grokPlanning: return .accentGrok
        case .claudeExecuting: return .arcBlue
        case .grokJudging: return .accentPurple
        case .approved: return .accentGreen
        case .error: return .accentRed
        }
    }

    private func startMonitoring() {
        (cpuUsage, memoryUsage) = Self.systemMetrics()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                let (cpu, mem) = Self.systemMetrics()
                withAnimation(.easeInOut(duration: 0.6)) {
                    cpuUsage = cpu
                    memoryUsage = mem
                }
            }
        }
    }

    private static var prevUser: Double = 0
    private static var prevSys: Double = 0
    private static var prevIdle: Double = 0
    private static var prevNice: Double = 0

    private static func systemMetrics() -> (cpu: Double, memory: Double) {
        var cpuPct: Double = 0
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let cpuResult = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        if cpuResult == KERN_SUCCESS {
            let user = Double(cpuInfo.cpu_ticks.0)
            let sys = Double(cpuInfo.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3)
            let dUser = user - prevUser
            let dSys = sys - prevSys
            let dIdle = idle - prevIdle
            let dNice = nice - prevNice
            let dTotal = dUser + dSys + dIdle + dNice
            if dTotal > 0 {
                cpuPct = ((dUser + dSys + dNice) / dTotal) * 100
            }
            prevUser = user; prevSys = sys; prevIdle = idle; prevNice = nice
        }

        var memPct: Double = 0
        var vmStats = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let active = Double(vmStats.active_count) * pageSize
            let wired = Double(vmStats.wire_count) * pageSize
            let compressed = Double(vmStats.compressor_page_count) * pageSize
            let totalRAM = Double(ProcessInfo.processInfo.physicalMemory)
            if totalRAM > 0 { memPct = ((active + wired + compressed) / totalRAM) * 100 }
        }

        mach_port_deallocate(mach_task_self_, hostPort)
        return (min(cpuPct, 100), min(memPct, 100))
    }
}

// MARK: - Section Container

private struct MetricSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.textTertiary)
                .tracking(1)
            content
        }
    }
}

// MARK: - Horizontal Bar Metric

private struct MetricBar: View {
    let label: String
    let value: Double
    let total: Double
    let text: String
    let color: Color

    private var progress: Double { total > 0 ? min(value / total, 1.0) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(ArcFont.xs(.medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(text)
                    .font(ArcFont.monoSmall(.bold))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(geo.size.width * progress, 2))
                        .shadow(color: color.opacity(0.4), radius: 3)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Token Row

private struct TokenRow: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(color)
                .frame(width: 14)
            Text(label)
                .font(ArcFont.xs(.medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(formatTokens(count))
                .font(ArcFont.monoSmall(.bold))
                .foregroundColor(color)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }
}
