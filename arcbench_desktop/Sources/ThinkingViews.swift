/// ThinkingViews — ThinkingBubble and ThinkingIndicator components.
/// Shows tool activity and animated "thinking" state for Claude.

import SwiftUI

// MARK: - Thinking Bubble

struct ThinkingBubble: View {
    let segments: [ClaudeSegment]
    @Binding var isExpanded: Bool

    private var toolCount: Int { segments.filter { if case .toolUse = $0 { return true }; return false }.count }
    private var summary: String {
        let tools = segments.compactMap { s -> String? in if case .toolUse(_, let n, _) = s { return n }; return nil }
        let u = Array(Set(tools))
        return u.count == 1 ? "\(toolCount) \(u[0]) action\(toolCount == 1 ? "" : "s")" : "\(toolCount) action\(toolCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ArcAnimation.quick) { isExpanded.toggle() }
            } label: {
                HStack(spacing: ArcSpacing.sm) {
                    Image(systemName: "brain.head.profile").font(ArcFont.small(.medium)).foregroundColor(.accentPurple)
                    Text("Thinking").font(ArcFont.caption(.semibold)).foregroundColor(.accentPurple)
                    Text("·").foregroundColor(.textTertiary)
                    Text(summary).font(.system(size: 10.5)).foregroundColor(.textTertiary).lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(ArcFont.xs(.semibold)).foregroundColor(.textTertiary)
                }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: ArcSpacing.xs) {
                    ForEach(segments) { seg in
                        switch seg {
                        case .toolUse(let icon, let name, let detail):
                            HStack(spacing: ArcSpacing.sm) {
                                Image(systemName: icon).font(ArcFont.xs(.medium)).foregroundColor(.accentPurple.opacity(0.7)).frame(width: 16)
                                Text(name).font(.system(size: 10.5, weight: .medium)).foregroundColor(.textSecondary)
                                Text(detail).font(ArcFont.monoSmall).foregroundColor(.textTertiary).lineLimit(1).truncationMode(.middle)
                            }.padding(.horizontal, 10).padding(.vertical, 2)
                        case .treeDetail(let path):
                            Text(path).font(ArcFont.monoSmall).foregroundColor(.textTertiary).padding(.horizontal, 10).padding(.vertical, 1)
                        case .text: EmptyView()
                        }
                    }
                }.padding(.bottom, ArcSpacing.md).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentPurple.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.accentPurple.opacity(0.15), lineWidth: 1))
        )
    }
}

// MARK: - Thinking Indicator (animated)

struct ThinkingIndicator: View {
    @State private var animating = false
    @State private var statusIndex = 0
    @State private var statusOpacity: Double = 1.0
    @State private var glowScale: CGFloat = 1.0
    private let statuses = ["Thinking", "Reasoning", "Analyzing", "Working"]
    private let timer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.arcBlue.opacity(0.06)).frame(width: 36, height: 36).scaleEffect(glowScale)
                Circle().fill(Color.arcBlue.opacity(0.12)).frame(width: 30, height: 30)
                ClaudeLogo(size: 16)
            }.padding(.top, 2)

            VStack(alignment: .leading, spacing: ArcSpacing.xs) {
                Text("Claude").font(ArcFont.caption(.semibold)).foregroundColor(.textTertiary)
                HStack(spacing: 10) {
                    HStack(spacing: 2.5) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(LinearGradient(colors: [.arcBlue, .arcBlue.opacity(0.5)], startPoint: .bottom, endPoint: .top))
                                .frame(width: 3, height: animating ? [CGFloat(10),16,12,18,8][i] : 4)
                                .animation(.easeInOut(duration: [0.5,0.4,0.6,0.35,0.55][i]).repeatForever(autoreverses: true).delay(Double(i)*0.12), value: animating)
                        }
                    }.frame(height: 18, alignment: .center)
                    Text(statuses[statusIndex]).font(ArcFont.label(.medium)).foregroundColor(.textTertiary)
                        .opacity(statusOpacity).animation(.easeInOut(duration: 0.3), value: statusOpacity)
                }
                .padding(.horizontal, ArcSpacing.xl).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.cardBg)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.borderSubtle, lineWidth: 1))
                )
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, ArcSpacing.xl)
        .onAppear {
            animating = true
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { glowScale = 1.25 }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeOut(duration: 0.2)) { statusOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                statusIndex = (statusIndex + 1) % statuses.count
                withAnimation(.easeIn(duration: 0.3)) { statusOpacity = 1.0 }
            }
        }
    }
}
