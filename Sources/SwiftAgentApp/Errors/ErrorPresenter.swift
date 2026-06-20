import SwiftUI

// MARK: - Error Presenter

/// Observable object that manages error presentation across the app.
///
/// `AppError` cases are defined in `ErrorTaxonomy.swift` — this presenter
/// is responsible only for display state: which errors are active, which
/// severity mode is visible, and how errors transition between states.
@MainActor
final class ErrorPresenter: ObservableObject {
    @Published var activeErrors: [AppError] = []
    @Published var showModal: Bool = false
    @Published var currentModalError: AppError?

    static let shared = ErrorPresenter()

    /// Present a fatal error as a modal.
    func presentModal(_ error: AppError) {
        currentModalError = error
        showModal = true
    }

    /// Add a retryable or warning error to the stack.
    func present(_ error: AppError) {
        switch error.severity {
        case .fatal:
            presentModal(error)
        case .retryable, .warning:
            if !activeErrors.contains(where: { $0.id == error.id }) {
                activeErrors.append(error)
            }
        }
    }

    /// Dismiss a specific error.
    func dismiss(_ error: AppError) {
        activeErrors.removeAll { $0.id == error.id }
        if currentModalError?.id == error.id {
            showModal = false
            currentModalError = nil
        }
    }

    /// Dismiss the current modal.
    func dismissModal() {
        showModal = false
        currentModalError = nil
    }
}
