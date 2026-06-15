import SwiftUI

/// Double-layer menu (per §5.7, §11.2):
/// Left: Reasoning strength (Low / Medium / High / Extra High)
/// Right: Model (DeepSeek-V3 / DeepSeek-R1 / DeepSeek-V3-0324 / DeepSeek-Coder-V2)
///
/// Only 4 fixed DeepSeek models — no custom model names (anti-pattern #22).
public struct ModelPickerView: View {
    @Binding var selectedModel: DeepSeekModel
    @Binding var reasoningStrength: ReasoningStrength

    public var body: some View {
        HStack(spacing: 0) {
            // Left panel: Reasoning strength
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

            Divider()

            // Right panel: Model
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
        }
        .padding(.vertical, 4)
    }
}
