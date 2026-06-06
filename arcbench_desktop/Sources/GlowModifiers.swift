/// Shared view modifiers for ArcBench premium UI — glow, glass, pulse, hover effects.

import SwiftUI

// MARK: - Arc Glow Shadow

struct ArcGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(opacity * 0.5), radius: radius * 0.5, x: 0, y: 2)
    }
}

extension View {
    func arcGlow(_ color: Color = .arcBlue, radius: CGFloat = 10, opacity: Double = 0.6) -> some View {
        modifier(ArcGlowModifier(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - Pulse Glow (breathing animation)

struct PulseGlowModifier: ViewModifier {
    let color: Color
    let minOpacity: Double
    let maxOpacity: Double
    let duration: Double
    @State private var glowing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(glowing ? maxOpacity : minOpacity), radius: glowing ? 14 : 6)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
    }
}

extension View {
    func pulseGlow(_ color: Color = .arcBlue, min: Double = 0.2, max: Double = 0.7, duration: Double = 2.0) -> some View {
        modifier(PulseGlowModifier(color: color, minOpacity: min, maxOpacity: max, duration: duration))
    }
}

// MARK: - Glassmorphism

struct GlassMorphismModifier: ViewModifier {
    let cornerRadius: CGFloat
    let strokeColor: Color
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor.opacity(strokeOpacity), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassMorphism(cornerRadius: CGFloat = 12, stroke: Color = .arcBlue, strokeOpacity: Double = 0.2) -> some View {
        modifier(GlassMorphismModifier(cornerRadius: cornerRadius, strokeColor: stroke, strokeOpacity: strokeOpacity))
    }
}

// MARK: - Hover Scale + Glow

struct HoverGlowModifier: ViewModifier {
    let color: Color
    let scale: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .shadow(color: isHovered ? color.opacity(0.5) : .clear, radius: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in isHovered = hovering }
    }
}

extension View {
    func hoverGlow(_ color: Color = .arcBlue, scale: CGFloat = 1.08) -> some View {
        modifier(HoverGlowModifier(color: color, scale: scale))
    }
}

// MARK: - Breathing Scale

struct BreathingScaleModifier: ViewModifier {
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double
    @State private var scale: CGFloat

    init(minScale: CGFloat = 0.97, maxScale: CGFloat = 1.03, duration: Double = 2.5) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.duration = duration
        _scale = State(initialValue: minScale)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    scale = maxScale
                }
            }
    }
}

extension View {
    func breathingScale(min: CGFloat = 0.97, max: CGFloat = 1.03, duration: Double = 2.5) -> some View {
        modifier(BreathingScaleModifier(minScale: min, maxScale: max, duration: duration))
    }
}

// MARK: - Neon Underline

struct NeonUnderlineModifier: ViewModifier {
    let color: Color
    let isActive: Bool
    let width: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isActive {
                Capsule()
                    .fill(color)
                    .frame(height: width)
                    .shadow(color: color.opacity(0.7), radius: 6, y: 2)
                    .padding(.horizontal, 6)
            }
        }
    }
}

extension View {
    func neonUnderline(_ color: Color = .arcBlue, active: Bool = true, width: CGFloat = 2) -> some View {
        modifier(NeonUnderlineModifier(color: color, isActive: active, width: width))
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    let color: Color
    let duration: Double
    @State private var offset: CGFloat = -200

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, color.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: offset)
                .clipShape(Rectangle())
            )
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    offset = 200
                }
            }
    }
}

extension View {
    func shimmer(_ color: Color = .arcBlue, duration: Double = 2.5) -> some View {
        modifier(ShimmerModifier(color: color, duration: duration))
    }
}

// MARK: - Gradient Border

struct GradientBorderModifier: ViewModifier {
    let colors: [Color]
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: lineWidth
                )
        )
    }
}

extension View {
    func gradientBorder(colors: [Color] = [.arcBlue.opacity(0.3), .accentPurple.opacity(0.2), .arcBlue.opacity(0.1)], cornerRadius: CGFloat = 12, lineWidth: CGFloat = 1) -> some View {
        modifier(GradientBorderModifier(colors: colors, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}

// MARK: - Status Dot (pulsing)

struct StatusDot: View {
    let color: Color
    let size: CGFloat
    var pulse: Bool = false
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if pulse {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: size * 2.2, height: size * 2.2)
                    .scaleEffect(pulsing ? 1.4 : 0.8)
                    .opacity(pulsing ? 0 : 0.6)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: pulsing)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: 4)
        }
        .onAppear { pulsing = true }
    }
}
