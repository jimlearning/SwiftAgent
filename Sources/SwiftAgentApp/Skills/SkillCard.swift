import SwiftUI

/// A card showing a single skill in the skills library.
struct SkillCard: View {
    let name: String
    let description: String
    let scope: SkillScope
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.uiLabel)
                            .foregroundColor(.textPrimary)
                        scopeBadge
                    }
                    Text(description)
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentPrimary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var scopeBadge: some View {
        Text(scope.rawValue)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color(hex: scope.badgeColor))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: scope.badgeColor).opacity(0.15))
            )
    }
}

// Color(hex:) defined in DesignSystem/Color.swift
