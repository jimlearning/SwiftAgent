import SwiftUI

struct PersonalizationSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var newMemory: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Personalization")

            SettingsRow(label: "Personality") {
                Picker("", selection: $viewModel.personality) {
                    Text("Pragmatic").tag("Pragmatic")
                    Text("Friendly").tag("Friendly")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityLabel("Personality")
            }

            Divider().background(Color.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom instructions")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                TextEditor(text: $viewModel.customInstructions)
                    .font(.system(size: 12))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.borderStrong, lineWidth: 1)
                    )
                    .accessibilityLabel("Custom instructions")
            }

            Divider().background(Color.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Memory")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)

                HStack {
                    TextField("Add a memory...", text: $newMemory)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .font(.system(size: 12))
                    Button("Add") {
                        let trimmed = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.memories.append(trimmed)
                            newMemory = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .accessibilityLabel("Add memory")

                if viewModel.memories.isEmpty {
                    Text("No saved memories")
                        .font(.uiCaption)
                        .foregroundColor(.textTertiary)
                        .padding(.top, 4)
                } else {
                    ForEach(viewModel.memories.indices, id: \.self) { index in
                        HStack {
                            Text("• \(viewModel.memories[index])")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Button {
                                viewModel.memories.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.danger)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .accessibilityLabel("Memory list")

            Spacer()
        }
        .padding(24)
    }
}
