/// DesignTokens — Single source of truth for all visual constants.
/// Typography, spacing, radii, shadows, animations, semantic colors, and shared modifiers.

import SwiftUI

// MARK: - Typography

enum ArcFont {
    static let xs: Font    = .system(size: 9)
    static let small: Font = .system(size: 10)
    static let caption: Font = .system(size: 11)
    static let label: Font = .system(size: 13)
    static let body: Font  = .system(size: 14)
    static let title: Font = .system(size: 18, weight: .bold)
    static let headline: Font = .system(size: 20, weight: .bold)

    // Mono variants
    static let monoXs: Font    = .system(size: 9, design: .monospaced)
    static let monoSmall: Font = .system(size: 10, design: .monospaced)
    static let monoCaption: Font = .system(size: 11, design: .monospaced)
    static let monoLabel: Font = .system(size: 13, design: .monospaced)
    static let monoBody: Font  = .system(size: 14, design: .monospaced)

    // Weighted variants
    static func body(_ weight: Font.Weight) -> Font { .system(size: 14, weight: weight) }
    static func label(_ weight: Font.Weight) -> Font { .system(size: 13, weight: weight) }
    static func caption(_ weight: Font.Weight) -> Font { .system(size: 11, weight: weight) }
    static func small(_ weight: Font.Weight) -> Font { .system(size: 10, weight: weight) }
    static func xs(_ weight: Font.Weight) -> Font { .system(size: 9, weight: weight) }
    static func title(_ weight: Font.Weight) -> Font { .system(size: 18, weight: weight) }

    // Mono weighted
    static func monoSmall(_ weight: Font.Weight) -> Font { .system(size: 10, weight: weight, design: .monospaced) }
    static func monoCaption(_ weight: Font.Weight) -> Font { .system(size: 11, weight: weight, design: .monospaced) }
    static func monoLabel(_ weight: Font.Weight) -> Font { .system(size: 13, weight: weight, design: .monospaced) }

    // Special sizes used in headings
    static func heading(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 17, weight: .bold)
        case 2: return .system(size: 15, weight: .bold)
        default: return .system(size: 13.5, weight: .bold)
        }
    }

    static let code: Font = .system(size: 12, design: .monospaced)
    static let codeLang: Font = .system(size: 9.5, weight: .semibold, design: .monospaced)
}

// MARK: - Spacing

enum ArcSpacing {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 6
    static let md: CGFloat  = 8
    static let lg: CGFloat  = 12
    static let xl: CGFloat  = 16
    static let xxl: CGFloat = 20
}

// MARK: - Radii

enum ArcRadius {
    static let sm: CGFloat     = 4
    static let md: CGFloat     = 8
    static let lg: CGFloat     = 12
    static let xl: CGFloat     = 16
    static let bubble: CGFloat = 18
    static let bar: CGFloat    = 22
}

// MARK: - Shadows

enum ArcShadow {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
}

// MARK: - Semantic Colors

enum ArcColor {
    static let userBubbleStart = Color.arcBlue.opacity(0.9)
    static let userBubbleEnd   = Color.arcBlue.opacity(0.75)
    static let avatarBg        = Color.arcBlue.opacity(0.08)
    static let cardBgHover     = Color.bgHover
    static let inputBg         = Color.bgTertiary.opacity(0.95)
    static let codeBgHover     = Color.bgTertiary.opacity(0.6)
}

// MARK: - Gradients

enum ArcGradient {
    static let userBubble = LinearGradient(
        colors: [ArcColor.userBubbleStart, ArcColor.userBubbleEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static func avatarGlow(_ color: Color) -> RadialGradient {
        RadialGradient(
            colors: [color.opacity(0.25), color.opacity(0.05)],
            center: .center, startRadius: 0, endRadius: 18
        )
    }
    static func neonBorder(_ color: Color, appeared: Bool = true) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(appeared ? 0.4 : 0.1), color.opacity(0.05)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Animation Presets

enum ArcAnimation {
    static let quick  = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let medium = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let soft   = Animation.spring(response: 0.35, dampingFraction: 0.85)
}

// MARK: - Shared View Modifiers

struct CapsuleButtonModifier: ViewModifier {
    let color: Color
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .foregroundColor(isHovered ? color : .textSecondary)
            .padding(.horizontal, ArcSpacing.lg)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isHovered ? color.opacity(0.10) : Color.bgTertiary.opacity(0.5))
                    .overlay(Capsule().stroke(isHovered ? color.opacity(0.3) : Color.borderSubtle, lineWidth: 1))
            )
            .shadow(color: isHovered ? color.opacity(0.15) : .clear, radius: ArcShadow.md)
            .contentShape(Capsule())
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovered = h } }
    }
}

struct DropOverlayModifier: ViewModifier {
    let color: Color
    let isDropping: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isDropping {
                DropOverlay(color: color)
            }
        }
    }
}

/// Shared drop overlay — used identically in TerminalView and GrokChatView
struct DropOverlay: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ArcRadius.xl, style: .continuous)
                .fill(Color.bgTertiary.opacity(0.95))
                .opacity(0.85)
            RoundedRectangle(cornerRadius: ArcRadius.xl, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2.5, dash: [10, 6]))
                .foregroundColor(color.opacity(0.6))
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 64, height: 64)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(color)
                }
                Text("Drop files here")
                    .font(ArcFont.body(.semibold))
                    .foregroundColor(.textPrimary)
                Text("Files will be attached to your next message")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(ArcSpacing.xxl)
        .allowsHitTesting(false)
    }
}

/// Shared sheet header — used identically in SwarmChatView and GrokChatView settings
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.textTertiary)
            }.buttonStyle(.plain)
        }
    }
}

extension View {
    func capsuleButton(color: Color) -> some View {
        modifier(CapsuleButtonModifier(color: color))
    }

    func dropOverlay(color: Color, isDropping: Bool) -> some View {
        modifier(DropOverlayModifier(color: color, isDropping: isDropping))
    }
}

/// Shared NSOpenPanel utility
func openFilePanel(attachedFiles: Binding<[AttachedFile]>) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    if panel.runModal() == .OK {
        for url in panel.urls {
            if !attachedFiles.wrappedValue.contains(where: { $0.url == url }) {
                withAnimation(ArcAnimation.medium) {
                    attachedFiles.wrappedValue.append(AttachedFile(url: url))
                }
            }
        }
    }
}
