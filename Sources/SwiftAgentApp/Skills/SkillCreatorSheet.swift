import SwiftUI

/// A wizard sheet for creating a new skill.
struct SkillCreatorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var scope: SkillScope = .user
    @State private var bodyText: String = """
## When to use
- 

## When NOT to use
- 

## Workflow
1. 
2. 

## Output format
- 

## Notes
- 
"""

    var onSave: ((String, String, SkillScope, String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Skill")
                .font(.uiHeadline)
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                    TextField("skill-name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.uiBody)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                    TextField("A short description the AI uses for routing", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.uiBody)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scope")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                    Picker("Scope", selection: $scope) {
                        ForEach(SkillScope.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Body")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                    TextEditor(text: $bodyText)
                        .font(.codeMono)
                        .frame(height: 200)
                        .border(Color.borderStrong, width: 1)
                        .cornerRadius(4)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Create") {
                    onSave?(name.trimmingCharacters(in: .whitespaces),
                            description.trimmingCharacters(in: .whitespaces),
                            scope,
                            bodyText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || description.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540, height: 580)
    }
}
