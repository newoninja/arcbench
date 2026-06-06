/// ActionOverlay — Animated HUD that appears when ArcBench performs computer control actions.
/// Shows a cinematic pulse → icon → label → success/fail sequence.

import SwiftUI

// MARK: - Action Overlay (main HUD)

struct ActionOverlay: View {
    @EnvironmentObject var computerControl: ComputerControlService

    var body: some View {
        ZStack {
            if let action = computerControl.activeAction {
                ActionHUD(action: action)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity),
                            removal: .scale(scale: 1.1).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: computerControl.activeAction)
    }
}

// MARK: - Action HUD Card

struct ActionHUD: View {
    let action: ActiveAction
    @State private var ringRotation: Double = 0
    @State private var iconScale: CGFloat = 0.3
    @State private var labelOpacity: Double = 0
    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 0.8
    @State private var particlesVisible = false
    @State private var shimmerOffset: CGFloat = -120

    private var color: Color { action.action.color }
    private var phase: ActionPhase { action.phase }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Ripple rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(color.opacity(0.15 - Double(i) * 0.04), lineWidth: 1.5)
                        .frame(width: 90 + CGFloat(i) * 30, height: 90 + CGFloat(i) * 30)
                        .scaleEffect(rippleScale + CGFloat(i) * 0.1)
                        .opacity(rippleOpacity - Double(i) * 0.2)
                }

                // Spinning arc ring
                Circle()
                    .trim(from: 0, to: phase == .running ? 0.7 : 1.0)
                    .stroke(
                        AngularGradient(
                            colors: [color, color.opacity(0.3), .clear],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(ringRotation))

                // Glow backdrop
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.25), color.opacity(0.05), .clear],
                            center: .center,
                            startRadius: 0, endRadius: 50
                        )
                    )
                    .frame(width: 80, height: 80)

                // Icon
                ZStack {
                    if phase == .success {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.accentGreen)
                            .transition(.scale.combined(with: .opacity))
                    } else if phase == .failure {
                        Image(systemName: "xmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.accentRed)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: action.action.icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(color)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(iconScale)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: phase)

                // Particle burst on success
                if phase == .success && particlesVisible {
                    ParticleBurst(color: color, count: 12)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Label
            VStack(spacing: 4) {
                Text(action.action.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                if phase == .running {
                    HStack(spacing: 4) {
                        BouncingDots(color: color, size: 4)
                    }
                    .transition(.opacity)
                } else if phase == .success {
                    Text("Done")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentGreen)
                        .transition(.scale.combined(with: .opacity))
                } else if phase == .failure {
                    Text("Failed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentRed)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: 280)
            .opacity(labelOpacity)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.bgSecondary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .overlay(
            // Shimmer sweep
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, color.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .offset(x: shimmerOffset)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .shadow(color: color.opacity(0.3), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .onAppear {
            // Entrance sequence
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                iconScale = 1.0
                rippleScale = 1.0
                rippleOpacity = 0.6
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                labelOpacity = 1.0
            }
            // Spinning ring
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            // Shimmer
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                shimmerOffset = 120
            }
            // Ripple pulse
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                rippleScale = 1.15
                rippleOpacity = 0.2
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .success {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    particlesVisible = true
                }
                // Dismiss particles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation { particlesVisible = false }
                }
            }
        }
    }
}

// MARK: - Particle Burst

struct ParticleBurst: View {
    let color: Color
    let count: Int
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(color.opacity(Double.random(in: 0.4...0.9)))
                    .frame(width: CGFloat.random(in: 3...6), height: CGFloat.random(in: 3...6))
                    .offset(
                        x: fired ? CGFloat.random(in: -50...50) : 0,
                        y: fired ? CGFloat.random(in: -50...50) : 0
                    )
                    .opacity(fired ? 0 : 1)
                    .scaleEffect(fired ? 0.2 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                fired = true
            }
        }
    }
}

// MARK: - Bouncing Dots (loading indicator)

struct BouncingDots: View {
    let color: Color
    let size: CGFloat
    @State private var offsets: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: size * 0.8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .offset(y: offsets[i])
            }
        }
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.45)
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.15)
                ) {
                    offsets[i] = -size * 1.5
                }
            }
        }
    }
}

// MARK: - Action History Strip (mini pills at bottom)

struct ActionHistoryStrip: View {
    @EnvironmentObject var computerControl: ComputerControlService

    var body: some View {
        if !computerControl.recentActions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(computerControl.recentActions.prefix(5)) { action in
                        HStack(spacing: 4) {
                            Image(systemName: action.action.icon)
                                .font(.system(size: 9))
                            Text(action.action.label)
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                        .foregroundColor(action.phase == .success ? .accentGreen : .accentRed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(action.action.color.opacity(0.08))
                                .overlay(Capsule().stroke(action.action.color.opacity(0.15), lineWidth: 0.5))
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
