import Foundation
import AppKit
import ScreenCaptureKit

/// Captures the active application window and extracts text.
public final class AppshotCapture: ObservableObject, @unchecked Sendable {
    public static let shared = AppshotCapture()

    @Published public var isCapturing: Bool = false
    @Published public var lastCapture: AppshotData?

    private init() {}

    /// The appshot data produced by a capture.
    public struct AppshotData: Sendable {
        public let imageData: Data
        public let extractedText: String?
        public let appName: String
        public let timestamp: Date

        public init(imageData: Data, extractedText: String?, appName: String, timestamp: Date = Date()) {
            self.imageData = imageData
            self.extractedText = extractedText
            self.appName = appName
            self.timestamp = timestamp
        }

        /// Format for injection into LLM context.
        public var contextDescription: String {
            var desc = "[Appshot] Captured from \(appName) at \(formattedTimestamp)\n\n"
            if let text = extractedText, !text.isEmpty {
                desc += "Visible text:\n\(text)\n"
            }
            return desc
        }

        private var formattedTimestamp: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: timestamp)
        }
    }

    /// Capture the currently active application window using ScreenCaptureKit.
    /// Returns the captured data, or nil if capture fails.
    public func captureActiveWindow() async -> AppshotData? {
        await MainActor.run { isCapturing = true }
        defer { Task { @MainActor in isCapturing = false } }

        do {
            // Get available windows
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )

            // Get the frontmost app
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                print("[AppshotCapture] No frontmost application")
                return nil
            }
            let appName = frontApp.localizedName ?? "Unknown"

            // Find windows belonging to the frontmost app
            let appWindows = shareableContent.windows.filter { window in
                window.owningApplication?.bundleIdentifier == frontApp.bundleIdentifier
            }

            // Pick the largest on-screen window (likely the main window)
            guard let targetWindow = appWindows.max(by: {
                ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
            }) else {
                print("[AppshotCapture] No windows found for front app")
                return nil
            }

            // Create filter for this specific window
            let filter = SCContentFilter(desktopIndependentWindow: targetWindow)

            // Configure for single image capture
            let config = SCStreamConfiguration()
            config.width = Int(targetWindow.frame.width)
            config.height = Int(targetWindow.frame.height)
            config.showsCursor = false
            config.scalesToFit = false

            // Capture using SCScreenshotManager with completion handler
            let cgImage: CGImage = try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                ) { image, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let image = image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "AppshotCapture",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No image captured"]
                        ))
                    }
                }
            }

            let imageRep = NSBitmapImageRep(cgImage: cgImage)
            guard let imageData = imageRep.representation(using: .png, properties: [:]) else {
                print("[AppshotCapture] Failed to convert image to PNG data")
                return nil
            }

            // Extract text via Accessibility API
            let extractedText = AXTextExtractor.extractTextFromActiveWindow()

            let capture = AppshotData(
                imageData: imageData,
                extractedText: extractedText,
                appName: appName
            )

            await MainActor.run { self.lastCapture = capture }
            return capture

        } catch {
            print("[AppshotCapture] Capture failed: \(error)")
            return nil
        }
    }
}
