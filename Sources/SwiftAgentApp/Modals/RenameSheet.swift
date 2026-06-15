import SwiftUI

/// Generic rename sheet for threads and projects.
struct RenameSheet: View {
    let target: RenameTarget
    let onRename: (String) -> Void

    @State private var newName: String = ""
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch target {
        case .thread: return "Rename Chat"
        case .project: return "Rename Project"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.uiHeadline)

            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Rename") {
                    onRename(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : newName)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            newName = "" // Reset
        }
    }
}
