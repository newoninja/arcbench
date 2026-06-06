/// SwarmStatusBanner — Animated bottom status strip showing current swarm phase.
/// IDLE / PLANNING / EXECUTING / REVIEWING / APPROVED with pulsing SF Symbols.

import SwiftUI

struct SwarmStatusBanner: View {
    @ObservedObject var engine: SwarmEngine
    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -300

    private var bannerState: BannerState {
        if engine.isApproved { return .approved }
        switch engine.phase {
        case .idle: return .idle
        case .grokPlanning: return .planning
        case .claudeExecuting: return .executing
        case .grokJudging: return .reviewing
        case .approved: return .approved
        case .error: return .error
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: animated icon
            ZStack {
                // Glow circle behind icon
                Circle()
                    .fill(bannerState.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .scaleEffect(pulseScale)

                Image(systemName: bannerState.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(bannerState.color)
                    .scaleEffect(pulseScale)
                    .symbolEffect(.pulse, options: engine.isRunning ? .repeating : .default, value: engine.isRunning)
            }
            .frame(width: 50)

            // Center: status text
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerState.label)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(bannerState.color)
                    .tracking(2)
                    .lineLimit(1)

                if engine.isRunning {
                    Text(bannerState.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Right: iteration + elapsed
            if engine.isRunning || engine.isApproved {
                HStack(spacing: 12) {
                    // Iteration
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.textTertiary)
                        Text("\(engine.iteration)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(bannerState.color)
                    }

                    // Phase dots
                    HStack(spacing: 3) {
                        PhaseDot(active: engine.phase == .grokPlanning, color: .accentGrok)
                        PhaseDot(active: engine.phase == .claudeExecuting, color: .arcBlue)
                        PhaseDot(active: engine.phase == .grokJudging, color: .accentPurple)
                        PhaseDot(active: engine.phase == .approved, color: .accentGreen)
                    }
                }
                .padding(.trailing, 14)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(Color.bgSecondary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [bannerState.color.opacity(0.4), bannerState.color.opacity(0.02)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .onAppear { startAnimations() }
        .onChange(of: engine.phase) { _, _ in startAnimations() }
    }

    private func startAnimations() {
        // Pulse
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = engine.isRunning ? 1.15 : 1.0
        }
        // Shimmer
        if engine.isRunning {
            shimmerOffset = -300
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 300
            }
        }
    }
}

// MARK: - Phase Dot

private struct PhaseDot: View {
    let active: Bool
    let color: Color

    var body: some View {
        Circle()
            .fill(active ? color : color.opacity(0.15))
            .frame(width: 6, height: 6)
            .shadow(color: active ? color.opacity(0.6) : .clear, radius: 3)
            .animation(.easeInOut(duration: 0.3), value: active)
    }
}

// MARK: - Banner State

private enum BannerState {
    case idle, planning, executing, reviewing, approved, error

    var label: String {
        switch self {
        case .idle: return "IDLE"
        case .planning: return "PLANNING"
        case .executing: return "EXECUTING"
        case .reviewing: return "REVIEWING"
        case .approved: return "APPROVED"
        case .error: return "ERROR"
        }
    }

    var subtitle: String {
        switch self {
        case .idle: return ""
        case .planning: return "Grok is crafting instructions..."
        case .executing: return "Claude is building..."
        case .reviewing: return "Grok is inspecting output..."
        case .approved: return "All checks passed"
        case .error: return "Something went wrong"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "pause.circle.fill"
        case .planning: return "brain.head.profile"
        case .executing: return "hammer.fill"
        case .reviewing: return "magnifyingglass"
        case .approved: return "rocket.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .textTertiary
        case .planning: return .accentOrange
        case .executing: return .arcBlue
        case .reviewing: return .accentPurple
        case .approved: return .accentGreen
        case .error: return .accentRed
        }
    }
}
