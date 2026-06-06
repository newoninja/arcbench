/// IterationCard — Neon-bordered card for each swarm iteration.
/// Replaces plain text bubbles with glowing, status-badged timeline cards.

import SwiftUI

// MARK: - Iteration Card

struct IterationCard: View {
    let event: SwarmEvent
    @State private var appeared = false

    private var isGrok: Bool { event.role == .grok }
    private var color: Color { isGrok ? .accentOrange : .arcBlue }
    private var roleLabel: String { isGrok ? "GROK" : "CLAUDE" }
    private var statusBadge: (String, Color) {
        switch event.phase {
        case .grokPlanning: return ("PLANNING", .accentGrok)
        case .grokJudging: return ("REVIEWING", .accentPurple)
        case .claudeExecuting: return ("EXECUTING", .arcBlue)
        case .approved: return ("APPROVED", .accentGreen)
        case .error: return ("ERROR", .accentRed)
        default: return ("", .textTertiary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack(spacing: 8) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [color.opacity(0.25), color.opacity(0.05)],
                                center: .center, startRadius: 0, endRadius: 18
                            )
                        )
                        .frame(width: 32, height: 32)
                    if isGrok {
                        GrokLogo(size: 16, color: color)
                    } else {
                        ClaudeLogo(size: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(roleLabel)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(color)
                            .tracking(0.5)

                        // Status badge
                        let badge = statusBadge
                        if !badge.0.isEmpty {
                            Text(badge.0)
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundColor(badge.1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(badge.1.opacity(0.12))
                                        .overlay(Capsule().stroke(badge.1.opacity(0.3), lineWidth: 0.5))
                                )
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Iteration \(event.iteration)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.textTertiary)

                        Circle().fill(Color.textTertiary.opacity(0.3)).frame(width: 3, height: 3)

                        Text(timestamp)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                // Iteration number badge
                Text("#\(event.iteration)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(color.opacity(0.5))
                    .frame(minWidth: 30)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Thin separator
            Rectangle()
                .fill(color.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 14)

            // Content
            WordTypewriter(text: event.content, color: color)
                .padding(.horizontal, 0)
                .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.cardBg.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(appeared ? 0.4 : 0.1), color.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: color.opacity(appeared ? 0.15 : 0), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timestamp: String {
        Self.timeFormatter.string(from: Date())
    }
}

// MARK: - Timeline Connector

struct TimelineConnector: View {
    let color: Color
    let isLast: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Dot
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .shadow(color: color.opacity(0.6), radius: 3)
                }

                // Line
                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.3), color.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                }
            }
            .frame(width: 24)
        }
    }
}

// MARK: - Approved Card (subtle)

struct SwarmApprovedCard: View {
    let iteration: Int
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.accentGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text("Task complete")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("\(iteration) iteration\(iteration == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentGreen.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.accentGreen.opacity(0.2), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }
}

// MARK: - Streaming Preview Card

struct StreamingPreviewCard: View {
    let content: String
    @State private var appeared = false
    @State private var pulseOpacity: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.arcBlue.opacity(0.25), Color.arcBlue.opacity(0.05)],
                                center: .center, startRadius: 0, endRadius: 18
                            )
                        )
                        .frame(width: 32, height: 32)
                    ClaudeLogo(size: 14)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("CLAUDE")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.arcBlue)
                            .tracking(0.5)

                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(Color.arcBlue)
                                    .frame(width: 4, height: 4)
                                    .opacity(pulseOpacity)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.2),
                                        value: pulseOpacity
                                    )
                            }
                        }

                        Text("BUILDING")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundColor(.arcBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.arcBlue.opacity(0.12))
                                    .overlay(Capsule().stroke(Color.arcBlue.opacity(0.3), lineWidth: 0.5))
                            )
                    }

                    Text("\(content.count) characters")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.arcBlue.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 14)

            // Live content preview
            livePreview
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.cardBg.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.arcBlue.opacity(0.4), Color.arcBlue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.arcBlue.opacity(appeared ? 0.15 : 0), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
            pulseOpacity = 1.0
        }
    }

    private var livePreview: some View {
        let lines = content.components(separatedBy: "\n")
        let lastLines = Array(lines.suffix(12))
        let preview = lastLines.joined(separator: "\n")

        return VStack(alignment: .leading, spacing: 4) {
            if lines.count > 12 {
                Text("... \(lines.count - 12) more lines above")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textTertiary)
                    .italic()
            }
            Text(preview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.arcBlue.opacity(0.85))
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.codeBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.arcBlue.opacity(0.1), lineWidth: 1)
                )
        )
    }
}
