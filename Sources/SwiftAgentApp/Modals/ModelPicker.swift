import SwiftUI

/// Reasoning strength for the model picker menu (per §5.7, §11.5).
public enum ReasoningStrength: String, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case extraHigh = "Extra High"
}

public struct ModelPickerView: View {
    @Binding var selectedModel: DeepSeekModel
    @Binding var reasoningStrength: ReasoningStrength

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left panel: Model
            VStack(alignment: .leading, spacing: 0) {
                Text("Model")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                ForEach(DeepSeekModel.allCases, id: \.rawValue) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Text(model.displayName)
                                .font(.uiBody)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if model == selectedModel {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.accentPrimary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 200)

            Divider()

            // Right panel: Reasoning
            VStack(alignment: .leading, spacing: 0) {
                Text("Reasoning")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                ForEach(ReasoningStrength.allCases, id: \.rawValue) { strength in
                    Button {
                        reasoningStrength = strength
                    } label: {
                        HStack {
                            Text(strength.rawValue)
                                .font(.uiBody)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if strength == reasoningStrength {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.accentPrimary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 160)
        }
        .padding(.vertical, 4)
    }
}
