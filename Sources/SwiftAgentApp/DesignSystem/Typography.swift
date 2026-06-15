import SwiftUI

extension Font {
    static let uiBody    = Font.system(size: 13, weight: .regular)
    static let uiLabel   = Font.system(size: 13, weight: .medium)
    static let uiHeadline = Font.system(size: 17, weight: .semibold)
    static let uiTitle   = Font.system(size: 28, weight: .semibold)
    static let uiCaption = Font.system(size: 12, weight: .regular)

    static let codeMono  = Font.system(size: 13, design: .monospaced)
    static let codeTag   = Font.system(size: 12, weight: .medium, design: .monospaced)
}
