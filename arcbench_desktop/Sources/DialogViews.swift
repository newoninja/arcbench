/// DialogViews — Permission, Trust, and Trusted banner cards.
/// Shown during Claude Code's trust/permission flow.

import SwiftUI

// MARK: - Permission Card

struct PermissionCard: View {
    let context: String; let onRespond: (Bool) -> Void
    @State private var hoverAllow = false; @State private var hoverDeny = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack { RoundedRectangle(cornerRadius: ArcRadius.md).fill(Color.accentOrange.opacity(0.15)).frame(width: 32, height: 32); Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(.accentOrange) }
                Text("Permission Required").font(ArcFont.label(.bold)).foregroundColor(.textPrimary)
            }
            Text(context).font(.system(size: 12)).foregroundColor(.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { withAnimation { onRespond(true) } } label: {
                    HStack(spacing: 5) { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)); Text("Allow").font(ArcFont.label(.semibold)) }
                    .foregroundColor(.white).padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.md)
                    .background(RoundedRectangle(cornerRadius: ArcRadius.md).fill(hoverAllow ? Color.accentGreen : Color.accentGreen.opacity(0.85)))
                    .shadow(color: hoverAllow ? Color.accentGreen.opacity(0.3) : .clear, radius: ArcShadow.md)
                }.buttonStyle(.plain).onHover { hoverAllow = $0 }

                Button { withAnimation { onRespond(false) } } label: {
                    Text("Deny").font(ArcFont.label(.medium)).foregroundColor(.textSecondary)
                        .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.md)
                        .background(RoundedRectangle(cornerRadius: ArcRadius.md).fill(hoverDeny ? Color.bgHover : Color.bgTertiary).overlay(RoundedRectangle(cornerRadius: ArcRadius.md).stroke(Color.borderMedium, lineWidth: 1)))
                }.buttonStyle(.plain).onHover { hoverDeny = $0 }
            }
        }.padding(ArcSpacing.xl)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: WidthPreferenceKey.self, value: geometry.size.width)
            }
        )
        .frame(maxWidth: 500, alignment: .leading)
        .glassMorphism(cornerRadius: ArcRadius.lg, stroke: .accentOrange, strokeOpacity: 0.25)
    }
}

// MARK: - Trust Card

struct TrustCard: View {
    let folder: String; let onRespond: (Bool) -> Void
    @State private var hoverYes = false; @State private var hoverNo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack { RoundedRectangle(cornerRadius: ArcRadius.md).fill(Color.accentOrange.opacity(0.15)).frame(width: 32, height: 32); Image(systemName: "shield.lefthalf.filled").font(.system(size: 14, weight: .semibold)).foregroundColor(.accentOrange) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workspace Trust Required").font(ArcFont.label(.bold)).foregroundColor(.textPrimary)
                    Text(folder).font(ArcFont.monoCaption).foregroundColor(.textTertiary).lineLimit(1).truncationMode(.tail)
                }
            }
            Text("Claude Code needs permission to read, edit, and execute files here.").font(.system(size: 12.5)).foregroundColor(.textSecondary)
            HStack(spacing: 10) {
                Button { withAnimation { onRespond(true) } } label: {
                    HStack(spacing: 5) { Image(systemName: "checkmark.shield.fill").font(.system(size: 12)); Text("Trust Folder").font(ArcFont.label(.semibold)) }
                    .foregroundColor(.white).padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.md)
                    .background(RoundedRectangle(cornerRadius: ArcRadius.md).fill(hoverYes ? Color.accentGreen : Color.accentGreen.opacity(0.85)))
                    .shadow(color: hoverYes ? Color.accentGreen.opacity(0.3) : .clear, radius: ArcShadow.md)
                }.buttonStyle(.plain).onHover { hoverYes = $0 }

                Button { withAnimation { onRespond(false) } } label: {
                    Text("Don't Trust").font(ArcFont.label(.medium)).foregroundColor(.textSecondary)
                        .padding(.horizontal, ArcSpacing.xl).padding(.vertical, ArcSpacing.md)
                        .background(RoundedRectangle(cornerRadius: ArcRadius.md).fill(hoverNo ? Color.bgHover : Color.bgTertiary).overlay(RoundedRectangle(cornerRadius: ArcRadius.md).stroke(Color.borderMedium, lineWidth: 1)))
                }.buttonStyle(.plain).onHover { hoverNo = $0 }
            }
        }.padding(ArcSpacing.xl).frame(maxWidth: 500, alignment: .leading).glassMorphism(cornerRadius: ArcRadius.lg, stroke: .accentOrange, strokeOpacity: 0.25)
    }
}

// MARK: - Trusted Banner

struct TrustedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack { Circle().fill(Color.accentGreen.opacity(0.15)).frame(width: 28, height: 28); Image(systemName: "checkmark.shield.fill").font(ArcFont.label).foregroundColor(.accentGreen) }
            VStack(alignment: .leading, spacing: 1) {
                Text("Workspace Trusted").font(ArcFont.label(.semibold)).foregroundColor(.accentGreen)
                Text("Claude Code can now read, edit, and execute files.").font(.system(size: 11.5)).foregroundColor(.textTertiary)
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentGreen.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentGreen.opacity(0.2), lineWidth: 1)))
    }
}

// MARK: - Width Preference Key (for responsive layout)

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
