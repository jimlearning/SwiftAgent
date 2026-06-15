import SwiftUI

/// View model for the Composer input area.
@MainActor
public final class ComposerViewModel: ObservableObject {
    /// Current text in the composer.
    @Published public var text: String = ""

    /// Whether the send button should be enabled.
    @Published public var isSendEnabled: Bool = false

    /// Whether the composer is showing the sending state.
    @Published public var isSending: Bool = false

    /// The currently selected permission mode.
    @Published public var permissionMode: PermissionMode = .custom

    /// The currently selected reasoning strength.
    @Published public var reasoningStrength: ReasoningStrength = .high

    /// The currently selected model.
    @Published public var selectedModel: DeepSeekModel = .v3

    /// Whether the add menu is shown.
    @Published public var showAddMenu: Bool = false

    /// Whether the permission picker is shown.
    @Published public var showPermissionPicker: Bool = false

    /// Whether the model picker is shown.
    @Published public var showModelPicker: Bool = false

    public init() {}

    /// Clear the composer text.
    public func clear() {
        text = ""
        isSendEnabled = false
    }

    /// Update send-button enabled state based on text content.
    public func updateSendEnabled() {
        isSendEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Permission mode for agent actions (per §5.4).
public enum PermissionMode: String, CaseIterable, Sendable {
    case askForApproval = "Ask for approval"
    case approveForMe = "Approve for me"
    case fullAccess = "Full access"
    case custom = "Custom (config.toml)"

    public var iconName: String {
        switch self {
        case .askForApproval: return "hand.raised"
        case .approveForMe: return "timer"
        case .fullAccess: return "shield"
        case .custom: return "gearshape"
        }
    }

    public var description: String {
        switch self {
        case .askForApproval:
            return "Always ask to edit external files and use the internet"
        case .approveForMe:
            return "Only ask for actions detected as potentially unsafe"
        case .fullAccess:
            return "Unrestricted access to the internet and any file on your computer"
        case .custom:
            return "Uses permissions defined in config.toml"
        }
    }
}
