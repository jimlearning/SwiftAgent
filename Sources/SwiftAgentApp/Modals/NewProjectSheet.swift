import SwiftUI

/// Sheet for creating a new Project.
struct NewProjectSheet: View {
    let onCreate: (String, String) -> Void

    @State private var name: String = ""
    @State private var path: String = NSHomeDirectory()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.uiHeadline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Project Name")
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
                TextField("My Project", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Folder Path")
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
                HStack {
                    TextField("~/Projects", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK {
                            path = panel.url?.path ?? path
                        }
                    }
                }
                .frame(width: 420)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Create") {
                    onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Project" : name, path)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 480)
    }
}
